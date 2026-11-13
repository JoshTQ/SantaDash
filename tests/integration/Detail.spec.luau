--[[
	Level of detail on phones (Shared.Detail): far dressing leaves the
	client's scene, colliding and gameplay parts never do, and everything
	comes back as the camera returns.
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Detail = load("ReplicatedStorage.Shared.Detail")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local LobbyMap = load("ServerScriptService.Server.LobbyMap")
local Maps = load("ReplicatedStorage.Shared.Maps")

local function build(seed)
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots, map.layout.StopSlots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	return MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })
end

local function partsIn(root)
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

-- A fresh route for each test, so one failure can't leave parts hidden for the next.
local route, total, stop1, stop3
local function fresh()
	route = build(11)
	total = partsIn(route.model)
	stop1 = route.stops[1].origin.Position
	stop3 = route.stops[#route.stops].origin.Position
end
fresh()

describe("Detail on a Frozen Canal route", function()
	beforeEach(fresh)

	it("is marked for the clients to scan", function()
		expect(route.model:GetAttribute("DetailRoot")).toBe(true)
	end)

	it("takes a big share of the route as dressing", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		local taken = culler:add(route.model)
		print(
			string.format(
				"  [detail] route parts %d, can be dropped far away %d (%.0f%%)",
				total,
				taken,
				taken / total * 100
			)
		)
		expect(taken / total).toBeGreaterThan(0.3)
		culler:drop(route.model)
	end)

	it("on a phone at Stop 1, keeps the scene well under the 9,000 budget", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		for _ = 1, 50 do
			if culler:step(stop1) == 0 then
				break
			end
		end
		local live = partsIn(route.model)
		print(string.format("  [detail] phone at Stop 1: %d of %d parts in the scene", live, total))
		expect(live).toBeLessThan(total * 0.5)
		expect(culler.hidden).toBe(total - live)
		culler:showAll()
		expect(partsIn(route.model)).toBe(total)
		culler:drop(route.model)
	end)

	it("on a phone, every stop's scene fits 4,000 parts and 80 lights", function()
		for i, stop in route.stops do
			local culler = Detail.new(Detail.Profiles.Phone)
			culler:add(route.model)
			local at = stop.origin.Position
			for _ = 1, 50 do
				if culler:step(at) == 0 then
					break
				end
			end
			local parts, lights = 0, 0
			for _, d in route.model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				elseif d:IsA("Light") then
					lights += 1
				end
			end
			print(string.format("  [detail] phone at Stop %d: %d parts, %d lights", i, parts, lights))
			expect(parts).toBeLessThan(4000)
			expect(lights).toBeLessThan(80)
			culler:showAll()
			culler:drop(route.model)
		end
	end)

	it("never takes a prompted, Trigger, unanchored or touch-only part; only Solid collides", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		for _, cell in culler.cells do
			for _, p in cell.parts do
				expect(p.Anchored).toBe(true)
				expect(p:FindFirstChildWhichIsA("ProximityPrompt", true)).toBeNil()
				expect(p:FindFirstChildWhichIsA("BillboardGui", true)).toBeNil()
				expect(p:GetAttribute("Trigger")).toBeNil()
				expect(p.CanCollide).toBe(cell.tier == "Solid")
				if cell.tier ~= "Solid" then
					expect(p.CanTouch or p.CanQuery).toBe(false)
				end
			end
		end
		culler:drop(route.model)
	end)

	it("the ground and the ice at your own stop always stay", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		for _ = 1, 50 do
			if culler:step(stop1) == 0 then
				break
			end
		end
		expect(route.model:FindFirstChild("Ground")).never.toBeNil()
		-- Ice near the stop you're on (the canal runs on towards Stop 2, 700 studs off).
		local near = 0
		for _, zone in route.stops[1].canal.iceZones do
			if (zone.CFrame.Position - stop1).Magnitude < 400 then
				near += 1
				expect(zone:IsDescendantOf(route.model)).toBe(true)
			end
		end
		expect(near).toBeGreaterThan(0)
		culler:showAll()
		culler:drop(route.model)
	end)

	it("desktops never hide Solid scenery", function()
		local culler = Detail.new(Detail.Profiles.Desktop)
		culler:add(route.model)
		for _ = 1, 50 do
			if culler:step(stop1) == 0 then
				break
			end
		end
		for _, cell in culler.cells do
			if cell.tier == "Solid" then
				expect(cell.shown).toBe(true)
			end
		end
		culler:showAll()
		culler:drop(route.model)
	end)

	it("a jump to another stop brings back everything near it in one step", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		for _ = 1, 50 do
			if culler:step(stop1) == 0 then
				break
			end
		end
		local hidden = culler.hidden
		culler:step(stop3, math.huge, true)
		expect(culler.hidden).toBeLessThan(hidden)
		for _, cell in culler.cells do
			if Detail.distanceToBox(stop3, cell.lo, cell.hi) <= Detail.Profiles.Phone[cell.tier].show then
				expect(cell.shown).toBe(true)
			end
		end
		-- showOnly never hides, even the cells now far behind.
		for _, cell in culler.cells do
			if Detail.distanceToBox(stop1, cell.lo, cell.hi) <= 100 then
				expect(cell.shown).toBe(true)
			end
		end
		culler:showAll()
		culler:drop(route.model)
	end)

	it("a part the server destroys while hidden doesn't break showing it again", function()
		local root = Instance.new("Model")
		root.Parent = newFolder()
		local part = Instance.new("Part")
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
		part.Size = Vector3.one
		part.CFrame = CFrame.new(0, 0, 5000)
		part.Parent = root
		local culler = Detail.new(Detail.Profiles.Phone)
		expect(culler:add(root)).toBe(1)
		culler:step(Vector3.zero)
		expect(part.Parent).toBeNil()
		part:Destroy()
		culler:step(Vector3.new(0, 0, 5000))
		expect(culler.hidden).toBe(0)
		culler:drop(root)
		expect(next(culler.cells)).toBeNil()
	end)

	it("cuts the lights on screen at a stop", function()
		local function lights()
			local n = 0
			for _, d in route.model:GetDescendants() do
				if d:IsA("Light") then
					n += 1
				end
			end
			return n
		end
		local all = lights()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		for _ = 1, 50 do
			if culler:step(stop1) == 0 then
				break
			end
		end
		local live = lights()
		print(string.format("  [detail] phone at Stop 1: %d of %d lights in the scene", live, all))
		expect(live).toBeLessThan(all)
		culler:showAll()
		culler:drop(route.model)
	end)

	it("leaves the sleigh, presents and the Lair alone", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		for _, cell in culler.cells do
			for _, p in cell.parts do
				local node = p.Parent
				while node and node ~= route.model do
					if Detail.KeepModels[node.Name] then
						error(p:GetFullName() .. " is inside " .. node.Name)
					end
					node = node.Parent
				end
			end
		end
		culler:drop(route.model)
	end)

	it("walking from Stop 1 to the last stop brings that stop back in full", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		local function settle(at)
			for _ = 1, 50 do
				if culler:step(at) == 0 then
					return
				end
			end
		end
		settle(stop1)
		local hiddenAtStop1 = culler.hidden
		settle(stop3)
		for _, cell in culler.cells do
			local band = Detail.Profiles.Phone[cell.tier]
			local d = Detail.distanceToBox(stop3, cell.lo, cell.hi)
			if d <= band.show then
				expect(cell.shown).toBe(true)
			elseif d > band.hide then
				expect(cell.shown).toBe(false)
			end
		end
		expect(hiddenAtStop1).toBeGreaterThan(0)
		culler:showAll()
		expect(partsIn(route.model)).toBe(total)
		culler:drop(route.model)
	end)

	it("a desktop keeps more in the scene than a phone", function()
		local phone, desk = Detail.new(Detail.Profiles.Phone), Detail.new(Detail.Profiles.Desktop)
		phone:add(route.model)
		for _ = 1, 50 do
			if phone:step(stop1) == 0 then
				break
			end
		end
		local phoneHidden = phone.hidden
		phone:showAll()
		phone:drop(route.model)
		desk:add(route.model)
		for _ = 1, 50 do
			if desk:step(stop1) == 0 then
				break
			end
		end
		expect(desk.hidden).toBeLessThan(phoneHidden)
		desk:showAll()
		desk:drop(route.model)
	end)

	it("moves at most one budget of parts per step (no frame hitch)", function()
		local culler = Detail.new(Detail.Profiles.Phone)
		culler:add(route.model)
		local biggest = 0
		for _, cell in culler.cells do
			biggest = math.max(biggest, #cell.parts)
		end
		local moved = culler:step(stop1)
		expect(moved).toBeLessThan(Detail.MaxMovesPerStep + biggest + 1)
		culler:showAll()
		culler:drop(route.model)
	end)
end)

describe("Detail on the hub", function()
	it("marks the Sleigh Station and has dressing to drop", function()
		local hub = LobbyMap.build(newFolder())
		expect(hub.model:GetAttribute("DetailRoot")).toBe(true)
		local culler = Detail.new(Detail.Profiles.Phone)
		local taken = culler:add(hub.model)
		print(string.format("  [detail] hub parts %d, dressing %d", partsIn(hub.model), taken))
		expect(taken).toBeGreaterThan(0)
	end)
end)
