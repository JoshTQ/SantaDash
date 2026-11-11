--[[
	Frame-rate and freeze reports (shared/ClientStats.luau): device types,
	frame counting, and the server's checks on what a client sends.
]]

local ClientStats = load("ReplicatedStorage.Shared.ClientStats")

describe("ClientStats.device", function()
	it("tells phones, tablets, computers, consoles and VR apart", function()
		local small, big = Vector2.new(844, 390), Vector2.new(1180, 820)
		expect(ClientStats.device({ TouchEnabled = true }, small)).toBe("Phone")
		expect(ClientStats.device({ TouchEnabled = true }, big)).toBe("Tablet")
		expect(ClientStats.device({ TouchEnabled = true })).toBe("Phone")
		expect(ClientStats.device({ KeyboardEnabled = true, TouchEnabled = true }, big)).toBe("Computer")
		expect(ClientStats.device({ KeyboardEnabled = true })).toBe("Computer")
		expect(ClientStats.device({ GamepadEnabled = true })).toBe("Console")
		expect(ClientStats.device({ GamepadEnabled = true, KeyboardEnabled = true })).toBe("Computer")
		expect(ClientStats.device({ VREnabled = true, KeyboardEnabled = true })).toBe("VR")
		for name in { Phone = 1, Tablet = 1, Computer = 1, Console = 1, VR = 1 } do
			expect(ClientStats.Devices[name]).toBe(true)
		end
	end)

	it("copes with an input service that errors on a property", function()
		local input = setmetatable({}, {
			__index = function()
				error("not a valid member")
			end,
		})
		expect(ClientStats.device(input)).toBe("Computer")
	end)
end)

describe("ClientStats segments", function()
	it("counts frames, stutters and freezes", function()
		local seg = ClientStats.newSegment()
		for _ = 1, 58 do
			ClientStats.addFrame(seg, 1 / 60)
		end
		ClientStats.addFrame(seg, 0.3) -- a stutter
		ClientStats.addFrame(seg, 1.5) -- a freeze
		local s = ClientStats.summary(seg)
		expect(s.hitches).toBe(1)
		expect(s.freezes).toBe(1)
		expect(s.worstMs).toBe(1500)
		expect(s.seconds).toBeNear(58 / 60 + 1.8, 0.06)
		expect(s.fps).toBeNear(22, 1) -- 60 frames in about 2.77 s
	end)

	it("reports an empty segment as zero fps", function()
		expect(ClientStats.summary(ClientStats.newSegment()).fps).toBe(0)
	end)
end)

describe("ClientStats.readSummary", function()
	it("accepts a real summary and rounds it", function()
		local s =
			ClientStats.readSummary({ seconds = 12.3, fps = 41.7, worstMs = 300.4, hitches = 2, freezes = 0 })
		expect(s).never.toBeNil()
		expect(s.fps).toBe(41)
		expect(s.worstMs).toBe(300)
	end)

	it("rejects junk: missing, negative, NaN, huge or wrong types", function()
		local good = { seconds = 1, fps = 60, worstMs = 20, hitches = 0, freezes = 0 }
		expect(ClientStats.readSummary(nil)).toBeNil()
		expect(ClientStats.readSummary("hi")).toBeNil()
		for _, bad in { -1, 0 / 0, 1e12, "5", true } do
			for key in good do
				local copy = table.clone(good)
				copy[key] = bad
				expect(ClientStats.readSummary(copy)).toBeNil()
			end
		end
	end)
end)
