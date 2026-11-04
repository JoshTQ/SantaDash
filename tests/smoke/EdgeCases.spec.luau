--[[
	Edge cases and failure paths in a headless world: respawns, leaving while
	snatched or hidden, a full sack, spam taps, broken routes, a run that
	crashes, pathfinding that finds nothing, and the Stop 1 tease.
]]

local function setup(names: { string })
	local world = headless()
	local engine = world.engine
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local players = {}
	for i, name in names do
		players[i] = engine:addPlayer(name)
	end
	return world, engine, world.load("ServerScriptService.Server.Run"), players
end

local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 300)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function sawBanner(engine, player, text: string): boolean
	for _, m in engine:hudMessages(player, "Banner") do
		if string.find(m.data.text, text, 1, true) then
			return true
		end
	end
	return false
end

local function start(world, Run, crew)
	local state = { finished = false }
	local run = Run.new(1, crew, function(_, survivors)
		state.finished = true
		state.survivors = survivors
	end)
	run:start()
	return run, state
end

local function atStop(world, run, index)
	waitUntil(world, function()
		return run.stopIndex == index and run.phase == "Sneak"
	end, 500, "stop " .. index)
end

local function atLair(world, run)
	atStop(world, run, 3)
	waitUntil(world, function()
		return run.krampus ~= nil
	end, 5, "Krampus")
	return run.krampus
end

