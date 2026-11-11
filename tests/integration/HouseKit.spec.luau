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
	-- Every house, the vault too (its front door is the vault door, no chimney).
	expect(found).toBe(#plans[1].houses)
	expect(#stop.doors).toBe(found - 1)
	expect(#stop.chimneys).toBe(found - 1)
	expect(stop.vaultDoor ~= nil and stop.vaultPrompt ~= nil).toBeTruthy()
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

test("any style can be the landing house; the Far ring prefers alpine", function()
	local alpine, candy = fakeHouse("alpine"), fakeHouse("candy")
	local rng = Random.new(1)
	expect(HouseKit.pick({ alpine }, rng, { isLanding = true, ring = "Near" })).toBe(alpine)
	expect(HouseKit.pick({ candy, alpine }, rng, { isLanding = false, ring = "Far" })).toBe(alpine)
	expect(HouseKit.pick({ candy }, rng, { isLanding = false, ring = "Far" })).toBe(candy)
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

-- Like the real import (tools/meshy/to_rbxm.luau): Meshy props never collide.
local function importedVaultDoor()
	local m = fakeVaultDoor()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	return m
end

-- Regression (Josh, 11 Nov 2026): you could walk straight through the vault.
for _, greybox in { false, true } do
	local how = if greybox then "greybox" else "kit"
	test("a shut vault blocks its doorway even though its model doesn't collide (" .. how .. " house)", function()
		local route = build({ houses = {}, vaultDoor = importedVaultDoor(), greybox = greybox }, 4)
		local checked = 0
		for _, stop in route.stops do
			if stop.vaultPrompt then
				checked += 1
				local blocker = stop.vaultBlocker
				expect(blocker ~= nil).toBeTruthy()
				expect(blocker.CanCollide).toBe(true)
				expect(blocker.Anchored).toBe(true)
				expect(blocker.Transparency).toBe(1)
				expect(blocker:IsDescendantOf(route.model)).toBe(true)
				-- Fills the doorway the vault door sits in: taller and wider than a Santa.
				expect(blocker.Size.Y).toBeGreaterThan(6)
				expect(blocker.Size.X).toBeGreaterThan(3)
				local offset = blocker.CFrame:PointToObjectSpace(stop.vaultDoor.CFrame.Position)
				expect(math.abs(offset.X)).toBeLessThan(blocker.Size.X / 2)
				expect(math.abs(offset.Y)).toBeLessThan(blocker.Size.Y / 2)
				expect(math.abs(offset.Z)).toBeLessThan(1.5)
			end
		end
		expect(checked).toBeGreaterThan(0)
	end)
end

test("the approved vault door goes in the vault doorway and swings open", function()
	local route = build({ houses = {}, vaultDoor = fakeVaultDoor() }, 4)
	local door = route.stops[1].vaultDoor
	expect(door.Name).toBe("Door")
	expect(door.CFrame.Position.Y).toBeLessThan(15)
	local open = HouseKit.doorCFrame(door.CFrame, door.Size, true)
	expect((open.Position - door.CFrame.Position).Magnitude).toBeGreaterThan(1)
	expect(HouseKit.doorCFrame(door.CFrame, door.Size, false)).toBe(door.CFrame)
end)

local function fakePresent(shape)
	local m = Instance.new("Model")
	m.Name = "Present"
	m:SetAttribute("Shape", shape)
	local at = CFrame.new(30, 40, 50)
	m.PrimaryPart = part(m, "Box", Vector3.new(2, 2.4, 2), at)
	part(m, "Ribbon", Vector3.new(2.05, 2.45, 0.3), at)
	part(m, "Bow", Vector3.new(1, 0.6, 1), at * CFrame.new(0, 1.5, 0))
	local grip = Instance.new("Attachment")
	grip.Name = "CarryGrip"
	grip.CFrame = CFrame.new(0, 1.2, 0)
	grip.Parent = m.PrimaryPart
	return m
end

test("approved presents are scaled to their size and sit on the floor", function()
	local rng = Random.new(6)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	local list = Instance.new("Model")
	list.Name = "NaughtyList"
	list.PrimaryPart = part(list, "Book", Vector3.new(3, 1, 4), CFrame.new(9, 9, 9))
	local route = MapBuilder.buildRoute(
		Instance.new("Folder"),
		1,
		rng,
		plans,
		onFoot,
		{ presents = { fakePresent("Cube"), fakePresent("Tall") }, naughtyList = list }
	)
	for _, stop in route.stops do
		for _, present in stop.presents do
			local main = present.model.PrimaryPart
			expect(present.prompt.Parent).toBe(main)
			if present.plan.naughtyList then
				expect(main.Name).toBe("Book")
			else
				local s = main.Size
				expect(math.max(s.X, s.Y, s.Z)).toBeNear(1.6 * present.plan.size, 0.001)
				local bottom = main.CFrame.Position.Y - s.Y / 2
				-- On a floor (ground, or a Two-storey's bedroom), not at the template's height.
				expect(bottom).toBeLessThan(15)
				expect(present.model:FindFirstChild("Bow") ~= nil).toBeTruthy()
			end
		end
	end
	-- Later routes without the kit go back to greybox boxes.
	local plain = MapBuilder.buildRoute(Instance.new("Folder"), 2, rng, plans, onFoot)
	expect(plain.stops[1].presents[1].model:FindFirstChild("Bow")).toBe(nil)
end)

describe("approved variants in ServerStorage.Assets", function()
	local function folder(name: string?)
		local f = Instance.new("Folder")
		f.Name = name or "Assets"
		return f
	end

	it("finds nothing when there is no Assets folder", function()
		expect(HouseKit.variants(nil)).toHaveLength(0)
		expect(HouseKit.presentVariants(nil)).toHaveLength(0)
	end)

	it("collects House models and an Assets.Houses folder, skipping ones without a Floor", function()
		local assets = folder()
		fakeHouse("candy").Parent = assets
		local houses = folder("Houses")
		houses.Parent = assets
		fakeHouse("alpine").Parent = houses
		local broken = Instance.new("Model")
		broken.Name = "House"
		broken.Parent = assets
		expect(HouseKit.variants(assets)).toHaveLength(2)
	end)

	it("collects Present models and an Assets.Presents folder, skipping ones without a Box", function()
		local assets = folder()
		local function present(parent, withBox)
			local m = Instance.new("Model")
			m.Name = "Present"
			if withBox then
				part(m, "Box", Vector3.new(2, 2, 2), CFrame.new())
			end
			m.Parent = parent
		end
		present(assets, true)
		present(assets, false)
		local presents = folder("Presents")
		presents.Parent = assets
		present(presents, true)
		expect(HouseKit.presentVariants(assets)).toHaveLength(2)
	end)
end)
