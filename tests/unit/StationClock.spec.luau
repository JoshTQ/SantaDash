local Config = load("ReplicatedStorage.Shared.Config")
local StationClock = load("ReplicatedStorage.Shared.StationClock")
local Util = load("ReplicatedStorage.Shared.Util")

test("a bay cycles Arriving, Boarding, Departing, Away", function()
	local lm = Config.LobbyMap
	local board = Config.LobbyMap.BoardSeconds.Public
	local base = StationClock.cycleLength("Public") * 1000
	expect(StationClock.phaseAt("Public", 1, base + 0.1).name).toBe("Arriving")
	expect(StationClock.phaseAt("Public", 1, base + lm.ArriveSeconds + 0.1).name).toBe("Boarding")
	expect(StationClock.phaseAt("Public", 1, base + lm.ArriveSeconds + board + 0.1).name).toBe("Departing")
	expect(StationClock.phaseAt("Public", 1, base + lm.ArriveSeconds + board + lm.DepartSeconds + 0.1).name).toBe(
		"Away"
	)
end)

test("phase windows contain t and the cycle advances", function()
	for _, kind in { "Public", "Party", "Private" } do
		local last = -math.huge
		for i = 0, 400 do
			local t = 1.7e9 + i * 0.37
			local p = StationClock.phaseAt(kind, 2, t)
			expect(p.startsAt <= t and t < p.endsAt).toBeTruthy()
			expect(p.cycle >= last).toBeTruthy()
			last = p.cycle
		end
	end
end)

test("bays are staggered so they do not all board together", function()
	local t = 1.7e9
	local starts = {}
	for n = 1, 3 do
		local p = StationClock.phaseAt("Public", n, t)
		starts[n] = (p.startsAt - p.cycle * StationClock.cycleLength("Public"))
	end
	expect(starts[1] ~= starts[2] and starts[2] ~= starts[3]).toBeTruthy()
end)

test("clock formats a countdown", function()
	expect(Util.clock(7.2)).toBe("0:08")
	expect(Util.clock(65)).toBe("1:05")
	expect(Util.clock(-3)).toBe("0:00")
end)
