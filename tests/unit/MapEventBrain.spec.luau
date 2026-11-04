local Config = load("ReplicatedStorage.Shared.Config")
local Brain = load("ServerScriptService.Server.MapEventBrain")
local E = Config.MapEvents

local map = { events = { { kind = "Blizzard", weight = 1 } } }

test("events only play on Street stops before Krampus can hunt", function()
	for _, i in Brain.eligibleStops(Config.Run.StopKinds) do
		expect(Config.Run.StopKinds[i]).toBe("Street")
		expect(i).toBeLessThan(Config.Krampus.FirstStop)
	end
	-- The Lair finale is never eligible, even if listed.
	local saved = E.Stops
	E.Stops = { 1, 2, 3 }
	local stops = Brain.eligibleStops({ "Street", "Street", "Finale" })
	expect(#stops).toBe(2)
	E.Stops = saved
end)

test("an event always ends before the horn and is warned first", function()
	local warnAt, startAt, endAt = Brain.timing()
	expect(warnAt).toBeLessThan(startAt)
	expect(startAt).toBeLessThan(endAt)
	expect(endAt <= Config.Run.HornAt).toBeTruthy()
	expect(startAt - warnAt).toBe(E.WarningSeconds)
end)

test("the roll hits about Chance of runs and picks from the map's pool", function()
	local rng = Random.new(7)
	local hits = 0
	for _ = 1, 1000 do
		local plan = Brain.plan(rng, map, Config.Run.StopKinds)
		if plan then
			hits += 1
			expect(plan.kind).toBe("Blizzard")
			expect(plan.entry).toBe(map.events[1])
		end
	end
	expect(hits / 1000).toBeNear(E.Chance, 0.06)
end)

test("switched-off or zero-weight events never play", function()
	local rng = Random.new(1)
	expect(Brain.plan(rng, { events = { { kind = "Blizzard", weight = 0 } } }, Config.Run.StopKinds) == nil).toBeTruthy()
	expect(
		Brain.plan(rng, { events = { { kind = "NoSuchEvent", weight = 5 } } }, Config.Run.StopKinds) == nil
	).toBeTruthy()
	expect(Brain.plan(rng, { events = {} }, Config.Run.StopKinds) == nil).toBeTruthy()
	E.Events.Blizzard.Enabled = false
	for _ = 1, 50 do
		expect(Brain.plan(rng, map, Config.Run.StopKinds) == nil).toBeTruthy()
	end
	E.Events.Blizzard.Enabled = true
end)

test("snow piles top up to the cap and throws respect the cooldown", function()
	local B = E.Events.Blizzard
	expect(Brain.takeSnowballs(0)).toBe(B.PileSnowballs)
	expect(Brain.takeSnowballs(B.MaxSnowballs - 1)).toBe(B.MaxSnowballs)
	expect(Brain.canThrow(0, -math.huge, 10)).toBeFalsy()
	expect(Brain.canThrow(3, 10, 10)).toBeFalsy()
	expect(Brain.canThrow(3, 10, 10 + B.ThrowCooldown)).toBeTruthy()
end)

test("Snowball MVP is whoever splatted most", function()
	expect(Brain.mvp({}) == nil).toBeTruthy()
	local name, count = Brain.mvp({ Ana = 2, Ben = 5, Cy = 1 })
	expect(name).toBe("Ben")
	expect(count).toBe(5)
end)
