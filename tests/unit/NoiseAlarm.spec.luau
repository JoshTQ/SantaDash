local Config = load("ReplicatedStorage.Shared.Config")
local NoiseAlarm = load("ServerScriptService.Server.NoiseAlarm")
local A = Config.Noise.Alarm

test("a full meter sets off the alarm on Stops 1-2, never where Krampus answers it", function()
	expect(NoiseAlarm.applies(1, "Street")).toBeTruthy()
	expect(NoiseAlarm.applies(2, "Street")).toBeTruthy()
	expect(NoiseAlarm.applies(Config.Krampus.NoiseArrivalFrom, "Street")).toBeFalsy()
	expect(NoiseAlarm.applies(1, "Finale")).toBeFalsy()
end)

test("the alarm horn gives HornSeconds when there's more time left", function()
	expect(NoiseAlarm.departAt(50, 120)).toBe(50 + A.HornSeconds)
end)

test("the alarm horn never resets a shorter countdown (20 s left stays 20 s)", function()
	expect(NoiseAlarm.departAt(100, 120)).toBe(120)
	expect(NoiseAlarm.departAt(119, 120)).toBe(120)
end)

test("dogs chase the nearest Santa in range who isn't safe at the Sleigh Stop", function()
	local from = Vector3.new(0, 0, 0)
	local santas = {
		{ player = "safe", position = Vector3.new(3, 0, 0), safe = true },
		{ player = "near", position = Vector3.new(20, 0, 0), safe = false },
		{ player = "far", position = Vector3.new(60, 0, 0), safe = false },
		{ player = "gone", position = Vector3.new(A.SenseRange + 1, 0, 0), safe = false },
	}
	expect(NoiseAlarm.target(from, santas).player).toBe("near")
	expect(NoiseAlarm.target(from, { santas[1], santas[4] })).toBe(nil)
end)

test("dogs start side by side, centred on the release point", function()
	local a, b = NoiseAlarm.spawnOffset(1, 2), NoiseAlarm.spawnOffset(2, 2)
	expect(a.X).toBe(-b.X)
	expect(a.X ~= b.X).toBeTruthy()
end)

test("an early horn isn't undone when the lights come on afterwards", function()
	expect(NoiseAlarm.nextPhase("Horn", "LightsOn")).toBe("Horn")
	expect(NoiseAlarm.nextPhase("Sneak", "LightsOn")).toBe("LightsOn")
	expect(NoiseAlarm.nextPhase("LightsOn", "Horn")).toBe("Horn")
	expect(NoiseAlarm.nextPhase("Horn", "Flight")).toBe("Flight")
end)
