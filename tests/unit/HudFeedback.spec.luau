--[[
	HUD feedback rules (launch polish, 11 Nov 2026): floating loot numbers,
	full sack, the horn's timer pulse, device-aware button labels, the
	two-tap Back to hub, the top column's order, and RichText-safe names.
]]

local HudFeedback = load("ReplicatedStorage.Shared.HudFeedback")
local HudLayout = load("ReplicatedStorage.Shared.HudLayout")
local Loot = load("ServerScriptService.Server.Loot")
local Util = load("ReplicatedStorage.Shared.Util")

local function data(jingle, count, value, banked, capacity)
	return { jingle = jingle, sackCount = count, sackValue = value, banked = banked, sackCapacity = capacity }
end

local function kinds(pops)
	local out = {}
	for _, p in pops do
		table.insert(out, p.kind .. "=" .. p.text)
	end
	return table.concat(out, ",")
end

describe("HudFeedback.pops", function()
	it("shows nothing for the first update of a run", function()
		expect(#HudFeedback.pops(nil, data(0, 0, 0, 0))).toBe(0)
	end)

	it("pops the present's value and the Jingle on a grab", function()
		expect(kinds(HudFeedback.pops(data(0, 0, 0, 0), data(5, 1, 30, 0)))).toBe("sack=+30,jingle=+5")
	end)

	it("pops one big BANKED number when the sack empties into the sleigh", function()
		expect(kinds(HudFeedback.pops(data(5, 3, 90, 0), data(5, 0, 0, 90)))).toBe("bank=+90")
	end)

	it("pops a red loss when a dog knocks a present out", function()
		expect(kinds(HudFeedback.pops(data(5, 3, 90, 0), data(5, 2, 60, 0)))).toBe("spill=-1")
		expect(kinds(HudFeedback.pops(data(5, 3, 90, 0), data(5, 1, 30, 0)))).toBe("spill=-2")
	end)

	it("pops a spend when Jingle goes down (vault, cocoa)", function()
		expect(kinds(HudFeedback.pops(data(50, 0, 0, 0), data(20, 0, 0, 0)))).toBe("spend=-30")
	end)

	it("pops nothing when nothing changed", function()
		expect(#HudFeedback.pops(data(5, 1, 30, 0), data(5, 1, 30, 0))).toBe(0)
	end)
end)

describe("HudFeedback.sackFull", function()
	it("uses the run's capacity, or the default", function()
		expect(HudFeedback.sackFull(data(0, 6, 0, 0, 6), 6)).toBe(true)
		expect(HudFeedback.sackFull(data(0, 5, 0, 0, 8), 6)).toBe(false)
		expect(HudFeedback.sackFull(data(0, 6, 0, 0, nil), 6)).toBe(true)
	end)
end)

describe("HudFeedback.timerUrgency", function()
	it("only pulses in the horn's last seconds, harder at the end", function()
		expect(HudFeedback.timerUrgency("Sneak", 3)).toBe(0)
		expect(HudFeedback.timerUrgency("Horn", 20)).toBe(0)
		expect(HudFeedback.timerUrgency("Horn", 10) > 0).toBe(true)
		expect(HudFeedback.timerUrgency("Horn", 3) > HudFeedback.timerUrgency("Horn", 8)).toBe(true)
		expect(HudFeedback.timerUrgency("Horn", 0)).toBe(0)
	end)
end)

describe("HudFeedback.keyHint", function()
	it("never shows keyboard keys on phones", function()
		expect(HudFeedback.keyHint("Tap", "Touch")).toBe("TAP!")
		expect(HudFeedback.keyHint("Throw", "Touch")).toBe("THROW")
	end)

	it("names the key or button elsewhere", function()
		expect(HudFeedback.keyHint("Tap", "Keyboard")).toBe("TAP! (Space)")
		expect(HudFeedback.keyHint("Throw", "Keyboard")).toBe("THROW (F)")
		expect(HudFeedback.keyHint("Tap", "Gamepad")).toBe("TAP! (A)")
		expect(HudFeedback.keyHint("Throw", "Gamepad")).toBe("THROW (R2)")
	end)

	it("picks the device from the last input type", function()
		expect(HudFeedback.deviceFor("Touch", true)).toBe("Touch")
		expect(HudFeedback.deviceFor("Gamepad1", false)).toBe("Gamepad")
		expect(HudFeedback.deviceFor("MouseMovement", false)).toBe("Keyboard")
		expect(HudFeedback.deviceFor("Keyboard", true)).toBe("Keyboard")
		expect(HudFeedback.deviceFor(nil, true)).toBe("Touch")
		expect(HudFeedback.deviceFor(nil, false)).toBe("Keyboard")
	end)
end)

describe("HudFeedback.confirmLeave", function()
	it("needs a second tap within a few seconds", function()
		local go, armed = HudFeedback.confirmLeave(100, 0)
		expect(go).toBe(false)
		expect(armed).toBe(100 + HudFeedback.ConfirmSeconds)
		go, armed = HudFeedback.confirmLeave(101, armed)
		expect(go).toBe(true)
		expect(armed).toBe(0)
	end)

	it("asks again if the second tap is too late", function()
		local _, armed = HudFeedback.confirmLeave(100, 0)
		local go = HudFeedback.confirmLeave(100 + HudFeedback.ConfirmSeconds + 1, armed)
		expect(go).toBe(false)
	end)
end)

describe("HudLayout.TopStack", function()
	it("gives every item its own slot, tips last", function()
		local seen = {}
		local last = 0
		for key, order in HudLayout.TopStack.order do
			expect(seen[order]).toBe(nil)
			seen[order] = key
			last = math.max(last, order)
		end
		expect(seen[last]).toBe("tip")
	end)

	it("starts under the stop panel", function()
		expect(HudLayout.TopStack.y >= 8 + 84).toBe(true)
	end)
end)

describe("results rows", function()
	it("carry the user id, so the HUD finds your row even with a shared display name", function()
		local a, b = Loot.newPlayerState(), Loot.newPlayerState()
		a.banked, b.banked = 10, 20
		local rows = Loot.results({ { "Sam", a, 5, 101 }, { "Sam", b, 5, 202 } })
		expect(rows[1].userId).toBe(202)
		expect(rows[2].userId).toBe(101)
	end)
end)

describe("Util.escapeRichText", function()
	it("escapes markup in names", function()
		expect(Util.escapeRichText("<b>Sam</b> & Co")).toBe("&lt;b&gt;Sam&lt;/b&gt; &amp; Co")
		expect(Util.escapeRichText("Plain")).toBe("Plain")
	end)
end)
