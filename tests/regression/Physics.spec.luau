--[[
	Physics and hazard regressions (4 Nov 2026 hardening pass), each played
	through a real Run in a headless world on Frozen Canal Town:

	- Corgi knockback set AssemblyLinearVelocity on the server, which a
	  client-owned Santa ignores: it now adds a replicated LinearVelocity.
	- Re-grabbing a present a corgi knocked out counted as another grab.
	- Dogs and the ice polisher bumped Santas standing on roofs above them.
	- Broken ice splashed on Touched, so a Santa who kept walking on the water
	  after the 1 s splash cooldown never re-touched it and strolled across
	  the lake: water is polled now.
	- Skating, boost hoops and their clean-up when the sleigh leaves.
]]

local function boot(names: { string }?)
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
	Config.MapEvents.Chance = 0
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local Run = world.load("ServerScriptService.Server.Run")
	local players = {}
	for i, name in names or { "A", "B" } do
		players[i] = engine:addPlayer(name)
	end
	return world, engine, Config, Run, players
end

local function startAtStop(world, Run, players, index: number)
	local run = Run.new(1, players, function() end)
	run:start()
	local deadline = world.engine.now + 400
	while not (run.stopIndex == index and run.phase ~= "Flight") do
		assert(world.engine.now < deadline, "never reached stop " .. index)
		world.wait(0.1)
	end
	world.wait(0.2) -- features started
	return run
end

local function banners(engine, player, pattern: string): number
	local n = 0
	for _, m in engine:hudMessages(player, "Banner") do
		if string.find(m.data.text, pattern, 1, true) then
			n += 1
		end
	end
	return n
end

local function findAll(root, name: string)
	local out = {}
	for _, d in root:GetDescendants() do
		if d.Name == name then
			table.insert(out, d)
		end
	end
	return out
end

-- Keeps a Santa at `offset` from a model's pivot (ground level) for `seconds`.
local function shadow(world, engine, player, model, rise: number, seconds: number, each: (() -> ())?)
	local t = 0
	while t < seconds do
		local p = model:GetPivot().Position
		engine:teleport(player, Vector3.new(p.X, rise, p.Z))
		world.wait(0.1)
		t += 0.1
		if each then
			each()
		end
	end
end

