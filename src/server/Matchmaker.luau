--[[
	Cross-server matchmaking, lobby side (Josh, 1 Nov 2026: "Do 2").

	Public riders and Party groups become tickets in one MemoryStore queue
	shared by every lobby server. Each lobby server runs the same packer loop:
	read a batch (read items are hidden from other servers until removed), pack
	crews with CrewPacker, reserve a run server per crew, announce it over
	MessagingService, put the leftovers back and remove the batch. Every lobby
	server that hears the announcement teleports its own members of that crew.
	Private sleighs skip the queue and teleport straight away.

	Hopping off before the teleport just means that server does not send you;
	the run server starts with whoever arrived (Config.Places.ArrivalTimeoutSeconds)
	and bots fill the seats.

	Launch hardening (5 Nov 2026): MemoryStore calls and teleports are retried
	(Config.Matchmaking.Attempts, server/Teleporter.luau); a crew message only
	moves riders still waiting on one of that crew's tickets, so a crew packed
	twice (a batch that couldn't be removed and came back) can't pull someone
	who has since queued again; and every failure is counted in Telemetry.

	Only active once both places are published (Config.Places) and outside
	Studio. Otherwise tickets wait in this server's own list and the same
	CrewPacker rules form crews (Matchmaker.packLocal), so riders queue the
	moment they sit down either way (Josh, 11 Nov 2026). Lobby also falls back
	to same-server runs for anyone still waiting after
	Config.Matchmaking.LocalFallbackSeconds.
]]

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local CrewPacker = require(ReplicatedStorage.Shared.CrewPacker)
local Handoff = require(ReplicatedStorage.Shared.Handoff)
local Util = require(ReplicatedStorage.Shared.Util)
local Analytics = require(script.Parent.Analytics)
local Telemetry = require(script.Parent.Telemetry)
local Teleporter = require(script.Parent.Teleporter)

local Matchmaker = {}

type Pending = { since: number, ticket: string, kind: string, shared: boolean }

local pending: { [Player]: Pending } = {} -- waiting for a crew on this server
local localTickets: { CrewPacker.Ticket } = {} -- the queue when the places aren't published
local localCount = 0 -- local ticket ids
local announced: { [string]: boolean } = {} -- crewIds already handled here
local packedTickets: { [string]: number } = {} -- ticket id -> until when: crews this server started from a batch it couldn't remove
local queue: MemoryStoreQueue? = nil
local cancelledMap: MemoryStoreSortedMap? = nil -- UserId -> ticket id they hopped off
local onFailed: ((players: { Player }, reason: string) -> ())? = nil
local onFound: ((players: { Player }) -> ())? = nil

function Matchmaker.enabled(): boolean
	return Config.Places.Lobby ~= 0 and Config.Places.Run ~= 0 and not RunService:IsStudio()
end

-- Groups (one per ticket, so a Party stays together) waiting longer than
-- LocalFallbackSeconds: the queue is probably down.
function Matchmaker.overdue(now: number): { { Player } }
	local groups: { [string]: { Player } } = {}
	local out = {}
	for player, p in pending do
		if p.shared and now - p.since >= Config.Matchmaking.LocalFallbackSeconds then
			local group = groups[p.ticket]
			if not group then
				group = {}
				groups[p.ticket] = group
				table.insert(out, group)
			end
			table.insert(group, player)
		end
	end
	return out
end

-- True while a player waits in the shared queue for a crew.
function Matchmaker.isQueued(player: Player): boolean
	return pending[player] ~= nil
end

-- The kind of ticket ("Public" | "Party") a player is waiting on, if any.
function Matchmaker.queued(player: Player): string?
	local p = pending[player]
	return p and p.kind
end

-- When the player started waiting (nil if not queued).
function Matchmaker.queuedSince(player: Player): number?
	local p = pending[player]
	return p and p.since
end

-- Takes a player out of a ticket in this server's own list.
local function dropLocal(userId: number, ticketId: string)
	for i, ticket in localTickets do
		if ticket.id == ticketId then
			local at = table.find(ticket.members, userId)
			if at then
				table.remove(ticket.members, at)
				table.remove(ticket.servers, at)
			end
			if #ticket.members == 0 then
				table.remove(localTickets, i)
			end
			return
		end
	end
end

-- Stop waiting for a crew (hopped off, left, or sent somewhere else). The
-- ticket is already in the shared queue, so leave a short-lived note that
-- takes this player out of it wherever it gets packed.
function Matchmaker.cancel(player: Player)
	Teleporter.forget(player)
	local p = pending[player]
	if not p then
		return
	end
	pending[player] = nil
	dropLocal(player.UserId, p.ticket)
	local map = cancelledMap
	if map then
		task.spawn(function()
			local ok, err = pcall(function()
				map:SetAsync(tostring(player.UserId), p.ticket, Config.Matchmaking.TicketTTLSeconds)
			end)
			if not ok then
				warn("[Matchmaker] could not cancel a ticket: " .. tostring(err))
			end
		end)
	end
end

-- UserId -> ticket id for riders who hopped off (one read per pack).
local function readCancelled(): { [number]: string }
	local out = {}
	local ok, entries = pcall(function()
		return (cancelledMap :: MemoryStoreSortedMap):GetRangeAsync(Enum.SortDirection.Ascending, 200)
	end)
	if ok then
		for _, entry in entries do
			local userId = tonumber(entry.key)
			if userId and type(entry.value) == "string" then
				out[userId] = entry.value
			end
		end
	else
		warn("[Matchmaker] could not read cancellations: " .. tostring(entries))
	end
	return out
end

local function failed(players: { Player }, reason: string)
	if onFailed then
		onFailed(players, reason)
	end
end

local function retry(fn: (...any) -> any, ...: any): (boolean, any)
	return Util.retry(Config.Matchmaking.Attempts, Config.Matchmaking.RetryBackoffSeconds, fn, ...)
end

local function teleport(players: { Player }, accessCode: string, data)
	if #players == 0 then
		return
	end
	Analytics.crewFound(players)
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(data)
	Teleporter.send(players, Config.Places.Run, options, failed)
end

-- Teleports this server's members of an announced crew.
local function onCrewReady(message)
	if type(message) ~= "table" or type(message.code) ~= "string" then
		return
	end
	local data = Handoff.read(message.data)
	if not data or announced[data.crewId] then
		return
	end
	announced[data.crewId] = true
	task.delay(120, function()
		announced[data.crewId] = nil
	end)
	-- Only riders still waiting on one of this crew's tickets.
	local tickets: { [string]: boolean }? = nil
	if type(message.tickets) == "table" then
		tickets = {}
		for _, id in message.tickets do
			if type(id) == "string" then
				(tickets :: any)[id] = true
			end
		end
	end
	local players = {}
	for _, userId in data.members do
		local player = Players:GetPlayerByUserId(userId)
		local p = player and pending[player]
		if player and p and (tickets == nil or tickets[p.ticket]) then
			pending[player] = nil
			table.insert(players, player)
		end
	end
	if #players > 0 and onFound then
		onFound(players)
	end
	task.spawn(teleport, players, message.code, data)
end

local function announce(crew: CrewPacker.Crew)
	local accessCode = TeleportService:ReserveServer(Config.Places.Run)
	local crewId = HttpService:GenerateGUID(false)
	local tickets = {}
	for _, ticket in crew.tickets do
		table.insert(tickets, ticket.id)
	end
	local message =
		{ code = accessCode, data = Handoff.make(crewId, crew.kind, crew.members), tickets = tickets }
	-- Other servers hear it over MessagingService; our own members go now.
	for _, jobId in crew.servers do
		if jobId ~= game.JobId then
			MessagingService:PublishAsync(Config.Matchmaking.Topic, message)
			break
		end
	end
	onCrewReady(message)
	Telemetry.count("MatchCrewFormed", crew.kind .. " " .. #crew.members)
end

local function addTicket(ticket)
	local ok, err = retry(function()
		(queue :: MemoryStoreQueue):AddAsync(ticket, Config.Matchmaking.TicketTTLSeconds)
	end)
	if not ok then
		warn("[Matchmaker] could not queue: " .. tostring(err)) -- LocalFallbackSeconds picks them up
		Telemetry.count("MatchQueueFailed", "add")
	end
end

-- Puts a Public rider or a Party group in the queue (the shared one once
-- the places are published, else this server's own list).
function Matchmaker.enqueue(kind: string, players: { Player }, since: number?)
	local now = Util.now()
	local shared = Matchmaker.enabled() and queue ~= nil
	local id
	if shared then
		id = HttpService:GenerateGUID(false)
	else
		localCount += 1
		id = "local-" .. localCount
	end
	local members, servers = {}, {}
	for _, player in players do
		pending[player] = { since = now, ticket = id, kind = kind, shared = shared }
		table.insert(members, player.UserId)
		table.insert(servers, game.JobId)
	end
	local ticket = {
		id = id,
		kind = kind,
		members = members,
		servers = servers,
		since = since or now,
	}
	if shared then
		task.spawn(addTicket, ticket)
	else
		table.insert(localTickets, ticket)
	end
	Telemetry.count("MatchQueued", kind, #players)
end

-- Same-server queue (places not published, Studio): forms crews from this
-- server's own tickets by the same rules as the shared queue, and returns
-- the players of each crew that should leave now.
function Matchmaker.packLocal(now: number): { { Player } }
	if #localTickets == 0 then
		return {}
	end
	local crews, keep = CrewPacker.pack(CrewPacker.clean(localTickets, now), now)
	local kept: { [string]: boolean } = {}
	for _, ticket in keep do
		kept[ticket.id] = true
	end
	-- Expired or malformed tickets were dropped by clean: forget them too.
	local still = {}
	for _, ticket in localTickets do
		if kept[ticket.id] then
			table.insert(still, ticket)
		end
	end
	localTickets = still
	local out = {}
	for _, crew in crews do
		local ids: { [string]: boolean } = {}
		for _, ticket in crew.tickets do
			ids[ticket.id] = true
		end
		local players = {}
		for _, userId in crew.members do
			local player = Players:GetPlayerByUserId(userId)
			local p = player and pending[player]
			if player and p and ids[p.ticket] then
				pending[player] = nil
				table.insert(players, player)
			end
		end
		if #players > 0 then
			Telemetry.count("MatchCrewFormed", "Local " .. crew.kind .. " " .. #players)
			table.insert(out, players)
		end
	end
	return out
end

-- A Party group leaves as soon as it can, topped up by any waiting randoms.
function Matchmaker.enqueueParty(players: { Player })
	Matchmaker.enqueue("Party", players, Util.now() - Config.Matchmaking.PartyFillSeconds)
end

-- Private sleighs: reserve a server for exactly these players, no queue.
function Matchmaker.sendPrivate(players: { Player })
	task.spawn(function()
		local members = {}
		for _, player in players do
			table.insert(members, player.UserId)
		end
		local ok, accessCode = retry(function()
			return TeleportService:ReserveServer(Config.Places.Run)
		end)
		if not ok then
			warn("[Matchmaker] could not reserve a server: " .. tostring(accessCode))
			Telemetry.count("MatchReserveFailed", "Private")
			failed(players, "reserve")
			return
		end
		Telemetry.count("MatchCrewFormed", "Private " .. #members)
		teleport(players, accessCode, Handoff.make(HttpService:GenerateGUID(false), "Private", members))
	end)
end

local function pack()
	local q = queue :: MemoryStoreQueue
	local items, readId = q:ReadAsync(Config.Matchmaking.ReadBatch, false, 0)
	if not items or #items == 0 then
		return
	end
	local now = Util.now()
	for id, untilTime in packedTickets do
		if untilTime <= now then
			packedTickets[id] = nil
		end
	end
	local fresh = {}
	for _, item in items do
		if not (type(item) == "table" and packedTickets[item.id]) then
			table.insert(fresh, item)
		end
	end
	local crews, keep = CrewPacker.pack(CrewPacker.clean(fresh, now, readCancelled()), now)
	local started = {}
	for _, crew in crews do
		local ok, err = pcall(announce, crew)
		if ok then
			table.insert(started, crew)
		else
			warn("[Matchmaker] could not start a crew: " .. tostring(err))
			Telemetry.count("MatchCrewRetry")
			for _, ticket in crew.tickets do
				table.insert(keep, ticket) -- try again next pack
			end
		end
	end
	-- Always remove the batch and put the rest back, even when no crew left:
	-- a batch left in place stays hidden from every server's next read, so
	-- riders queued a few seconds apart would never be packed together.
	local removed, removeErr = retry(function()
		q:RemoveAsync(readId)
	end)
	if not removed then
		-- The whole batch comes back once it stops being hidden, so don't add
		-- the leftovers again (they'd be in the queue twice), and remember the
		-- crews already started so this server doesn't start them twice.
		warn("[Matchmaker] could not remove a packed batch: " .. tostring(removeErr))
		Telemetry.count("MatchQueueFailed", "remove")
		local forget = now + Config.Matchmaking.InvisibleSeconds + Config.Matchmaking.TicketTTLSeconds
		for _, crew in started do
			for _, ticket in crew.tickets do
				packedTickets[ticket.id] = forget
			end
		end
		return
	end
	for _, ticket in keep do
		task.spawn(addTicket, ticket)
	end
end

-- onFail(players, reason) is called when a teleport or reservation gives up;
-- found(players) when this server's riders of a crew are about to teleport.
function Matchmaker.start(
	onFail: (players: { Player }, reason: string) -> (),
	found: ((players: { Player }) -> ())?
)
	onFailed = onFail
	onFound = found
	queue = MemoryStoreService:GetQueue(Config.Matchmaking.QueueName, Config.Matchmaking.InvisibleSeconds)
	cancelledMap = MemoryStoreService:GetSortedMap(Config.Matchmaking.CancelledMapName)

	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(Config.Matchmaking.Topic, function(packet)
			onCrewReady(packet.Data)
		end)
	end)
	if not ok then
		warn("[Matchmaker] could not subscribe: " .. tostring(err))
	end

	Teleporter.start()

	task.spawn(function()
		while true do
			task.wait(Config.Matchmaking.PackEverySeconds)
			local packed, packErr = pcall(pack)
			if not packed then
				warn("[Matchmaker] pack failed: " .. tostring(packErr))
				Telemetry.count("MatchQueueFailed", "pack")
			end
		end
	end)
end

return Matchmaker
