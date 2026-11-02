--[[
	The HUD (Hud.client) running against the real server in one headless
	world: the lobby, a run, Krampus, results, and the HUD's own buttons.
]]

local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 120)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function boot()
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
	local me = engine:addPlayer("Me")
	engine:setLocalPlayer(me)
	world.run(function()
		world.runScript("ServerScriptService.Server.Main")
		world.runScript("StarterPlayer.StarterPlayerScripts.Client.Hud")
		world.wait(0.5)
	end)
	local pad = engine.workspace:FindFirstChild("SleighStation"):FindFirstChild("QuickJoinPad")
	return world, engine, me, pad, Config
end

local function shows(world, text: string, seconds: number?)
	waitUntil(world, function()
		return world.engine:guiShows(text)
	end, seconds or 30, '"' .. text .. '" on the HUD')
end

describe("the HUD", function()
	it("shows the queue countdown, then the stop, timer, Jingle and sack during a run", function()
		local world, engine, me, pad, Config = boot()
		world.run(function()
			expect(engine:guiShows("Sleigh leaves")).toBe(false)
			engine:teleport(me, pad.Position + Vector3.new(0, 3, 0))
			shows(world, "Sleigh leaves in")
			shows(world, "1/" .. Config.Lobby.CrewMax .. " Santas")
			shows(world, "TAKE-OFF", 20)
			shows(world, "STOP 1/2 · SNEAK", 30)
			shows(world, "Jingle: 500")
			shows(world, "Sack: 0/" .. Config.Sack.Capacity)
			shows(world, "0:2") -- the stop timer is counting down from 0:24
			shows(world, "LIGHTS ON", 30)
			-- Off the sleigh, so it waits for the horn instead of leaving at once.
			engine:teleport(me, engine.rootOf(me).Position + Vector3.new(0, 0, 80))
			shows(world, "GET ON THE SLEIGH!", 30)
		end)
	end)

	it("warns of Krampus in the Lair and shows the results with the next-run countdown", function()
		local world, engine, me, pad = boot()
		world.run(function()
			engine:teleport(me, pad.Position + Vector3.new(0, 3, 0))
			shows(world, "KRAMPUS'S LAIR", 200)
			shows(world, "KRAMPUS IS COMING!", 5)
			shows(world, "Best thief: Me", 200)
			shows(world, "(escaped x2)")
			shows(world, "Next run in")
			shows(world, "Heist again together!", 30)
		end)
	end)

	it("Leave crew and Back to hub buttons leave the queue and the run", function()
		local world, engine, me, pad = boot()
		world.run(function()
			engine:teleport(me, pad.Position + Vector3.new(0, 3, 0))
			shows(world, "Sleigh leaves in")
			engine:teleport(me, Vector3.new(0, 3, -40))
			engine:guiButton("Leave crew").Activated:Fire()
			world.wait(0.5)
			expect(engine:guiShows("Sleigh leaves in")).toBe(false)

			engine:teleport(me, pad.Position + Vector3.new(0, 3, 0))
			shows(world, "STOP 1/2", 40)
			engine:guiButton("Back to hub").Activated:Fire()
			world.wait(0.5)
			expect(engine:guiShows("STOP 1/2")).toBe(false)
		end)
	end)

	it("shows the hiding panel, and Space taps refill your breath", function()
		local world, engine, me, pad = boot()
		world.run(function()
			engine:teleport(me, pad.Position + Vector3.new(0, 3, 0))
			shows(world, "STOP 1/2 · SNEAK", 40)
			-- Find the run's first wardrobe and hide in it.
			local spot
			for _, d in engine.workspace:GetDescendants() do
				if d:IsA("ProximityPrompt") and d.ActionText == "Hide" then
					spot = d
					break
				end
			end
			expect(spot).never.toBeNil()
			engine.trigger(spot, me)
			shows(world, "Hiding! Tap to hold your breath", 5)
			local tap = engine.boundActions.SleighHeistTap
			expect(tap).never.toBeNil()
			tap("SleighHeistTap", Enum.UserInputState.Begin)
			engine:guiButton("Come out").Activated:Fire()
			world.wait(0.5)
			expect(engine:guiShows("Hiding!")).toBe(false)
			expect(engine.boundActions.SleighHeistTap).toBeNil()
		end)
	end)
end)
