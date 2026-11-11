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

describe("noise alarm (Josh, 6 Nov)", function()
	local function startStop1(world)
		local engine = world.engine
		local Config = world.load("ReplicatedStorage.Shared.Config")
		fastRuns(Config)
		Config.Noise.Alarm.HornSeconds = 5 -- shorter than the fast 24 s stop
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local Run = world.load("ServerScriptService.Server.Run")
		local a = engine:addPlayer("A")
		local run = Run.new(1, { a }, function() end)
		run:start()
		while run.stopIndex < 1 or run.phase ~= "Sneak" do
			world.wait(0.1)
		end
		-- Off the sleigh, so the stop doesn't end early with everyone aboard.
		local root = a.Character.HumanoidRootPart
		root.CFrame = run.route.stops[1].deckCFrame * CFrame.new(0, 3, 60)
		return run, engine
	end

	local function hasDog(run): boolean
		for _, d in run.route.model:GetDescendants() do
			if d:IsA("Model") and string.sub(d.Name, 1, 3) == "Dog" and d.Name ~= "DroppedPresent" then
				return true
			end
		end
		return false
	end

	it("a full meter on Stop 1 lets the dogs loose and sounds the horn early", function()
		local world = headless()
		world.run(function()
			local run, engine = startStop1(world)
			local before = run.times.departAt
			run:_addNoise(10000)
			world.wait(0.5)
			expect(run.phase).toBe("Horn")
			expect(run.times.departAt < before).toBeTruthy()
			expect(run.times.departAt - engine.now <= 5).toBeTruthy()
			expect(hasDog(run)).toBeTruthy()
		end, { maxSeconds = 120 })
	end)

	it("an alarm after the horn doesn't reset the countdown to 30", function()
		local world = headless()
		world.run(function()
			local run = startStop1(world)
			while run.phase ~= "Horn" do
				world.wait(0.1)
			end
			local departAt = run.times.departAt
			run:_addNoise(10000)
			world.wait(0.5)
			expect(run.times.departAt).toBe(departAt)
			expect(hasDog(run)).toBeTruthy()
		end, { maxSeconds = 120 })
	end)
end)

describe("bugs found 11 Nov", function()
	-- Josh: "you can walk through the vault without unlocking it". The imported
	-- VaultDoor's parts all have CanCollide off (Meshy props never collide), and
	-- the house's own door was removed to make room for it.
	it("the real VaultDoor model leaves its doorway solid until the vault is bought", function()
		local fs = require("@lune/fs")
		local roblox = require("@lune/roblox")
		local vault = roblox.deserializeModel(fs.readFile("assets/models/VaultDoor.rbxm"))[1]
		local Config = load("ReplicatedStorage.Shared.Config")
		local Loot = load("ServerScriptService.Server.Loot")
		local MapBuilder = load("ServerScriptService.Server.MapBuilder")
		local rng = Random.new(11)
		local plans, onFoot = {}, {}
		for i = 1, #Config.Run.StopKinds do
			plans[i] = Loot.planStop(rng, i)
			onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
		end
		local route = MapBuilder.buildRoute(
			Instance.new("Folder"),
			1,
			rng,
			plans,
			onFoot,
			{ houseKit = { houses = {}, vaultDoor = vault } }
		)
		local vaults = 0
		for _, stop in route.stops do
			if stop.vaultPrompt then
				vaults += 1
				expect(stop.vaultDoor.CanCollide).toBe(false) -- the model itself is all looks
				expect(stop.vaultBlocker.CanCollide).toBe(true)
				local offset = stop.vaultBlocker.CFrame:PointToObjectSpace(stop.vaultDoor.CFrame.Position)
				expect(math.abs(offset.X) < stop.vaultBlocker.Size.X / 2).toBe(true)
				expect(math.abs(offset.Y) < stop.vaultBlocker.Size.Y / 2).toBe(true)
			end
		end
		expect(vaults).toBeGreaterThan(0)
	end)
end)
