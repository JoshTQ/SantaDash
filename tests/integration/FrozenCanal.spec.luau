-- Builds Frozen Canal Town from real plans and checks its geometry: the
-- Sleigh Stops sit on dry ground, ice is tagged for skating and Thin Ice,
-- the Lair is on its island, and the street dressing is there.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local Maps = load("ReplicatedStorage.Shared.Maps")
local CanalTown = load("ServerScriptService.Server.CanalTown")

local function build(seed)
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	return MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map }), map
end

local function named(root, name)
	local list = {}
	for _, d in root:GetDescendants() do
		if d.Name == name then
			table.insert(list, d)
		end
	end
	return list
end

-- Is the flat point inside the part's footprint (any rotation about Y)?
local function over(part, p)
	local l = part.CFrame:PointToObjectSpace(p)
	if part.Shape == Enum.PartType.Cylinder then
		return math.sqrt(l.Y * l.Y + l.Z * l.Z) < part.Size.Y / 2
	end
	return math.abs(l.X) < part.Size.X / 2 and math.abs(l.Z) < part.Size.Z / 2
end

test("Frozen Canal Town is in the rotation and builds every stop", function()
	expect(table.find(Maps.Rotation, "FrozenCanal") ~= nil).toBeTruthy()
	local route = build(1)
	expect(#route.stops).toBe(#Config.Run.StopKinds)
	for _, stop in route.stops do
		expect(stop.canal ~= nil).toBeTruthy()
		expect(#stop.canal.iceZones).toBeGreaterThan(0)
	end
end)

test("each Sleigh Stop is on dry ground, never on ice", function()
	for seed = 1, 3 do
		local route = build(seed)
		for _, stop in route.stops do
			local p = stop.deckCFrame.Position
			for _, s in route.stops do
				for _, zone in s.canal.iceZones do
					expect(over(zone, p)).toBeFalsy()
				end
			end
			for _, road in named(route.model, "Road") do
				expect(over(road, p)).toBeFalsy()
			end
		end
	end
end)

test("only middle canal pieces are CrackZone, far from every stop", function()
	local route = build(2)
	local cracks = 0
	for _, stop in route.stops do
		for _, zone in stop.canal.iceZones do
			expect(zone:GetAttribute("IceZone")).toBe(true)
			if zone:GetAttribute("CrackZone") then
				cracks += 1
				for _, s in route.stops do
					local d = (zone.CFrame.Position - s.deckCFrame.Position).Magnitude
					expect(d).toBeGreaterThan(Config.Canal.StopEndClear + 20)
				end
			end
		end
	end
	expect(cracks).toBeGreaterThan(6)
	expect(#named(route.model, "BellBridge")).toBe(1)
end)

test("the Lair sits on its island and the lake breaks into floes around it", function()
	local route, map = build(3)
	local finale = route.stops[#route.stops]
	local island = named(route.model, "Island")[1]
	local d = ((finale.krampusSpawn.Position - island.CFrame.Position) * Vector3.new(1, 0, 1)).Magnitude
	local lake
	for _, f in map.features do
		if f.kind == "FloeLake" then
			lake = f
		end
	end
	expect(d).toBeLessThan(lake.islandRadius)
	local floes = CanalTown.breakZone(finale.canal.lake, Random.new(1))
	expect(#floes).toBeGreaterThan(100)
	expect(finale.canal.lake:GetAttribute("Broken")).toBe(true)
	for _, f in floes do
		expect(over(island, f.CFrame.Position)).toBeFalsy()
	end
	expect(#CanalTown.breakZone(finale.canal.lake)).toBe(#floes) -- twice is safe
end)

test("streets have gardens, fences, hedges and barriers; the market and rink are at their stops", function()
	local route = build(4)
	local stop1 = route.model:FindFirstChild("Stop1_Street")
	local stop2 = route.model:FindFirstChild("Stop2_Street")
	for _, name in { "Lawn", "Picket", "Hedge", "Bollard", "Pavement", "IceSign", "BoostHoop" } do
		expect(#named(stop1, name)).toBeGreaterThan(0)
	end
	expect(#named(stop1, "StallCounter")).toBeGreaterThan(10)
	expect(#route.stops[1].canal.dogs).toBe(Config.Canal.Dogs.Count)
	expect(#named(stop2, "StallCounter")).toBe(0)
	expect(#named(stop2, "RinkIce")).toBe(1)
	expect(#route.stops[2].canal.rink.snowbanks).toBe(4)
end)

test("dog patrols keep out of the Sleigh Stop", function()
	local route = build(5)
	local stop = route.stops[1]
	for _, dog in stop.canal.dogs do
		for _, p in dog.points do
			local d = ((p - stop.deckCFrame.Position) * Vector3.new(1, 0, 1)).Magnitude
			expect(d).toBeGreaterThan(Config.Map.SleighStopRadius + Config.Canal.Dogs.HitRadius)
		end
	end
end)

test("the town has a forest, hills and Christmas lights, all off the streets", function()
	local route = build(6)
	expect(#named(route.model, "PineTier")).toBeGreaterThan(300)
	expect(#named(route.model, "SnowHill")).toBeGreaterThan(5)
	expect(#named(route.model, "Bulb")).toBeGreaterThan(200)
	expect(#named(route.model, "Wreath")).toBeGreaterThan(10)
	local lamps = named(route.model, "LampGlow")
	expect(lamps[1]:FindFirstChildOfClass("PointLight") ~= nil).toBeTruthy()
	-- No tree trunk stands on a street canal, a canal, the lake or a Sleigh Stop.
	local blockers = {}
	for _, n in { "Road", "CanalIce", "LakeIce", "Plaza", "Island" } do
		for _, p in named(route.model, n) do
			table.insert(blockers, p)
		end
	end
	for _, trunk in named(route.model, "PineTrunk") do
		for _, b in blockers do
			expect(over(b, trunk.CFrame.Position)).toBeFalsy()
		end
	end
end)
