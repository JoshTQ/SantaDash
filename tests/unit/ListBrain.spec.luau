-- The Naughty List heist (Josh, 11 Nov 2026: "Naughty book is underwhelming,
-- make it more important more challenging. Maybe the lair has PvE?").
local Config = load("ReplicatedStorage.Shared.Config")
local Brain = load("ServerScriptService.Server.ListBrain")
local L, C = Config.NaughtyList, Config.CuckooWatch

describe("the List is the escape bonus", function()
	test("the stop's bonus only with the List aboard", function()
		expect(Brain.escapeMultiplier(2, true)).toBe(2)
		expect(Brain.escapeMultiplier(2, false)).toBe(L.NoListMultiplier)
		expect(L.NoListMultiplier).toBe(1) -- your sack still banks, like any stop
	end)

	test("the carrier walks at 15, and Peppermint Rush doesn't help", function()
		expect(Brain.carrierSpeed(Config.Player.WalkSpeed)).toBe(15)
		expect(Brain.carrierSpeed(Config.Buys.PeppermintRush.WalkSpeed)).toBe(15)
		expect(Brain.carrierSpeed(8)).toBe(8) -- soggy or skidding stays slower
	end)

	test("a dropped List lies there a while, less on the water", function()
		expect(Brain.looseSeconds(false)).toBe(L.LooseSeconds)
		expect(Brain.looseSeconds(true)).toBe(L.WetSeconds)
		expect(L.WetSeconds).toBeLessThan(L.LooseSeconds)
	end)

	test("a pass goes to the nearest free friend in range", function()
		local from = Vector3.zero
		local friends = {
			{ player = "Far", position = Vector3.new(L.PassRange + 1, 0, 0), free = true },
			{ player = "Near", position = Vector3.new(6, 0, 0), free = true },
			{ player = "Nearer", position = Vector3.new(3, 0, 0), free = false }, -- in a basket
			{ player = "Mid", position = Vector3.new(10, 0, 0), free = true },
		}
		expect(Brain.passTarget(from, friends)).toBe("Near")
		expect(Brain.passTarget(from, { friends[1], friends[3] })).toBeNil()
	end)
end)

describe("Cuckoo Watch", function()
	test("warns, looks, then is done", function()
		expect(Brain.watchState(10, 9)).toBe("Idle")
		expect(Brain.watchState(10, 10)).toBe("Warn")
		expect(Brain.watchState(10, 10 + C.WarnSeconds)).toBe("Look")
		expect(Brain.watchState(10, 10 + C.WarnSeconds + C.LookSeconds)).toBe("Done")
	end)

	test("the next watch comes about Interval seconds later", function()
		local rng = Random.new(3)
		for _ = 1, 50 do
			local at = Brain.nextWatch(rng, 100)
			expect(at).toBeGreaterThanOrEqual(100 + C.Interval - C.Jitter)
			expect(at).toBeLessThanOrEqual(100 + C.Interval + C.Jitter)
		end
	end)

	test("the den is the Lair's footprint, with a little padding", function()
		local box, size = CFrame.new(100, 9, 0), Vector3.new(48, 18, 48)
		expect(Brain.inDen(box, size, Vector3.new(100, 3, 0))).toBe(true)
		expect(Brain.inDen(box, size, Vector3.new(124 + C.DenPadding - 0.5, 3, 0))).toBe(true)
		expect(Brain.inDen(box, size, Vector3.new(130, 3, 0))).toBe(false)
		expect(Brain.inDen(box, size, Vector3.new(100, 3, -40))).toBe(false)
	end)

	test("freezing (or a nudge) is safe; walking is spotted; jumping on the spot is safe", function()
		local a = Vector3.new(0, 3, 0)
		expect(Brain.moved(a, a, 0.25)).toBe(false)
		expect(Brain.moved(a, a + Vector3.new(0.5, 0, 0), 0.25)).toBe(false)
		expect(Brain.moved(a, a + Vector3.new(4, 0, 0), 0.25)).toBe(true) -- 16 studs/s
		expect(Brain.moved(a, a + Vector3.new(0, 5, 0), 0.25)).toBe(false)
		expect(Brain.moved(a, a + Vector3.new(4, 0, 0), 0)).toBe(false)
	end)
end)
