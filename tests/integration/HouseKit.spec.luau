-- Approved house models, faked with plain parts that follow the models
-- thread's contract, built through the real MapBuilder.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local HouseKit = load("ServerScriptService.Server.HouseKit")

local function part(parent, name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.Parent = parent
	return p
end

-- A house built far from the origin, to prove placement is relative.
local function fakeHouse(style)
	local m = Instance.new("Model")
	m.Name = "House"
	local at = CFrame.new(500, 50, -300)
	local floor = part(m, "Floor", Vector3.new(24, 1, 24), at)
	m.PrimaryPart = floor
	m:SetAttribute("Style", style)
	part(m, "Walls", Vector3.new(24, 12, 24), at * CFrame.new(0, 6.5, 0)).Transparency = 1
	part(m, "TypeSign", Vector3.new(4, 2, 0.5), at * CFrame.new(0, 16, 0))
	part(m, "ChimneyTop", Vector3.new(3, 1, 3), at * CFrame.new(6, 18, 6))
	part(m, "Fireplace", Vector3.new(5, 4, 2), at * CFrame.new(0, 2.5, 10))
	part(m, "Wardrobe", Vector3.new(3, 8, 4), at * CFrame.new(-9, 4.5, 4))
	local front = Instance.new("Model")
	front.Name = "FrontDoor"
	front.Parent = m
	part(front, "Door", Vector3.new(4, 8, 0.5), at * CFrame.new(0, 4.5, -12))
	for i = 1, 3 do
		part(m, "PresentSpawn" .. i, Vector3.new(1, 0.2, 1), at * CFrame.new(i * 3 - 6, 0.6, 0))
	end
	return m
end

local function fakeLair()
	local m = Instance.new("Model")
	m.Name = "KrampusLair"
	local at = CFrame.new(-50, 20, 80)
	m.PrimaryPart = part(m, "Floor", Vector3.new(44, 1, 44), at)
	part(m, "ListPedestal", Vector3.new(3, 3, 3), at * CFrame.new(0, 2, 10))
	part(m, "KrampusSpawn", Vector3.new(2, 0.2, 2), at * CFrame.new(0, 0.6, 15))
	part(m, "HideSpot1", Vector3.new(4, 4, 4), at * CFrame.new(-15, 2.5, 0))
	part(m, "HideSpot2", Vector3.new(3, 8, 4), at * CFrame.new(15, 4.5, 0))
	return m
end

local function fakeVaultDoor()
	local m = Instance.new("Model")
	m.Name = "VaultDoor"
	local at = CFrame.new(0, 100, 0)
	m.PrimaryPart = part(m, "Frame", Vector3.new(10, 13, 1), at)
	part(m, "Door", Vector3.new(8, 12, 0.6), at * CFrame.new(0, -0.5, 0))
	return m
end

local function build(kit, seed)
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	return MapBuilder.buildRoute(Instance.new("Folder"), 1, rng, plans, onFoot, { houseKit = kit }), plans
end

test("street houses come from the approved kit, sitting on the ground", function()
	local kit = { houses = { fakeHouse("candy"), fakeHouse("alpine") } }
	local route, plans = build(kit, 3)
	local stop = route.stops[1]
	local found = 0
	local stopModel = route.model:FindFirstChild("Stop1_" .. plans[1].kindName)
	for _, child in stopModel:GetChildren() do
		if child.Name:match("House$") and child:FindFirstChild("Wardrobe") then
			found += 1
			local floor = child:FindFirstChild("Floor")
			expect(floor.Anchored).toBeTruthy()
			expect(floor.CFrame.Position.Y - floor.Size.Y / 2).toBeNear(0, 0.01)
			expect(child:GetAttribute("HouseType") ~= nil).toBeTruthy()
		end
	end
	expect(found).toBe(#plans[1].houses - 1) -- every house but the vault
	expect(#stop.doors).toBe(found)
	expect(#stop.chimneys).toBe(found)
end)

test("kit houses fill their spawn points first and keep every present", function()
	local route, plans = build({ houses = { fakeHouse("candy") } }, 5)
	for i, stop in route.stops do
		local planned = 0
		for _, house in plans[i].houses do
			planned += #house.presents
		end
		expect(#stop.presents).toBe(planned)
	end
end)

test("the landing house is always a candy house", function()
	local alpineOnly = { fakeHouse("alpine") }
	local candy = fakeHouse("candy")
	local rng = Random.new(1)
	expect(HouseKit.pick(alpineOnly, rng, { isLanding = true, ring = "Near" })).toBe(nil)
	expect(HouseKit.pick({ candy, alpineOnly[1] }, rng, { isLanding = true, ring = "Near" })).toBe(candy)
	expect(HouseKit.pick({ candy, alpineOnly[1] }, rng, { isLanding = false, ring = "Far" })).toBe(
		alpineOnly[1]
	)
end)

test("the Lair model sets Krampus's spawn, hide spots and the Naughty List pedestal", function()
	local route = build({ houses = {}, lair = fakeLair() }, 2)
	local finale = route.stops[#route.stops]
	expect(#finale.hideSpots).toBe(Config.Houses.Types.Lair.HideSpots + 1) -- + the landing house's
	local list
	for _, present in finale.presents do
		if present.plan.naughtyList then
			list = present
		end
	end
	local spawnHeight = finale.krampusSpawn.Position.Y
	expect(spawnHeight).toBeLessThan(10)
	expect(list ~= nil).toBeTruthy()
end)

test("the approved vault door goes in the vault doorway and swings open", function()
	local route = build({ houses = {}, vaultDoor = fakeVaultDoor() }, 4)
	local door = route.stops[1].vaultDoor
	expect(door.Name).toBe("Door")
	expect(door.CFrame.Position.Y).toBeLessThan(15)
	local open = HouseKit.doorCFrame(door.CFrame, door.Size, true)
	expect((open.Position - door.CFrame.Position).Magnitude).toBeGreaterThan(1)
	expect(HouseKit.doorCFrame(door.CFrame, door.Size, false)).toBe(door.CFrame)
end)
