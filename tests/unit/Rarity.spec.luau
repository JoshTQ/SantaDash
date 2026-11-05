-- Present rarities: odds add up, luck only touches Rare and up, and Mythic
-- and Secret are never random (so never boosted or sold).
local Rarity = load("ReplicatedStorage.Shared.Rarity")
local PlayerDefaults = load("ReplicatedStorage.Shared.PlayerDefaults")

local function sum(odds)
	local total = 0
	for _, o in odds do
		total += o.percent
	end
	return total
end

test("odds add up to 100 at any luck", function()
	for _, luck in { nil, 1, 2, 3, 10 } do
		expect(sum(Rarity.odds(luck))).toBeNear(100, 0.0001)
	end
end)

test("the base weights match the design (60 / 25 / 10 / ~4 / under 1)", function()
	local odds = Rarity.odds()
	expect(odds[1].percent).toBeNear(60, 0.001)
	expect(odds[2].percent).toBeNear(25, 0.001)
	expect(odds[3].percent).toBeNear(10, 0.001)
	expect(odds[5].percent).toBeLessThan(1)
end)

test("luck raises Rare, Epic and Legendary and lowers Common", function()
	local base, lucky = Rarity.odds(1), Rarity.odds(3)
	expect(lucky[1].percent).toBeLessThan(base[1].percent)
	for i = 3, 5 do
		expect(lucky[i].percent).toBeGreaterThan(base[i].percent)
	end
end)

test("luck below 1 is treated as 1", function()
	expect(Rarity.odds(0.5)[1].percent).toBeNear(60, 0.001)
end)

test("Mythic and Secret are never in the odds or a roll, even with luck", function()
	for _, odd in Rarity.odds(100) do
		expect(Rarity.EarnedOnly[odd.name]).toBeNil()
	end
	local rng = Random.new(7)
	local seen = {}
	for _ = 1, 5000 do
		local r = Rarity.roll(rng, 50)
		expect(Rarity.EarnedOnly[r]).toBeNil()
		seen[r] = true
	end
	expect(seen.Legendary).toBe(true)
	expect(Rarity.EarnedOnly.Mythic and Rarity.EarnedOnly.Secret).toBe(true)
end)

test("format rounds for the store card", function()
	expect(Rarity.format(60)).toBe("60%")
	expect(Rarity.format(0.8)).toBe("0.8%")
	expect(Rarity.format(12.345)).toBe("12.3%")
	expect(Rarity.format(0.05)).toBe("<0.1%")
end)

test("player defaults: reconcile fills new fields and keeps saved ones", function()
	local old = { coal = 42, tutorial = { done = { Grab = true } } }
	PlayerDefaults.reconcile(old)
	expect(old.coal).toBe(42)
	expect(old.playSeconds).toBe(0)
	expect(old.tutorial.done.Grab).toBe(true)
	expect(old.tutorial.tipsOff).toBe(false)
	expect(type(old.receipts)).toBe("table")
	-- Empty default tables never overwrite saved contents.
	local saved = { owned = { TwoXLoot = true } }
	PlayerDefaults.reconcile(saved)
	expect(saved.owned.TwoXLoot).toBe(true)
end)
