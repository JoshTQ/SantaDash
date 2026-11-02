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

test("floes leave hoppable gaps and keep clear of the island", function()
	local floes = CanalRules.floeLayout(300, 340, Random.new(4), { { x = 0, z = 0, radius = 40 } })
	expect(#floes).toBeGreaterThan(200)
	for _, f in floes do
		expect(f.sizeX).toBeLessThan(C.FloeCell)
		expect(f.sizeX).toBeGreaterThan(C.FloeCell - 5)
		local d = math.sqrt(f.x * f.x + f.z * f.z)
		expect(d).toBeGreaterThan(40)
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
