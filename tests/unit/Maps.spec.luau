local Config = load("ReplicatedStorage.Shared.Config")
local Maps = load("ReplicatedStorage.Shared.Maps")
local MapFeatures = load("ServerScriptService.Server.MapFeatures")

test("the default map is the original street with Config's layout", function()
	local map = Maps.get()
	expect(map.id).toBe(Maps.Default)
	expect(map.layout.Slots).toBe(Config.Street.Slots)
	expect(map.layout.StopSpacing).toBe(Config.Map.StopSpacing)
	expect(map.palette.Ground[1] ~= nil).toBeTruthy()
end)

test("every map in the rotation resolves and is playable", function()
	for _, id in Maps.Rotation do
		local map = Maps.get(id)
		expect(map.id).toBe(id)
		local landing = map.layout.Slots[1]
		expect(landing.Ring).toBe("Near") -- the sleigh lands on slot 1
		for _, slot in map.layout.Slots do
			expect(Config.Rings[slot.Ring] ~= nil).toBeTruthy()
			expect(slot.Side == -1 or slot.Side == 1).toBeTruthy()
		end
		for _, kindName in Config.Run.StopKinds do
			for _, slotIndex in Config.StopKinds[kindName].Slots do
				expect(map.layout.Slots[slotIndex] ~= nil).toBeTruthy()
			end
		end
		for _, feature in map.features do
			expect(MapFeatures[feature.kind] ~= nil).toBeTruthy()
		end
	end
end)

test("unknown maps fail loudly", function()
	local ok = pcall(Maps.get, "NoSuchMap")
	expect(ok).toBeFalsy()
end)

test("a run never repeats the map the crew just played when there is a choice", function()
	local saved = Maps.Rotation
	Maps.Rotation = { "A", "B", "C" }
	local rng = Random.new(3)
	for _ = 1, 30 do
		expect(Maps.pick(rng, "B") ~= "B").toBeTruthy()
	end
	Maps.Rotation = { "A" }
	expect(Maps.pick(rng, "A")).toBe("A")
	Maps.Rotation = saved
end)

test("Maps.ids lists every map, sorted, including the default and the rotation", function()
	local ids = Maps.ids()
	expect(ids).toContain(Maps.Default)
	for _, id in Maps.Rotation do
		expect(ids).toContain(id)
	end
	local sorted = table.clone(ids)
	table.sort(sorted)
	expect(ids).toEqual(sorted)
end)

test("Maps.get caches each map", function()
	expect(Maps.get(Maps.Default)).toBe(Maps.get(Maps.Default))
end)
