local Config = load("ReplicatedStorage.Shared.Config")
local Brain = load("ServerScriptService.Server.KrampusBrain")
local K = Config.Krampus

test("he never comes to Stops 1-2, even on a full noise meter", function()
	expect(Brain.shouldArrive(1, "Street", 100, true)).toBeFalsy()
	expect(Brain.shouldArrive(2, "Street", 100, true)).toBeFalsy()
end)

test("from Stop 3 a full meter or ArriveAt brings him", function()
	expect(Brain.shouldArrive(3, "Street", 0, true)).toBeTruthy()
	expect(Brain.shouldArrive(3, "Street", K.ArriveAt - 1, false)).toBeFalsy()
	expect(Brain.shouldArrive(3, "Street", K.ArriveAt, false)).toBeTruthy()
end)

test("he is always home in his Lair", function()
	expect(Brain.shouldArrive(3, "Finale", 0, false)).toBeTruthy()
end)

test("the Stop 1 tease is off until Josh approves it", function()
	expect(Brain.shouldTease(1, 100)).toBe(K.TeaseEnabled)
end)

local origin = Vector3.new(0, 0, 0)
local function candidate(name, x, extra)
	local c =
		{ player = name, position = Vector3.new(x, 0, 0), hidden = false, captive = false, aboard = false }
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

test("chases the nearest Santa he can sense", function()
	local target = Brain.pickTarget(origin, { candidate("far", 40), candidate("near", 10) }, 0)
	expect(target.player).toBe("near")
end)

test("ignores hidden, snatched, on-sleigh, recently dropped and out-of-range Santas", function()
	local list = {
		candidate("hidden", 5, { hidden = true }),
		candidate("captive", 5, { captive = true }),
		candidate("aboard", 5, { aboard = true }),
		candidate("dropped", 5, { ignoreUntil = 10 }),
		candidate("faraway", K.SenseRange + 1),
	}
	expect(Brain.pickTarget(origin, list, 0)).toBe(nil)
	expect(Brain.pickTarget(origin, list, 10).player).toBe("dropped")
end)

test("catch range", function()
	expect(Brain.canCatch(origin, Vector3.new(K.CatchRange, 0, 0))).toBeTruthy()
	expect(Brain.canCatch(origin, Vector3.new(K.CatchRange + 1, 0, 0))).toBeFalsy()
end)

test("bells only work from behind him", function()
	local facing = CFrame.new() -- looking down -Z, so his back is +Z
	expect(Brain.isBehind(facing, Vector3.new(0, 0, 4))).toBeTruthy()
	expect(Brain.isBehind(facing, Vector3.new(0, 0, -4))).toBeFalsy()
	expect(Brain.isBehind(facing, Vector3.new(0, 0, K.BellRange + 1))).toBeFalsy()
end)

test("breath drains when he is near and recovers when he leaves", function()
	local drained = Brain.breathStep(1, K.BreathRange - 1, 1)
	expect(drained).toBeNear(1 - 1 / K.BreathSeconds)
	expect(Brain.breathStep(drained, K.BreathRange + 1, 1)).toBeNear(1)
	expect(Brain.breathStep(0.01, 0, 10)).toBe(0)
end)

test("tapping fast enough out-breathes him", function()
	local perSecond = math.min(K.MaxTapsPerSecond, 4) * K.BreathPerTap
	expect(perSecond).toBeGreaterThan(1 / K.BreathSeconds)
end)

test("taps are rate limited", function()
	expect(Brain.tapAllowed(0, 1 / K.MaxTapsPerSecond)).toBeTruthy()
	expect(Brain.tapAllowed(0, 0.5 / K.MaxTapsPerSecond)).toBeFalsy()
end)

test("solo Santas wiggle free faster than crews", function()
	expect(Brain.wiggleNeeded(1)).toBe(K.WiggleSolo)
	expect(Brain.wiggleNeeded(4)).toBe(K.WiggleCrew)
	expect(K.WiggleSolo).toBeLessThan(K.WiggleCrew)
end)
