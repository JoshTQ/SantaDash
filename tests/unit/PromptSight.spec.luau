-- Josh (13 Nov 2026): "you can interact with gifts through walls, outside of the house".
local PromptSight = load("ReplicatedStorage.Shared.PromptSight")

test("gift, search, hide, steal and tree-box prompts need sight; doors and buys don't", function()
	expect(PromptSight.applies("Grab", "Box")).toBe(true)
	expect(PromptSight.applies("Search", "SpotTrigger")).toBe(true)
	expect(PromptSight.applies("Hide", "Wardrobe")).toBe(true)
	expect(PromptSight.applies("Steal", "Scroll")).toBe(true)
	expect(PromptSight.applies("Open", "TreeBox")).toBe(true)
	expect(PromptSight.applies("Open", "Door")).toBe(false)
	expect(PromptSight.applies("Close", "Door")).toBe(false)
	expect(PromptSight.applies("Slide down", "ChimneyTop")).toBe(false)
	expect(PromptSight.applies("Buy perk", "CocoaMachine")).toBe(false)
end)

test("a clear ray sees it; a wall a few studs short blocks it; clipping its shelf doesn't", function()
	local gift, size = Vector3.new(0, 1, 0), Vector3.new(2, 2, 2)
	expect(PromptSight.blocked(nil, gift, size)).toBe(false)
	expect(PromptSight.blocked(Vector3.new(0, 1, -3.5), gift, size)).toBe(true) -- wall face
	expect(PromptSight.blocked(Vector3.new(0, 0.1, -1.2), gift, size)).toBe(false) -- the table edge
end)

test("a thin secret-bookcase trigger on the back wall can't be found from outside", function()
	local trigger, size = Vector3.new(0, 4, 0), Vector3.new(5.1, 10, 1.2)
	expect(PromptSight.blocked(Vector3.new(0, 4, -1.7), trigger, size)).toBe(true) -- wall's outer face
	expect(PromptSight.blocked(Vector3.new(0, 4, 0.6), trigger, size)).toBe(false) -- its own face
end)
