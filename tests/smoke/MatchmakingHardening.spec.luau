--[[
	Launch hardening for cross-server matchmaking (5 Nov 2026, "make the game
	launch-ready and stable"). Same headless cloud as CrossServer.spec, but
	aimed at what goes wrong on a busy launch day:

	- hiccups: a teleport, TeleportInitFailed or MemoryStore call that fails
	  once or twice and then works must not cost the rider their sleigh;
	- a queue batch that can't be removed comes back later: nobody may be
	  teleported twice or pulled off a newer ticket;
	- load: many lobby servers boarding at once form full crews, inside
	  Roblox's MemoryStore request budget;
	- a fault soak: random riders and random cloud failures, checked against
	  rules that must always hold. A failure names the seed:
	    MM_SOAK_SEED=3 lune run tests/runner MatchmakingHardening
	  MM_SOAK_RUNS=20 runs more seeds (default 3).
]]

local process = require("@lune/process")

local SOAK_RUNS = tonumber(process.env.MM_SOAK_RUNS) or 3
local SOAK_ONLY = tonumber(process.env.MM_SOAK_SEED)

local QUEUE = "SleighHeist_PublicCrews_v1"
local TOPIC = "SleighHeist_CrewReady_v1"
local BAY_NUMBER = { Public = 1, Party = 2, Private = 3 }

local function fastRuns(Config)
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
end

local function newCloud(tweak: ((Config: any) -> ())?)
	return cloud({
		configure = function(Config)
			fastRuns(Config)
			if tweak then
				tweak(Config)
			end
		end,
	})
end

local function humanoidOf(player)
	return player.Character and player.Character:FindFirstChild("Humanoid")
end

local function seated(player): boolean
	local humanoid = humanoidOf(player)
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function phase(c, world, kind: string)
	local StationClock = world.load("ReplicatedStorage.Shared.StationClock")
	return StationClock.phaseAt(kind, BAY_NUMBER[kind], c.now)
end

local function waitForBoarding(c, world, kind: string, left: number?)
	c:waitUntil(function()
		local p = phase(c, world, kind)
		return p.name == "Boarding" and p.endsAt - c.now >= (left or 4)
	end, 120, kind .. " boarding")
end

local function walkIn(world, kind: string, player)
	local zone = world.engine.workspace:FindFirstChild(kind .. "Zone", true)
	assert(zone, "no " .. kind .. " board zone")
	world.engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
end

local function board(c, world, kind: string, players: { any })
	for _, player in players do
		walkIn(world, kind, player)
	end
	c:waitUntil(function()
		for _, player in players do
			if not seated(player) then
				return false
			end
		end
		return true
	end, 5, "riders to sit down")
end

local function joinAll(c, world, names: { string })
	local out = {}
	for _, name in names do
		table.insert(out, c:join(world, name))
	end
	return out
end

local function serverOf(c, name: string)
	local world = c:find(name)
	return world
end

local function teleportsTo(c, placeId: number)
	local out = {}
	for _, t in c.teleports do
		if t.placeId == placeId then
			table.insert(out, t)
		end
	end
	return out
end

local function hasWarning(c, text: string): boolean
	for _, w in c:warnings() do
		if string.find(w, text, 1, true) then
			return true
		end
	end
	return false
end

-- How many times each rider was sent to the run place.
local function runTeleportsPerRider(c): { [string]: number }
	local out = {}
	for _, t in teleportsTo(c, c.RunPlace) do
		for _, name in t.names do
			out[name] = (out[name] or 0) + 1
		end
	end
	return out
end

local function telemetryOf(world)
	return world.load("ServerScriptService.Server.Telemetry")
end

describe("Matchmaking hardening: hiccups", function()
	it("retries a teleport call that fails twice, and the rider still makes the sleigh", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.teleport = 2
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 9.5)
			board(c, lobby, "Public", { ann })
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 40, "Ann on a run server")
			expect(c.calls.teleport).toBe(3)
			expect(#lobby.engine:hudMessages(ann, "QueueClear")).toBe(0)
			expect(telemetryOf(lobby).totals().TeleportRetried).toBe(2)
			expect(telemetryOf(lobby).totals().TeleportFailed).toBeNil()
		end)
	end)

	it("retries a teleport that started and then failed (TeleportInitFailed)", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.teleportInit = 1
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 9.5)
			board(c, lobby, "Public", { ann })
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 40, "Ann on a run server")
			expect(c.calls.teleport).toBe(2)
			expect(#lobby.engine:hudMessages(ann, "QueueClear")).toBe(0)
			local Teleporter = lobby.load("ServerScriptService.Server.Teleporter")
			expect(Teleporter.inFlight()).toBe(0) -- forgotten once Ann left
		end)
	end)

	it("gives up after Attempts tries and puts the rider back in the hub", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.teleportInit = true
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 9.5)
			board(c, lobby, "Public", { ann })
			c:waitUntil(function()
				return #lobby.engine:hudMessages(ann, "QueueClear") > 0
			end, 40, "Ann back at the hub")
			c:wait(0.5)
			expect(c.calls.teleport).toBe(lobby.Config.Matchmaking.Attempts)
			expect(serverOf(c, "Ann")).toBe(lobby)
			expect(seated(ann)).toBe(false)
			expect(telemetryOf(lobby).totals().TeleportFailed).toBe(1)
			expect(telemetryOf(lobby).totals().Warning).toBeGreaterThan(0) -- its warning was counted too
		end)
	end)

	it("does not retry a teleport to a run server that is full or gone", function()
		local c = newCloud()
		local lobby = c:lobby()
		local teleport = lobby.engine:service("TeleportService")
		local tries = 0
		teleport.TeleportAsync = function(_, _placeId, players)
			tries += 1
			for _, player in players do
				lobby.engine:delay(0.2, function()
					teleport.TeleportInitFailed:Fire(player, Enum.TeleportResult.GameFull, "full")
				end)
			end
			return { PrivateServerId = "x" }
		end
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 9.5)
			board(c, lobby, "Public", { ann })
			c:waitUntil(function()
				return #lobby.engine:hudMessages(ann, "QueueClear") > 0
			end, 40, "Ann back at the hub")
			c:wait(5)
			expect(tries).toBe(1)
			expect(hasWarning(c, "could not teleport: GameFull")).toBe(true)
		end)
	end)

	it("queues a ticket through a MemoryStore hiccup without falling back to a local run", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local ann, bo = c:join(a, "Ann"), c:join(b, "Bo")
			waitForBoarding(c, a, "Public", 9.5)
			c.faults.memoryStore = 1 -- Ann's AddAsync fails once
			board(c, a, "Public", { ann })
			board(c, b, "Public", { bo })
			c:waitUntil(function()
				local world = serverOf(c, "Ann")
				return world.kind == "Run" and serverOf(c, "Bo") == world
			end, 40, "Ann and Bo on one run server")
			expect(hasWarning(c, "could not queue")).toBe(false)
		end)
	end)
