--[[
	Matchmaking smoke tests in a headless world, starting from the real
	entry point (Main.server): the single-server Sleigh Station lobby
	(Public bay boarding, crews, requeue, leaving) and the run place host that
	receives a crew teleported from the lobby place (Handoff).
]]

-- Short stops so whole runs fit in a few virtual minutes.
local function fastRuns(Config)
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
end

local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 120)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function last(engine, player, kind)
	local list = engine:hudMessages(player, kind)
	return list[#list] and list[#list].data
end

local function count(engine, player, kind)
	return #engine:hudMessages(player, kind)
end

-- A world running Main.server as the lobby (or the run place with runPlace).
local function boot(options: { runPlace: boolean? }?)
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	fastRuns(Config)
	if options and options.runPlace then
		engine.workspace:SetAttribute("RunPlace", true)
	end
	world.run(function()
		world.runScript("ServerScriptService.Server.Main")
		world.wait(0.5)
	end)
	return world, engine, Config
end

local function inRun(engine, player): boolean
	return count(engine, player, "Stop") > 0
end

local function seated(player): boolean
	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- The Public bay's (bay 1) phase right now.
local function publicPhase(world)
	return world.load("ReplicatedStorage.Shared.StationClock").phaseAt("Public", 1, world.engine.now)
end

-- Waits for the Public sleigh to be boarding with at least `left` seconds to go.
local function waitForBoarding(world, left: number?)
	waitUntil(world, function()
		local p = publicPhase(world)
		return p.name == "Boarding" and p.endsAt - world.engine.now >= (left or 4)
	end, 120, "Public boarding")
end

local function publicZone(engine)
	local zone = engine.workspace:FindFirstChild("PublicZone", true)
	assert(zone, "no Public board zone")
	return zone
end

-- Walks players into the Public bay's board zone and waits until they sit.
local function walkOn(world, players: { any })
	local zone = publicZone(world.engine)
	for _, player in players do
		world.engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
	end
	waitUntil(world, function()
		for _, player in players do
			if not seated(player) then
				return false
			end
		end
		return true
	end, 5, "riders to sit down")
end

-- Boards the next Public sleigh; returns the time its gate shuts.
local function boardPublic(world, players: { any }, left: number?): number
	waitForBoarding(world, left)
	walkOn(world, players)
	return publicPhase(world).endsAt
end

describe("Sleigh Station lobby (single server)", function()
	it("boards Public riders onto one sleigh that leaves when its gate shuts", function()
		local world, engine = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			local shutsAt = boardPublic(world, { a }, 8)
			walkOn(world, { b })
			expect(publicPhase(world).endsAt).toBe(shutsAt) -- same sleigh
			expect(inRun(engine, a)).toBe(false)
			waitUntil(world, function()
				return inRun(engine, a) and inRun(engine, b)
			end, 30, "the sleigh to leave")
			expect(engine.now).toBeGreaterThanOrEqual(shutsAt)
			expect(count(engine, a, "QueueClear")).toBeGreaterThan(0)
		end)
	end)

	it("seats a crew of 6 per sleigh, and the 7th rider takes the next one", function()
		local world, engine, Config = boot()
		world.run(function()
			local riders = {}
			for i = 1, Config.Lobby.CrewMax + 1 do
				riders[i] = engine:addPlayer("R" .. i)
			end
			local first = table.clone(riders)
			local seventh = table.remove(first)
			boardPublic(world, first, 8)
			engine:teleport(seventh, publicZone(engine).Position + Vector3.new(0, 3, 0))
			world.wait(1)
			expect(seated(seventh)).toBe(false) -- the sleigh is full
			waitUntil(world, function()
				return inRun(engine, riders[1])
			end, 30, "the full sleigh to leave")
			expect(inRun(engine, seventh)).toBe(false)
			boardPublic(world, { seventh })
			waitUntil(world, function()
				return inRun(engine, seventh)
			end, 30, "the next sleigh")
		end)
	end)

	it("lets a rider hop off, and walking back on doesn't take two seats", function()
		local world, engine = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			local c = engine:addPlayer("C")
			boardPublic(world, { a, b, c }, 8)
			local leave = world.load("ReplicatedStorage.Shared.Remotes").get("LeaveCrew")
			leave.OnServerEvent:Fire(a) -- hop off
			world.wait(0.5)
			expect(seated(a)).toBe(false)
			walkOn(world, { a }) -- back on: one seat again
			local taken = 0
			for _, d in engine.workspace:GetDescendants() do
				if d:IsA("Seat") and d.Occupant ~= nil then
					taken += 1
				end
			end
			expect(taken).toBe(3)

			engine:removePlayer(c) -- leaving the game frees the seat
			leave.OnServerEvent:Fire(a)
			world.wait(0.5)
			waitUntil(world, function()
				return inRun(engine, b)
			end, 30, "the sleigh to leave")
			expect(inRun(engine, a)).toBe(false)
		end)
	end)

	it("requeues the crew together after a run, then starts their next run", function()
		local world, engine = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			boardPublic(world, { a, b })
			waitUntil(world, function()
				return count(engine, a, "Results") > 0
			end, 300, "the first run's results")
			waitUntil(world, function()
				local q = last(engine, a, "Queue")
				return q ~= nil and q.requeue == true
			end, 30, "the requeue")
			expect(last(engine, b, "Queue").requeue).toBe(true)
			expect(last(engine, a, "Queue").count).toBe(2)
			local stopsBefore = count(engine, a, "Stop")
			waitUntil(world, function()
				return count(engine, a, "Stop") > stopsBefore
			end, 30, "the next run")
		end)
	end)

	it("sends a Santa who leaves mid-run back to the station while the crew plays on", function()
		local world, engine, Config = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			boardPublic(world, { a, b })
			waitUntil(world, function()
				return inRun(engine, a)
			end, 30, "the run")
			world.wait(8)
			world.load("ReplicatedStorage.Shared.Remotes").get("LeaveCrew").OnServerEvent:Fire(a)
			world.wait(0.5)
			expect(count(engine, a, "RunEnd")).toBe(1)
			local hub = Config.Map.HubSpawn.Position
			expect((engine.rootOf(a).Position - hub).Magnitude).toBeLessThan(1)
			local stops = count(engine, b, "Stop")
			world.wait(30)
			expect(count(engine, b, "Stop")).toBeGreaterThan(stops) -- B is still playing
		end)
	end)

	it("routes taps from the Input remote to the player's run", function()
		local world, engine = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			boardPublic(world, { a })
			waitUntil(world, function()
				return inRun(engine, a)
			end, 30, "the run")
			waitUntil(world, function()
				return count(engine, a, "Stop") >= 2 -- landed at Stop 1
			end, 20, "Stop 1")
			world.wait(1)
			-- Hide in a wardrobe, then tap: the Hud gets the new breath.
			local Remotes = world.load("ReplicatedStorage.Shared.Remotes")
			local hides = count(engine, a, "Hide")
			Remotes.get("Input").OnServerEvent:Fire(a, "Tap")
			Remotes.get("Input").OnServerEvent:Fire(a, 42) -- junk input is ignored
			world.wait(0.5)
			expect(count(engine, a, "Hide")).toBe(hides) -- not hidden: taps do nothing
		end)
	end)

	it("makes a full server's fifth crew wait for a free street", function()
		local world, engine, Config = boot()
		world.run(function()
			local crews = Config.Lobby.MaxRunsPerServer + 1
			local firsts = {}
			for c = 1, crews do
				local crew = {}
				for i = 1, Config.Lobby.CrewMax do
					crew[i] = engine:addPlayer("C" .. c .. "P" .. i)
				end
				firsts[c] = crew[1]
				boardPublic(world, crew)
				waitUntil(world, function()
					return publicPhase(world).name ~= "Boarding"
				end, 30, "this sleigh to leave")
			end
			waitUntil(world, function()
				local queue = last(engine, firsts[crews], "Queue")
				return queue ~= nil and queue.waiting == true
			end, 30, "the fifth crew to wait")
			expect(inRun(engine, firsts[crews])).toBe(false)
			waitUntil(world, function()
				return inRun(engine, firsts[crews])
			end, 400, "a street to free up")
		end)
	end)
