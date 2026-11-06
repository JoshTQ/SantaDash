-- The always-on gold line to the sleigh (Josh, 6 Nov 2026) and the skating pose.
local Config = load("ReplicatedStorage.Shared.Config")
local SleighGuide = load("ReplicatedStorage.Shared.SleighGuide")
local SantaMoves = load("ReplicatedStorage.Shared.SantaMoves")

local SLEIGH = Vector3.new(100, 2, 50)

describe("SleighGuide.shows", function()
	it("points at the sleigh whenever you're off it during a stop, in every phase", function()
		for _, phase in { "Sneak", "LightsOn", "Horn" } do
			local state = { stop = 2, phase = phase, sleighAt = SLEIGH }
			expect(SleighGuide.shows(state, SLEIGH + Vector3.new(300, 0, 0), false)).toBe(true)
			expect(SleighGuide.shows(state, SLEIGH + Vector3.new(SleighGuide.HIDE_WITHIN + 1, 0, 0), false)).toBe(
				true
			)
		end
	end)

	it("hides when you're aboard, in flight, at take-off, in a cutscene or out of a run", function()
		local state = { stop = 1, phase = "Sneak", sleighAt = SLEIGH }
		expect(SleighGuide.shows(state, SLEIGH + Vector3.new(2, 5, 0), false)).toBe(false)
		expect(SleighGuide.shows(state, SLEIGH + Vector3.new(200, 0, 0), true)).toBe(false)
		expect(SleighGuide.shows({ stop = 1, phase = "Flight", sleighAt = SLEIGH }, Vector3.zero, false)).toBe(
			false
		)
		expect(SleighGuide.shows({ stop = 0, phase = "Sneak", sleighAt = SLEIGH }, Vector3.zero, false)).toBe(
			false
		)
		expect(SleighGuide.shows({ stop = 1, phase = "Sneak" }, Vector3.zero, false)).toBe(false)
		expect(SleighGuide.shows(nil, Vector3.zero, false)).toBe(false)
		expect(SleighGuide.shows(state, nil, false)).toBe(false)
	end)

	it("hides inside the Sleigh Stop, where you count as aboard", function()
		expect(SleighGuide.HIDE_WITHIN).toBeLessThan(Config.Map.SleighStopRadius)
	end)
end)

describe("SleighGuide.style and label", function()
	it("gets wider and arcs higher the further away you are, and turns orange after the horn", function()
		local near, far = SleighGuide.style(20, false), SleighGuide.style(600, false)
		expect(far.width).toBeGreaterThan(near.width)
		expect(far.curve).toBeGreaterThan(near.curve)
		expect(SleighGuide.style(600, false).width).toBe(SleighGuide.style(5000, false).width)
		expect(SleighGuide.style(50, true).color).never.toBe(near.color)
	end)

	it("rounds long distances to tens", function()
		expect(SleighGuide.label(42.4)).toBe("SLEIGH  42")
		expect(SleighGuide.label(234)).toBe("SLEIGH  230")
		expect(SleighGuide.label(99.6)).toBe("SLEIGH  100")
	end)
end)

describe("SantaMoves.skatePose", function()
	it("leans forward and sways side to side at skating speed, still when stopped", function()
		local lean, sway = SantaMoves.skatePose(0, 0)
		expect(lean).toBe(0)
		expect(sway).toBe(0)
		local maxSway, minSway = 0, 0
		for k = 0, 40 do
			local l, s = SantaMoves.skatePose(k / 20, Config.Canal.SkateSpeed)
			expect(l).toBeGreaterThan(math.rad(10))
			maxSway, minSway = math.max(maxSway, s), math.min(minSway, s)
		end
		expect(maxSway).toBeGreaterThan(math.rad(8))
		expect(minSway).toBeLessThan(-math.rad(8))
	end)

	it("glides with slow, long strides", function()
		expect(SantaMoves.SKATE_STRIDE).toBeLessThan(1)
	end)
end)
