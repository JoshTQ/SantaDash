--[[
	Pop-in houses (Josh, 11 Nov 2026: "most houses on the map are closed with
	no entry"): which filler townhouses open their room and which pack it away.
]]

local Config = load("ReplicatedStorage.Shared.Config")
local PopInRules = load("ServerScriptService.Server.PopInRules")
local P = Config.PopIn

local function house(x: number)
	return { doorAt = Vector3.new(x, 0, 0), open = false, lastNear = 0 }
end

test("distance is flat: height doesn't matter", function()
	expect(PopInRules.nearest(Vector3.zero, { Vector3.new(3, 50, 4) })).toBe(5)
	expect(PopInRules.nearest(Vector3.zero, {})).toBe(math.huge)
end)

test("a Santa walking up to the door opens it, and nobody else's door", function()
	local houses = { house(0), house(100) }
	local opens, closes = PopInRules.step(houses, { Vector3.new(P.OpenRadius - 1, 3, 0) }, 1)
	expect(#opens).toBe(1)
	expect(opens[1]).toBe(1)
	expect(#closes).toBe(0)
	expect(houses[1].open).toBe(true)
	expect(houses[2].open).toBe(false)
	-- Just outside the radius: stays shut.
	local shut = { house(0) }
	opens = PopInRules.step(shut, { Vector3.new(P.OpenRadius + 0.5, 0, 0) }, 1)
	expect(#opens).toBe(0)
end)

test("an open room stays while a Santa is around, packs away CloseSeconds after they leave", function()
	local houses = { house(0) }
	PopInRules.step(houses, { Vector3.new(2, 0, 0) }, 0)
	-- Inside the room, or out in the garden: still open.
	local _, closes = PopInRules.step(houses, { Vector3.new(P.CloseRadius - 1, 0, 0) }, 30)
	expect(#closes).toBe(0)
	-- Gone, but not for long enough yet.
	_, closes = PopInRules.step(houses, { Vector3.new(500, 0, 0) }, 30 + P.CloseSeconds - 0.5)
	expect(#closes).toBe(0)
	_, closes = PopInRules.step(houses, { Vector3.new(500, 0, 0) }, 30 + P.CloseSeconds)
	expect(#closes).toBe(1)
	expect(houses[1].open).toBe(false)
end)

test("a room with a dog, an elf or Krampus inside never packs away on them", function()
	local houses = { house(0) }
	PopInRules.step(houses, { Vector3.zero }, 0)
	houses[1].occupied = true
	local _, closes = PopInRules.step(houses, {}, 100)
	expect(#closes).toBe(0)
	houses[1].occupied = false
	_, closes = PopInRules.step(houses, {}, 101)
	expect(#closes).toBe(1)
end)

test("never more than MaxOpen rooms: the one idle longest makes way", function()
	local houses = {}
	for i = 1, P.MaxOpen + 1 do
		houses[i] = house(i * 200)
	end
	-- One Santa visits each house in turn and moves on.
	for i = 1, P.MaxOpen do
		PopInRules.step(houses, { houses[i].doorAt }, i)
	end
	local open = 0
	for _, h in houses do
		open += if h.open then 1 else 0
	end
	expect(open).toBe(P.MaxOpen)
	local opens, closes = PopInRules.step(houses, { houses[P.MaxOpen + 1].doorAt }, P.MaxOpen + 1)
	expect(#opens).toBe(1)
	expect(opens[1]).toBe(P.MaxOpen + 1)
	expect(#closes).toBe(1)
	expect(closes[1]).toBe(1) -- visited first
	open = 0
	for _, h in houses do
		open += if h.open then 1 else 0
	end
	expect(open).toBe(P.MaxOpen)
end)

test("when every open room has a Santa by it, a new door waits rather than going over MaxOpen", function()
	local houses, santas = {}, {}
	for i = 1, P.MaxOpen + 1 do
		houses[i] = house(i * 10) -- a terrace: doors 10 studs apart
	end
	for i = 1, P.MaxOpen do
		table.insert(santas, houses[i].doorAt)
	end
	PopInRules.step(houses, santas, 0)
	table.insert(santas, houses[P.MaxOpen + 1].doorAt)
	local opens, closes = PopInRules.step(houses, santas, 1)
	expect(#closes).toBe(0)
	local open = 0
	for _, h in houses do
		open += if h.open then 1 else 0
	end
	expect(open <= P.MaxOpen).toBeTruthy()
	expect(#opens).toBe(0)
end)

test("the closest door wins when several want to open", function()
	local houses = { house(0), house(10) }
	local opens = PopInRules.step(houses, { Vector3.new(9, 0, 0) }, 0, {
		OpenRadius = 18,
		CloseRadius = 46,
		CloseSeconds = 6,
		MaxOpen = 1,
	})
	expect(#opens).toBe(1)
	expect(opens[1]).toBe(2)
end)

test("pop-in tuning: the doorway is roomy and rooms close only once you're well away", function()
	expect(P.DoorWidth >= 8).toBeTruthy()
	expect(P.DoorHeight >= 10).toBeTruthy()
	expect(P.CloseRadius > P.OpenRadius + 10).toBeTruthy()
	expect(P.MaxOpen >= 4).toBeTruthy()
end)
