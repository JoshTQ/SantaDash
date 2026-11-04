--[[
	The Blizzard map event played through a real Run (headless): piles,
	snowballs, splats, the MVP shout-out and clean-up, and the client side
	(the HUD's fog and snow), including the Atmosphere bug: Roblox ignores
	Lighting.FogEnd while an Atmosphere exists, so the blizzard had no fog.
]]

local function boot()
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 14
	Config.Run.ResultsSeconds = 2
	Config.MapEvents.Chance = 1
	Config.MapEvents.WarningSeconds = 2
	Config.MapEvents.StartAt = 3
	Config.MapEvents.MaxSeconds = 8
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	local a, b = engine:addPlayer("Ana"), engine:addPlayer("Bo")
	return world, engine, Config, Run, a, b
end

local function last(engine, player, kind: string)
	local list = engine:hudMessages(player, kind)
	return list[#list] and list[#list].data
end

local function bannerHas(engine, player, text: string): boolean
	for _, m in engine:hudMessages(player, "Banner") do
		if string.find(m.data.text, text, 1, true) then
			return true
		end
	end
	return false
end

describe("Blizzard", function()
	it("plays at its stop: fog, muffled noise, piles, throws, splats, MVP and clean-up", function()
		local world, engine, Config, Run, ana, bo = boot()
		local cfg = Config.MapEvents.Events.Blizzard
		world.run(function()
			local run = Run.new(1, { ana, bo }, function() end)
			expect(run.eventPlan).never.toBeNil()
			expect(run.eventPlan.kind).toBe("Blizzard")
			run:start()
			while not run.eventCleanup do
				world.wait(0.2)
			end
			expect(run.stopIndex).toBe(run.eventPlan.stop)
			expect(run.noiseScale).toBe(cfg.NoiseMultiplier)

			-- The client is told to thicken the Atmosphere, not just FogEnd.
			local weather = last(engine, ana, "Weather")
			expect(weather.kind).toBe("Blizzard")
			expect(weather.density).toBe(cfg.AtmosphereDensity)
			expect(weather.haze).toBe(cfg.AtmosphereHaze)

			local folder = run.route.model:FindFirstChild("Blizzard")
			local piles = {}
			for _, d in folder:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					table.insert(piles, d)
				end
			end
			expect(#piles).toBe(#cfg.Piles)

			-- No snowballs yet: a throw does nothing.
			run:onInput(ana, "Throw")
			expect(folder:FindFirstChild("Snowball")).toBeNil()

			engine.trigger(piles[1], ana)
			world.wait(0.1)
			expect(last(engine, ana, "Snowballs").count).toBe(cfg.PileSnowballs)
			engine.trigger(piles[1], ana)
			engine.trigger(piles[1], ana)
			world.wait(0.1)
			expect(last(engine, ana, "Snowballs").count).toBe(cfg.MaxSnowballs) -- capped

			run:onInput(ana, "Throw")
			run:onInput(ana, "Throw") -- inside the cooldown: ignored
			world.wait(0.05)
			expect(last(engine, ana, "Snowballs").count).toBe(cfg.MaxSnowballs - 1)
			local ball = folder:FindFirstChild("Snowball")
			expect(ball).never.toBeNil()
			expect(ball.AssemblyLinearVelocity.Magnitude).toBeNear(cfg.ThrowSpeed, 0.01)

			-- It hits Bo: a cosmetic splat for Bo, a cheer for Ana.
			ball.Touched:Fire(bo.Character.HumanoidRootPart)
			world.wait(0.1)
			expect(ball.Parent).toBeNil()
			expect(last(engine, bo, "Splat").by).toBe(ana.DisplayName)
			expect(bannerHas(engine, ana, "SPLAT! You got")).toBe(true)

			-- A throw that hits the thrower's own body doesn't count.
			world.wait(cfg.ThrowCooldown)
			run:onInput(ana, "Throw")
			world.wait(0.05)
			local own = folder:FindFirstChild("Snowball")
			own.Touched:Fire(ana.Character.HumanoidRootPart)
			world.wait(0.1)
			expect(own.Parent).never.toBeNil()
			world.wait(cfg.SnowballLife + 0.2)
			expect(own.Parent).toBeNil() -- a miss melts

			-- Bo can't throw what he never picked up.
			run:onInput(bo, "Throw")
			expect(last(engine, bo, "Snowballs")).toBeNil()

			while run.eventCleanup do
				world.wait(0.2)
			end
			expect(run.noiseScale).toBe(1)
			expect(run.eventInput).toBeNil()
			expect(folder.Parent).toBeNil()
			expect(last(engine, ana, "Snowballs").count).toBe(0)
			expect(last(engine, ana, "Weather").kind).toBeNil()
			expect(bannerHas(engine, ana, "Snowball MVP: " .. ana.DisplayName .. " (1 splats)")).toBe(true)
			run.ended = true
		end)
	end)

	it("a pile grows back the ball it lost", function()
		local world, engine, Config, Run, ana, bo = boot()
		local cfg = Config.MapEvents.Events.Blizzard
		-- An approved-looking SnowPile model with balls to hide.
		local Assets = engine:service("ServerStorage")
		local New = engine.Instance.new
		local folder = New("Folder")
		folder.Name = "Assets"
		local pile = New("Model")
		pile.Name = "SnowPile"
		for _, name in { "Drift", "Ball1", "Ball2", "Ball3", "Ball4", "Ball5", "Glow" } do
			local p = New("Part")
			p.Name = name
			p.Parent = pile
		end
		pile.PrimaryPart = pile:FindFirstChild("Drift")
		pile.Parent = folder
		folder.Parent = Assets
		world.run(function()
			local run = Run.new(1, { ana, bo }, function() end)
			run:start()
			while not run.eventCleanup do
				world.wait(0.2)
			end
			local live = run.route.model:FindFirstChild("Blizzard"):FindFirstChild("SnowPile")
			local prompt = live:FindFirstChildWhichIsA("ProximityPrompt", true)
			engine.trigger(prompt, ana)
			world.wait(0.1)
			expect(live:FindFirstChild("Ball1").Transparency).toBe(1)
			world.wait(cfg.PileRegrowSeconds + 0.2)
			expect(live:FindFirstChild("Ball1").Transparency).toBe(0)
			run.ended = true
		end)
	end)
end)

describe("Blizzard on the client", function()
	it("thickens the night Atmosphere (FogEnd alone does nothing) and puts it back", function()
		local world = headless()
		local engine = world.engine
		local me = engine:addPlayer("Me")
		engine:setLocalPlayer(me)
		local Config = world.load("ReplicatedStorage.Shared.Config")
		local cfg = Config.MapEvents.Events.Blizzard
		world.run(function()
			world.runScript("ServerScriptService.Server.Main") -- night lighting + Atmosphere
			world.runScript("StarterPlayer.StarterPlayerScripts.Client.Hud")
			world.wait(0.5)
			local Lighting = engine:service("Lighting")
			local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
			expect(atmosphere).never.toBeNil()
			local density, haze, color = atmosphere.Density, atmosphere.Haze, atmosphere.Color
			local hud = world.load("ReplicatedStorage.Shared.Remotes").get("Hud")

			hud:FireClient(me, "Weather", {
				kind = "Blizzard",
				fogEnd = cfg.FogEnd,
				fogColor = cfg.FogColor,
				density = cfg.AtmosphereDensity,
				haze = cfg.AtmosphereHaze,
			})
			world.wait(0.2)
			expect(atmosphere.Density).toBe(cfg.AtmosphereDensity)
			expect(atmosphere.Haze).toBe(cfg.AtmosphereHaze)
			expect(engine.workspace:FindFirstChild("Snowfall")).never.toBeNil()

			hud:FireClient(me, "Weather", {})
			world.wait(0.2)
			expect(atmosphere.Density).toBe(density)
			expect(atmosphere.Haze).toBe(haze)
			expect(atmosphere.Color).toBe(color)
			expect(engine.workspace:FindFirstChild("Snowfall")).toBeNil()
		end)
	end)
end)
