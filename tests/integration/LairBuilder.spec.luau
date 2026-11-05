-- Krampus's Lair (the approved Cuckoo Clock Den) built from parts, and run
-- through the real MapBuilder/HouseKit as the finale's end house.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local LairBuilder = load("ServerScriptService.Server.LairBuilder")

local S = LairBuilder.Scale

local function partsOf(model: Instance): { BasePart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- Is `p` inside any colliding part (oriented boxes; good enough for a clearance check)?
local function blocked(model: Instance, p: Vector3): string?
	for _, part in partsOf(model) do
		if part.CanCollide then
			local q = part.CFrame:Inverse() * p
			local h = part.Size / 2
			if math.abs(q.X) < h.X and math.abs(q.Y) < h.Y and math.abs(q.Z) < h.Z then
				return part.Name
			end
		end
	end
	return nil
end

describe("LairBuilder.build", function()
	local lair = LairBuilder.build()
	local floor = lair.PrimaryPart :: BasePart
	local floorTop = floor.CFrame.Position.Y + floor.Size.Y / 2

	it("meets the KrampusLair contract HouseKit and Run look for", function()
		expect(lair.Name).toBe("KrampusLair")
		expect(floor.Name).toBe("Floor")
		for _, name in
			{
				"ListPedestal",
				"KrampusSpawn",
				"HideSpot1",
				"HideSpot2",
				"Fireplace",
				"ChimneyTop",
				"Ladder",
				"TypeSign",
				"Entrance",
				"CuckooDoor",
				"ClockFace",
			}
		do
			expect(lair:FindFirstChild(name, true) ~= nil).toBeTruthy()
		end
		for i = 1, 7 do
			expect(lair:FindFirstChild("Bell" .. i, true):IsA("BasePart")).toBeTruthy()
		end
		for i = 1, Config.Houses.Types.Lair.Presents do
			expect(lair:FindFirstChild("PresentSpawn" .. i, true) ~= nil).toBeTruthy()
		end
		expect(lair:FindFirstChild("FireLight", true):IsA("PointLight")).toBeTruthy()
	end)

	it("sits on y = 0, is Lair-sized and faces -Z", function()
		expect(floor.CFrame.Position.Y - floor.Size.Y / 2).toBeNear(0, 0.001)
		expect(floor.Size.X).toBeGreaterThanOrEqual(Config.Houses.Types.Lair.Size.X)
		expect(floor.Size.X).toBeLessThan(Config.Houses.Types.Lair.Size.X + 8)
		local clock = lair:FindFirstChild("ClockFace", true) :: BasePart
		expect(clock.CFrame.Position.Z).toBeLessThan(-15)
		for _, part in partsOf(lair:FindFirstChild("Entrance")) do
			expect(part.CFrame.Position.Z).toBeLessThan(0)
		end
	end)

	it("keeps to a phone-friendly part budget, all anchored", function()
		local parts = partsOf(lair)
		expect(#parts).toBeLessThan(500)
		for _, part in parts do
			expect(part.Anchored).toBeTruthy()
			-- No NaN frames (a straight-up CFrame.lookAt makes one, and the part vanishes).
			for _, v in { part.CFrame:GetComponents() } do
				expect(v == v).toBeTruthy()
			end
		end
	end)

	it("has a doorway Krampus (about 12 studs) walks through", function()
		local frontEdge = -floor.Size.Z / 2
		for x = -6, 6, 2 do
			for y = floorTop + 0.5, floorTop + 13, 1.5 do
				for z = frontEdge - 1, frontEdge + 8, 1 do
					expect(blocked(lair, Vector3.new(x, y, z))).toBe(nil)
				end
			end
		end
	end)

	it("leaves the present spots, hide spot exits and Krampus's spawn clear", function()
		for i = 1, Config.Houses.Types.Lair.Presents do
			local spot = lair:FindFirstChild("PresentSpawn" .. i, true) :: BasePart
			local top = spot.CFrame.Position + Vector3.new(0, spot.Size.Y / 2, 0)
			expect(top.Y).toBeNear(floorTop + 0.1 * S, 0.01) -- on the planks
			for _, lift in { 0.5, 2, 4 } do
				expect(blocked(lair, top + Vector3.new(0, lift, 0))).toBe(nil)
			end
		end
		local spawn = (lair:FindFirstChild("KrampusSpawn", true) :: BasePart).CFrame.Position
		for _, lift in { 1, 4, 8 } do
			expect(blocked(lair, Vector3.new(spawn.X, floorTop + lift, spawn.Z))).toBe(nil)
		end
	end)

	it("puts its own ladder up to the eaves on the chimney's side", function()
		local ladder = lair:FindFirstChild("Ladder", true) :: BasePart
		local top = lair:FindFirstChild("ChimneyTop", true) :: BasePart
		expect(ladder:IsA("TrussPart")).toBeTruthy()
		expect(math.sign(ladder.CFrame.Position.X)).toBe(math.sign(top.CFrame.Position.X))
		expect(math.abs(ladder.CFrame.Position.X)).toBeGreaterThan(floor.Size.X / 2)
		expect(ladder.CFrame.Position.Y - ladder.Size.Y / 2).toBeNear(0, 0.01)
	end)

	it("builds the template once and reuses it", function()
		expect(LairBuilder.template()).toBe(LairBuilder.template())
	end)
end)

test("the built Lair is the finale's end house, with its chimney, hide spots and List", function()
	local rng = Random.new(9)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	local route = MapBuilder.buildRoute(Instance.new("Folder"), 1, rng, plans, onFoot, {
		houseKit = { houses = {}, lair = LairBuilder.template() },
	})
	local finale = route.stops[#route.stops]
	local stopModel = route.model:FindFirstChild("Stop" .. #plans .. "_" .. plans[#plans].kindName)
	local lair = stopModel:FindFirstChild("LairHouse")
	expect(lair ~= nil).toBeTruthy()
	expect(lair:FindFirstChild("Gear1", true) ~= nil).toBeTruthy()

	-- Exactly one ladder: HouseKit keeps the Lair's own.
	local ladders = 0
	for _, d in lair:GetDescendants() do
		if d.Name == "Ladder" then
			ladders += 1
		end
	end
	expect(ladders).toBe(1)

	-- The Lair's chimney route works (the landing house adds the other one).
	local lairChimney
	for _, chimney in finale.chimneys do
		if chimney.down.Parent.Name == "ChimneyTop" and chimney.down.Parent:IsDescendantOf(lair) then
			lairChimney = chimney
		end
	end
	expect(lairChimney ~= nil).toBeTruthy()

	local floor = lair:FindFirstChild("Floor") :: BasePart
	local floorTop = floor.CFrame.Position.Y + floor.Size.Y / 2
	local spawn = floor.CFrame:Inverse() * finale.krampusSpawn.Position
	expect(math.abs(spawn.X)).toBeLessThan(floor.Size.X / 2)
	expect(math.abs(spawn.Z)).toBeLessThan(floor.Size.Z / 2)
	expect(finale.krampusSpawn.Position.Y).toBeNear(floorTop + 6, 0.01)
	-- Not on top of the chimney's way out, or the door (Josh, 5 Nov).
	local flat = Vector3.new(1, 0, 1)
	local entrance = (lair:FindFirstChild("Entrance") :: Model):FindFirstChild("Post").CFrame.Position
	expect(((finale.krampusSpawn.Position - lairChimney.inside.Position) * flat).Magnitude).toBeGreaterThan(
		24
	)
	expect(((finale.krampusSpawn.Position - entrance) * flat).Magnitude).toBeGreaterThan(24)

	local lairHides = 0
	for _, spot in finale.hideSpots do
		if spot.prompt.Parent:IsDescendantOf(lair) then
			lairHides += 1
		end
	end
	expect(lairHides).toBe(Config.Houses.Types.Lair.HideSpots)

	local pedestal = lair:FindFirstChild("ListPedestal", true) :: BasePart
	local pedestalTop = pedestal.CFrame.Position.Y + pedestal.Size.Y / 2
	local inLair, list = 0, nil
	for _, present in finale.presents do
		if present.model:IsDescendantOf(lair) then
			inLair += 1
			if present.plan.naughtyList then
				list = present
			else
				-- On a spawn spot on the planks, not on furniture or inside a wall.
				local bottom = present.model.PrimaryPart.CFrame.Position.Y
					- present.model.PrimaryPart.Size.Y / 2
				expect(bottom).toBeLessThan(floorTop + 1)
			end
		end
	end
	local planned = 0
	for _, house in plans[#plans].houses do
		if house.typeName == "Lair" then
			planned = #house.presents
		end
	end
	expect(planned).toBeGreaterThan(0)
	expect(inLair).toBe(planned)
	expect(list ~= nil).toBeTruthy()
	local listBottom = list.model.PrimaryPart.CFrame.Position.Y - list.model.PrimaryPart.Size.Y / 2
	expect(listBottom).toBeGreaterThan(pedestalTop - 2)
end)
