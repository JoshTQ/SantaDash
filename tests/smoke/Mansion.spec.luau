--[[
	The Gingerbread Mansion played through a real Run (Josh approved, 6 Nov
	2026): hold Search on the furniture. A hidden gift becomes grabbable, an
	empty spot gives a dust puff and a 10 Jingle tip, a decoy box under the
	tree goes POP (noise), the piano is a noisy trap, and the gold marker
	counts what's still hidden.
]]

local function boot()
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 60
	Config.Run.LightsOnAt = 50
	Config.Run.HornAt = 55
	Config.MapEvents.Chance = 0
	Config.Mansion.Stops = { 1 } -- meet it at the first stop
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	return world, engine, Config, Run, { engine:addPlayer("A") }
end

local function atStop1(world, engine, Run, players)
	local run = Run.new(1, players, function() end)
	run:start()
	local deadline = engine.now + 200
	while not (run.stopIndex == 1 and run.phase ~= "Flight") do
		assert(engine.now < deadline, "never reached stop 1")
		world.wait(0.1)
	end
	local stop = run.route.stops[1]
	local mansion
	for _, h in stop.houses do
		if h.plan.typeName == "Mansion" then
			mansion = h
		end
	end
	assert(mansion, "no mansion at stop 1")
	return run, stop, mansion
end

it("searching finds gifts, dust and tips, and the marker counts down", function()
	local world, engine, Config, Run, players = boot()
	local santa = players[1]
	world.run(function()
		local run, stop, mansion = atStop1(world, engine, Run, players)
		local st = run.players[santa]
		expect(mansion.marker.Text).toBe("SEARCH ME · 8 GIFTS")
		local full, empty
		for _, s in stop.searchSpots do
			if s.kind == "Spot" then
				if s.present and not full then
					full = s
				elseif not s.present and not empty then
					empty = s
				end
			end
		end
		assert(full and empty)

		-- An empty spot: it opens, glows, and tips the searcher.
		local jingle = st.jingle
		local noise = run.noise
		engine.trigger(empty.prompt, santa)
		world.wait(0.1)
		expect(empty.searched).toBe(true)
		expect(empty.prompt.Enabled).toBe(false)
		expect(st.jingle).toBe(jingle + Config.Mansion.EmptyJingle)
		expect(empty.trigger:FindFirstChild("Searched").Enabled).toBe(true)
		expect(run.noise).toBe(noise)

		-- A full one: the gift appears and can be grabbed; the marker counts it.
		local moved = false
		local before = {}
		for _, d in full.model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Open") then
				before[d] = d.CFrame
			end
		end
		engine.trigger(full.prompt, santa)
		world.wait(0.1)
		for d, cf in before do
			moved = moved or d.CFrame ~= cf
		end
		expect(moved).toBe(true)
		expect(full.present.hidden).toBeNil()
		expect(full.present.prompt.Enabled).toBe(true)
		expect(mansion.marker.Text).toBe("SEARCH ME · 8 GIFTS") -- found, not grabbed yet
		local count = st.sackCount
		engine.trigger(full.present.prompt, santa)
		world.wait(0.5)
		expect(st.sackCount).toBe(count + 1)
		expect(mansion.marker.Text).toBe("SEARCH ME · 7 GIFTS")

		-- Searching again does nothing more.
		jingle = st.jingle
		run:_searchSpot(santa, stop, empty)
		expect(st.jingle).toBe(jingle)
		run.ended = true
	end)
end)

it("one tree box is real, the others pop; the piano is a trap", function()
	local world, engine, Config, Run, players = boot()
	local santa = players[1]
	world.run(function()
		local run, stop = atStop1(world, engine, Run, players)
		local real, decoys, piano = nil, {}, nil
		for _, s in stop.searchSpots do
			if s.kind == "TreeBox" then
				if s.present then
					expect(real).toBeNil()
					real = s
				else
					table.insert(decoys, s)
				end
			elseif s.kind == "Piano" then
				piano = s
			end
		end
		assert(real and piano)
		expect(#decoys).toBe(5)
		expect(real.model:GetAttribute("Wobble")).toBe(true)

		local noise = run.noise
		engine.trigger(decoys[1].prompt, santa)
		world.wait(0.1)
		expect(run.noise).toBeGreaterThan(noise)
		expect(decoys[1].model.Transparency).toBe(1)

		engine.trigger(real.prompt, santa)
		world.wait(0.1)
		expect(real.present.prompt.Enabled).toBe(true)
		expect(real.model:GetAttribute("Wobble")).toBeNil()

		noise = run.noise
		engine.trigger(piano.prompt, santa)
		world.wait(0.1)
		expect(run.noise - noise).toBeGreaterThan(Config.Mansion.PopNoise)
		run.ended = true
	end)
end)

it("elves leave the mansion's upstairs gifts to the Santas", function()
	local world, engine, _, Run, players = boot()
	world.run(function()
		local run, stop = atStop1(world, engine, Run, players)
		for _, s in stop.searchSpots do
			if s.present then
				run:_searchSpot(players[1], stop, s)
			end
		end
		for _, c in run:presentCandidates() do
			local floor = c.present.plan.floor
			expect(floor == nil or floor == 0).toBe(true)
		end
		run.ended = true
	end)
end)
