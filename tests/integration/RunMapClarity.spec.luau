-- Josh's first playtest (6 Nov 2026): the run map has to say what to do and
-- join up. Robbable houses wear gold gift markers and open doors, filler
-- townhouses have no fake doors, a back ice lane joins every street end and
-- runs on to the Lair's back gate, and nothing there is water.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local Maps = load("ReplicatedStorage.Shared.Maps")
local CanalTown = load("ServerScriptService.Server.CanalTown")
local CanalRules = load("ServerScriptService.Server.CanalRules")

local B = Config.Canal.BackLane

local function build(seed)
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots, map.layout.StopSlots)
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

-- Is a point standing on the top face of any of these parts (flat footprint)?
local function onTopOf(parts, p)
	for _, part in parts do
		local l = part.CFrame:PointToObjectSpace(p)
		if math.abs(l.X) <= part.Size.X / 2 + 0.01 and math.abs(l.Z) <= part.Size.Z / 2 + 0.01 then
			return part
		end
	end
	return nil
end

local route, map = build(4)
local last = #Config.Run.StopKinds

describe("gift markers", function()
	it("every house you can rob has a gold marker counting its gifts", function()
		for _, stop in route.stops do
			local robbable = 0
			for _, house in stop.plan.houses do
				if house.typeName ~= "Lair" then
					robbable += 1
				end
			end
			expect(#stop.houses).toBe(robbable)
			for _, house in stop.houses do
				expect(#house.presents).toBe(#house.plan.presents)
				local gui = house.marker.Parent
				expect(gui.AlwaysOnTop).toBe(true)
				if house.locked then
					expect(string.find(house.marker.Text, "VAULT", 1, true) ~= nil).toBeTruthy()
					expect(
						string.find(house.marker.Text, tostring(Config.Buys.VaultDoor.Cost), 1, true) ~= nil
					).toBeTruthy()
				elseif house.plan.typeName == "Mansion" then
					-- The mansion counts the gifts hidden in its furniture.
					expect(house.marker.Text).toBe(string.format("SEARCH ME · %d GIFTS", #house.presents))
				else
					-- A secret room's present isn't counted until someone finds it.
					local shown = 0
					for _, present in house.presents do
						shown += if present.hidden then 0 else 1
					end
					expect(house.marker.Text).toBe(
						string.format("ROB ME · %d GIFT%s", shown, if shown == 1 then "" else "S")
					)
				end
			end
		end
	end)

	it("counts down as gifts go and says EMPTY at the end", function()
		local house = route.stops[1].houses[1]
		for i, present in house.presents do
			present.taken = true
			MapBuilder.refreshMarker(house, true)
			local left = #house.presents - i
			if left > 0 then
				expect(string.find(house.marker.Text, tostring(left), 1, true) ~= nil).toBeTruthy()
			end
		end
		expect(house.marker.Text).toBe("EMPTY")
		expect(house.marker.Parent.AlwaysOnTop).toBe(false)
	end)

	it("an opened vault reads like any other house", function()
		local vault = { presents = { {}, {} }, locked = true } :: any
		expect(MapBuilder.markerText(vault, true)).toBe(
			"VAULT · 2 GIFTS\n" .. Config.Buys.VaultDoor.Cost .. " Jingle to open"
		)
		expect(MapBuilder.markerText(vault, false)).toBe("ROB ME · 2 GIFTS")
	end)
end)

describe("filler townhouses", function()
	it("have no front doors, so nothing looks locked", function()
		expect(#named(route.model, "Townhouse")).toBeGreaterThan(10)
		expect(#named(route.model, "TownhouseDoor")).toBe(0)
	end)
end)

describe("the back lane", function()
	local ice = {}
	for _, stop in route.stops do
		for _, zone in stop.canal.iceZones do
			table.insert(ice, zone)
		end
	end
	-- Ice zones plus the street canals (Road, in Ice), each in world space.
	for _, road in named(route.model, "Road") do
		table.insert(ice, road)
	end

	it("is ice all the way from each street's far end to the next stop", function()
		for i = 1, last - 1 do
			local here = route.stops[i].origin
			local nextStop = route.stops[i + 1].origin
			-- Down the street canal, along the back lane, up the next street (or into the lake).
			local points = {}
			for z = Config.Rings.Far.Distance, B.Z, 10 do
				table.insert(points, (here * CFrame.new(0, 0, z)).Position)
			end
			local a = (here * CFrame.new(0, 0, B.Z)).Position
			local b = (nextStop * CFrame.new(0, 0, B.Z)).Position
			for k = 0, 100 do
				table.insert(points, a:Lerp(b, k / 100))
			end
			for _, p in points do
				local hit = onTopOf(ice, p)
				if not hit then
					error(string.format("no ice under %s between stop %d and %d", tostring(p), i, i + 1))
				end
				expect(hit.Material).toBe(Enum.Material.Ice)
			end
		end
	end)

	it("keeps trees and hills off the lane", function()
		for _, stop in route.stops do
			for _, tree in named(stop.origin and route.model, "PineTrunk") do
				local l = stop.origin:PointToObjectSpace(tree.CFrame.Position)
				if math.abs(l.X) < 350 then
					expect(math.abs(l.Z - B.Z) > B.Width / 2).toBeTruthy()
				end
			end
		end
	end)

	it("is signposted at every junction", function()
		local texts = {}
		for _, board in named(route.model, "SignBoard") do
			table.insert(
				texts,
				board:FindFirstChildOfClass("BillboardGui"):FindFirstChildOfClass("TextLabel").Text
			)
		end
		local joined = table.concat(texts, "|")
		expect(string.find(joined, "STOP 2  >>", 1, true) ~= nil).toBeTruthy()
		expect(string.find(joined, "KRAMPUS'S LAIR  >>", 1, true) ~= nil).toBeTruthy()
		expect(string.find(joined, "<<  STOP 1", 1, true) ~= nil).toBeTruthy()
	end)
end)

describe("the Lair Lane", function()
	local finale = route.stops[last]
	local lanes = named(route.model, "LairLane")

	it("runs from the lake's edge to the castle's back gate", function()
		expect(#lanes).toBe(2)
		local lake
		for _, f in map.features do
			if f.kind == "FloeLake" then
				lake = f
			end
		end
		local laneZ = math.min(B.Z, lake.to - B.LairLaneWidth)
		local from = (finale.origin * CFrame.new(-lake.halfWidth, 0, laneZ)).Position
		local corner = (finale.origin * CFrame.new(0, 0, laneZ)).Position
		local gate = (finale.origin * CFrame.new(0, 0, lake.island.Z + lake.islandRadius - 6)).Position
		for k = 0, 40 do
			for _, p in { from:Lerp(corner, k / 40), corner:Lerp(gate, k / 40) } do
				if not onTopOf(lanes, p) then
					error("no Lair Lane under " .. tostring(finale.origin:PointToObjectSpace(p)))
				end
			end
		end
	end)

	it("never turns to water: no floes on it, and standing on it is not a splash", function()
		local floes = CanalTown.breakZone(finale.canal.lake, Random.new(2))
		for _, floe in floes do
			expect(onTopOf(lanes, floe.CFrame.Position)).toBeNil()
		end
		local lake = finale.canal.lake
		for _, lane in lanes do
			local top = lane.CFrame.Position.Y + lane.Size.Y / 2
			local root = Vector3.new(lane.CFrame.Position.X, top + 3, lane.CFrame.Position.Z)
			expect(CanalRules.inWater({ cframe = lake.CFrame, size = lake.Size }, {}, root, 3)).toBe(false)
		end
	end)
end)

test("ice is a real speed-up over walking", function()
	expect(Config.Canal.SkateSpeed).toBeGreaterThan(Config.Player.WalkSpeed * 1.6)
	expect(CanalRules.walkSpeed(Config.Player.WalkSpeed, true, false)).toBe(Config.Canal.SkateSpeed)
end)

-- Josh (13 Nov 2026): "Why are there still so many random houses. I'd like
-- the ones you can enter being more dispersed, not just top & bottom."
test("robbable houses are spread down every street, not just at its ends", function()
	for _, seed in { 3, 11, 42 } do
		local route = build(seed)
		for i, stop in route.stops do
			local zs = {}
			for _, h in stop.houses do
				if h.plan.side ~= 0 then
					table.insert(zs, h.plan.distance)
				end
			end
			table.sort(zs)
			expect(#zs >= 2).toBeTruthy()
			-- Something to rob in the middle of the street (between 100 and 350)...
			local middle = false
			for _, z in zs do
				if z >= 100 and z <= 350 then
					middle = true
				end
			end
			expect(middle).toBeTruthy()
			-- ...and, on the full streets, never a stretch over 200 studs without one.
			if i < #route.stops then
				for k = 2, #zs do
					expect(zs[k] - zs[k - 1] <= 200).toBeTruthy()
				end
			end
		end
	end
end)

test("filler townhouses are thinned out and never crowd a robbable house", function()
	local route = build(11)
	local blocks = named(route.model, "Townhouse")
	expect(#blocks <= 24).toBeTruthy() -- was 41 a route before 13 Nov 2026
	for _, stop in route.stops do
		for _, entry in stop.popIns do
			local fz = stop.origin:PointToObjectSpace(entry.frame.Position).Z
			for _, h in stop.houses do
				if h.plan.side ~= 0 then
					local same = (stop.origin:PointToObjectSpace(entry.frame.Position).X > 0)
						== (h.plan.side > 0)
					if same then
						expect(math.abs(fz - h.plan.distance) >= h.plan.size.X / 2 + 26).toBeTruthy()
					end
				end
			end
		end
	end
end)