describe("players during a run", function()
	it("respawn on the sleigh, out of a wardrobe or Krampus's basket", function()
		local world, engine, Run, players = setup({ "A", "B" })
		local a, b = players[1], players[2]
		world.run(function()
			local run = start(world, Run, players)
			local krampus = atLair(world, run)
			krampus.stunnedUntil = math.huge
			-- A hides, then resets: out of the wardrobe and back on the sleigh.
			local spot = run.route.stops[3].hideSpots[1]
			engine.trigger(spot.prompt, a)
			expect(run.players[a].hidden).toBe(spot)
			a:LoadCharacter()
			world.wait(0.5)
			expect(run.players[a].hidden).toBeNil()
			expect(spot.occupant).toBeNil()
			-- B is snatched, then resets: Krampus lets go.
			krampus:_snatch(b)
			expect(run.players[b].captive).toBe(true)
			b:LoadCharacter()
			world.wait(0.5)
			expect(run.players[b].captive).toBe(false)
			expect(krampus.captive).toBeNil()
		end)
	end)

	it("can leave while snatched or hidden without breaking the run", function()
		local world, engine, Run, players = setup({ "A", "B", "C" })
		local a, b = players[1], players[2]
		world.run(function()
			local run, state = start(world, Run, players)
			local krampus = atLair(world, run)
			krampus.stunnedUntil = math.huge
			krampus:_snatch(a)
			run:removePlayer(a)
			expect(krampus.captive).toBeNil()
			local spot = run.route.stops[3].hideSpots[1]
			engine.trigger(spot.prompt, b)
			run:removePlayer(b)
			expect(spot.occupant).toBeNil()
			run:removePlayer(b) -- twice is harmless
			waitUntil(world, function()
				return state.finished
			end, 300, "the run to finish")
			expect(state.survivors).toEqual({ players[3] })
		end)
	end)

	it("won't let two Santas share a wardrobe, or a snatched Santa buy or grab", function()
		local world, engine, Run, players = setup({ "A", "B" })
		local a, b = players[1], players[2]
		world.run(function()
			local run = start(world, Run, players)
			local krampus = atLair(world, run)
			krampus.stunnedUntil = math.huge
			local spot = run.route.stops[3].hideSpots[1]
			engine.trigger(spot.prompt, a)
			engine.trigger(spot.prompt, b)
			expect(run.players[b].hidden).toBeNil()

			krampus:_snatch(b)
			run.players[b].jingle = 99999
			engine.trigger(run.route.stops[3].cocoaPrompt, b)
			expect(run.players[b].perks.PeppermintRush).toBeNil()
			local present = run.route.stops[3].presents[1]
			engine.trigger(present.prompt, b)
			expect(run.players[b].sackCount).toBe(0)
			krampus:wiggle(a) -- not his captive: ignored
			expect(krampus.wiggles).toBe(0)
		end)
	end)

	it("stops grabbing at a full sack and says so", function()
		local world, engine, Run, players = setup({ "A" })
		local a = players[1]
		world.run(function()
			local run = start(world, Run, players)
			atStop(world, run, 1)
			run.players[a].sackCount = 15
			local present
			for _, p in run.route.stops[1].presents do
				if not p.inVault then
					present = p
					break
				end
			end
			engine.trigger(present.prompt, a)
			expect(present.taken).toBeFalsy()
			expect(sawBanner(engine, a, "Sack full!")).toBe(true)
		end)
	end)

	it("announces the Naughty List theft to the whole crew", function()
		local world, engine, Run, players = setup({ "Thief", "Friend" })
		world.run(function()
			local run = start(world, Run, players)
			local krampus = atLair(world, run)
			krampus.stunnedUntil = math.huge
			for _, p in run.route.stops[3].presents do
				if p.plan.naughtyList then
					engine.trigger(p.prompt, players[1])
				end
			end
			expect(sawBanner(engine, players[2], "Thief stole the Naughty List!")).toBe(true)
		end)
	end)

	it("ignores taps faster than the tap limit and input after the run ends", function()
		local world, engine, Run, players = setup({ "A" })
		local a = players[1]
		world.run(function()
			local run = start(world, Run, players)
			local krampus = atLair(world, run)
			krampus.stunnedUntil = math.huge
			krampus:_snatch(a)
			for _ = 1, 10 do
				run:onInput(a, "Tap") -- all in the same instant
			end
			expect(krampus.wiggles).toBe(1)
			run.ended = true
			world.wait(1)
			run:onInput(a, "Tap")
			expect(krampus.wiggles).toBe(1)
		end, { allowErrors = true })
	end)

	it("says to get behind Krampus when the bells are rung from the front, and has a cooldown", function()
		local world, engine, Run, players = setup({ "A", "B" })
		local a, b = players[1], players[2]
		world.run(function()
			local run = start(world, Run, players)
			local krampus = atLair(world, run)
			krampus.stunnedUntil = math.huge
			local front = (krampus.body.root.CFrame * CFrame.new(0, 0, -4)).Position
			engine:teleport(a, front)
			engine.trigger(krampus.body.bellPrompt, a)
			expect(sawBanner(engine, a, "Get behind him to ring the bells!")).toBe(true)

			local behind = (krampus.body.root.CFrame * CFrame.new(0, 0, 4)).Position
			engine:teleport(a, behind)
			engine.trigger(krampus.body.bellPrompt, a)
			expect(sawBanner(engine, b, "A rang the bells! Krampus is dizzy!")).toBe(true)
			local stunned = krampus.stunnedUntil
			engine:teleport(b, (krampus.body.root.CFrame * CFrame.new(0, 0, 4)).Position)
			engine.trigger(krampus.body.bellPrompt, b) -- still cooling down
			expect(krampus.stunnedUntil).toBe(stunned)
		end)
	end)

	it("sends Krampus toward the last noise when he can't see anyone", function()
		local world, engine, Run, players = setup({ "A" })
		local a = players[1]
		world.run(function()
			local run = start(world, Run, players)
			local krampus = atLair(world, run)
			-- While he stands still for the warning, A sneaks off the sleigh,
			-- grabs a present across the Lair and gets back on.
			local seat = engine.rootOf(a).Position
			local present = run.route.stops[3].presents[1]
			local at = present.model:GetPivot().Position
			engine:teleport(a, at + Vector3.new(0, 3, 0))
			engine.trigger(present.prompt, a)
			engine:teleport(a, seat)
			expect(run.lastNoisePos).never.toBeNil()
			waitUntil(world, function()
				return krampus.mover.goal ~= nil and (krampus.mover.goal - at).Magnitude < 20
			end, 30, "Krampus to head for the noise")
		end)
	end)

	it("walks Krampus straight at his target when pathfinding finds no route", function()
		local world, engine, Run, players = setup({ "A" })
		local a = players[1]
		engine.pathfindingFails = true
		world.run(function()
			local run = start(world, Run, players)
			local krampus = atLair(world, run)
			engine:teleport(a, krampus.body.root.Position + Vector3.new(0, 0, 30))
			waitUntil(world, function()
				return run.players[a].captive
			end, 60, "Krampus to catch A without a path")
		end)
	end)

	it("plays the distant-bells tease at Stop 1 when it is turned on", function()
		local world, engine, Run, players = setup({ "A" })
		local Config = world.load("ReplicatedStorage.Shared.Config")
		Config.Krampus.TeaseEnabled = true
		world.run(function()
			local run = start(world, Run, players)
			atStop(world, run, 1)
			world.wait(Config.Krampus.TeaseAt + 1)
			expect(#engine:hudMessages(players[1], "KrampusTease")).toBe(1)
			expect(run.krampus).toBeNil() -- heard, not seen
		end)
	end)
end)

describe("failures", function()
	it("a crash inside a run is logged and the crew still gets sent home", function()
		local world, engine, Run, players = setup({ "A" })
		world.run(function()
			local run, state = start(world, Run, players)
			atStop(world, run, 1)
			run._fly = function()
				error("boom") -- the flight to Stop 2 blows up
			end
			waitUntil(world, function()
				return state.finished
			end, 300, "the crashed run to finish")
			expect(state.survivors).toEqual(players)
		end)
		local logged = false
		for _, w in engine.warnings do
			logged = logged or string.find(w, "crashed", 1, true) ~= nil
		end
		expect(logged).toBe(true)
	end)

	it("the lobby gives the crew their queue back when a route fails to build", function()
		local world = headless()
		local engine = world.engine
		local Maps = world.load("ReplicatedStorage.Shared.Maps")
		Maps.Rotation = { "NoSuchMap" }
		local a
		world.run(function()
			world.runScript("ServerScriptService.Server.Main")
			world.wait(0.5)
			a = engine:addPlayer("A")
			-- Board the next Public sleigh (bay 1) and let it leave.
			local StationClock = world.load("ReplicatedStorage.Shared.StationClock")
			while true do
				local p = StationClock.phaseAt("Public", 1, engine.now)
				if p.name == "Boarding" and p.endsAt - engine.now >= 4 then
					break
				end
				world.wait(0.25)
			end
			local zone = engine.workspace:FindFirstChild("PublicZone", true)
			engine:teleport(a, zone.Position + Vector3.new(0, 3, 0))
			world.wait(20)
		end)
		expect(#engine:hudMessages(a, "QueueClear")).toBe(1)
		expect(#engine:hudMessages(a, "Stop")).toBe(0)
		local logged = false
		for _, w in engine.warnings do
			logged = logged or string.find(w, "failed to build a route", 1, true) ~= nil
		end
		expect(logged).toBe(true)
	end)

	it("the run place requeues the crew when a route fails to build", function()
		local world = headless()
		local engine = world.engine
		engine.workspace:SetAttribute("RunPlace", true)
		local Handoff = world.load("ReplicatedStorage.Shared.Handoff")
		world.load("ReplicatedStorage.Shared.Maps").Rotation = { "NoSuchMap" }
		local a
		world.run(function()
			world.runScript("ServerScriptService.Server.Main")
			world.wait(0.5)
			a = engine:addPlayer(
				"A",
				{ userId = 11, joinData = { TeleportData = Handoff.make("c", "Public", { 11 }) } }
			)
			world.wait(3)
		end)
		local queues = engine:hudMessages(a, "Queue")
		expect(#queues).toBeGreaterThanOrEqual(2) -- queued, failed, queued again
		local logged = false
		for _, w in engine.warnings do
			logged = logged or string.find(w, "failed to build a route", 1, true) ~= nil
		end
		expect(logged).toBe(true)
	end)

	it("the run place falls back to the waiting spot when the lobby teleport fails", function()
		local world = headless()
		local engine = world.engine
		engine.workspace:SetAttribute("RunPlace", true)
		local Config = world.load("ReplicatedStorage.Shared.Config")
		Config.Places.Lobby = 4321
		local teleport = engine:service("TeleportService")
		teleport.TeleportAsync = function()
			error("Teleport failed: HTTP 500")
		end
		local stranger
		world.run(function()
			world.runScript("ServerScriptService.Server.Main")
			world.wait(0.5)
			stranger = engine:addPlayer("Stranger")
			world.wait(1)
		end)
		expect(#engine:hudMessages(stranger, "QueueClear")).toBe(1)
		local logged = false
		for _, w in engine.warnings do
			logged = logged or string.find(w, "teleport to lobby failed", 1, true) ~= nil
		end
		expect(logged).toBe(true)
	end)
end)