describe("security dogs", function()
	it("a corgi bump pushes with a replicated LinearVelocity, and re-grabbing isn't a new grab", function()
		local world, engine, Config, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local st = run.players[santa]
			st.sackCount, st.sackValue, st.grabs = 2, 200, 2
			local corgi = findAll(run.route.model, "DogCorgi")[1]
			expect(corgi).never.toBeNil()

			local pushed = nil
			local root = santa.Character.HumanoidRootPart
			shadow(world, engine, santa, corgi, 3, 1, function()
				local a = root:FindFirstChild("SleighHeistKnockback")
				pushed = pushed or (a and a:FindFirstChild("Push"))
			end)
			expect(pushed).never.toBeNil()
			expect(pushed.ClassName).toBe("LinearVelocity")
			expect(pushed.MaxForce).toBe(Config.Knockback.MaxForce)
			expect(pushed.VectorVelocity.Y).toBe(Config.Knockback.Lift)
			world.wait(Config.Knockback.Seconds + 0.2)
			expect(root:FindFirstChild("SleighHeistKnockback")).toBeNil() -- short-lived

			expect(st.sackCount).toBe(1)
			expect(st.sackValue).toBe(100)
			local dropped = findAll(run.route.model, "DroppedPresent")
			expect(#dropped).toBeGreaterThan(0)
			local prompt = dropped[1]:FindFirstChildWhichIsA("ProximityPrompt", true)
			local jingle = st.jingle
			engine.trigger(prompt, santa)
			world.wait(0.1)
			expect(st.sackCount).toBe(2)
			expect(st.sackValue).toBe(200)
			expect(st.grabs).toBe(2) -- the known bug: this was 3
			expect(st.jingle).toBe(jingle)
			run.ended = true
		end)
	end)

	it("a dog never bumps a Santa on a roof above it", function()
		local world, engine, _, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local st = run.players[santa]
			st.sackCount, st.sackValue = 2, 200
			for _, kind in { "DogCorgi", "DogTin" } do
				local dog = findAll(run.route.model, kind)[1]
				shadow(world, engine, santa, dog, 18, 1.5)
			end
			expect(st.sackCount).toBe(2)
			expect(santa.Character.HumanoidRootPart:FindFirstChild("SleighHeistKnockback")).toBeNil()
			expect(banners(engine, santa, "WOOF")).toBe(0)
			expect(banners(engine, santa, "BONK")).toBe(0)
			run.ended = true
		end)
	end)

	it("a tin dog bonk winds it down and knocks nothing out", function()
		local world, engine, _, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local st = run.players[santa]
			st.sackCount, st.sackValue = 2, 200
			local dog = findAll(run.route.model, "DogTin")[1]
			shadow(world, engine, santa, dog, 3, 0.6)
			expect(banners(engine, santa, "BONK")).toBe(1)
			expect(st.sackCount).toBe(2)
			-- Wound down: it stands still for a moment.
			local before = dog:GetPivot().Position
			world.wait(1)
			expect((dog:GetPivot().Position - before).Magnitude).toBeLessThan(0.01)
			run.ended = true
		end)
	end)

	-- Josh's first playtest (6 Nov 2026): "I can walk by them and they don't find me."
	it("a market dog spots a Santa in front of it and runs them down", function()
		local world, engine, _, Run, players = boot({ "A" })
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local corgi = findAll(run.route.model, "DogCorgi")[1]
			local pivot = corgi:GetPivot()
			local spot = pivot.Position + pivot.LookVector * 12
			engine:teleport(santa, Vector3.new(spot.X, 3, spot.Z))
			world.wait(2) -- standing still in front of it: seen, not heard
			expect(banners(engine, santa, "SPOTTED")).toBe(1)
			expect((corgi:GetPivot().Position - spot).Magnitude).toBeLessThan(6) -- ran at them
			run.ended = true
		end)
	end)

	-- 11 Nov 2026 (Josh: "their AI is pretty poor"): the sight ray only ignored
	-- dogs, so it hit the Santa's own body and every Santa read as behind a
	-- wall. Real rays here (engine.raycasts).
	it("with real rays a dog sees a Santa in front of it, not one behind a wall", function()
		local world, engine, _, Run, players = boot({ "A" })
		local santa = players[1]
		engine.raycasts = true
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local corgi = findAll(run.route.model, "DogCorgi")[1]
			local pivot = corgi:GetPivot()
			local spot = pivot.Position + pivot.LookVector * 12
			engine:teleport(santa, Vector3.new(spot.X, pivot.Position.Y, spot.Z))
			world.wait(1.5)
			expect(banners(engine, santa, "SPOTTED")).toBe(1)
			run.ended = true
		end)

		local world2, engine2, _, Run2, players2 = boot({ "B" })
		local hidden = players2[1]
		engine2.raycasts = true
		world2.run(function()
			local run = startAtStop(world2, Run2, players2, 1)
			local corgi = findAll(run.route.model, "DogCorgi")[1]
			local pivot = corgi:GetPivot()
			local wall = world2.engine.Instance.new("Part")
			wall.Name = "TestWall"
			wall.Size = Vector3.new(30, 30, 1)
			wall.Anchored = true
			wall.CFrame = CFrame.lookAt(pivot.Position + pivot.LookVector * 6, pivot.Position)
			wall.Parent = world2.engine.workspace
			local spot = pivot.Position + pivot.LookVector * 14
			engine2:teleport(hidden, Vector3.new(spot.X, pivot.Position.Y, spot.Z))
			world2.wait(0.6) -- stood still behind the wall: unseen (and unheard)
			expect(banners(engine2, hidden, "SPOTTED")).toBe(0)
			run.ended = true
		end)
	end)

	it("a Santa hiding in a wardrobe is never sniffed out", function()
		local world, engine, _, Run, players = boot({ "A" })
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local corgi = findAll(run.route.model, "DogCorgi")[1]
			run.players[santa].hidden = { occupant = santa } -- in a wardrobe
			local p = corgi:GetPivot()
			engine:teleport(santa, p.Position + p.LookVector * 6)
			world.wait(2)
			local mark = corgi:FindFirstChild("DogAlert", true)
			expect(mark.Enabled).toBeFalsy()
			run.players[santa].hidden = nil
			run.ended = true
		end)
	end)

	it("an empty sack gets a bump but nothing to drop", function()
		local world, engine, _, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local corgi = findAll(run.route.model, "DogCorgi")[1]
			shadow(world, engine, santa, corgi, 3, 0.6)
			expect(banners(engine, santa, "Your sack is empty")).toBe(1)
			expect(#findAll(run.route.model, "DroppedPresent")).toBe(0)
			run.ended = true
		end)
	end)
