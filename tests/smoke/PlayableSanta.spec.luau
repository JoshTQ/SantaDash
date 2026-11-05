--[[
	The server side of the playable Santa in a real run (headless engine):
	the sneak flag follows the stop's phases, and a grab asks the client to
	play Grab. The clips themselves play on clients (docs/PLAYTEST.md #12-14).
]]

local function fastRuns(Config)
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
end

describe("playable Santa in a run", function()
	it("tiptoes in the sneak phase, walks after the lights, and grabs with a Grab move", function()
		local world = headless()
		local engine = world.engine
		fastRuns(world.load("ReplicatedStorage.Shared.Config"))
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local SantaMoves = world.load("ReplicatedStorage.Shared.SantaMoves")
		local Run = world.load("ServerScriptService.Server.Run")
		local a = engine:addPlayer("A")
		world.run(function()
			local run = Run.new(1, { a }, function() end)
			run:start()
			while run.phase ~= "Sneak" do
				world.wait(0.2)
			end
			expect(a:GetAttribute(SantaMoves.SNEAK_ATTRIBUTE)).toBe(true)

			-- Pretend this character is the Meshy Santa, then grab a present.
			a.Character:SetAttribute(SantaMoves.SANTA_ATTRIBUTE, true)
			local present = run.route.stops[run.stopIndex].presents[1]
			run:_grab(a, present)
			expect(SantaMoves.decode(a.Character:GetAttribute(SantaMoves.MOVE_ATTRIBUTE))).toBe("Grab")

			-- The same present again: nothing new to grab, no second move.
			local before = a.Character:GetAttribute(SantaMoves.MOVE_ATTRIBUTE)
			run:_grab(a, present)
			expect(a.Character:GetAttribute(SantaMoves.MOVE_ATTRIBUTE)).toBe(before)

			while run.phase == "Sneak" do
				world.wait(0.2)
			end
			expect(a:GetAttribute(SantaMoves.SNEAK_ATTRIBUTE)).toBe(false)
			run.ended = true
		end)
	end)
end)