end)

describe("run place host (cross-server handoff)", function()
	local function crewData(world, crewId, members)
		local Handoff = world.load("ReplicatedStorage.Shared.Handoff")
		return { TeleportData = Handoff.make(crewId, "Public", members) }
	end

	it("starts the run as soon as the whole crew has arrived", function()
		local world, engine = boot({ runPlace = true })
		world.run(function()
			local data = crewData(world, "crew-1", { 501, 502 })
			local a = engine:addPlayer("A", { userId = 501, joinData = data })
			world.wait(2)
			expect(inRun(engine, a)).toBe(false) -- waiting for B
			local b = engine:addPlayer("B", { userId = 502, joinData = data })
			waitUntil(world, function()
				return inRun(engine, a) and inRun(engine, b)
			end, 5, "the crew's run")
		end)
	end)

	it("starts with whoever made it after the arrival timeout", function()
		local world, engine, Config = boot({ runPlace = true })
		world.run(function()
			local data = crewData(world, "crew-2", { 601, 602, 603 })
			local a = engine:addPlayer("A", { userId = 601, joinData = data })
			world.wait(Config.Places.ArrivalTimeoutSeconds - 2)
			expect(inRun(engine, a)).toBe(false)
			waitUntil(world, function()
				return inRun(engine, a)
			end, 5, "the timeout")
		end)
	end)

	it("turns away players who aren't in the crew", function()
		local world, engine, Config = boot({ runPlace = true })
		world.run(function()
			local data = crewData(world, "crew-3", { 701 })
			engine:addPlayer("Member", { userId = 701, joinData = data })
			local stranger = engine:addPlayer("Stranger", { userId = 999, joinData = data })
			local forged =
				engine:addPlayer("Forged", { userId = 998, joinData = crewData(world, "other", { 998 }) })
			local none = engine:addPlayer("NoData", { userId = 997 })
			world.wait(1)
			for _, p in { stranger, forged, none } do
				expect(count(engine, p, "QueueClear")).toBe(1) -- sent back (no lobby place yet)
				expect(inRun(engine, p)).toBe(false)
			end

			-- With a published lobby place they are teleported there.
			Config.Places.Lobby = 1234
			engine:addPlayer("Late", { userId = 996 })
			world.wait(1)
			expect(#engine.teleports).toBe(1)
			expect(engine.teleports[1].placeId).toBe(1234)
			Config.Places.Lobby = 0
		end)
	end)

	it("plays runs back to back for the crew, and sends leavers to the lobby", function()
		local world, engine, Config = boot({ runPlace = true })
		world.run(function()
			local data = crewData(world, "crew-4", { 801, 802 })
			local a = engine:addPlayer("A", { userId = 801, joinData = data })
			local b = engine:addPlayer("B", { userId = 802, joinData = data })
			waitUntil(world, function()
				return count(engine, a, "Results") > 0
			end, 300, "the first run")
			waitUntil(world, function()
				local q = last(engine, a, "Queue")
				return q ~= nil and q.requeue == true
			end, 30, "the requeue")
			local stops = count(engine, a, "Stop")
			waitUntil(world, function()
				return count(engine, a, "Stop") > stops
			end, 30, "the second run")

			Config.Places.Lobby = 1234
			world.load("ReplicatedStorage.Shared.Remotes").get("LeaveCrew").OnServerEvent:Fire(b)
			world.wait(0.5)
			expect(engine.teleports[#engine.teleports].players[1]).toBe(b)
			Config.Places.Lobby = 0
		end)
	end)
end)
