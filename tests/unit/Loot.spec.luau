local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")

local function countTypes(list)
	local counts = { Cosy = 0, Normal = 0, Risky = 0 }
	for _, t in list do
		counts[t] += 1
	end
	return counts
end

test("Stop 1 never rolls a Risky house", function()
	local rng = Random.new(1)
	for _ = 1, 500 do
		expect(countTypes(Loot.rollStreet(rng, 1, 6)).Risky).toBe(0)
	end
end)

test("every street has at least one Cosy house", function()
	local rng = Random.new(2)
	for stop = 1, 3 do
		for _ = 1, 500 do
			expect(countTypes(Loot.rollStreet(rng, stop, 3)).Cosy >= 1).toBeTruthy()
		end
	end
end)

test("later stops can roll Risky houses", function()
	local rng = Random.new(3)
	local risky = 0
	for _ = 1, 500 do
		risky += countTypes(Loot.rollStreet(rng, 2, 6)).Risky
	end
	expect(risky).toBeGreaterThan(0)
end)

test("present value follows the size-squared rule", function()
	expect(Loot.presentValue(2, 1, 0)).toBe(4 * Loot.presentValue(1, 1, 0))
end)

test("each threat adds 25% loot and the ring multiplies it", function()
	expect(Loot.presentValue(1, 1, 2)).toBe(15)
	expect(Loot.presentValue(1, 2.5, 0)).toBe(25)
end)

test("rollSize only returns configured sizes", function()
	local rng = Random.new(4)
	local allowed = {}
	for _, entry in Config.Presents.Sizes do
		allowed[entry[1]] = true
	end
	for _ = 1, 300 do
		expect(allowed[Loot.rollSize(rng)]).toBeTruthy()
	end
end)

