-- Frozen Canal Town rules: skating speed, Thin Ice segments, floes, patrols.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local CanalRules = load("ServerScriptService.Server.CanalRules")
local C = Config.Canal

test("ice is a WalkSpeed boost, hoops boost more, nothing slows a Santa", function()
	expect(CanalRules.walkSpeed(16, false, false)).toBe(16)
	expect(CanalRules.walkSpeed(16, true, false)).toBe(C.SkateSpeed)
	expect(CanalRules.walkSpeed(16, true, true)).toBe(C.HoopSpeed)
	expect(CanalRules.walkSpeed(16, false, true)).toBe(C.HoopSpeed)
	expect(CanalRules.walkSpeed(50, true, true)).toBe(50)
end)

test("canal ice by the stops never cracks; the middle is split into pieces", function()
	local segs = CanalRules.segments(40, 660)
	expect(segs[1].crack).toBeFalsy()
	expect(segs[#segs].crack).toBeFalsy()
	expect(segs[1].to - segs[1].from).toBe(C.StopEndClear)
	expect(segs[#segs].to).toBe(660)
	local cracks = 0
	for i, s in segs do
		if s.crack then
			cracks += 1
			expect(s.to - s.from).toBeLessThan(C.SegmentLength * 1.5)
		end
		if i > 1 then
			expect(math.abs(s.from - segs[i - 1].to)).toBeLessThan(0.001) -- no gaps
		end
	end
	expect(cracks).toBeGreaterThan(3)
end)

test("floes are round and lumpy, keep their gaps, stay hoppable and clear of the island", function()
	local floes = CanalRules.floeLayout(300, 340, Random.new(4), { { x = 0, z = 0, radius = 40 } })
	expect(#floes).toBeGreaterThan(200)
	local lumpy = 0
	local discs = {}
	for i, f in floes do
		expect(f.sizeX).toBeLessThan(C.FloeCell)
		expect(f.sizeZ).toBeLessThan(C.FloeCell)
		if #f.discs > 1 then
			lumpy += 1
		end
		for _, d in f.discs do
			expect(math.sqrt(d.x * d.x + d.z * d.z)).toBeGreaterThan(40)
			table.insert(discs, { x = d.x, z = d.z, r = d.r, floe = i })
		end
	end
	-- Not a grid of identical shapes (Josh's playtest, 6 Nov 2026).
	expect(lumpy).toBeGreaterThan(#floes * 0.3)
	expect(lumpy).toBeLessThan(#floes * 0.9)
	-- Different floes never touch, and every floe has a neighbour within a hop.
	local nearestGap = {}
	for i = 1, #discs do
		local a = discs[i]
		for j = i + 1, #discs do
			local b = discs[j]
			if a.floe ~= b.floe then
				local gap = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) - a.r - b.r
				expect(gap).toBeGreaterThan(C.FloeGap[1] - 1e-6)
				nearestGap[a.floe] = math.min(nearestGap[a.floe] or math.huge, gap)
				nearestGap[b.floe] = math.min(nearestGap[b.floe] or math.huge, gap)
			end
		end
	end
	for _, gap in nearestGap do
		expect(gap).toBeLessThan(7.5)
	end
end)

test("a splash lands you on the nearest floe", function()
	local pts = { Vector3.new(0, 0, 0), Vector3.new(10, 5, 0), Vector3.new(-30, 0, 0) }
	expect(CanalRules.nearest(pts, Vector3.new(8, 0, 1))).toBe(2)
	expect(CanalRules.nearest({}, Vector3.zero)).toBe(nil)
end)

test("dogs patrol back and forth along their path", function()
	local pts = { Vector3.new(0, 0, 0), Vector3.new(0, 0, 100) }
	local p = CanalRules.patrolAt(pts, 10, 5)
	expect(p.Z).toBeNear(50, 0.01)
	local back, facing = CanalRules.patrolAt(pts, 10, 15)
	expect(back.Z).toBeNear(50, 0.01)
	expect(facing.Z).toBeLessThan(0)
end)

test("a corgi knocks out one average present; an empty sack loses nothing", function()
	local st = Loot.newPlayerState()
	expect(Loot.dropOne(st)).toBe(nil)
	st.sackCount, st.sackValue = 3, 300
	expect(Loot.dropOne(st)).toBe(100)
	expect(st.sackCount).toBe(2)
	expect(st.sackValue).toBe(200)
end)

test("forest and hills fill the bands and stay off the canal", function()
	local regions = { { x0 = 90, x1 = 350, z0 = -115, z1 = 630 } }
	local canal = { x0 = -1e4, x1 = 1e4, z0 = -70, z1 = -10 }
	local trees, hills = CanalRules.woodland(Random.new(3), regions, { canal })
	expect(#trees).toBeGreaterThan(80)
	expect(#hills).toBeGreaterThan(5)
	local lit, raised = 0, 0
	for _, t in trees do
		expect(t.z < -76 or t.z > -4).toBeTruthy()
		expect(t.x >= 90 and t.x <= 350).toBeTruthy()
		if t.lit then
			lit += 1
		end
		if t.y > 0.5 then
			raised += 1
		end
	end
	expect(lit).toBeGreaterThan(0)
	expect(raised).toBeGreaterThan(0) -- some trees stand on hills
	for _, h in hills do
		expect(CanalRules.groundHeight(hills, h.x, h.z)).toBeGreaterThan(h.height - 0.01) -- overlaps only add
		expect(h.z + h.radius < -70 or h.z - h.radius > -10).toBeTruthy()
	end
	expect(CanalRules.groundHeight(hills, -500, -500)).toBe(0)
end)
