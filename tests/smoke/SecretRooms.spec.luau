--[[
	Secret rooms played through a real Run (Josh, 6 Nov 2026): hold Search on
	the bookcase / rug / hatch, the room opens and glows gold for the crew,
	the Big present inside becomes grabbable, the finder gets Jingle, and the
	house's gift marker says SECRET FOUND.
]]

local function boot()
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 60
	Config.Run.LightsOnAt = 50
	Config.Run.HornAt = 55
	Config.MapEvents.Chance = 0
	Config.Houses.Secret.Chance = 1 -- every robbable house has one
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	return world, engine, Config, Run, { engine:addPlayer("A") }
end

it("finding a secret room opens it, lights it and pays the finder", function()
	local world, engine, Config, Run, players = boot()
	local santa = players[1]
	world.run(function()
		local run = Run.new(1, players, function() end)
		run:start()
		local deadline = engine.now + 200
		while not (run.stopIndex == 1 and run.phase ~= "Flight") do
			assert(engine.now < deadline, "never reached stop 1")
			world.wait(0.1)
		end
		local stop = run.route.stops[1]
		expect(#stop.secrets).toBeGreaterThan(0)
		local secret = stop.secrets[1]
		local house
		for _, h in stop.houses do
			if h.secret == secret then
				house = h
			end
		end
		expect(house ~= nil).toBeTruthy()
		expect(secret.present ~= nil).toBeTruthy()
		expect(secret.present.hidden).toBe(true)
		expect(secret.present.prompt.Enabled).toBe(false)
		expect(string.find(house.marker.Text, "SECRET", 1, true)).toBeNil()
		local before = secret.trigger.CFrame

		local st = run.players[santa]
		local jingle = st.jingle
		engine.trigger(secret.prompt, santa)
		world.wait(0.1)

		expect(secret.found).toBe(true)
		expect(secret.prompt.Enabled).toBe(false)
		expect(st.jingle).toBe(jingle + Config.Houses.Secret.FinderJingle)
		expect(secret.trigger.CFrame == before).toBe(false) -- swung / flipped open
		local glows = 0
		for _, d in secret.model:GetDescendants() do
			if d.Name == "SecretGlow" then
				glows += 1
				expect(d.Transparency).toBeLessThan(1)
			elseif d:IsA("PointLight") then
				expect(d.Enabled).toBe(true)
			end
		end
		expect(glows).toBeGreaterThan(0)
		expect(secret.present.hidden).toBeNil()
		expect(secret.present.prompt.Enabled).toBe(true)
		expect(string.find(house.marker.Text, "SECRET FOUND", 1, true) ~= nil).toBeTruthy()
		if secret.climb then
			expect(secret.climb.down.Enabled).toBe(true)
			expect(secret.climb.up.Enabled).toBe(true)
		end

		-- A second Search does nothing more.
		run:_findSecret(santa, stop, secret) -- (the prompt is off now)
		expect(st.jingle).toBe(jingle + Config.Houses.Secret.FinderJingle)

		-- The Big present inside can be grabbed now.
		local count = st.sackCount
		engine.trigger(secret.present.prompt, santa)
		world.wait(0.5)
		expect(st.sackCount).toBe(count + 1)
		run.ended = true
	end)
end)

it("elves never go for secret-room presents", function()
	local world, engine, _, Run, players = boot()
	world.run(function()
		local run = Run.new(1, players, function() end)
		run:start()
		local deadline = engine.now + 200
		while not (run.stopIndex == 1 and run.phase ~= "Flight") do
			assert(engine.now < deadline, "never reached stop 1")
			world.wait(0.1)
		end
		for _, c in run:presentCandidates() do
			expect(c.present.plan.secret).toBeNil()
		end
		run.ended = true
	end)
end)
