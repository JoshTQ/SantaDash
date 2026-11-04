--[[
	Regression tests for bugs found by the soak test and probes (4 Nov 2026).
	Each test failed before its fix.
]]

local function fastRuns(Config)
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
end

describe("bugs found 4 Nov", function()
	it("a Santa who respawns mid-flight rides the rest of the way in a seat", function()
		local world = headless()
		local engine = world.engine
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local MapBuilder = world.load("ServerScriptService.Server.MapBuilder")
		local Run = world.load("ServerScriptService.Server.Run")
		local a, b = engine:addPlayer("A"), engine:addPlayer("B")
		world.run(function()
			local run = Run.new(1, { a, b }, function() end)
			run:start()
			world.wait(2) -- in the take-off flight
			expect(run.phase).toBe("Flight")
			a:LoadCharacter()
			world.wait(0.5)
			expect(a.Character.HumanoidRootPart.Anchored).toBe(true) -- held in the seat, not falling
			while run.stopIndex < 1 do
				world.wait(0.2)
			end
			local root = a.Character.HumanoidRootPart
			expect(MapBuilder.isAboard(run.deck, root.Position)).toBe(true)
			expect(root.Anchored).toBe(false) -- free to hop off at the stop
			run.ended = true
		end)
	end)

	it("a crew member who loads in after the run started joins the next run", function()
		local world = headless()
		local engine = world.engine
		fastRuns(world.load("ReplicatedStorage.Shared.Config"))
		engine.workspace:SetAttribute("RunPlace", true)
		local Handoff = world.load("ReplicatedStorage.Shared.Handoff")
		local data = Handoff.make("crew-1", "Public", { 501, 502 })
		world.run(function()
			world.runScript("ServerScriptService.Server.Main")
			world.wait(0.5)
			local a = engine:addPlayer("A", { userId = 501, joinData = { TeleportData = data } })
			world.wait(20) -- the run starts at the arrival timeout without B
			expect(#engine:hudMessages(a, "Stop")).toBeGreaterThan(0)
			-- B's phone took 20 s to load the run place.
			local b = engine:addPlayer("B", { userId = 502, joinData = { TeleportData = data } })
			local deadline = engine.now + 400
			while #engine:hudMessages(b, "Stop") == 0 and engine.now < deadline do
				world.wait(1)
			end
			expect(#engine:hudMessages(b, "Stop")).toBeGreaterThan(0)
		end, { maxSeconds = 600 })
	end)
end)
