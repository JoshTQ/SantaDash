-- First-time player tips: lesson rules (shared/Tutorial.luau).
local Tutorial = load("ReplicatedStorage.Shared.Tutorial")

describe("Tutorial lessons", function()
	it("keeps every tip short enough for kids (8 words or fewer)", function()
		for _, l in Tutorial.Lessons do
			expect(Tutorial.wordCount(l.text) <= Tutorial.MaxWords).toBe(true)
			if l.touch then
				expect(Tutorial.wordCount(l.touch) <= Tutorial.MaxWords).toBe(true)
			end
		end
	end)

	it("has unique ids, sensible durations and no tutorial-only wording on phones", function()
		local seen = {}
		for _, l in Tutorial.Lessons do
			expect(seen[l.id]).toBeNil()
			seen[l.id] = true
			expect(l.seconds >= 3 and l.seconds <= 8).toBe(true)
			expect(l.doneOn == "show" or l.doneOn == "action").toBe(true)
		end
		-- Phones never say "Press" or a keyboard key.
		for _, l in Tutorial.Lessons do
			local phone = Tutorial.text(l.id, true)
			expect(phone).never.toContain("Press")
			expect(phone).never.toContain(" E ")
		end
	end)

	it("uses the phone wording on touch screens", function()
		expect(Tutorial.text("Grab", false)).toContain("E")
		expect(Tutorial.text("Grab", true)).never.toBe(Tutorial.text("Grab", false))
		expect(Tutorial.text("Sneak", true)).toBe(Tutorial.text("Sneak", false))
		expect(Tutorial.text("Nope", true)).toBe("")
	end)
end)

describe("Tutorial state", function()
	it("shows a tip once, and 'show' tips are learnt as soon as they are shown", function()
		local s = Tutorial.newState()
		expect(Tutorial.shouldShow(s, "Sneak")).toBe(true)
		expect(Tutorial.onShown(s, "Sneak")).toBe(true)
		expect(Tutorial.shouldShow(s, "Sneak")).toBe(false)
		expect(Tutorial.onShown(s, "Sneak")).toBe(false)
	end)

	it("keeps 'action' tips until the player does it", function()
		local s = Tutorial.newState()
		expect(Tutorial.onShown(s, "Grab")).toBe(false)
		expect(Tutorial.shouldShow(s, "Grab")).toBe(true)
		expect(Tutorial.complete(s, "Grab")).toBe(true)
		expect(Tutorial.shouldShow(s, "Grab")).toBe(false)
		expect(Tutorial.complete(s, "Grab")).toBe(false)
	end)

	it("is new until every core lesson is learnt", function()
		local s = Tutorial.newState()
		expect(Tutorial.isNew(s)).toBe(true)
		for _, l in Tutorial.Lessons do
			if l.core then
				Tutorial.complete(s, l.id)
			end
		end
		expect(Tutorial.isNew(s)).toBe(false)
		-- Optional lessons (Hide, Snatched, Cocoa, Missed) don't keep you new.
		expect(Tutorial.shouldShow(s, "Hide")).toBe(true)
	end)

	it("never shows tips once switched off, and is no longer new", function()
		local s = Tutorial.newState()
		s.tipsOff = true
		expect(Tutorial.shouldShow(s, "Sneak")).toBe(false)
		expect(Tutorial.isNew(s)).toBe(false)
	end)

	it("ignores unknown lessons", function()
		local s = Tutorial.newState()
		expect(Tutorial.shouldShow(s, "Dance")).toBe(false)
		expect(Tutorial.onShown(s, "Dance")).toBe(false)
		expect(Tutorial.complete(s, "Dance")).toBe(false)
		expect(Tutorial.get("Dance")).toBeNil()
	end)

	it("normalises saved data, dropping junk and lessons that no longer exist", function()
		local s = Tutorial.normalise({
			done = { Sneak = true, Gone = true, Grab = "yes", [5] = true },
			tipsOff = 1,
		})
		expect(s.done.Sneak).toBe(true)
		expect(s.done.Gone).toBeNil()
		expect(s.done.Grab).toBeNil()
		expect(s.tipsOff).toBe(false)
		expect(Tutorial.normalise(nil)).toEqual(Tutorial.newState())
		expect(Tutorial.normalise("junk")).toEqual(Tutorial.newState())
		expect(Tutorial.normalise({ tipsOff = true }).tipsOff).toBe(true)
	end)
end)
