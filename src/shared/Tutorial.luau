--[[
	First-time player tips: what each lesson says and when it counts as learnt.
	Pure data and rules so it runs in tests; server/Onboarding.luau decides
	when to teach, client/Tips.client.luau shows the card and the guide trail.

	Design (5 Nov 2026): no separate tutorial level. A new player's first real
	run is the tutorial (Stop 1 is already the easy, mostly-Cosy street).
	Each tip shows once per player and is saved in PlayerData (tutorial.done),
	so veterans in the same crew never see them. Tips are short (8 words or
	fewer) because kids skip text; a glowing trail does most of the teaching.

	Lesson fields:
		text       keyboard / mouse wording
		touch      phone wording (optional, falls back to text)
		seconds    how long the card stays up
		doneOn     "show": learnt once shown. "action": stays until the
		           server calls Onboarding.complete (the player actually did it)
		core       part of the first heist; when every core lesson is learnt
		           the player stops being "new" (no First heist! tag)
]]

local Tutorial = {}

export type Lesson = {
	id: string,
	text: string,
	touch: string?,
	seconds: number,
	doneOn: "show" | "action",
	core: boolean,
}

export type State = {
	done: { [string]: boolean },
	tipsOff: boolean,
}

local function lesson(
	id: string,
	text: string,
	touch: string?,
	seconds: number,
	doneOn,
	core: boolean
): Lesson
	return { id = id, text = text, touch = touch, seconds = seconds, doneOn = doneOn, core = core }
end

-- In the order a new player meets them.
Tutorial.Lessons = {
	lesson("Board", "Follow the trail to a sleigh!", nil, 8, "action", true),
	lesson("Sneak", "Lights are off, so you tiptoe. Sneak in!", nil, 5, "show", true),
	lesson("Grab", "Hold E on a present to grab it!", "Hold the button on a present!", 6, "action", true),
	lesson("Carry", "Presents count once they're on the sleigh!", nil, 5, "show", true),
	lesson("LightsOn", "Flickering lights? Hide or get out!", nil, 5, "show", true),
	lesson("Horn", "HONK! Back to the glowing ring!", nil, 5, "show", true),
	lesson("Bank", "Banked! That loot is safe now.", nil, 4, "show", true),
	lesson("Cocoa", "You can afford cocoa! Find the booth.", nil, 5, "show", false),
	lesson("Lair", "Krampus's Lair! Steal the Naughty List!", nil, 5, "show", true),
	lesson("Krampus", "Krampus! Hide in a wardrobe or run!", nil, 5, "show", true),
	lesson("Hide", "Tap fast to hold your breath!", nil, 4, "show", false),
	lesson("Snatched", "Tap fast to wiggle out of the basket!", nil, 4, "show", false),
	lesson("Missed", "Missed it! Run to the next stop!", nil, 5, "show", false),
	lesson("Done", "First heist done! Go again with your crew!", nil, 5, "show", true),
}

Tutorial.MaxWords = 8 -- red-team: kids skip anything longer

local byId: { [string]: Lesson } = {}
for _, l in Tutorial.Lessons do
	byId[l.id] = l
end

function Tutorial.get(id: string): Lesson?
	return byId[id]
end

function Tutorial.newState(): State
	return { done = {}, tipsOff = false }
end

-- Accepts whatever PlayerData saved (or nil) and returns a usable State.
function Tutorial.normalise(saved: any): State
	local state = Tutorial.newState()
	if type(saved) == "table" then
		if type(saved.done) == "table" then
			for id, value in saved.done do
				if type(id) == "string" and value == true and byId[id] then
					state.done[id] = true
				end
			end
		end
		state.tipsOff = saved.tipsOff == true
	end
	return state
end

-- Should this tip be shown now?
function Tutorial.shouldShow(state: State, id: string): boolean
	return byId[id] ~= nil and not state.tipsOff and not state.done[id]
end

-- Called when a tip is shown. Returns true if the state changed (save it).
function Tutorial.onShown(state: State, id: string): boolean
	local l = byId[id]
	if l and l.doneOn == "show" and not state.done[id] then
		state.done[id] = true
		return true
	end
	return false
end

-- The player did the thing. Returns true if the state changed.
function Tutorial.complete(state: State, id: string): boolean
	if byId[id] and not state.done[id] then
		state.done[id] = true
		return true
	end
	return false
end

-- New = still has core lessons to learn (and hasn't switched tips off).
function Tutorial.isNew(state: State): boolean
	if state.tipsOff then
		return false
	end
	for _, l in Tutorial.Lessons do
		if l.core and not state.done[l.id] then
			return true
		end
	end
	return false
end

-- Wording for this device.
function Tutorial.text(id: string, touch: boolean): string
	local l = byId[id]
	if not l then
		return ""
	end
	return if touch and l.touch then l.touch else l.text
end

function Tutorial.wordCount(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

return Tutorial
