--[[
	Several headless servers on one shared clock, joined by stand-ins for
	Roblox's cross-server services, so cross-server matchmaking runs end to end:

	- MemoryStoreService queues, shared by every server: AddAsync with a TTL,
	  ReadAsync hides the items it returns for the queue's invisibility
	  timeout, RemoveAsync(readId) deletes them. Sorted maps too.
	- MessagingService: PublishAsync reaches every subscribed server (the
	  sender too) after a short delay, as in Roblox.
	- TeleportService: ReserveServer hands out access codes; TeleportAsync
	  moves players to the reserved run server for that code (started on
	  first use) or to a lobby server, with TeleportData in GetJoinData().
	- HttpService:GenerateGUID, Instance.new("TeleportOptions").

	Values sent through the cloud are deep-copied (as Roblox serialises
	them), so a server never shares tables with another. Every server is a
	`headless()` world running Main.server, with Config.Places set to the
	cloud's place ids. Tests can break things on purpose through
	`cloud.faults` (see below).

	Use it through the runner's `cloud()` helper.
]]

local roblox = require("@lune/roblox")
local Engine = require("./Engine")

local Enum = roblox.Enum

local Cloud = {}
Cloud.__index = Cloud

Cloud.LobbyPlace = 1001
Cloud.RunPlace = 2002
Cloud.LATENCY = 0.2 -- seconds for a message or a teleport to arrive

local function copy(value, seen)
	if type(value) ~= "table" then
		assert(not Engine.isInstance(value), "Instances can't be sent across servers")
		return value
	end
	seen = seen or {}
	assert(not seen[value], "cyclic tables can't be sent across servers")
	seen[value] = true
	local out = {}
	for k, v in value do
		out[copy(k, seen)] = copy(v, seen)
	end
	seen[value] = nil
	return out
end
Cloud.copy = copy

export type Options = {
	configure: ((Config: any, kind: string) -> ())?, -- tweak each server's Config before Main runs
}

function Cloud.new(headless, options: Options?)
	local self = setmetatable({}, Cloud)
	self.headless = headless
	self.options = options or {}
	self.now = 0
	self.driver = Engine.new() -- runs the test's own thread
	self.servers = {} -- { world }, in start order
	self.lobbies = {}
	self.runServers = {} -- [accessCode] = world
	self.queues = {} -- [name] = { items, reads }
	self.maps = {} -- [name] = { [key] = { value, expiresAt } }
	self.subscribers = {} -- [topic] = { { world, callback } }
	self.published = {} -- { { topic, data, from } }
	self.reservations = {} -- { { code, by } }
	self.teleports = {} -- { { from, to, placeId, names, data } }
	self.moves = {} -- teleports in flight
	self.nextUserId = 5000
	self.nextGuid = 0
	self.nextJob = 0
	self.accounts = {} -- [userId] = name
	-- Set these to break the cloud on purpose: true = always fails, a
	-- number n = the next n calls fail (a hiccup), then it works again.
	self.faults = {
		memoryStore = false, -- every queue call errors
		queueRemove = false, -- only queue RemoveAsync errors (the batch stays hidden, then comes back)
		publish = false, -- PublishAsync errors
		subscribe = false, -- SubscribeAsync errors
		reserve = false, -- ReserveServer errors
		teleport = false, -- TeleportAsync errors
		teleportInit = false, -- TeleportAsync accepts, then TeleportInitFailed fires
	}
	-- Random hiccups: [fault name] = chance (0-1) that any one call fails,
	-- drawn from cloud.rng so a seed repeats exactly (fault soak).
	self.flaky = {}
	self.rng = Cloud.random(1)
	-- Calls made to each cloud service, for request budgets (load tests).
	self.calls = { memoryStore = 0, publish = 0, reserve = 0, teleport = 0 }
	return self
end

-- Services ---------------------------------------------------------------

function Cloud:_queue(name: string)
	local q = self.queues[name]
	if not q then
		q = { items = {}, reads = {}, nextRead = 0 }
		self.queues[name] = q
	end
	return q
end