end)

describe("ice rink polisher", function()
	it("scoops a Santa on the ice into a snowbank, but not one above it", function()
		local world, engine, _, Run, players = boot()
		local santa, high = players[1], players[2]
		world.run(function()
			local run = startAtStop(world, Run, players, 2)
			local polisher = findAll(run.route.model, "IcePolisher")[1]
			expect(polisher).never.toBeNil()
			shadow(world, engine, high, polisher, 20, 1)
			expect(banners(engine, high, "WHOOSH")).toBe(0)

			local p = polisher:GetPivot().Position
			engine:teleport(santa, Vector3.new(p.X, 3, p.Z))
			world.wait(0.2)
			expect(banners(engine, santa, "WHOOSH")).toBe(1)
			local at = santa.Character.HumanoidRootPart.Position
			local nearest = math.huge
			for _, bank in run.route.stops[2].canal.rink.snowbanks do
				nearest = math.min(nearest, ((bank - at) * Vector3.new(1, 0, 1)).Magnitude)
			end
			expect(nearest).toBeLessThan(1)
			run.ended = true
		end)
	end)
end)

describe("floe hop", function()
	local function boxesOf(world, zone)
		local CanalTown = world.load("ServerScriptService.Server.CanalTown")
		local boxes = {}
		for _, floe in zone:FindFirstChild("Floes"):GetChildren() do
			table.insert(boxes, CanalTown.floeBox(floe))
		end
		return boxes
	end

	local function waterPoint(world, CanalRules, zone, standHeight: number): Vector3
		local boxes = boxesOf(world, zone)
		local box = { cframe = zone.CFrame, size = zone.Size }
		local top = zone.CFrame.Position.Y + zone.Size.Y / 2
		local hx, hz = zone.Size.X / 2 - 1, zone.Size.Z / 2 - 1
		for x = -math.min(hx, 100), math.min(hx, 100), 1.5 do
			for z = -math.min(hz, 150), math.min(hz, 150), 1.5 do
				local p = (zone.CFrame * CFrame.new(x, 0, z)).Position
				p = Vector3.new(p.X, top + standHeight, p.Z)
				if CanalRules.inWater(box, boxes, p, standHeight) then
					return p
				end
			end
		end
		error("no open water in the zone")
	end

	-- Round floes: on one if within a disc's radius, above it.
	local function onAFloe(zone, at: Vector3): boolean
		for _, floe in zone:FindFirstChild("Floes"):GetChildren() do
			local c = floe.CFrame.Position
			local flat = Vector3.new(at.X - c.X, 0, at.Z - c.Z).Magnitude
			if flat <= floe.Size.Z / 2 and at.Y > c.Y then
				return true
			end
		end
		return false
	end

	-- Thin Ice on a canal (no terrain water there) still SPLOOSHes you back
	-- onto a floe, polled so walking on the water can't dodge it.
	it("keeps splashing a Santa who keeps walking on broken canal ice", function()
		local world, engine, _, Run, players = boot()
		local santa = players[1]
		local CanalRules = world.load("ServerScriptService.Server.CanalRules")
		local CanalTown = world.load("ServerScriptService.Server.CanalTown")
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local zone
			for _, z in run.route.stops[1].canal.splashZones do
				if z:GetAttribute("CrackZone") then
					zone = z
					break
				end
			end
			assert(zone, "no Thin Ice segment on stop 1")
			CanalTown.breakZone(zone, Random.new(2))
			local water = waterPoint(world, CanalRules, zone, 3)

			engine:teleport(santa, water)
			world.wait(0.3)
			expect(banners(engine, santa, "SPLOOSH")).toBe(1)
			expect(onAFloe(zone, santa.Character.HumanoidRootPart.Position)).toBe(true)

			-- Straight back onto the water inside the 1 s cooldown, then stay
			-- there: the old Touched splash never fired again.
			engine:teleport(santa, water)
			world.wait(2)
			expect(banners(engine, santa, "SPLOOSH")).toBe(2)
			expect(onAFloe(zone, santa.Character.HumanoidRootPart.Position)).toBe(true)
			run.ended = true
		end)
	end)

	it("a Santa standing on a floe or hopping over the water stays dry", function()
		local world, engine, Config, Run, players = boot()
		local santa = players[1]
		local CanalRules = world.load("ServerScriptService.Server.CanalRules")
		world.run(function()
			local run = startAtStop(world, Run, players, 3)
			local lake = run.route.stops[3].canal.lake
			world.wait(Config.Canal.StompDelay + 0.5)
			if run.krampus then
				run.krampus.stunnedUntil = math.huge
			end
			local floe = lake:FindFirstChild("Floes"):GetChildren()[1]
			local top = floe.CFrame.Position.Y + floe.Size.X / 2
			engine:teleport(santa, Vector3.new(floe.CFrame.Position.X, top + 3, floe.CFrame.Position.Z))
			world.wait(1.5)
			local water = waterPoint(world, CanalRules, lake, 3)
			engine:teleport(santa, water + Vector3.new(0, 4, 0)) -- mid-hop
			world.wait(1.5)
			expect(banners(engine, santa, "SPLOOSH")).toBe(0)
			run.ended = true
		end)
	end)

	it("unbroken ice never splashes", function()
		local world, engine, _, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local zone = run.route.stops[1].canal.splashZones[1]
			expect(zone:GetAttribute("Broken")).toBeFalsy()
			local top = zone.CFrame.Position.Y + zone.Size.Y / 2
			engine:teleport(santa, zone.CFrame.Position + Vector3.new(0, top + 3 - zone.CFrame.Position.Y, 0))
			world.wait(1.5)
			expect(banners(engine, santa, "SPLOOSH")).toBe(0)
			run.ended = true
		end)
	end)
