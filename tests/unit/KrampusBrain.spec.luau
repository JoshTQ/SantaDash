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

test("wiggling free takes 15 taps, solo or in a crew", function()
	expect(Brain.wiggleNeeded()).toBe(15)
end)

test("tapping refills breath but never past full", function()
	expect(Brain.tapBreath(0.5)).toBeNear(0.5 + K.BreathPerTap)
	expect(Brain.tapBreath(0.99)).toBe(1)
	expect(Brain.tapBreath(1)).toBe(1)
end)

describe("clipFor (Meshy animations)", function()
	local function rig(clips)
		local set = {}
		for _, c in clips do
			set[c] = true
		end
		return function(name)
			return set[name] == true
		end
	end
	local full = rig({ "Idle", "Scheme", "Tiptoe", "Sniff", "Snatch", "Dizzy" })

	it("maps each state to its clip", function()
		expect(Brain.clipFor("waiting", full)).toBe("Scheme")
		expect(Brain.clipFor("dizzy", full)).toBe("Dizzy")
		expect(Brain.clipFor("sniffing", full)).toBe("Sniff")
		expect(Brain.clipFor("moving", full)).toBe("Tiptoe")
		expect(Brain.clipFor("still", full)).toBe("Idle")
	end)

	it("falls back to what the rig has", function()
		local some = rig({ "Idle", "Tiptoe" })
		expect(Brain.clipFor("sniffing", some)).toBe("Tiptoe")
		expect(Brain.clipFor("dizzy", some)).toBe("Idle")
		expect(Brain.clipFor("unknown", some)).toBe("Idle")
	end)

	it("is nil on the stand-in (no clips)", function()
		expect(Brain.clipFor("moving", rig({}))).toBeNil()
	end)
end)

-- Magic tricks and the Grumpy Meter (Josh, 6 Nov 2026: "Krampus is too easy").
describe("magic tricks", function()
	local M = K.Magic
	local function ctx(extra)
		local c = {
			now = 100,
			level = 3,
			lastCastAt = -math.huge,
			lastTrick = nil,
			from = origin,
			candidates = {},
			hitAt = {},
			noiseAt = nil,
			safe = function()
				return false
			end,
		}
		for k, v in extra do
			c[k] = v
		end
		return c
	end

	it("gets grumpier over time and with every bell ring, up to Furious", function()
		expect(Brain.grumpyLevel(0, 0)).toBe(1)
		expect(Brain.grumpyLevel(M.Grumpy.At[2], 0)).toBe(2)
		expect(Brain.grumpyLevel(M.Grumpy.At[3], 0)).toBe(3)
		expect(Brain.grumpyLevel(0, 1)).toBe(2)
		expect(Brain.grumpyLevel(0, 5)).toBe(3)
	end)

	it("is slower than a Santa until Furious, and Peppermint Rush always outruns him", function()
		expect(Brain.speedFor(1) < Config.Player.WalkSpeed).toBe(true)
		expect(Brain.speedFor(3) > Config.Player.WalkSpeed).toBe(true)
		expect(Brain.speedFor(3) < Config.Buys.PeppermintRush.WalkSpeed).toBe(true)
	end)

	it("only unlocks Frost Zap at first", function()
		local trick = Brain.pickTrick(ctx({ level = 1, candidates = { candidate("near", 10) } }))
		expect(trick).toBeNil()
		local zap = Brain.pickTrick(ctx({ level = 1, candidates = { candidate("mid", 40) } }))
		expect(zap).toBe("FrostZap")
	end)

	it("never zaps point blank or out of range", function()
		expect(Brain.pickTrick(ctx({ level = 1, candidates = { candidate("a", M.FrostZap.MinRange - 1) } }))).toBeNil()
		expect(Brain.pickTrick(ctx({ level = 1, candidates = { candidate("a", M.FrostZap.MaxRange + 1) } }))).toBeNil()
	end)

	it("stomps when a Santa gets close, once he's Cross", function()
		local trick, target = Brain.pickTrick(ctx({ level = 2, candidates = { candidate("near", 10) } }))
		expect(trick).toBe("FrostStomp")
		expect(target.player).toBe("near")
	end)

	it("blinks to the Santa nearest the latest noise when they've got away", function()
		local trick, target = Brain.pickTrick(ctx({
			candidates = { candidate("quiet", 70), candidate("noisy", -80) },
			noiseAt = Vector3.new(-82, 0, 0),
		}))
		expect(trick).toBe("BellBlink")
		expect(target.player).toBe("noisy")
	end)

	it("never blinks into the Sleigh Stop", function()
		local trick = Brain.pickTrick(ctx({
			candidates = { candidate("far", 80) },
			safe = function()
				return true
			end,
		}))
		expect(trick).never.toBe("BellBlink")
	end)

	it("waits out the cooldown between tricks", function()
		local c = ctx({
			level = 1,
			candidates = { candidate("mid", 40) },
			lastCastAt = 100 - M.Grumpy.Cooldown[1] + 1,
		})
		expect(Brain.pickTrick(c)).toBeNil()
		c.lastCastAt = 100 - M.Grumpy.Cooldown[1]
		expect(Brain.pickTrick(c)).toBe("FrostZap")
	end)

	it("never picks a hidden, snatched, aboard, swimming, iced or recently hit Santa", function()
		for _, extra in
			{ { hidden = true }, { captive = true }, { aboard = true }, { inWater = true }, { iced = true } }
		do
			expect(Brain.pickTrick(ctx({ level = 1, candidates = { candidate("x", 40, extra) } }))).toBeNil()
		end
		local hit =
			ctx({ level = 1, candidates = { candidate("x", 40) }, hitAt = { x = 100 - M.RehitSeconds + 1 } })
		expect(Brain.pickTrick(hit)).toBeNil()
	end)

	it("mixes it up: the trick he just used goes last", function()
		local c = ctx({ level = 3, candidates = { candidate("far", 50) }, lastTrick = "BellBlink" })
		expect(Brain.pickTrick(c)).toBe("FrostZap")
	end)

	it("still chases an ice cube so he can scoop it up", function()
		local target = Brain.pickTarget(origin, { candidate("cube", 20, { iced = true }) }, 0)
		expect(target.player).toBe("cube")
	end)

	it("lands beside the Santa, on his side", function()
		local spot = Brain.blinkSpot(origin, Vector3.new(50, 0, 0))
		expect(spot.X).toBe(50 - M.BellBlink.LandBeside)
	end)

	it("the frost ring only catches Santas on the ground at its edge", function()
		expect(Brain.stompHits(20, 20, false)).toBe(true)
		expect(Brain.stompHits(20, 20, true)).toBe(false)
		expect(Brain.stompHits(10, 20, false)).toBe(false)
		expect(Brain.stompRadius(M.FrostStomp.Seconds * 2)).toBe(M.FrostStomp.Radius)
		expect(Brain.skidSpeed(16)).toBe(16 * M.FrostStomp.SkidSpeed)
	end)
end)
