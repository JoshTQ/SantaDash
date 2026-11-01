-- Invariants the design relies on; catches a bad edit to Config.luau.
local Config = load("ReplicatedStorage.Shared.Config")

test("stop timeline is ordered: lights, horn, departure", function()
	expect(Config.Run.LightsOnAt).toBeLessThan(Config.Run.HornAt)
	expect(Config.Run.HornAt).toBeLessThan(Config.Run.StopSeconds)
end)

test("the route ends in the finale and every stop kind exists", function()
	local kinds = Config.Run.StopKinds
	expect(kinds[#kinds]).toBe("Finale")
	for _, name in kinds do
		expect(Config.StopKinds[name] ~= nil).toBeTruthy()
	end
end)

test("launch slice: 3 stops, Near and Far rings only", function()
	expect(#Config.Run.StopKinds).toBe(3)
	for _, slotIndex in Config.StopKinds.Street.Slots do
		expect(Config.Street.Slots[slotIndex].Ring ~= "Mid").toBeTruthy()
	end
end)

test("every stop kind's slots and end house exist", function()
	for _, kind in Config.StopKinds do
		expect(Config.Street.Slots[kind.Slots[1]].Ring).toBe("Near") -- landing house first
		for _, slotIndex in kind.Slots do
			expect(Config.Street.Slots[slotIndex] ~= nil).toBeTruthy()
		end
		expect(Config.Houses.Types[kind.EndHouse] ~= nil).toBeTruthy()
	end
end)

test("noise escalation covers every stop", function()
	expect(#Config.Noise.StopMultiplier >= #Config.Run.StopKinds).toBeTruthy()
end)

test("Krampus starts at Stop 3 (Josh, 1 Nov) and can be outrun", function()
	expect(Config.Krampus.FirstStop).toBe(3)
	expect(Config.Krampus.WalkSpeed).toBeLessThan(Config.Player.WalkSpeed)
	expect(Config.Krampus.CarrySpeed).toBeLessThan(Config.Krampus.WalkSpeed)
end)

test("Krampus fits through doors", function()
	expect(Config.Krampus.Height).toBeLessThan(Config.Map.DoorSize.Y)
end)

test("house weights only name real house types", function()
	for _, weights in Config.Houses.StopWeights do
		for typeName in weights do
			expect(Config.Houses.Types[typeName] ~= nil).toBeTruthy()
		end
	end
end)