end)

-- Josh's playtest (6 Nov 2026): the Lair's water was glitchy (a fall
-- snapped you back onto a floe) and the floes were all rectangles. Now the
-- lake is real water: you swim, body heat drains, and at zero you freeze
-- and wash ashore. Krampus never swims.
describe("Lair swimming and body heat", function()
	local function lakeRun(world, Run, players, Config)
		local run = startAtStop(world, Run, players, 3)
		world.wait(Config.Canal.StompDelay + 0.5)
		if run.krampus then
			run.krampus.stunnedUntil = math.huge -- this is about water
		end
		return run, run.route.stops[3].canal.lake
	end

	local function swimAt(engine, santa, at: Vector3)
		engine:teleport(santa, at)
		santa.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
	end

	it("the stomp clears the ice away and leaves round floes, with no SPLOOSH snap", function()
		local world, engine, Config, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run, lake = lakeRun(world, Run, players, Config)
			expect(lake:GetAttribute("Broken")).toBe(true)
			expect(lake.CanCollide).toBe(false)
			expect(lake.Transparency).toBe(1)
			for _, floe in lake:FindFirstChild("Floes"):GetChildren() do
				expect(floe.Shape).toBe(Enum.PartType.Cylinder)
			end
			swimAt(engine, santa, lake.CFrame.Position + Vector3.new(60, 0, 0))
			world.wait(1)
			expect(banners(engine, santa, "SPLOOSH")).toBe(0)
			run.ended = true
		end)
	end)

	it("swimming drains body heat; at zero you freeze, wash ashore and come back soggy", function()
		local world, engine, Config, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run, lake = lakeRun(world, Run, players, Config)
			local st = run.players[santa]
			local at = lake.CFrame.Position + Vector3.new(80, 0, 0)
			swimAt(engine, santa, at)
			world.wait(Config.BodyHeat.SwimSeconds / 2)
			local half = santa:GetAttribute("BodyHeat")
			expect(half).toBeLessThan(0.6)
			expect(half).toBeGreaterThan(0.3)
			expect(st.swimming).toBe(true)

			world.wait(Config.BodyHeat.SwimSeconds / 2 + 0.3)
			expect(st.frozen).toBe(true)
			expect(santa:GetAttribute("Frozen")).toBe(true)
			expect(santa.Character.HumanoidRootPart.Anchored).toBe(true)
			expect(banners(engine, santa, "FROZEN SOLID")).toBe(1)
			expect(run:_free(santa)).toBeNil() -- no buying or grabbing in an ice cube

			santa.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
			world.wait(Config.BodyHeat.FrozenSeconds + 0.3)
			expect(st.frozen).toBe(false)
			expect(santa:GetAttribute("Frozen")).toBeNil()
			expect(santa.Character.HumanoidRootPart.Anchored).toBe(false)
			-- Washed up on the bridge or the island, not left in the water.
			local swim = run.route.stops[3].canal.swim
			local p = santa.Character.HumanoidRootPart.Position
			local flat = Vector3.new(p.X - swim.island.X, 0, p.Z - swim.island.Z).Magnitude
			local onBridge = math.abs(
				(p - swim.bridgeFrom):Dot((swim.bridgeTo - swim.bridgeFrom).Unit:Cross(Vector3.yAxis))
			) < 1
			expect(flat < swim.islandRadius or onBridge).toBe(true)
			expect(run:baseWalkSpeed(st)).toBe(Config.BodyHeat.SoggyWalkSpeed)
			world.wait(Config.BodyHeat.SoggySeconds + 0.2)
			expect(run:baseWalkSpeed(st)).toBe(Config.Player.WalkSpeed)
			run.ended = true
		end)
	end)

	it("heat comes back on land, fastest by the island's fires", function()
		local world, engine, Config, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run, lake = lakeRun(world, Run, players, Config)
			swimAt(engine, santa, lake.CFrame.Position + Vector3.new(80, 0, 0))
			world.wait(Config.BodyHeat.SwimSeconds / 2)
			local swim = run.route.stops[3].canal.swim
			engine:teleport(santa, swim.island + Vector3.new(0, 3, 0))
			santa.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
			world.wait(Config.BodyHeat.FireRecoverSeconds)
			expect(santa:GetAttribute("BodyHeat")).toBe(1)
			run.ended = true
		end)
	end)

	it("Krampus won't chase a Santa in the water", function()
		local world, engine, Config, Run, players = boot({ "A" })
		local santa = players[1]
		world.run(function()
			local run, lake = lakeRun(world, Run, players, Config)
			swimAt(engine, santa, lake.CFrame.Position + Vector3.new(60, 0, 0))
			world.wait(0.3)
			local list = run:krampusCandidates({})
			expect(list[1].inWater).toBe(true)
			local KrampusBrain = world.load("ServerScriptService.Server.KrampusBrain")
			expect(KrampusBrain.pickTarget(list[1].position, list, math.huge)).toBeNil()
			run.ended = true
		end)
	end)
