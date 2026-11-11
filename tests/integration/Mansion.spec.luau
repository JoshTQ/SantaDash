--[[
	The Gingerbread Mansion (Josh approved, 6 Nov 2026): one per route at
	Stop 2, 4 floors, gifts hidden in the furniture (bigger higher up), six
	boxes under the tree with one real, and a noisy piano. Checks the plan,
	the build (HouseKit contract, stairs that a Santa can climb, the part
	count) and where it stands on the street.
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MansionBuilder = load("ServerScriptService.Server.MansionBuilder")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local Maps = load("ReplicatedStorage.Shared.Maps")

local function partsIn(root)
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

test("Loot plans one mansion per route, at Stop 2 only, with bigger gifts higher up", function()
	for seed = 1, 20 do
		local rng = Random.new(seed)
		for i = 1, #Config.Run.StopKinds do
			local plan = Loot.planStop(rng, i, Maps.get("FrozenCanal").layout.Slots)
			local mansions = {}
			for _, h in plan.houses do
				if h.typeName == "Mansion" then
					table.insert(mansions, h)
				end
			end
			expect(#mansions).toBe(if table.find(Config.Mansion.Stops, i) then 1 else 0)
			local m = mansions[1]
			if m then
				expect(m.secret).toBe(false)
				expect(m.side).toBe(Config.Mansion.Side)
				local want, trees = 1, 0
				for _, row in Config.Mansion.Gifts do
					want += row.count
				end
				expect(#m.presents).toBe(want) -- 8: 7 in furniture + the tree box
				local sizeByFloor = {}
				for _, p in m.presents do
					expect(p.floor ~= nil).toBeTruthy()
					if p.tree then
						trees += 1
					else
						sizeByFloor[p.floor] = p.size
					end
				end
				expect(trees).toBe(1)
				expect(sizeByFloor[3] > sizeByFloor[0]).toBeTruthy()
				expect(sizeByFloor[1] >= sizeByFloor[0]).toBeTruthy()
			end
		end
	end
end)

test("the build follows the house contract and has 15 search spots on 4 floors", function()
	local m = MansionBuilder.build(Random.new(3))
	expect(m.PrimaryPart.Name).toBe("Floor")
	for _, name in
		{ "TypeSign", "Chimney", "ChimneyTop", "Fireplace", "Wardrobe", "FrontDoor", "Ladder", "Piano" }
	do
		expect(m:FindFirstChild(name, true) ~= nil and name).toBe(name)
	end
	local door = m:FindFirstChild("FrontDoor"):FindFirstChild("Door")
	expect(door.Size.Y).toBeGreaterThan(10.5) -- Krampus (11) walks in
	local perLevel = {}
	for _, s in m.SearchSpots:GetChildren() do
		local level = s:GetAttribute("Level")
		perLevel[level] = (perLevel[level] or 0) + 1
		local trigger = s:FindFirstChild("SpotTrigger")
		expect(trigger ~= nil and s.Name).toBe(s.Name)
		expect(trigger:FindFirstChild("GiftAt") ~= nil and s.Name).toBe(s.Name)
		local opens = 0
		for _, d in s:GetDescendants() do
			if d:IsA("BasePart") and typeof(d:GetAttribute("Open")) == "CFrame" then
				opens += 1
			end
		end
		expect(opens > 0 and s.Name).toBe(s.Name) -- something visibly opens
	end
	expect(perLevel[0]).toBe(7)
	expect(perLevel[1]).toBe(4)
	expect(perLevel[2]).toBe(2)
	expect(perLevel[3]).toBe(2)
	-- Each floor has room for its planned gifts.
	for _, row in Config.Mansion.Gifts do
		expect(perLevel[row.floor] >= row.count).toBeTruthy()
	end
	expect(#m.TreeBoxes:GetChildren()).toBe(6)
	expect(partsIn(m)).toBeLessThan(320) -- phone budget: ~1/30 of a route
end)

test("both flights of stairs climb a storey in steps a Santa can take", function()
	local m = MansionBuilder.build(Random.new(1))
	local tops = {}
	for _, d in m:GetChildren() do
		if d.Name == "Stairs" then
			table.insert(tops, d.CFrame.Position.Y + d.Size.Y / 2)
		end
	end
	table.sort(tops)
	expect(#tops).toBe(28)
	local L = MansionBuilder.Levels
	expect(tops[1] - L[0]).toBeLessThan(1.5)
	for i = 2, #tops do
		expect(tops[i] - tops[i - 1]).toBeLessThan(1.5)
	end
	expect(tops[14]).toBeNear(L[1], 0.01)
	expect(tops[28]).toBeNear(L[2], 0.01)
	-- The attic is a truss climb from the playroom.
	local truss = m:FindFirstChild("AtticLadder")
	expect(truss.ClassName).toBe("TrussPart")
	expect(truss.CFrame.Position.Y + truss.Size.Y / 2).toBeGreaterThan(L[3])
end)

test("on the street it lines up with the other houses and stays clear of the Ice Rink", function()
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(5)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	local route = MapBuilder.buildRoute(Instance.new("Folder"), 1, rng, plans, onFoot, { map = map })
	local stop = route.stops[2]
	local mansion, spots = nil, 0
	for _, house in stop.houses do
		if house.plan.typeName == "Mansion" then
			mansion = house
		end
	end
	expect(mansion ~= nil).toBeTruthy()
	for _, s in stop.searchSpots do
		spots += 1
		expect(s.prompt.Enabled).toBe(true)
	end
	expect(spots).toBe(15 + 6 + 1)
	local hidden = 0
	for _, p in mansion.presents do
		hidden += if p.hidden then 1 else 0
		expect(p.prompt.Enabled).toBe(false)
	end
	expect(hidden).toBe(#mansion.presents)
	-- The mansion's front face lines up with an ordinary house's.
	local stopModel = route.model:FindFirstChild("Stop2_Street")
	local house = stopModel:FindFirstChild("MansionHouse", true)
	local floor = house.PrimaryPart
	local local_ = stop.origin:PointToObjectSpace(floor.CFrame.Position)
	local front = math.abs(local_.X) - floor.Size.Z / 2
	expect(front).toBeNear(map.layout.SideOffset - Config.Map.HouseSize.Z / 2, 0.01)
	local rink = map.features[5]
	expect(rink.kind).toBe("IceRink")
	expect(local_.Z + floor.Size.X / 2).toBeLessThan(rink.centre.Z - rink.radius)
	-- No terrace townhouse inside the mansion's plot.
	for _, d in stopModel:GetDescendants() do
		if d.Name == "Townhouse" then
			local p = stop.origin:PointToObjectSpace(d.CFrame.Position)
			local near = math.sign(p.X) == Config.Mansion.Side and math.abs(p.Z - local_.Z) < 52
			expect(near and "townhouse in the mansion plot").toBe(false)
		end
	end
end)
