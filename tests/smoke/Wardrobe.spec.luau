--[[
	The Wardrobe stand at each Sleigh Stop, played through a real Run in a
	headless world: warm gear for Jingle, worn over any suit (a character
	attribute the client dresses from), kept through a respawn, and off by
	default until Josh approves the art.
]]

local function boot(enabled: boolean)
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.MapEvents.Chance = 0
	Config.Wardrobe.Enabled = enabled
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	local players = { engine:addPlayer("A") }
	return world, engine, Config, Run, players
end

local function atFirstStop(world, Run, players)
	local run = Run.new(1, players, function() end)
	run:start()
	local deadline = world.engine.now + 200
	while not (run.stopIndex == 1 and run.phase ~= "Flight") do
		assert(world.engine.now < deadline, "never reached stop 1")
		world.wait(0.1)
	end
	return run
end

it("is off by default: no stand, no prompts", function()
	local world, _, _, Run, players = boot(false)
	world.run(function()
		local run = atFirstStop(world, Run, players)
		for _, stop in run.route.stops do
			expect(next(stop.wardrobePrompts)).toBeNil()
		end
		run.ended = true
	end)
end)

it("sells warm gear for Jingle, dresses Santa and refuses a second scarf", function()
	local world, engine, Config, Run, players = boot(true)
	local santa = players[1]
	world.run(function()
		local run = atFirstStop(world, Run, players)
		local stop = run.route.stops[1]
		for _, id in Config.Wardrobe.Order do
			expect(stop.wardrobePrompts[id]).toBeTruthy()
		end
		local st = run.players[santa]
		st.jingle = 1000
		engine.trigger(stop.wardrobePrompts.Scarf, santa)
		world.wait(0.1)
		expect(st.wardrobe.Scarf).toBe(true)
		expect(st.jingle).toBe(1000 - Config.Wardrobe.Items.Scarf.price)
		expect(santa.Character:GetAttribute("Wardrobe")).toBe("Scarf")

		engine.trigger(stop.wardrobePrompts.Scarf, santa)
		world.wait(0.1)
		expect(st.jingle).toBe(1000 - Config.Wardrobe.Items.Scarf.price) -- not charged twice

		st.jingle = 0
		engine.trigger(stop.wardrobePrompts.HotWaterBottle, santa)
		world.wait(0.1)
		expect(st.wardrobe.HotWaterBottle).toBeNil() -- can't afford it

		-- A respawn keeps the gear on.
		santa:LoadCharacter()
		world.wait(0.5)
		expect(santa.Character:GetAttribute("Wardrobe")).toBe("Scarf")
		run.ended = true
	end)
end)
