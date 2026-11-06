local Config = load("ReplicatedStorage.Shared.Config")
local LightsCheck = load("ServerScriptService.Server.LightsCheck")
local L = Config.LightsCheck

test("houses check themselves on street stops, never in Krampus's Lair", function()
	expect(LightsCheck.applies("Street")).toBeTruthy()
	expect(LightsCheck.applies(nil)).toBeTruthy()
	expect(LightsCheck.applies("Finale")).toBeFalsy()
end)

test("the first checks are staggered across one interval, after a warning", function()
	local first = LightsCheck.firstCheckAt(45, 1, 4)
	expect(first).toBe(45 + L.FirstDelay + L.WarnSeconds)
	local last = LightsCheck.firstCheckAt(45, 4, 4)
	expect(last > first).toBeTruthy()
	expect(last - first < L.Interval).toBeTruthy()
	expect(LightsCheck.firstCheckAt(0, 1, 0)).toBe(L.FirstDelay + L.WarnSeconds)
end)

test("checks repeat every Interval, give or take Jitter", function()
	expect(LightsCheck.nextCheckAt(10, 0.5)).toBe(10 + L.Interval)
	expect(LightsCheck.nextCheckAt(10, 0)).toBe(10 + L.Interval - L.Jitter)
	expect(LightsCheck.nextCheckAt(10, 1)).toBe(10 + L.Interval + L.Jitter)
	-- Never so close that the next warning overlaps the last flash.
	expect(L.Interval - L.Jitter > L.WarnSeconds + L.FlashSeconds).toBeTruthy()
end)

test("the warning shows for WarnSeconds before the flash, and not after", function()
	expect(LightsCheck.warning(20 - L.WarnSeconds - 0.1, 20)).toBeFalsy()
	expect(LightsCheck.warning(20 - L.WarnSeconds, 20)).toBeTruthy()
	expect(LightsCheck.warning(19.9, 20)).toBeTruthy()
	expect(LightsCheck.warning(20, 20)).toBeFalsy()
end)

test("inside means within the walls, Margin in, at any height of the house", function()
	local box = CFrame.new(100, 10, 0) * CFrame.Angles(0, math.rad(90), 0)
	local size = Vector3.new(20, 20, 30)
	expect(LightsCheck.inside(box, size, Vector3.new(100, 3, 0))).toBeTruthy()
	-- Rotated 90: the 30-stud side runs along X.
	expect(LightsCheck.inside(box, size, Vector3.new(114, 3, 0))).toBeTruthy()
	expect(LightsCheck.inside(box, size, Vector3.new(100, 3, 14))).toBeFalsy()
	expect(LightsCheck.inside(box, size, Vector3.new(100, 3, 10 - L.Margin / 2))).toBeFalsy()
	expect(LightsCheck.inside(box, size, Vector3.new(100, 25, 0))).toBeFalsy() -- on the roof
end)

test("a flash spots Santas inside, but not hiding ones or ones in Krampus's basket", function()
	local box, size = CFrame.new(), Vector3.new(20, 20, 20)
	local caught = LightsCheck.spotted(box, size, {
		{ player = "in", position = Vector3.new(2, 0, 2), hidden = false, captive = false },
		{ player = "wardrobe", position = Vector3.new(0, 0, 0), hidden = true, captive = false },
		{ player = "basket", position = Vector3.new(1, 0, 0), hidden = false, captive = true },
		{ player = "outside", position = Vector3.new(40, 0, 0), hidden = false, captive = false },
	})
	expect(#caught).toBe(1)
	expect(caught[1]).toBe("in")
end)

test("a spotted Santa lands outside the wall with the front door, facing away", function()
	local box, size = CFrame.new(0, 10, 0), Vector3.new(20, 20, 30)
	-- Door off-centre in the +Z wall (a porch step makes it sit a little inside).
	local exit = LightsCheck.exitCFrame(box, size, Vector3.new(6, 3.5, 13), Vector3.xAxis)
	expect(exit.Position.Z).toBe(15 + L.ExitDistance)
	expect(exit.Position.X).toBe(6)
	expect(exit.Position.Y).toBe(3.5)
	expect(exit.LookVector.Z > 0.99).toBeTruthy()
	-- A door in the -X wall of a turned house.
	local turned = CFrame.new(50, 10, 0) * CFrame.Angles(0, math.rad(90), 0)
	local side = LightsCheck.exitCFrame(
		turned,
		size,
		turned:PointToWorldSpace(Vector3.new(-9.5, -6.5, 0)),
		Vector3.xAxis
	)
	expect(LightsCheck.inside(turned, size, side.Position)).toBeFalsy()
	local back = turned:PointToObjectSpace(side.Position)
	expect(math.abs(back.X - (-10 - L.ExitDistance)) < 1e-3).toBeTruthy()
end)

test("with no front door, a spotted Santa lands outside the wall facing the street", function()
	local box, size = CFrame.new(0, 10, 0), Vector3.new(20, 20, 30)
	local exit = LightsCheck.exitCFrame(box, size, nil, Vector3.new(-1, 0, 0))
	expect(exit.Position.X).toBe(-10 - L.ExitDistance)
	expect(exit.Position.Y).toBe(3)
	expect(exit.LookVector.X < -0.99).toBeTruthy()
end)
