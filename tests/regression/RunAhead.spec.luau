--[[
	Regression: running ahead to rob stops the sleigh hasn't reached (Josh,
	13 Nov 2026: "You can just run to the next stop, and steal everything
	before they spawn in. This include Krampus' lair, so i can get the naughty
	book before the sleigh moves to stop 3."). Each test failed before the fix.
]]

local function fastRuns(Config)
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
end

local function sawBanner(engine, player, text: string): boolean
	for _, m in engine:hudMessages(player, "Banner") do
		if string.find(m.data.text, text, 1, true) then
			return true
		end
	end
	return false
end

-- A run parked at Stop 1, with A off the sleigh (so it doesn't leave early).
local function atStop1(world, names: { string }?)
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	fastRuns(Config)
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	local crew = {}
	for i, name in names or { "A" } do
		crew[i] = engine:addPlayer(name)
	end
	local run = Run.new(1, crew, function() end)
	run:start()
	while run.stopIndex < 1 or run.phase ~= "Sneak" do
		world.wait(0.1)
	end
	for _, p in crew do
		engine:teleport(p, (run.route.stops[1].deckCFrame * CFrame.new(0, 3, 60)).Position)
	end
	return run, engine, crew, Config
end

local function naughtyList(stop)
	for _, present in stop.presents do
		if present.plan.naughtyList then
			return present
		end
	end
	return nil
end

describe("running ahead (Josh, 13 Nov)", function()
	it("the Naughty List can't be stolen from Stop 1", function()
		local world = headless()
		world.run(function()
			local run, engine, crew = atStop1(world)
			local a = crew[1]
			local list = naughtyList(run.route.stops[3])
			expect(list ~= nil).toBe(true)
			engine.trigger(list.prompt, a)
			local st = run.players[a]
			expect(list.taken).toBeFalsy()
			expect(st.sackCount).toBe(0)
			expect(st.grabs).toBe(0)
			expect(list.model.Parent ~= nil).toBe(true) -- still on its pedestal
			expect(sawBanner(engine, a, "Too early!")).toBe(true)
			run.ended = true
		end, { maxSeconds = 120 })
	end)

	it("no present on a later stop or the path past the next stop can be grabbed", function()
		local world = headless()
		world.run(function()
			local run, engine, crew = atStop1(world)
			local a = crew[1]
			local tried = 0
			local function try(present)
				if present.prompt.Enabled then -- vault and secret-room gifts start hidden
					engine.trigger(present.prompt, a)
					tried += 1
				end
			end
			for i = 2, 3 do
				for _, present in run.route.stops[i].presents do
					try(present)
				end
			end
			for _, present in run.route.onFootPresents do
				if present.footGap == 2 then
					try(present)
				end
			end
			expect(tried > 10).toBe(true)
			expect(run.players[a].sackCount).toBe(0)
			-- Stop 1's own presents and the path to Stop 2 still work.
			engine.trigger(run.route.stops[1].presents[1].prompt, a) -- the landing house
			expect(run.players[a].sackCount).toBe(1)
			for _, present in run.route.onFootPresents do
				if present.footGap == 1 then
					engine.trigger(present.prompt, a)
					break
				end
			end
			expect(run.players[a].sackCount).toBe(2)
			run.ended = true
		end, { maxSeconds = 120 })
	end)

	it("buys, hiding and searches at a later stop are refused", function()
		local world = headless()
		world.run(function()
			local run, engine, crew = atStop1(world)
			local a = crew[1]
			local st = run.players[a]
			st.jingle = 100000
			local stop3 = run.route.stops[3]
			engine.trigger(stop3.cocoaPrompt, a)
			expect(st.perks.PeppermintRush).toBeFalsy()
			local stop2 = run.route.stops[2]
			if stop2.vaultPrompt then
				engine.trigger(stop2.vaultPrompt, a)
				expect(stop2.vaultPrompt.Enabled).toBe(true) -- still shut
			end
			expect(st.jingle).toBe(100000)
			local spot = stop2.hideSpots[1]
			if spot then
				engine.trigger(spot.prompt, a)
				expect(st.hidden).toBe(nil)
			end
			run.ended = true
		end, { maxSeconds = 120 })
	end)

	it(
		"a Santa who runs into the next street is bounced, and one deep inside is put back on the path",
		function()
			local world = headless()
			world.run(function()
				local run, engine, crew = atStop1(world, { "A", "B" })
				local a, b = crew[1], crew[2]
				local StopGate = world.load("ServerScriptService.Server.StopGate")
				local layout = run.route.map.layout
				local stop2, stop3 = run.route.stops[2], run.route.stops[3]
				-- A is just inside Stop 2's street: a BOING back towards the path.
				local edge = (stop2.origin * CFrame.new(0, 3, layout.FootPathZ + 30)).Position
				engine:teleport(a, edge)
				-- B is standing on the Lair island, next to the Naughty List.
				local listAt = naughtyList(stop3).model:GetPivot().Position
				engine:teleport(b, listAt + Vector3.new(0, 3, 0))
				world.wait(0.5)
				expect(sawBanner(engine, a, "Too early!")).toBe(true)
				expect(sawBanner(engine, b, "Too early!")).toBe(true)
				local rootB = engine.rootOf(b)
				expect(StopGate.depth(stop3.origin, layout.FootPathZ, rootB.Position)).toBe(nil)
				expect((rootB.Position - listAt).Magnitude > 300).toBe(true)
				run.ended = true
			end, { maxSeconds = 120 })
		end
	)

	it("the live street isn't warded, the next opens on landing, and old streets stay open", function()
		local world = headless()
		world.run(function()
			local run, engine, crew = atStop1(world)
			local a = crew[1]
			local deep = (run.route.stops[1].origin * CFrame.new(0, 3, 400)).Position
			engine:teleport(a, deep)
			world.wait(1)
			expect((engine.rootOf(a).Position - deep).Magnitude < 5).toBe(true)
			expect(sawBanner(engine, a, "Too early!")).toBe(false)
			while run.stopIndex < 2 or run.phase ~= "Sneak" do
				world.wait(0.2)
			end
			local present = run.route.stops[2].presents[1]
			engine:teleport(a, present.model:GetPivot().Position + Vector3.new(0, 3, 0))
			engine.trigger(present.prompt, a)
			expect(present.taken).toBe(true)
			-- Old streets stay open (Josh, 13 Nov: "Let them do old streets").
			local before = run.players[a].sackCount
			for _, left in run.route.stops[1].presents do
				if not left.taken and left.prompt.Enabled then
					engine.trigger(left.prompt, a)
					break
				end
			end
			expect(run.players[a].sackCount).toBe(before + 1)
			run.ended = true
		end, { maxSeconds = 300 })
	end)

	it("elf bots never fetch presents from later stops or the path past the next stop", function()
		local world = headless()
		world.run(function()
			local run = atStop1(world)
			for _, c in run:presentCandidates() do
				local p = c.present
				expect(p.stopIndex == nil or p.stopIndex == 1).toBe(true)
				expect(p.footGap == nil or p.footGap == 1).toBe(true)
			end
			run.ended = true
		end, { maxSeconds = 120 })
	end)
end)
