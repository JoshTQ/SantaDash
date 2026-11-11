-- Krampus's Lair clockwork timing (LairAnimator.client applies it).
local LairMotion = load("ReplicatedStorage.Shared.LairMotion")

describe("LairMotion", function()
	it("ticks the clock once a second, the minute hand round once a minute", function()
		local hour0, minute0 = LairMotion.hands(120)
		expect(minute0).toBeNear(0, 1e-9)
		local _, minuteHalf = LairMotion.hands(150.7)
		expect(minuteHalf).toBeNear(math.pi, 1e-9) -- 30 ticks, the 0.7 s ignored
		local hour1 = LairMotion.hands(120 + 60)
		expect(hour1 - hour0).toBeNear(2 * math.pi / 12, 1e-9)
	end)

	it("turns neighbouring gears opposite ways, small gears faster", function()
		expect(LairMotion.gear(10, 1, 1) > 0).toBeTruthy()
		expect(LairMotion.gear(10, 2, 1) < 0).toBeTruthy()
		expect(math.abs(LairMotion.gear(10, 1, 0.5))).toBeGreaterThan(math.abs(LairMotion.gear(10, 1, 1)))
	end)

	it("opens the cuckoo on the horn, holds it, then shuts it", function()
		local o, h = LairMotion.CuckooOpenSeconds, LairMotion.CuckooHoldSeconds
		expect(LairMotion.cuckoo(nil)).toBe(0)
		expect(LairMotion.cuckoo(-1)).toBe(0)
		expect(LairMotion.cuckoo(o / 2)).toBeNear(0.5, 1e-9)
		expect(LairMotion.cuckoo(o + h / 2)).toBe(1)
		expect(LairMotion.cuckoo(o + h + o / 2)).toBeNear(0.5, 1e-9)
		expect(LairMotion.cuckoo(o + h + o + 1)).toBe(0)
		expect(LairMotion.pop(0.2)).toBe(0) -- the doors open before he pops out
		expect(LairMotion.pop(1)).toBe(1)
	end)

	it("the Cuckoo Watch's short look shuts the doors sooner (Josh, 11 Nov 2026)", function()
		local o = LairMotion.CuckooOpenSeconds
		expect(LairMotion.cuckoo(o + 1, 1.5)).toBe(1)
		expect(LairMotion.cuckoo(o + 1.5 + o + 0.1, 1.5)).toBe(0)
		expect(LairMotion.cuckoo(o + 1.5 + o + 0.1)).toBe(1) -- the horn's cuckoo holds longer
	end)

	it("sways the bells gently, shakes them on the horn", function()
		local idle = LairMotion.bell(3, 1, nil, nil)
		expect(math.abs(idle)).toBeLessThan(0.051)
		local biggest = 0
		for t = 0, 1, 0.05 do
			biggest =
				math.max(biggest, math.abs((LairMotion.bell(t, 1, LairMotion.CuckooOpenSeconds + 1, nil))))
		end
		expect(biggest).toBeGreaterThan(0.2)
	end)

	it("lights the seven bells one by one when Krampus wakes, then stops", function()
		local gap = LairMotion.BellsLightGap
		local _, firstLit = LairMotion.bell(0, 1, nil, 0)
		local _, lastEarly = LairMotion.bell(0, 7, nil, gap)
		local _, lastLit = LairMotion.bell(0, 7, nil, 6 * gap)
		local _, after = LairMotion.bell(0, 1, nil, LairMotion.BellsRingSeconds + 1)
		expect(firstLit).toBe(true)
		expect(lastEarly).toBe(false)
		expect(lastLit).toBe(true)
		expect(after).toBe(false)
	end)

	it("blinks the eyes briefly", function()
		local closed = 0
		for t = 0, 10, 0.01 do
			if not LairMotion.eyesOpen(t, 1) then
				closed += 1
			end
		end
		expect(closed).toBeGreaterThan(0)
		expect(closed).toBeLessThan(200) -- under a fifth of the time
	end)
end)