test("street stop plan: landing house first, vault at the end", function()
	local plan = Loot.planStop(Random.new(5), 1)
	expect(plan.kindName).toBe("Street")
	expect(plan.houses[1].isLanding).toBeTruthy()
	expect(plan.houses[1].ring).toBe("Near")
	local vault = plan.houses[#plan.houses]
	expect(vault.typeName).toBe("Vault")
	expect(vault.locked).toBeTruthy()
	expect(vault.chimney).toBeFalsy() -- no sneaking round the paid door
	expect(vault.hideSpots).toBe(0)
	expect(#vault.presents).toBe(Config.Houses.Types.Vault.Presents)
	expect(plan.escapeMultiplier).toBe(nil)
end)

test("finale plan: the Lair holds exactly one Naughty List and escaping doubles", function()
	local plan = Loot.planStop(Random.new(6), #Config.Run.StopKinds)
	expect(plan.kindName).toBe("Finale")
	expect(plan.escapeMultiplier).toBe(2)
	local lair = plan.houses[#plan.houses]
	expect(lair.typeName).toBe("Lair")
	local lists = 0
	for _, present in lair.presents do
		if present.naughtyList then
			lists += 1
		end
	end
	expect(lists).toBe(1)
end)

test("Risky houses get an extra present", function()
	local rng = Random.new(7)
	for _ = 1, 50 do
		local plan = Loot.planStop(rng, 2)
		for _, house in plan.houses do
			if house.typeName == "Risky" then
				expect(#house.presents).toBe(Config.Houses.PresentsPerHouse[house.ring] + 1)
			end
		end
	end
end)

test("grab fills the sack and pays Jingle until the sack is full", function()
	local st = Loot.newPlayerState()
	local present = { size = 1, value = 10, ringMultiplier = 2.5, threats = 0 }
	for _ = 1, Config.Sack.Capacity do
		expect(Loot.grab(st, present)).toBeTruthy()
	end
	expect(Loot.grab(st, present)).toBeFalsy()
	expect(st.sackCount).toBe(Config.Sack.Capacity)
	expect(st.sackValue).toBe(10 * Config.Sack.Capacity)
	expect(st.jingle).toBe(Config.Jingle.Start + Config.Sack.Capacity * Loot.jingleForGrab(2.5))
end)

test("banking empties the sack; escaping the finale doubles loot", function()
	local st = Loot.newPlayerState()
	Loot.grab(st, { size = 1, value = 40, ringMultiplier = 1, threats = 0 })
	Loot.bank(st, nil)
	expect(st.sackCount).toBe(0)
	expect(st.banked).toBe(40)
	expect(Loot.finalLoot(st)).toBe(40)
	Loot.grab(st, { size = 1, value = 10, ringMultiplier = 1, threats = 0 })
	Loot.bank(st, 2)
	expect(Loot.finalLoot(st)).toBe(100)
end)

test("missing the final sleigh keeps banked loot and half the sack, with no escape bonus", function()
	local st = Loot.newPlayerState()
	Loot.grab(st, { size = 1, value = 40, ringMultiplier = 1, threats = 0 })
	Loot.bank(st, nil)
	Loot.grab(st, { size = 1, value = 100, ringMultiplier = 1, threats = 0 })
	Loot.bankMissed(st)
	expect(st.sackCount).toBe(0)
	expect(Loot.finalLoot(st)).toBe(40 + 50)
	expect(Loot.results({ { "Ann", st } })[1].escaped).toBeFalsy()
end)

test("results rank the best thief first and convert loot to Coal", function()
	local a, b = Loot.newPlayerState(), Loot.newPlayerState()
	a.banked, b.banked = 50, 80
	Loot.bank(b, 2)
	local rows = Loot.results({ { "Ann", a }, { "Bo", b } })
	expect(rows[1].name).toBe("Bo")
	expect(rows[1].loot).toBe(160)
	expect(rows[1].escaped).toBeTruthy()
	expect(rows[2].escaped).toBeFalsy()
	expect(rows[1].coal).toBe(math.floor(160 * Config.Coal.PerLootValue))
end)

test("solo runs with elf bots pay the solo share of the loot", function()
	local st = Loot.newPlayerState()
	expect(st.lootMultiplier).toBe(1)
	st.lootMultiplier = Config.ElfBots.SoloLootMultiplier
	Loot.grab(st, { size = 1, value = 100, ringMultiplier = 1, threats = 0 })
	Loot.bank(st, 2)
	expect(Loot.finalLoot(st)).toBe(math.floor(200 * Config.ElfBots.SoloLootMultiplier))
end)

test("stops are planned from the map's own street slots", function()
	local slots = {
		{ Ring = "Near", Side = 1, Extra = 0 },
		{ Ring = "Near", Side = -1, Extra = 0 },
		{ Ring = "Near", Side = 1, Extra = 0 },
		{ Ring = "Near", Side = -1, Extra = 0 },
		{ Ring = "Far", Side = 1, Extra = 25 },
		{ Ring = "Far", Side = -1, Extra = 25 },
	}
	local plan = Loot.planStop(Random.new(9), 1, slots)
	expect(plan.houses[1].side).toBe(1)
	expect(plan.houses[2].distance).toBe(Config.Rings.Far.Distance + 25)
	expect(plan.houses[#plan.houses].side).toBe(0) -- the vault still closes the street
end)

test("grab noise rises each stop and with every threat in the house", function()
	local N = Config.Noise
	expect(Loot.noiseForGrab(1, 0)).toBe(N.PerGrab)
	expect(Loot.noiseForGrab(2, 0)).toBeGreaterThan(Loot.noiseForGrab(1, 0))
	expect(Loot.noiseForGrab(3, 0)).toBeGreaterThan(Loot.noiseForGrab(2, 0))
	expect(Loot.noiseForGrab(1, 2)).toBeNear(N.PerGrab * (1 + 2 * N.PerThreatMultiplier))
	-- Stops past the table fall back to x1 instead of erroring.
	expect(Loot.noiseForGrab(99, 0)).toBe(N.PerGrab)
end)
