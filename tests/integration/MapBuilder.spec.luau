-- Builds real Instances (Lune's Roblox library) from real plans and checks the
-- greybox layout: counts, prompts, sleigh placement, no overlapping houses.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")

local function buildRoute(seed)
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i)
		if i < #Config.Run.StopKinds then
			onFoot[i] = Loot.planOnFoot(rng)
		end
	end
	local parent = newFolder()
	return MapBuilder.buildRoute(parent, 1, rng, plans, onFoot), plans, parent
end

local function countClass(root, className)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.ClassName == className then
			n += 1
		end
	end
	return n
end

test("hub has a spawn, a Quick Join pad and returns the spawn point", function()
	local hub = MapBuilder.buildHub(newFolder())
	expect(countClass(hub.model, "SpawnLocation")).toBe(1)
	expect(hub.quickJoinPad.Name).toBe("QuickJoinPad")
	expect(hub.spawn).toBe(Config.Map.HubSpawn)
end)

test("route has one built stop per planned stop and a sleigh", function()
	local route, plans, parent = buildRoute(1)
	expect(#route.stops).toBe(#plans)
	expect(route.model.Parent).toBe(parent)
	expect(route.sleigh.PrimaryPart ~= nil).toBeTruthy()
end)

test("every planned present is built with a prompt", function()
	for seed = 1, 5 do
		local route, plans = buildRoute(seed)
		for i, stop in route.stops do
			local planned = 0
			for _, house in plans[i].houses do
				planned += #house.presents
			end
			expect(#stop.presents).toBe(planned)
			for _, present in stop.presents do
				expect(present.prompt.ClassName).toBe("ProximityPrompt")
				expect(present.prompt.Parent ~= nil).toBeTruthy()
			end
		end
		expect(#route.onFootPresents).toBe(Config.Presents.OnFootPresents * (#plans - 1))
	end
end)

test("street stops have a paid vault door; the finale has the Naughty List instead", function()
	local route = buildRoute(2)
	for _, stop in route.stops do
		if stop.plan.kindName == "Finale" then
			expect(stop.vaultPrompt).toBe(nil)
			expect(stop.presents[#stop.presents].model.Name).toBe("NaughtyList")
		else
			expect(stop.vaultPrompt.Enabled).toBeTruthy()
			expect(stop.vaultDoor.CanCollide).toBeTruthy()
		end
	end
end)

test("hiding spots and chimneys match the plan", function()
	local route = buildRoute(3)
	for _, stop in route.stops do
		local spots, chimneys = 0, 0
		for _, house in stop.plan.houses do
			spots += house.hideSpots
			chimneys += if house.chimney then 1 else 0
		end
		expect(#stop.hideSpots).toBe(spots)
		expect(#stop.chimneys).toBe(chimneys)
	end
end)

test("the sleigh lands on the ground at the Sleigh Stop and the clearing counts as aboard", function()
	local route = buildRoute(4)
	local r = Config.Map.SleighStopRadius
	for _, stop in route.stops do
		local deck = stop.deckCFrame
		local ground = deck.Position - Vector3.new(0, Config.Map.DeckHeight, 0)
		expect(deck.Position.Y).toBeLessThan(4) -- on the street, not a roof
		expect(MapBuilder.isAboard(deck, (deck * MapBuilder.SeatOffsets[1]).Position)).toBeTruthy()
		expect(MapBuilder.isAboard(deck, ground + Vector3.new(r - 1, 3, 0))).toBeTruthy()
		expect(MapBuilder.isAboard(deck, ground + Vector3.new(0, 3, r + 1))).toBeFalsy()
	end
end)

test("a map can put each Sleigh Stop where it wants", function()
	local Maps = load("ReplicatedStorage.Shared.Maps")
	local base = Maps.get()
	local map = table.clone(base)
	map.layout = table.clone(base.layout)
	local spot = CFrame.new(10, 0, 60)
	map.layout.LandingAt = { spot, spot, spot }
	local rng = Random.new(4)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	local route = MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })
	local origin = CFrame.new(0, 0, Config.Map.RouteOriginZ)
	local expected = (origin * spot).Position + Vector3.new(0, Config.Map.DeckHeight, 0)
	expect((route.stops[1].deckCFrame.Position - expected).Magnitude).toBeLessThan(0.01)
end)

test("houses on a street never overlap", function()
	for seed = 1, 5 do
		local route = buildRoute(seed)
		for _, stopModel in route.model:GetChildren() do
			local floors = {}
			for _, house in stopModel:GetChildren() do
				local floor = house:IsA("Model") and house:FindFirstChild("Floor")
				if floor then
					table.insert(floors, floor)
				end
			end
			for i = 1, #floors do
				for j = i + 1, #floors do
					local a, b = floors[i], floors[j]
					local gap = (a.CFrame.Position - b.CFrame.Position)
					local overlapX = math.abs(gap.X) < (a.Size.X + b.Size.X) / 2
					local overlapZ = math.abs(gap.Z) < (a.Size.Z + b.Size.Z) / 2
					expect(overlapX and overlapZ).toBeFalsy()
				end
			end
		end
	end
end)

test("everything in a route is anchored (nothing falls over)", function()
	local route = buildRoute(5)
	for _, d in route.model:GetDescendants() do
		if d:IsA("BasePart") then
			expect(d.Anchored).toBeTruthy()
		end
	end
end)

test("Krampus stand-in: humanoid rig, basket with bell prompt, about Config height", function()
	local body = MapBuilder.buildKrampus(newFolder(), CFrame.new(0, 5.5, 0))
	expect(body.humanoid.RequiresNeck).toBeFalsy()
	expect(body.root.Name).toBe("HumanoidRootPart")
	expect(body.bellPrompt.Parent).toBe(body.basket)
	local top, bottom = -math.huge, math.huge
	for _, part in body.model:GetChildren() do
		if part:IsA("BasePart") and part ~= body.root then
			top = math.max(top, part.CFrame.Position.Y + part.Size.Y / 2)
			bottom = math.min(bottom, part.CFrame.Position.Y - part.Size.Y / 2)
		end
	end
	expect(bottom).toBeNear(0, 0.01) -- feet on the floor
	expect(top - bottom).toBeNear(Config.Krampus.Height, 1)
	-- The basket is on his back, where the bells must be rung from.
	expect(body.root.CFrame:PointToObjectSpace(body.basket.CFrame.Position).Z).toBeGreaterThan(0)
end)

test("Krampus spawns in the open on streets and inside his Lair in the finale", function()
	for seed = 1, 5 do
		local route = buildRoute(seed)
		for i, stop in route.stops do
			local spawn = stop.krampusSpawn.Position
			local insideAny = nil
			for _, house in route.model:FindFirstChild("Stop" .. i .. "_" .. stop.plan.kindName):GetChildren() do
				local floor = house:IsA("Model") and house:FindFirstChild("Floor")
				if floor then
					local rel = floor.CFrame:PointToObjectSpace(spawn)
					if math.abs(rel.X) < floor.Size.X / 2 and math.abs(rel.Z) < floor.Size.Z / 2 then
						insideAny = house.Name
					end
				end
			end
			if stop.plan.kindName == "Finale" then
				expect(insideAny).toBe("LairHouse")
			else
				expect(insideAny).toBe(nil)
			end
		end
	end
end)

test("greybox routes use the six default sleigh seats", function()
	local route = buildRoute(4)
	expect(#route.seatOffsets).toBe(6)
	expect(route.seatOffsets).toBe(MapBuilder.SeatOffsets)
end)

test("elf stand-ins have a Humanoid, a root and their design's colours", function()
	for _, variant in Config.ElfBots.Variants do
		local elf = MapBuilder.buildElf(newFolder(), CFrame.new(0, 5, 0), variant)
		expect(elf.humanoid.ClassName).toBe("Humanoid")
		expect(elf.root.Name).toBe("HumanoidRootPart")
		expect(elf.humanoid.WalkSpeed).toBe(Config.ElfBots.WalkSpeed)
		expect(elf.model.Name).toBe(variant .. "StandIn")
	end
end)

test("only vault presents are marked as behind the vault door", function()
	local route = buildRoute(5)
	for _, stop in route.stops do
		local inVault = 0
		for _, present in stop.presents do
			if present.inVault then
				inVault += 1
			end
		end
		expect(inVault).toBe(if stop.vaultDoor then Config.Houses.Types.Vault.Presents else 0)
	end
end)

test("a map's palette, layout and features shape the built route", function()
	local Maps = load("ReplicatedStorage.Shared.Maps")
	local MapFeatures = load("ServerScriptService.Server.MapFeatures")
	local built = 0
	MapFeatures.TestPond = {
		build = function(ctx)
			built += 1
			ctx.newPart(ctx.model, "Pond", Vector3.new(20, 1, 20), ctx.origin, Color3.new(0, 0, 1))
		end,
	}
	local base = Maps.get()
	local map = table.clone(base)
	map.palette = table.clone(base.palette)
	map.palette.Road = { Color3.fromRGB(10, 20, 30), Enum.Material.Ice }
	map.layout = table.clone(base.layout)
	map.layout.RoadWidth = 40
	map.features = { { kind = "TestPond" } }

	local rng = Random.new(2)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	local route = MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })
	MapFeatures.TestPond = nil

	expect(built).toBe(#plans)
	expect(route.map).toBe(map)
	local stop1 = route.model:FindFirstChild("Stop1_" .. plans[1].kindName)
	local road = stop1:FindFirstChild("Road")
	expect(road.Size.X).toBe(40)
	expect(road.Material).toBe(Enum.Material.Ice)
	expect(stop1:FindFirstChild("Pond") ~= nil).toBeTruthy()
end)

test("every map in the rotation builds a full route", function()
	local Maps = load("ReplicatedStorage.Shared.Maps")
	for _, id in Maps.Rotation do
		local map = Maps.get(id)
		local rng = Random.new(1)
		local plans, onFoot = {}, {}
		for i = 1, #Config.Run.StopKinds do
			plans[i] = Loot.planStop(rng, i, map.layout.Slots)
			onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
		end
		local route = MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })
		expect(#route.stops).toBe(#plans)
	end
end)

test("maps can place stops anywhere and the paths follow them", function()
	local Maps = load("ReplicatedStorage.Shared.Maps")
	local base = Maps.get()
	local map = table.clone(base)
	map.layout = table.clone(base.layout)
	local lairAt = CFrame.new(0, 0, 300)
	map.layout.StopOrigins = {
		CFrame.new(0, 0, 0),
		CFrame.new(500, 0, 300) * CFrame.Angles(0, math.rad(90), 0),
		CFrame.new(900, 0, -200),
	}
	map.layout.EndHouseAt = { Finale = lairAt }

	local rng = Random.new(8)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	local route = MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })

	-- The sleigh lands at each stop's own Sleigh Stop, near that stop's origin.
	local routeBase = CFrame.new(0, 0, Config.Map.RouteOriginZ)
	for i, stop in route.stops do
		local origin = (routeBase * map.layout.StopOrigins[i]).Position
		local flat = (stop.deckCFrame.Position - origin) * Vector3.new(1, 0, 1)
		expect(flat.Magnitude).toBeLessThan(Config.Map.SideOffset + 10)
	end
	-- Each path runs from one stop's path point to the next.
	local paths = {}
	for _, d in route.model:GetChildren() do
		if d.Name == "FootPath" then
			table.insert(paths, d)
		end
	end
	expect(#paths).toBe(#plans - 1)
	for _, path in paths do
		expect(path.Size.Z).toBeGreaterThan(300)
	end
	-- The Lair sits where the map put it, with Krampus inside.
	local finale = route.stops[#route.stops]
	local lairPos = (routeBase * map.layout.StopOrigins[3] * lairAt).Position
	expect((finale.krampusSpawn.Position - lairPos).Magnitude).toBeLessThan(30)
end)