end)

describe("Matchmaking hardening: a batch that can't be removed", function()
	it("teleports each rider once and doesn't queue the leftovers twice", function()
		local c = newCloud(function(Config)
			Config.Matchmaking.InvisibleSeconds = 6 -- the stuck batch comes back quickly
			Config.Matchmaking.PackEverySeconds = 5 -- both servers' riders land in the first batch
		end)
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local early = joinAll(c, a, { "A1", "A2", "A3", "A4", "A5", "A6" })
			local late = c:join(b, "B1")
			waitForBoarding(c, a, "Public", 9.5)
			c.faults.queueRemove = 3 -- every try of the first removal fails
			board(c, a, "Public", early)
			board(c, b, "Public", { late })
			c:waitUntil(function()
				return serverOf(c, "A1").kind == "Run"
			end, 30, "the full crew")
			c:waitUntil(function()
				return hasWarning(c, "could not remove a packed batch")
			end, 10, "the removal to give up")
			-- While the batch is hidden, B1's ticket must not have been added again.
			local ids = {}
			for _, t in c:queued(QUEUE) do
				expect(ids[t.id]).toBeNil()
				ids[t.id] = true
			end
			-- The batch comes back; B1 still leaves (part-full), once.
			c:waitUntil(function()
				return serverOf(c, "B1").kind == "Run"
			end, 60, "B1's crew")
			c:wait(10)
			for name, n in runTeleportsPerRider(c) do
				if n ~= 1 then
					error(name .. " was teleported " .. n .. " times")
				end
			end
			expect(serverOf(c, "B1")).never.toBe(serverOf(c, "A1"))
			-- The stuck crew isn't started again by the server that started it.
			expect(#c.reservations).toBe(2)
		end)
	end)

	it("a stale crew message can't pull a rider off their newer ticket", function()
		local c = newCloud(function(Config)
			Config.Matchmaking.PublicWaitSeconds = 60 -- Ann's new ticket keeps waiting
		end)
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 9.5)
			board(c, lobby, "Public", { ann })
			c:wait(1)
			local ticket = c:queued(QUEUE)[1]
			expect(ticket).never.toBeNil()
			-- An old crew for Ann (some other ticket) turns up late.
			local Handoff = lobby.load("ReplicatedStorage.Shared.Handoff")
			local code = lobby.engine:service("TeleportService"):ReserveServer(c.RunPlace)
			lobby.engine:service("MessagingService"):PublishAsync(TOPIC, {
				code = code,
				data = Handoff.make("old-crew", "Public", { ann.UserId }),
				tickets = { "an-old-ticket" },
			})
			c:wait(3)
			expect(#c.teleports).toBe(0)
			expect(serverOf(c, "Ann")).toBe(lobby)
			-- The real crew for her current ticket still works.
			lobby.engine:service("MessagingService"):PublishAsync(TOPIC, {
				code = code,
				data = Handoff.make("new-crew", "Public", { ann.UserId }),
				tickets = { ticket.id },
			})
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 10, "Ann on her crew's server")
		end)
	end)
