--[[
	Matchmaking smoke tests in a headless world, starting from the real
	entry point (Main.server): the single-server Sleigh Station lobby
	(Quick Join pad, crews, requeue, leaving) and the run place host that
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
	local pad = engine.workspace:FindFirstChild("SleighStation"):FindFirstChild("QuickJoinPad")
	return world, engine, Config, pad
end

local function stepOnPad(engine, pad, player)
	engine:teleport(player, pad.Position + Vector3.new(0, 3, 0))
end

local function inRun(engine, player): boolean
	return count(engine, player, "Stop") > 0
end

describe("Sleigh Station lobby (single server)", function()
	it("boards Quick Join riders onto one sleigh that leaves 10 s after the first rider", function()
		local world, engine, Config, pad = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			stepOnPad(engine, pad, a)
			world.wait(1)
			local queue = last(engine, a, "Queue")
			expect(queue.count).toBe(1)
			local departAt = queue.departAt
			expect(departAt - engine.now).toBeNear(Config.Lobby.QuickJoinSeconds - 1, 0.6)

			stepOnPad(engine, pad, b)
			world.wait(1)
			expect(last(engine, a, "Queue").count).toBe(2)
			expect(last(engine, b, "Queue").departAt).toBe(departAt) -- same sleigh

			expect(inRun(engine, a)).toBe(false)
			waitUntil(world, function()
				return inRun(engine, a) and inRun(engine, b)
			end, 20, "the sleigh to leave")
			expect(engine.now).toBeGreaterThanOrEqual(departAt)
			expect(count(engine, a, "QueueClear")).toBeGreaterThan(0)
		end)
	end)

	it("leaves at once when the sleigh is full, and a 7th rider starts a new sleigh", function()
		local world, engine, Config, pad = boot()
		world.run(function()
			local riders = {}
			for i = 1, Config.Lobby.CrewMax + 1 do
				riders[i] = engine:addPlayer("R" .. i)
			end
			for i = 1, Config.Lobby.CrewMax do
				stepOnPad(engine, pad, riders[i])
			end
			waitUntil(world, function()
				return inRun(engine, riders[1])
			end, 3, "a full sleigh to leave straight away")
			stepOnPad(engine, pad, riders[Config.Lobby.CrewMax + 1])
			world.wait(1)
			expect(last(engine, riders[Config.Lobby.CrewMax + 1], "Queue").count).toBe(1)
		end)
	end)

	it("lets a rider leave the queue, and stepping on the pad again doesn't queue twice", function()
		local world, engine, _, pad = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			stepOnPad(engine, pad, a)
			stepOnPad(engine, pad, b)
			world.wait(1)
			engine:teleport(a, Vector3.new(0, 3, -40))
			world.wait(0.5)
			stepOnPad(engine, pad, a) -- walks back on: still one seat
			world.wait(1)
			expect(last(engine, b, "Queue").count).toBe(2)

			local leave = world.load("ReplicatedStorage.Shared.Remotes").get("LeaveCrew")
			leave.OnServerEvent:Fire(a)
			world.wait(0.5)
			expect(count(engine, a, "QueueClear")).toBe(1)
			expect(last(engine, b, "Queue").count).toBe(1)

			engine:removePlayer(b) -- leaving the game empties the crew
			world.wait(15)
			expect(inRun(engine, a)).toBe(false)
		end)
	end)

	it("requeues the crew together after a run, then starts their next run", function()
		local world, engine, _, pad = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			stepOnPad(engine, pad, a)
			stepOnPad(engine, pad, b)
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
		local world, engine, Config, pad = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			stepOnPad(engine, pad, a)
			stepOnPad(engine, pad, b)
			waitUntil(world, function()
				return inRun(engine, a)
			end, 20, "the run")
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
		local world, engine, _, pad = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			stepOnPad(engine, pad, a)
			waitUntil(world, function()
				return inRun(engine, a)
			end, 20, "the run")
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
		local world, engine, Config, pad = boot()
		world.run(function()
			local crews = Config.Lobby.MaxRunsPerServer + 1
			local firsts = {}
			for c = 1, crews do
				for i = 1, Config.Lobby.CrewMax do
					local p = engine:addPlayer("C" .. c .. "P" .. i)
					if i == 1 then
						firsts[c] = p
					end
					stepOnPad(engine, pad, p)
				end
				world.wait(1)
			end
			world.wait(3)
			local queue = last(engine, firsts[crews], "Queue")
			expect(queue.waiting).toBe(true)
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
