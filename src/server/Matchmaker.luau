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

	Only active once both places are published (Config.Places) and outside
	Studio; Lobby falls back to same-server runs otherwise, and for anyone
	still waiting after Config.Matchmaking.LocalFallbackSeconds.
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

local Matchmaker = {}

type Pending = { since: number, kind: string }

local pending: { [Player]: Pending } = {} -- waiting for a crew on this server
local announced: { [string]: boolean } = {} -- crewIds already handled here
local queue: MemoryStoreQueue? = nil
local onFailed: ((players: { Player }, reason: string) -> ())? = nil

function Matchmaker.enabled(): boolean
	return Config.Places.Lobby ~= 0 and Config.Places.Run ~= 0 and not RunService:IsStudio()
end

function Matchmaker.isPending(player: Player): boolean
	return pending[player] ~= nil
end

-- Players waiting longer than LocalFallbackSeconds (the queue is probably down).
function Matchmaker.overdue(now: number): { Player }
	local out = {}
	for player, p in pending do
		if now - p.since >= Config.Matchmaking.LocalFallbackSeconds then
			table.insert(out, player)
		end
	end
	return out
end

-- Stop waiting for a crew (hopped off, left, or sent somewhere else).
function Matchmaker.cancel(player: Player)
	pending[player] = nil
end

local function teleport(players: { Player }, accessCode: string, data)
	if #players == 0 then
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData(data)
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.Places.Run, players, options)
	end)
	if not ok then
		warn("[Matchmaker] teleport failed: " .. tostring(err))
		if onFailed then
			onFailed(players, "teleport")
		end
	end
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
	local players = {}
	for _, userId in data.members do
		local player = Players:GetPlayerByUserId(userId)
		if player and pending[player] then
			pending[player] = nil
			table.insert(players, player)
		end
	end
	teleport(players, message.code, data)
end

local function announce(crew: CrewPacker.Crew)
	local accessCode = TeleportService:ReserveServer(Config.Places.Run)
	local crewId = HttpService:GenerateGUID(false)
	local message = { code = accessCode, data = Handoff.make(crewId, crew.kind, crew.members) }
	-- Our own members go now; everyone else hears it over MessagingService.
	onCrewReady(message)
	local others = false
	for _, jobId in crew.servers do
		if jobId ~= game.JobId then
			others = true
		end
	end
	if others then
		MessagingService:PublishAsync(Config.Matchmaking.Topic, message)
	end
end

-- Puts a Public rider or a Party group in the shared queue.
function Matchmaker.enqueue(kind: string, players: { Player }, since: number?)
	local now = Util.now()
	local members, servers = {}, {}
	for _, player in players do
		pending[player] = { since = now, kind = kind }
		table.insert(members, player.UserId)
		table.insert(servers, game.JobId)
	end
	local ticket = {
		id = HttpService:GenerateGUID(false),
		kind = kind,
		members = members,
		servers = servers,
		since = since or now,
	}
	task.spawn(function()
		local ok, err = pcall(function()
			(queue :: MemoryStoreQueue):AddAsync(ticket, Config.Matchmaking.TicketTTLSeconds)
		end)
		if not ok then
			warn("[Matchmaker] could not queue: " .. tostring(err)) -- LocalFallbackSeconds picks them up
		end
	end)
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
		local ok, accessCode = pcall(TeleportService.ReserveServer, TeleportService, Config.Places.Run)
		if not ok then
			warn("[Matchmaker] could not reserve a server: " .. tostring(accessCode))
			if onFailed then
				onFailed(players, "reserve")
			end
			return
		end
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
	local crews, keep = CrewPacker.pack(CrewPacker.clean(items, now), now)
	for _, crew in crews do
		local ok, err = pcall(announce, crew)
		if not ok then
			warn("[Matchmaker] could not start a crew: " .. tostring(err))
			for _, ticket in crew.tickets do
				table.insert(keep, ticket) -- try again next pack
			end
		end
	end
	for _, ticket in keep do
		q:AddAsync(ticket, Config.Matchmaking.TicketTTLSeconds)
	end
	q:RemoveAsync(readId)
end

-- failed(players, reason) is called when a teleport or reservation fails.
function Matchmaker.start(failed: (players: { Player }, reason: string) -> ())
	onFailed = failed
	queue = MemoryStoreService:GetQueue(Config.Matchmaking.QueueName, 30)

	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(Config.Matchmaking.Topic, function(packet)
			onCrewReady(packet.Data)
		end)
	end)
	if not ok then
		warn("[Matchmaker] could not subscribe: " .. tostring(err))
	end

	TeleportService.TeleportInitFailed:Connect(function(player, result, message)
		warn(("[Matchmaker] %s could not teleport: %s %s"):format(player.Name, tostring(result), message))
		if onFailed then
			onFailed({ player }, "teleport")
		end
	end)

	Players.PlayerRemoving:Connect(Matchmaker.cancel)

	task.spawn(function()
		while true do
			task.wait(Config.Matchmaking.PackEverySeconds)
			local packed, packErr = pcall(pack)
			if not packed then
				warn("[Matchmaker] pack failed: " .. tostring(packErr))
			end
		end
	end)
end

return Matchmaker