end)

describe("skating", function()
	it("ice skates, a hoop boosts, and leaving the stop puts speeds back", function()
		local world, engine, Config, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			local humanoid = santa.Character.Humanoid
			humanoid.FloorMaterial = Enum.Material.Ice
			world.wait(0.3)
			expect(humanoid.WalkSpeed).toBe(Config.Canal.SkateSpeed)
			humanoid.FloorMaterial = Enum.Material.Snow
			world.wait(0.3)
			expect(humanoid.WalkSpeed).toBe(Config.Player.WalkSpeed)

			local hoop = run.route.stops[1].canal.hoops[1]
			engine:teleport(santa, hoop.CFrame.Position)
			world.wait(0.3)
			expect(humanoid.WalkSpeed).toBe(Config.Canal.HoopSpeed)
			engine:teleport(santa, hoop.CFrame.Position + Vector3.new(0, 0, 30))
			world.wait(Config.Canal.HoopBoostSeconds + 0.3)
			expect(humanoid.WalkSpeed).toBe(Config.Player.WalkSpeed)

			-- Still skating as the sleigh leaves: back to walking speed after.
			humanoid.FloorMaterial = Enum.Material.Ice
			while run.stopIndex == 1 and run.phase ~= "Flight" do
				world.wait(0.2)
			end
			world.wait(0.3)
			expect(humanoid.WalkSpeed).toBe(Config.Player.WalkSpeed)
			run.ended = true
		end)
	end)

	it("Peppermint Rush is never slowed by skating", function()
		local world, _, Config, Run, players = boot()
		local santa = players[1]
		world.run(function()
			local run = startAtStop(world, Run, players, 1)
			run.players[santa].perks.PeppermintRush = true
			local humanoid = santa.Character.Humanoid
			humanoid.FloorMaterial = Enum.Material.Ice
			world.wait(0.3)
			expect(humanoid.WalkSpeed).toBe(
				math.max(Config.Buys.PeppermintRush.WalkSpeed, Config.Canal.SkateSpeed)
			)
			run.ended = true
		end)
	end)
end)
