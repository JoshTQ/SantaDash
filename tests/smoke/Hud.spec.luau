--[[
	The HUD (Hud.client) running against the real server in one headless
	world: the station lobby, a run, Krampus, results, and the HUD's own buttons.
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
	return world, engine, me, Config
end

local function seated(player): boolean
	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- Waits for the Public sleigh (bay 1) to be boarding, walks on and sits down.
local function boardPublic(world, player)
	local StationClock = world.load("ReplicatedStorage.Shared.StationClock")
	waitUntil(world, function()
		local p = StationClock.phaseAt("Public", 1, world.engine.now)
		return p.name == "Boarding" and p.endsAt - world.engine.now >= 4
	end, 120, "Public boarding")
	local zone = world.engine.workspace:FindFirstChild("PublicZone", true)
	world.engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
	waitUntil(world, function()
		return seated(player)
	end, 5, "sitting on the sleigh")
end

local function boardShows(engine, text: string): boolean
	for _, d in engine.workspace:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == text then
			return true
		end
	end
	return false
end

local function shows(world, text: string, seconds: number?)
	waitUntil(world, function()
		return world.engine:guiShows(text)
	end, seconds or 30, '"' .. text .. '" on the HUD')
end

describe("the HUD", function()
	it("shows the crew on the bay board, then the stop, timer, Jingle and sack during a run", function()
		local world, engine, me, Config = boot()
		world.run(function()
			expect(engine:guiShows("TAKE-OFF")).toBe(false)
			boardPublic(world, me)
			world.wait(0.5)
			expect(boardShows(engine, "CREW 1/" .. Config.Lobby.CrewMax)).toBe(true)
			shows(world, "TAKE-OFF", 30)
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
		local world, engine, me = boot()
		world.run(function()
			boardPublic(world, me)
			shows(world, "KRAMPUS'S LAIR", 200)
			shows(world, "KRAMPUS IS COMING!", 5)
			shows(world, "Best thief: Me", 200)
			shows(world, "(escaped x2)")
			shows(world, "Next run in")
			shows(world, "Heist again together!", 30)
		end)
	end)

	it("Leave crew and Back to hub buttons leave the sleigh and the run", function()
		local world, engine, me = boot()
		world.run(function()
			boardPublic(world, me)
			engine:guiButton("Leave crew").Activated:Fire()
			world.wait(0.5)
			expect(seated(me)).toBe(false)

			boardPublic(world, me)
			shows(world, "STOP 1/2", 60)
			engine:guiButton("Back to hub").Activated:Fire()
			world.wait(0.5)
			expect(engine:guiShows("STOP 1/2")).toBe(false)
		end)
	end)

	it("shows the hiding panel, and Space taps refill your breath", function()
		local world, engine, me = boot()
		world.run(function()
			boardPublic(world, me)
			shows(world, "STOP 1/2 · SNEAK", 60)
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