end)

describe("Matchmaking hardening: load", function()
	it(
		"8 lobby servers boarding 48 riders at once make 8 full crews within the MemoryStore budget",
		function()
			local c = newCloud()
			local lobbies = {}
			for i = 1, 8 do
				lobbies[i] = c:lobby()
			end
			local names = {}
			c:run(function()
				local riders = {}
				for i, world in lobbies do
					local group = {}
					for j = 1, 6 do
						local name = string.format("L%dR%d", i, j)
						table.insert(names, name)
						table.insert(group, name)
					end
					riders[i] = joinAll(c, world, group)
				end
				waitForBoarding(c, lobbies[1], "Public", 9.5)
				local startCalls, startAt = c.calls.memoryStore, c.now
				for i, world in lobbies do
					board(c, world, "Public", riders[i])
				end
				c:waitUntil(function()
					for _, name in names do
						local world = serverOf(c, name)
						if not world or world.kind ~= "Run" then
							return false
						end
					end
					return true
				end, 60, "all 48 riders on run servers")

				-- Full crews, each on its own run server, nobody twice.
				expect(#c.reservations).toBe(8)
				local perServer = {}
				for _, name in names do
					local world = serverOf(c, name)
					perServer[world] = (perServer[world] or 0) + 1
				end
				local servers = 0
				for _, n in perServer do
					servers += 1
					expect(n).toBe(6)
				end
				expect(servers).toBe(8)
				for name, n in runTeleportsPerRider(c) do
					if n ~= 1 then
						error(name .. " was teleported " .. n .. " times")
					end
				end
				expect(#c:queued(QUEUE)).toBe(0)

				-- Roblox allows 1000 + 100 per player MemoryStore requests a minute.
				local minutes = math.max(1, (c.now - startAt) / 60)
				local perMinute = (c.calls.memoryStore - startCalls) / minutes
				expect(perMinute).toBeLessThan(1000 + 100 * #names)
				expect(#c:_errors()).toBe(0)
			end, { maxSeconds = 600 })
		end
	)
end)

-- Fault soak ---------------------------------------------------------------

local function faultSoak(seed: number)
	local c = newCloud()
	c.rng = c.random(seed)
	local rng = c.random(seed * 7919)
	local lobbies = { c:lobby(), c:lobby(), c:lobby() }
	local riders = {} -- { name, world }
	local log = {}
	local problems = {}
	local function problem(text: string)
		if #problems < 10 then
			table.insert(problems, string.format("t=%.1f %s", c.now, text))
		end
	end

	c:run(function()
		for i = 1, 14 do
			local world = lobbies[(i - 1) % #lobbies + 1]
			local name = "S" .. i
			c:join(world, name)
			table.insert(riders, name)
		end
		c.flaky = {
			memoryStore = 0.1,
			publish = 0.15,
			reserve = 0.1,
			teleport = 0.15,
			teleportInit = 0.1,
		}

		local stopAt = c.now + 120
		while c.now < stopAt do
			c:wait(1)
			for _, name in riders do
				local world, player = c:find(name)
				if not world or world.kind ~= "Lobby" then
					continue
				end
				local roll = rng:NextNumber()
				local p = phase(c, world, "Public")
				if not seated(player) and roll < 0.3 and p.name == "Boarding" and p.endsAt - c.now > 2 then
					table.insert(log, name .. " boards")
					walkIn(world, "Public", player)
				elseif seated(player) and roll < 0.03 then
					table.insert(log, name .. " hops off")
					humanoidOf(player).Jump = true
				elseif roll < 0.004 then
					table.insert(log, name .. " leaves the game")
					world.engine:removePlayer(player)
				end
			end
			for code, world in c.runServers do
				local n = #world.engine.Players:GetPlayers()
				if n > 6 then
					problem("run server " .. code .. " holds " .. n .. " Santas")
				end
			end
		end

		-- The cloud recovers; everyone still seated must get going.
		c.flaky = {}
		local Config = lobbies[1].Config
		c:wait(Config.Matchmaking.LocalFallbackSeconds + Config.Matchmaking.PublicWaitSeconds + 20)
		for _, name in riders do
			local world, player = c:find(name)
			if world and world.kind == "Lobby" and seated(player) then
				problem(name .. " is still sitting on a sleigh in " .. world.jobId)
			end
		end
	end, { maxSeconds = 1200, allowErrors = true })

	for _, err in c:_errors() do
		problem("game thread error: " .. string.sub(err, 1, 300))
	end
	-- Nobody is in two servers at once.
	local seen = {}
	for _, world in c.servers do
		for _, player in world.engine.Players:GetPlayers() do
			if seen[player.Name] then
				problem(player.Name .. " is in two servers")
			end
			seen[player.Name] = true
		end
	end
	-- Nobody leaves a run in the soak, so no run server should ever send
	-- someone back: that would mean a rider was teleported to the wrong crew.
	for _, t in teleportsTo(c, c.RunPlace) do
		if t.from.kind == "Run" then
			problem("a run server teleported to the run place")
		end
	end
	for _, t in teleportsTo(c, c.LobbyPlace) do
		problem(table.concat(t.names, ", ") .. " turned away by run server " .. tostring(t.from.jobId))
	end
	-- Every failure that happened was counted.
	local counted = 0
	for _, world in lobbies do
		for _, n in telemetryOf(world).totals() do
			counted += n
		end
	end
	if #c:warnings() > 0 and counted == 0 then
		problem("warnings were logged but Telemetry counted nothing")
	end

	-- The soak must actually exercise something.
	local sent = 0
	for _ in runTeleportsPerRider(c) do
		sent += 1
	end
	if sent == 0 then
		problem("nobody ever reached a run server")
	end
	if process.env.MM_SOAK_DEBUG then
		print(seed, "riders sent", sent, "warnings", #c:warnings(), "reservations", #c.reservations)
	end

	if #problems > 0 then
		local recent = {}
		for i = math.max(1, #log - 8), #log do
			table.insert(recent, log[i])
		end
		error(
			string.format(
				"seed %d: %s\n      last actions: %s",
				seed,
				table.concat(problems, "\n      "),
				table.concat(recent, "; ")
			),
			0
		)
	end
end

describe("Matchmaking hardening: fault soak (random riders, random cloud failures)", function()
	for seed = 1, if SOAK_ONLY then 1 else SOAK_RUNS do
		local s = SOAK_ONLY or seed
		it("seed " .. s, function()
			faultSoak(s)
		end)
	end
end)
