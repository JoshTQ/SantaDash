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

describe("HudFeedback.countUp", function()
	it("starts at 0, rises fast, and lands exactly on the total", function()
		expect(HudFeedback.countUp(100, 0)).toBe(0)
		local half = HudFeedback.countUp(100, HudFeedback.CountUpSeconds / 2)
		expect(half > 50 and half < 100).toBe(true) -- eased out
		expect(HudFeedback.countUp(100, HudFeedback.CountUpSeconds)).toBe(100)
		expect(HudFeedback.countUp(100, 99)).toBe(100)
		expect(HudFeedback.countUp(0, 0.5)).toBe(0)
	end)
end)

describe("HudFeedback.summary", function()
	it("says what you grabbed and whether you escaped", function()
		expect(HudFeedback.summary({ grabs = 1, escaped = true, bonus = 2 }, false)).toBe(
			"You grabbed 1 present · escaped x2!"
		)
		expect(HudFeedback.summary({ grabs = 2, escaped = true, bonus = 1 }, false)).toBe(
			"You grabbed 2 presents · escaped!"
		)
		expect(HudFeedback.summary({ grabs = 4, escaped = false }, false)).toBe(
			"You grabbed 4 presents · missed the sleigh"
		)
	end)

	it("points a first heist at the Shop", function()
		local text = HudFeedback.summary({ grabs = 0, escaped = true }, true)
		expect(string.find(text, "Shop", 1, true) ~= nil).toBe(true)
	end)
end)

describe("HudFeedback.edgeArrow", function()
	local size = Vector2.new(800, 400)

	it("hides while Krampus is on screen in front", function()
		expect(HudFeedback.edgeArrow(Vector3.new(300, 200, 20), true, size)).toBe(nil)
	end)

	it("sits on the right edge pointing right when he is off to the right", function()
		local a = HudFeedback.edgeArrow(Vector3.new(2000, 200, 20), false, size)
		expect(a.x).toBe(800 - HudFeedback.ArrowMargin)
		expect(a.y).toBe(200)
		expect(math.abs(a.rotation) < 1e-6).toBe(true)
	end)

	it("flips the direction when he is behind the camera", function()
		local a = HudFeedback.edgeArrow(Vector3.new(2000, 200, -20), false, size)
		expect(a.x).toBe(HudFeedback.ArrowMargin)
		expect(math.abs(math.abs(a.rotation) - 180) < 1e-6).toBe(true)
	end)

	it("points down when he is straight behind", function()
		local a = HudFeedback.edgeArrow(Vector3.new(400, 200, -5), false, size)
		expect(a.y).toBe(400 - HudFeedback.ArrowMargin)
		expect(a.rotation).toBe(90)
	end)

	it("always stays inside the margin", function()
		for _, p in { Vector3.new(-900, -900, 5), Vector3.new(900, 50, 5), Vector3.new(10, 1000, -3) } do
			local a = HudFeedback.edgeArrow(p, false, size)
			expect(a.x >= HudFeedback.ArrowMargin - 1e-6 and a.x <= 800 - HudFeedback.ArrowMargin + 1e-6).toBe(
				true
			)
			expect(a.y >= HudFeedback.ArrowMargin - 1e-6 and a.y <= 400 - HudFeedback.ArrowMargin + 1e-6).toBe(
				true
			)
		end
	end)
end)

describe("HudFeedback.escapeText", function()
	it("only claims a multiplier that was earned", function()
		expect(HudFeedback.escapeText({ escaped = true, bonus = 2 })).toBe("escaped x2")
		expect(HudFeedback.escapeText({ escaped = true, bonus = 1 })).toBe("escaped") -- no Naughty List
		expect(HudFeedback.escapeText({ escaped = true })).toBe("escaped")
		expect(HudFeedback.escapeText({ escaped = true, bonus = 2.5 })).toBe("escaped x2.5")
		expect(HudFeedback.escapeText({ escaped = false, bonus = 2 })).toBe("missed the sleigh")
	end)
end)

describe("HudFeedback banner feed", function()
	local function texts(feed)
		local out = {}
		for _, e in feed do
			table.insert(out, e.text)
		end
		return table.concat(out, "|")
	end

	it("keeps a warning when crew news arrives right after it", function()
		local feed = {}
		HudFeedback.feedAdd(feed, "KRAMPUS IS COMING!", 4)
		HudFeedback.feedAdd(feed, "Sam grabbed the Naughty List!", 2)
		expect(texts(feed)).toBe("KRAMPUS IS COMING!|Sam grabbed the Naughty List!")
		HudFeedback.feedTick(feed, 2.5, false)
		expect(texts(feed)).toBe("KRAMPUS IS COMING!")
		HudFeedback.feedTick(feed, 2, false)
		expect(#feed).toBe(0)
	end)

	it("shows at most BannerMax, dropping the oldest", function()
		local feed = {}
		for i = 1, HudFeedback.BannerMax + 2 do
			HudFeedback.feedAdd(feed, "line " .. i, 3)
		end
		expect(#feed).toBe(HudFeedback.BannerMax)
		expect(feed[1].text).toBe("line 3")
	end)

	it("refreshes a repeat instead of stacking it", function()
		local feed = {}
		HudFeedback.feedAdd(feed, "HONK!", 3)
		HudFeedback.feedTick(feed, 2, false)
		HudFeedback.feedAdd(feed, "HONK!", 3)
		expect(#feed).toBe(1)
		HudFeedback.feedTick(feed, 2, false)
		expect(#feed).toBe(1) -- the clock restarted
	end)

	it("waits out a cutscene, then shows for at most DeferredMax", function()
		local feed = {}
		HudFeedback.feedAdd(feed, "Take-off!", 4)
		HudFeedback.feedAdd(feed, "KRAMPUS IS COMING!", 9)
		HudFeedback.feedTick(feed, 5, true) -- a 5 s cutscene
		expect(#feed).toBe(2) -- nothing used up while hidden
		HudFeedback.feedTick(feed, HudFeedback.DeferredMax - 0.1, false)
		expect(#feed).toBe(2)
		HudFeedback.feedTick(feed, 0.2, false)
		expect(#feed).toBe(0) -- not the full 9 s after Krampus already arrived
	end)

	it("ignores empty text", function()
		local feed = {}
		HudFeedback.feedAdd(feed, "", 3)
		expect(#feed).toBe(0)
	end)
end)

describe("HudFeedback.keyHint for the Lair buttons", function()
	it("PASS LIST and BONE drop their keys on phones", function()
		expect(HudFeedback.keyHint("PassList", "Touch")).toBe("PASS LIST")
		expect(HudFeedback.keyHint("PassList", "Keyboard")).toBe("PASS LIST (Q)")
		expect(HudFeedback.keyHint("PassList", "Gamepad")).toBe("PASS LIST (L1)")
		expect(HudFeedback.keyHint("Bone", "Touch")).toBe("BONE")
		expect(HudFeedback.keyHint("Bone", "Keyboard")).toBe("BONE (G)")
		expect(HudFeedback.keyHint("Bone", "Gamepad")).toBe("BONE (L2)")
		expect(HudFeedback.keyHint("Launch", "Touch")).toBe("LAUNCH")
		expect(HudFeedback.keyHint("Launch", "Keyboard")).toBe("LAUNCH (R)")
		expect(HudFeedback.keyHint("Glitter", "Touch")).toBe("GLITTER")
		expect(HudFeedback.keyHint("Glitter", "Gamepad")).toBe("GLITTER (Y)")
	end)
end)
