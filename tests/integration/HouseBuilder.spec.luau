-- The approved house kit built from parts (HouseBuilder), checked against
-- the HouseKit contract, the preview's seeds and the street it stands in.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local Maps = load("ReplicatedStorage.Shared.Maps")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local HouseBuilder = load("ServerScriptService.Server.HouseBuilder")
local HouseKit = load("ServerScriptService.Server.HouseKit")

local function partsOf(model)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function each(fn)
	local seed = 679
	for _, style in HouseBuilder.Styles do
		for _, layout in HouseBuilder.Layouts do
			fn(HouseBuilder.build(seed, style, layout), style, layout)
			seed += 13
		end
	end
end

test("random numbers match the 3D preview's mulberry32, so seeds give the same houses", function()
	local rng = HouseBuilder.mulberry(679)
	for _, want in
		{
			0.7714479176793247,
			0.49541665939614177,
			0.5993613973259926,
			0.1299970594700426,
			0.5651690231170505,
		}
	do
		expect(rng()).toBeNear(want, 1e-12)
	end
	local big = HouseBuilder.mulberry(2 ^ 30 - 1)
	for _, want in { 0.39119086414575577, 0.38500550971366465, 0.936559634283185 } do
		expect(big()).toBeNear(want, 1e-12)
	end
end)

test("every style and layout follows the HouseKit contract", function()
	each(function(house, style, layout)
		expect(house.PrimaryPart.Name).toBe("Floor")
		for _, name in { "TypeSign", "Chimney", "ChimneyTop", "Fireplace", "LooseBrick", "Wardrobe" } do
			local part = house:FindFirstChild(name, true)
			expect(part ~= nil and part:IsA("BasePart")).toBeTruthy()
		end
		local door = house:FindFirstChild("FrontDoor"):FindFirstChild("Door")
		expect(door:IsA("BasePart")).toBeTruthy()
		for i = 1, 8 do
			expect(house:FindFirstChild("PresentSpawn" .. i, true) ~= nil).toBeTruthy()
		end
		local upstairs = layout == "Two-storey"
			or (layout == "Room Mix" and house:GetAttribute("Floors") == 2)
		expect(house:FindFirstChild("Stairs") ~= nil).toBe(upstairs)
		expect(house:FindFirstChild("InnerDoorway") ~= nil).toBe(layout == "L-shape")
		expect(house:GetAttribute("Style")).toBe(style)
		expect(house:GetAttribute("Layout")).toBe(layout)
		expect(table.find(HouseBuilder.Types, house:GetAttribute("HouseType")) ~= nil).toBeTruthy()
	end)
end)

test("houses stand on the ground at the origin with the front door facing -Z", function()
	each(function(house)
		local floor = house.PrimaryPart
		expect(floor.CFrame.Position.Y - floor.Size.Y / 2).toBeNear(0, 1e-3)
		expect(floor.CFrame.LookVector.Z).toBeNear(-1, 1e-6)
		local door = house:FindFirstChild("FrontDoor"):FindFirstChild("Door")
		expect(door.CFrame.Position.Z).toBeLessThan(0)
		for _, p in partsOf(house) do
			expect(p.Anchored).toBeTruthy()
			local _, _, _, _, _, _, r10, r11, r12 = p.CFrame:GetComponents()
			local halfY = (math.abs(r10) * p.Size.X + math.abs(r11) * p.Size.Y + math.abs(r12) * p.Size.Z) / 2
			expect(p.CFrame.Position.Y - halfY).toBeGreaterThan(-0.01)
		end
	end)
end)