-- A tiny seeded generator (Lune has no Random outside game code):
-- rng:NextNumber() in [0, 1), rng:NextInteger(a, b).
function Cloud.random(seed: number)
	local state = (math.floor(seed) % 2147483646) + 1
	local rng = {}
	function rng:NextNumber(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
	function rng:NextInteger(a: number, b: number): number
		return a + math.floor(self:NextNumber() * (b - a + 1))
	end
	return rng
end

-- Whether the next call of this kind fails (see faults and flaky).
function Cloud:_fails(name: string): boolean
	local f = self.faults[name]
	if type(f) == "number" then
		if f > 0 then
			self.faults[name] = f - 1
			return true
		end
	elseif f then
		return true
	end
	local chance = self.flaky[name]
	return chance ~= nil and self.rng:NextNumber() < chance
end

-- Tickets visible in a queue right now (for assertions).
function Cloud:queued(name: string): { any }
	local out = {}
	for _, item in self:_queue(name).items do
		if item.expiresAt > self.now then
			table.insert(out, copy(item.value))
		end
	end
	return out
end

function Cloud:_install(world, kind: string)
	local cloud = self
	local engine = world.engine
	local server = { world = world, kind = kind }

	local function fault(name: string)
		if cloud:_fails(name) then
			error(name .. " is down (cloud fault)", 3)
		end
	end

	local http = engine:service("HttpService")
	http.GenerateGUID = function(_, wrap)
		cloud.nextGuid += 1
		local guid = string.format("00000000-0000-4000-8000-%012d", cloud.nextGuid)
		return if wrap == false then guid else "{" .. guid .. "}"
	end
	http.JSONEncode = function(_, value)
		return require("@lune/serde").encode("json", value)
	end

	local memory = engine:service("MemoryStoreService")
	memory.GetQueue = function(_, name: string, invisibility: number?)
		local q = cloud:_queue(name)
		local hideFor = invisibility or 30
		local handle = engine.Instance.new("MemoryStoreQueue")
		handle.Name = name
		handle.AddAsync = function(_, value, expiration: number, priority: number?)
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			table.insert(q.items, {
				value = copy(value),
				expiresAt = cloud.now + expiration,
				hiddenUntil = -math.huge,
				priority = priority or 0,
			})
		end
		handle.ReadAsync = function(_, count: number, allOrNothing: boolean, _wait: number)
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			local picked, values = {}, {}
			for _, item in q.items do
				if #picked >= count then
					break
				end
				if item.expiresAt > cloud.now and item.hiddenUntil <= cloud.now then
					table.insert(picked, item)
				end
			end
			if allOrNothing and #picked < count then
				return {}, nil
			end
			if #picked == 0 then
				return {}, nil
			end
			for _, item in picked do
				item.hiddenUntil = cloud.now + hideFor
				table.insert(values, copy(item.value))
			end
			if cloud.trace then
				local ids = {}
				for _, v in values do
					table.insert(ids, table.concat(v.members or {}, "+"))
				end
				print(string.format("%.1f %s read %s", cloud.now, world.jobId, table.concat(ids, ",")))
			end
			q.nextRead += 1
			local readId = "read-" .. q.nextRead
			q.reads[readId] = picked
			return values, readId
		end
		handle.RemoveAsync = function(_, readId: string)
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			fault("queueRemove")
			local picked = q.reads[readId]
			q.reads[readId] = nil
			for _, item in picked or {} do
				local i = table.find(q.items, item)
				if i then
					table.remove(q.items, i)
				end
			end
		end
		handle.GetSizeAsync = function()
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			return #cloud:queued(name)
		end
		return handle
	end

	-- Sorted maps: SetAsync with a TTL, GetAsync, RemoveAsync, GetRangeAsync (by key).
	memory.GetSortedMap = function(_, name: string)
		cloud.maps[name] = cloud.maps[name] or {}
		local map = cloud.maps[name]
		local handle = engine.Instance.new("MemoryStoreSortedMap")
		handle.Name = name
		handle.SetAsync = function(_, key: string, value, expiration: number)
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			map[key] = { value = copy(value), expiresAt = cloud.now + expiration }
			return true
		end
		handle.GetAsync = function(_, key: string)
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			local entry = map[key]
			if entry and entry.expiresAt > cloud.now then
				return copy(entry.value)
			end
			return nil
		end
		handle.RemoveAsync = function(_, key: string)
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			map[key] = nil
		end
		handle.GetRangeAsync = function(_, direction, count: number)
			cloud.calls.memoryStore += 1
			fault("memoryStore")
			local keys = {}
			for key, entry in map do
				if entry.expiresAt > cloud.now then
					table.insert(keys, key)
				end
			end
			table.sort(keys)
			if direction == Enum.SortDirection.Descending then
				local reversed = {}
				for i = #keys, 1, -1 do
					table.insert(reversed, keys[i])
				end
				keys = reversed
			end
			local out = {}
			for i = 1, math.min(count, #keys) do
				table.insert(out, { key = keys[i], value = copy(map[keys[i]].value) })
			end
			return out
		end
		return handle
	end

	local messaging = engine:service("MessagingService")
	messaging.PublishAsync = function(_, topic: string, message)
		cloud.calls.publish += 1
		fault("publish")
		table.insert(cloud.published, { topic = topic, data = copy(message), from = world })
		for _, sub in table.clone(cloud.subscribers[topic] or {}) do
			if sub.connected then
				local packet = { Data = copy(message), Sent = cloud.now }
				sub.world.engine:delay(Cloud.LATENCY, sub.callback, packet)
			end
		end
	end
	messaging.SubscribeAsync = function(_, topic: string, callback)
		fault("subscribe")
		local sub = { world = world, callback = callback, connected = true }
		cloud.subscribers[topic] = cloud.subscribers[topic] or {}
		table.insert(cloud.subscribers[topic], sub)
		return {
			Disconnect = function()
				sub.connected = false
			end,
		}
	end

	local teleport = engine:service("TeleportService")
	teleport.ReserveServer = function(_, placeId: number)
		cloud.calls.reserve += 1
		fault("reserve")
		assert(placeId == Cloud.RunPlace, "ReserveServer for an unknown place " .. tostring(placeId))
		local code = "code-" .. tostring(#cloud.reservations + 1)
		table.insert(cloud.reservations, { code = code, by = world })
		return code, "private-" .. code
	end
	teleport.TeleportAsync = function(_, placeId: number, players, options)
		cloud.calls.teleport += 1
		fault("teleport")
		assert(
			placeId == Cloud.RunPlace or placeId == Cloud.LobbyPlace,
			"TeleportAsync to an unknown place " .. tostring(placeId)
		)
		assert(type(players) == "table" and #players > 0, "TeleportAsync needs players")
		local code = options and options.ReservedServerAccessCode
		if placeId == Cloud.RunPlace then
			assert(code, "the run place only takes reserved-server teleports")
			local known = false
			for _, r in cloud.reservations do
				known = known or r.code == code
			end
			assert(known, "no reserved server with access code " .. tostring(code))
		end
		local data = options and rawget(options, "_data")
		local names = {}
		for _, player in players do
			assert(player.Parent == engine.Players, player.Name .. " is not in this server")
			table.insert(names, player.Name)
		end
		local record = { from = world, placeId = placeId, code = code, names = names, data = copy(data) }
		table.insert(cloud.teleports, record)
		if cloud:_fails("teleportInit") then
			for _, player in players do
				engine:delay(Cloud.LATENCY, function()
					teleport.TeleportInitFailed:Fire(player, Enum.TeleportResult.Failure, "cloud fault")
				end)
			end
			return { PrivateServerId = code }
		end
		for _, player in players do
			table.insert(cloud.moves, {
				at = cloud.now + Cloud.LATENCY,
				player = player,
				from = world,
				placeId = placeId,
				code = code,
				data = copy(data),
			})
		end
		return { PrivateServerId = code }
	end

	-- TeleportOptions: ReservedServerAccessCode is a plain property; the
	-- TeleportData set on it is copied when it is set, as Roblox does.
	local new = engine.Instance.new
	engine.Instance.new = function(className: string, parent)
		local inst = new(className, parent)
		if className == "TeleportOptions" then
			inst.SetTeleportData = function(o, value)
				rawset(o, "_data", copy(value))
			end
			inst.GetTeleportData = function(o)
				return copy(rawget(o, "_data"))
			end
		end
		return inst
	end

	return server
end

-- Servers ----------------------------------------------------------------

-- Starts a lobby server (or a run server with `code`) running Main.server.
function Cloud:start(kind: string, code: string?)
	local world = self.headless()
	local engine = world.engine
	engine.now = self.now
	self.nextJob += 1
	local jobId = string.format("%s-%d", if kind == "Run" then "run" else "lobby", self.nextJob)
	engine.DataModel.JobId = jobId
	engine.DataModel.PlaceId = if kind == "Run" then Cloud.RunPlace else Cloud.LobbyPlace
	if code then
		engine.DataModel.PrivateServerId = "private-" .. code
	end
	world.kind = kind
	world.jobId = jobId
	world.code = code
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Places.Lobby = Cloud.LobbyPlace
	Config.Places.Run = Cloud.RunPlace
	if self.options.configure then
		self.options.configure(Config, kind)
	end
	world.Config = Config
	self:_install(world, kind)
	table.insert(self.servers, world)
	if kind == "Run" then
		self.runServers[code :: string] = world
	else
		table.insert(self.lobbies, world)
	end
	world.runScript("ServerScriptService.Server.Main")
	return world
end

function Cloud:lobby()
	return self:start("Lobby")
end

-- A new player joining a server from the Roblox app.
function Cloud:join(world, name: string)
	self.nextUserId += 1
	self.accounts[self.nextUserId] = name
	return world.engine:addPlayer(name, { userId = self.nextUserId })
end

-- Which server a player (by name) is in now, and their Player there.
function Cloud:find(name: string)
	for _, world in self.servers do
		local player = world.engine.Players:FindFirstChild(name)
		if player then
			return world, player
		end
	end
	return nil, nil
end

-- Clock ------------------------------------------------------------------

function Cloud:_land(move)
	local player = move.player
	local userId = player.UserId
	local name = player.Name
	if player.Parent ~= move.from.engine.Players then
		return -- left before the teleport finished
	end
	move.from.engine:removePlayer(player)
	local target
	if move.placeId == Cloud.RunPlace then
		target = self.runServers[move.code] or self:start("Run", move.code)
	else
		target = self.lobbies[1] or self:lobby()
	end
	target.engine:addPlayer(name, {
		userId = userId,
		joinData = { TeleportData = copy(move.data), SourcePlaceId = move.from.engine.DataModel.PlaceId },
	})
end

function Cloud:_errors(): { string }
	local out = {}
	for _, world in self.servers do
		for _, err in world.engine.errors do
			table.insert(out, world.jobId .. ": " .. err)
		end
	end
	for _, err in self.driver.errors do
		table.insert(out, "test: " .. err)
	end
	return out
end

function Cloud:step()
	-- Teleports land between frames (starting a server reads files, which
	-- can't happen inside a game thread).
	local landing = {}
	for i = #self.moves, 1, -1 do
		if self.moves[i].at <= self.now + 1e-9 then
			table.insert(landing, 1, table.remove(self.moves, i))
		end
	end
	for _, move in landing do
		self:_land(move)
	end
	self.now += 0.1
	for _, world in table.clone(self.servers) do
		world.engine:step(0.1)
	end
	self.driver:step(0.1)
end

-- Runs fn (the test) in its own thread while every server runs alongside it.
function Cloud:run(fn: () -> (), options: { maxSeconds: number?, allowErrors: boolean? }?)
	local opts = options or {}
	local limit = self.now + (opts.maxSeconds or 900)
	local done, failure = false, nil
	self.driver.now = self.now
	self.driver:spawn(function()
		local ok, err = xpcall(fn, debug.traceback)
		done = true
		if not ok then
			failure = err
		end
	end)
	while not done and self.now < limit do
		self:step()
	end
	if failure then
		error(failure, 0)
	end
	if not done then
		error(string.format("cloud run didn't finish within %d virtual seconds", opts.maxSeconds or 900), 0)
	end
	local errors = self:_errors()
	if not opts.allowErrors and #errors > 0 then
		error("a game thread errored:\n" .. errors[1], 0)
	end
end

-- Inside cloud:run: let every server run for `seconds`.
function Cloud:wait(seconds: number?)
	return self.driver:wait(seconds or 0)
end

-- Inside cloud:run: wait until check() is true.
function Cloud:waitUntil(check: () -> boolean, seconds: number?, what: string?)
	local deadline = self.now + (seconds or 120)
	while not check() do
		if self.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		self:wait(0.2)
	end
end

-- Every warning any server logged.
function Cloud:warnings(): { string }
	local out = {}
	for _, world in self.servers do
		for _, w in world.engine.warnings do
			table.insert(out, world.jobId .. ": " .. w)
		end
	end
	return out
end

return Cloud