test("doors fit Santas and Krampus, stairs are walkable", function()
	each(function(house, _, layout)
		local door = house:FindFirstChild("FrontDoor"):FindFirstChild("Door")
		expect(door.Size.X).toBeGreaterThan(5)
		expect(door.Size.Y).toBeGreaterThan(10)
		expect(door.CanCollide).toBeTruthy()
		if layout == "Two-storey" then
			local tops = {}
			for _, step in house.Stairs:GetChildren() do
				if step.Name == "Step" then
					table.insert(tops, step.CFrame.Position.Y + step.Size.Y / 2)
				end
			end
			table.sort(tops)
			expect(#tops).toBe(13)
			for i = 2, #tops do
				expect(tops[i] - tops[i - 1]).toBeLessThan(1.1)
			end
		end
	end)
end)

test("a house fits its 28-stud plot between the garden hedges, inside the phone budget", function()
	local plot = Config.Map.HouseSize
	each(function(house, style, layout)
		local parts = partsOf(house)
		-- Room Mix houses have 5-7 rooms; the route budget (RenderBudget.spec) pays for them.
		expect(#parts).toBeLessThan(if layout == "Room Mix" then 185 else 175)
		for _, p in parts do
			local pos, half = p.CFrame.Position, p.Size.Magnitude / 2
			if
				p.Name ~= "Roof"
				and p.Name ~= "RoofSnow"
				and p.Name ~= "RoofRidge"
				and p.Name ~= "RoofRidgeSnow"
			then
				-- Hedges sit 4 studs past the plot; the front stops short of the shrubs.
				expect(math.abs(pos.X)).toBeLessThan(plot.X / 2 + 4)
				expect(pos.Z).toBeGreaterThan(-plot.Z / 2 - 3)
				expect(pos.Z).toBeLessThan(plot.Z / 2 + 3)
			end
			expect(half).toBeLessThan(40)
		end
	end)
end)

test("the same seed builds the same house; another seed varies it", function()
	local a = HouseBuilder.build(42, "candy", "Cottage")
	local b = HouseBuilder.build(42, "candy", "Cottage")
	local pa, pb = partsOf(a), partsOf(b)
	expect(#pa).toBe(#pb)
	for i, p in pa do
		expect(p.Color).toBe(pb[i].Color)
		expect(p.CFrame).toBe(pb[i].CFrame)
	end
	local walls = {}
	for seed = 1, 30 do
		local wall = HouseBuilder.build(seed, "candy", "Cottage"):FindFirstChild("Wall")
		walls[wall.Color:ToHex()] = true
	end
	local n = 0
	for _ in walls do
		n += 1
	end
	expect(n).toBeGreaterThan(3)
end)

test("the roof sign follows the House Card, not the seed", function()
	for _, sign in HouseBuilder.Types do
		local house = HouseBuilder.build(5, "alpine", "Cottage", { houseType = sign })
		expect(house:GetAttribute("HouseType")).toBe(sign)
		local symbols = 0
		for _, d in house:GetChildren() do
			if d.Name == "SignSymbol" then
				symbols += 1
			end
		end
		expect(symbols).toBe(if sign == "Snowflake" then 3 else 2)
	end
	expect(function()
		HouseBuilder.build(1, "gothic", "Cottage")
	end).toThrow()
end)

test("forPlan: Far ring houses are Alpine, the vault is a Cottage, the sign matches the card", function()
	local rng = Random.new(3)
	for _ = 1, 10 do
		local far = HouseBuilder.forPlan(rng, { ring = "Far", typeName = "Risky" }, HouseKit.HouseTypeSign)
		expect(far:GetAttribute("Style")).toBe("alpine")
		expect(far:GetAttribute("HouseType")).toBe("Horns")
		local vault = HouseBuilder.forPlan(
			rng,
			{ ring = "Far", typeName = "Vault", locked = true },
			HouseKit.HouseTypeSign
		)
		expect(vault:GetAttribute("Layout")).toBe("Cottage")
	end
	local styles, layouts = {}, {}
	for _ = 1, 40 do
		local h = HouseBuilder.forPlan(rng, { ring = "Mid", typeName = "Cosy" }, HouseKit.HouseTypeSign)
		styles[h:GetAttribute("Style")] = true
		layouts[h:GetAttribute("Layout")] = true
		expect(h:GetAttribute("HouseType")).toBe("Snowflake")
	end
	expect(styles.candy and styles.alpine).toBeTruthy()
	-- Every robbable house is a Room Mix house now (Josh, 6 Nov 2026).
	expect(layouts["Room Mix"]).toBeTruthy()
	expect(layouts.Cottage or layouts["Two-storey"] or layouts["L-shape"]).toBeFalsy()
end)

describe("on the Frozen Canal street", function()
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(8)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	local route = MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })

	it("every street house and the vault come from the kit, the Lair stays the Lair's", function()
		for i, stop in route.stops do
			local stopModel = route.model:FindFirstChild("Stop" .. i .. "_" .. plans[i].kindName)
			local kit, lairs = 0, 0
			for _, child in stopModel:GetChildren() do
				if child.Name:match("House$") then
					if child:GetAttribute("Layout") then
						kit += 1
						expect(child.Name).never.toBe("LairHouse")
					else
						lairs += 1
						expect(child.Name).toBe("LairHouse")
					end
				end
			end
			local wantLairs = 0
			for _, house in plans[i].houses do
				if house.typeName == "Lair" then
					wantLairs += 1
				end
			end
			expect(kit).toBe(#plans[i].houses - wantLairs)
			expect(lairs).toBe(wantLairs)
		end
	end)

	it("front doors start open (shut reads as locked), close from a prompt, face the street", function()
		for _, stop in route.stops do
			expect(#stop.doors).toBeGreaterThan(0)
			for _, door in stop.doors do
				expect(door.open).toBe(true)
				expect(door.door.CanCollide).toBe(false)
				expect(door.prompt.ActionText).toBe("Close")
				local local_ = stop.origin:PointToObjectSpace(door.closed.Position)
				local outward = stop.origin:VectorToObjectSpace(door.door.CFrame.LookVector)
				if math.abs(local_.X) > 20 then
					-- Side houses: the door's front points back toward the road (X = 0).
					outward = stop.origin:VectorToObjectSpace(door.closed.LookVector)
					expect(outward.X * local_.X).toBeLessThan(0)
					-- and it swings open outward, onto the path.
					local open = HouseKit.doorCFrame(door.closed, door.door.Size, true)
					expect((open.Position - door.door.CFrame.Position).Magnitude).toBeLessThan(0.01)
					local moved = stop.origin:PointToObjectSpace(open.Position) - local_
					expect(moved.X * local_.X).toBeLessThan(0)
				end
			end
		end
	end)

	it("the vault house's front door is the gold vault door, opened by a buy", function()
		local stop = route.stops[1]
		expect(stop.vaultDoor ~= nil).toBeTruthy()
		expect(stop.vaultDoor.Name).toBe("VaultDoor")
		expect(stop.vaultPrompt.ActionText).toBe("Open vault")
		for _, door in stop.doors do
			expect(door.door).never.toBe(stop.vaultDoor)
		end
		local inVault = 0
		for _, present in stop.presents do
			if present.inVault then
				inVault += 1
			end
		end
		expect(inVault).toBe(Config.Houses.Types.Vault.Presents)
	end)

	it("roof signs match each house's card", function()
		for i, stop in route.stops do
			local stopModel = route.model:FindFirstChild("Stop" .. i .. "_" .. plans[i].kindName)
			for _, child in stopModel:GetChildren() do
				local typeName = child.Name:match("^(%a+)House$")
				local want = typeName and HouseKit.HouseTypeSign[typeName]
				if want and child:GetAttribute("Layout") then
					expect(child:GetAttribute("HouseType")).toBe(want)
				end
			end
			expect(#stop.chimneys).toBeGreaterThan(0)
		end
	end)
end)
