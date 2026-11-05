-- The store's compliance rules (Config.Store, shared/StoreRules.luau):
-- no prompts in the first 3 minutes, odds + PolicyService for paid random
-- items, never Jingle / Mythic / Secret for Robux, holiday dates.
local Config = load("ReplicatedStorage.Shared.Config")
local PlayerDefaults = load("ReplicatedStorage.Shared.PlayerDefaults")
local StoreRules = load("ReplicatedStorage.Shared.StoreRules")

local DEC_10 = StoreRules.day("2026-12-10") + 3600

local function ctx(overrides)
	local c = {
		now = DEC_10,
		playSeconds = 600,
		owned = {},
		paidRandomRestricted = false,
		runServer = true,
		saving = true,
	}
	for k, v in overrides or {} do
		c[k] = v
	end
	return c
end

local function with(base, overrides)
	local item = table.clone(base)
	for k, v in overrides do
		item[k] = v
	end
	return item
end

describe("catalog", function()
	test("the shipped catalog passes every compliance check", function()
		expect(#StoreRules.validate(Config.Store.Items)).toBe(0)
	end)

	test("Jingle can never be sold", function()
		local bad = { id = "X", kind = "Product", price = 10, assetId = 0, grants = { jingle = 500 } }
		expect(#StoreRules.validate({ bad })).toBe(1)
		local alsoBad = { id = "Y", kind = "Product", price = 10, assetId = 0, grants = { Jingle = 5 } }
		expect(#StoreRules.validate({ alsoBad })).toBe(1)
	end)

	test("Mythic and Secret presents can never be sold", function()
		for _, id in { "Mythic", "Secret", "mythic" } do
			local bad =
				{ id = "X", kind = "Product", price = 10, assetId = 0, grants = { inventory = { [id] = 1 } } }
			expect(#StoreRules.validate({ bad })).toBeGreaterThan(0)
		end
	end)

	test("a paid random item without a luck value (so no odds) is rejected", function()
		local bad = { id = "X", kind = "Product", price = 10, assetId = 0, paidRandom = true, grants = {} }
		expect(#StoreRules.validate({ bad })).toBe(1)
	end)

	test("catches duplicate ids, missing prices, unknown grants and bad kinds", function()
		local a = { id = "A", kind = "Product", price = 10, assetId = 0, grants = {} }
		expect(#StoreRules.validate({ a, a })).toBe(1)
		expect(#StoreRules.validate({ with(a, { price = 0 }) })).toBe(1)
		expect(#StoreRules.validate({ with(a, { grants = { robux = 1 } }) })).toBe(1)
		expect(#StoreRules.validate({ with(a, { kind = "Box" }) })).toBe(1)
		expect(#StoreRules.validate({ with(a, { kind = "Pass", grants = { inventory = { X = 1 } } }) })).toBe(
			1
		)
		expect(#StoreRules.validate({ with(a, { assetId = "123" }) })).toBe(1)
	end)

	test("every paid random item in the catalog shows odds", function()
		for _, item in Config.Store.Items do
			if item.paidRandom then
				expect(StoreRules.oddsFor(item) ~= nil).toBeTruthy()
			end
		end
	end)

	test("Lucky Sack odds list base and boosted chances for every random rarity", function()
		local rows = StoreRules.oddsFor(StoreRules.item("LuckySack"))
		expect(#rows).toBe(5)
		expect(rows[1].name).toBe("Common")
		expect(rows[5].name).toBe("Legendary")
		expect(rows[5].base).toBe("0.8%")
		expect(rows[5].boosted ~= rows[5].base).toBeTruthy()
		expect(StoreRules.oddsFor(StoreRules.item("TwoXLoot"))).toBeNil()
	end)

	test("item lookups", function()
		expect(StoreRules.item("TwoXLoot").price).toBe(149)
		expect(StoreRules.item("Nope")).toBeNil()
		expect(StoreRules.itemByAsset("Product", 0)).toBeNil()
	end)
end)

describe("3-minute rule", function()
	test("nothing is listed or prompted before 3 minutes of play, not even the Starter Sack", function()
		for _, item in Config.Store.Items do
			local early = ctx({ playSeconds = Config.Store.NoPromptSeconds - 1 })
			expect((StoreRules.visible(item, early))).toBe(false)
			expect((StoreRules.canPrompt(with(item, { assetId = 1 }), early))).toBe(false)
		end
	end)

	test("ready items appear at 3 minutes", function()
		local ok, reason = StoreRules.visible(StoreRules.item("StarterSack"), ctx({ playSeconds = 180 }))
		expect(ok).toBe(true)
		expect(reason).toBeNil()
		local _, early = StoreRules.visible(StoreRules.item("StarterSack"), ctx({ playSeconds = 10 }))
		expect(early).toBe("tooSoon")
	end)

	test("the limit is 3 minutes", function()
		expect(Config.Store.NoPromptSeconds).toBe(180)
	end)
end)

describe("PolicyService", function()
	test("paid random items are hidden from restricted players", function()
		local lucky = with(StoreRules.item("LuckySack"), { ready = true, assetId = 5 })
		local ok, reason = StoreRules.visible(lucky, ctx({ paidRandomRestricted = true }))
		expect(ok).toBe(false)
		expect(reason).toBe("restricted")
		expect((StoreRules.canPrompt(lucky, ctx({ paidRandomRestricted = true })))).toBe(false)
		expect((StoreRules.canPrompt(lucky, ctx()))).toBe(true)
	end)

	test("other items are unaffected by the restriction", function()
		local pass = with(StoreRules.item("TwoXLoot"), { assetId = 5 })
		expect((StoreRules.canPrompt(pass, ctx({ paidRandomRestricted = true })))).toBe(true)
	end)
end)

describe("canPrompt", function()
	test("refuses items not built yet, not created, unsaved, owned or on the wrong server", function()
		local function reason(item, c)
			local _, r = StoreRules.canPrompt(item, c or ctx())
			return r
		end
		expect(reason(nil)).toBe("unknown")
		expect(reason(StoreRules.item("NaughtyPass"))).toBe("notReady")
		expect(reason(StoreRules.item("TwoXLoot"))).toBe("notCreated")
		local pass = with(StoreRules.item("TwoXLoot"), { assetId = 9 })
		expect(reason(pass, ctx({ saving = false }))).toBe("notSaving")
		expect(reason(pass, ctx({ owned = { TwoXLoot = true } }))).toBe("owned")
		local blessing = with(StoreRules.item("SantasBlessing"), { assetId = 9 })
		expect(reason(blessing, ctx({ runServer = false }))).toBe("runServerOnly")
		expect(reason(blessing)).toBeNil()
		local starter = with(StoreRules.item("StarterSack"), { assetId = 9 })
		expect(reason(starter, ctx({ owned = { StarterSack = true } }))).toBe("owned")
	end)

	test("consumables can be bought again", function()
		local breakout = with(StoreRules.item("InstantBreakout"), { assetId = 9 })
		expect((StoreRules.canPrompt(breakout, ctx({ owned = { InstantBreakout = true } })))).toBe(true)
	end)
end)

describe("holiday dates", function()
	test("day() is midnight UTC", function()
		expect(StoreRules.day("2026-12-06")).toBe(1796515200)
		expect(StoreRules.day("2027-01-06")).toBe(1799193600)
		expect(StoreRules.day("2000-02-29")).toBe(951782400)
		expect(function()
			StoreRules.day("6 Dec")
		end).toThrow()
	end)

	test("the holiday bundle is on sale Dec 6 to Jan 5 inclusive", function()
		local bundle = StoreRules.item("HolidayBundle")
		expect(StoreRules.onSale(bundle, StoreRules.day("2026-12-06") - 1)).toBe(false)
		expect(StoreRules.onSale(bundle, StoreRules.day("2026-12-06"))).toBe(true)
		expect(StoreRules.onSale(bundle, StoreRules.day("2027-01-05") + 86399)).toBe(true)
		expect(StoreRules.onSale(bundle, StoreRules.day("2027-01-06"))).toBe(false)
	end)

	test("holiday items are live by Dec 20 and the shop closes Jan 5", function()
		local allBy = StoreRules.day(Config.Store.HolidayAllBy)
		for _, item in Config.Store.Items do
			if item.from then
				expect(StoreRules.day(item.from) <= allBy).toBeTruthy()
				expect(StoreRules.day(item.from) >= StoreRules.day(Config.Store.HolidayFrom)).toBeTruthy()
				expect(item.to).toBe(Config.Store.HolidayTo)
			end
		end
	end)

	test("IgnoreDates shows dated items any day (Staging testing)", function()
		local bundle = StoreRules.item("HolidayBundle")
		Config.Store.IgnoreDates = true
		local ok = StoreRules.onSale(bundle, StoreRules.day("2026-11-05"))
		Config.Store.IgnoreDates = false
		expect(ok).toBe(true)
		expect(StoreRules.onSale(bundle, StoreRules.day("2026-11-05"))).toBe(false)
	end)
end)

describe("grants", function()
	test("Starter Sack gives Coal and Break-outs once", function()
		local data = PlayerDefaults.new()
		local live = StoreRules.grant(data, StoreRules.item("StarterSack"))
		expect(data.coal).toBe(1000)
		expect(data.inventory.InstantBreakout).toBe(2)
		expect(data.owned.StarterSack).toBe(true)
		expect(live.blessing).toBe(false)
	end)

	test("revoke undoes a grant exactly", function()
		for _, item in Config.Store.Items do
			local data = PlayerDefaults.new()
			local before = PlayerDefaults.new()
			StoreRules.grant(data, item)
			StoreRules.revoke(data, item)
			expect(data.coal).toBe(before.coal)
			for id, count in data.inventory do
				expect(count).toBe(0)
				expect(id ~= nil).toBeTruthy()
			end
			expect(next(data.owned)).toBeNil()
		end
	end)

	test("passes mark ownership; Blessing asks for a live effect", function()
		local data = PlayerDefaults.new()
		StoreRules.grant(data, StoreRules.item("TwoXLoot"))
		expect(data.owned.TwoXLoot).toBe(true)
		expect(StoreRules.grant(data, StoreRules.item("SantasBlessing")).blessing).toBe(true)
		StoreRules.grant(data, StoreRules.item("HolidayBundle"))
		expect(data.owned.HolidaySuit).toBe(true)
	end)

	test("consume takes one and refuses at zero", function()
		local data = PlayerDefaults.new()
		expect(StoreRules.consume(data, "InstantBreakout")).toBe(false)
		StoreRules.grant(data, StoreRules.item("InstantBreakout"))
		expect(StoreRules.consume(data, "InstantBreakout")).toBe(true)
		expect(StoreRules.consume(data, "InstantBreakout")).toBe(false)
	end)

	test("a receipt is granted once, and the ledger is capped", function()
		local data = PlayerDefaults.new()
		expect(StoreRules.recordReceipt(data, "r1")).toBe(true)
		expect(StoreRules.recordReceipt(data, "r1")).toBe(false)
		for i = 2, 60 do
			StoreRules.recordReceipt(data, "r" .. i, 50)
		end
		expect(#data.receipts).toBe(50)
		expect(data.receipts[1]).toBe("r11")
	end)
end)

describe("perks", function()
	test("Bigger Sack tiers multiply the sack; the best tier wins", function()
		local base = Config.Sack.Capacity
		expect(StoreRules.sackCapacity({})).toBe(base)
		expect(StoreRules.sackCapacity({ BiggerSack2 = true })).toBe(base * 2)
		expect(StoreRules.sackCapacity({ BiggerSack2 = true, BiggerSack5 = true })).toBe(base * 5)
		expect(StoreRules.sackCapacity({ BiggerSack3 = true })).toBe(base * 3)
	end)

	test("2X Loot and Santa's Blessing stack", function()
		expect(StoreRules.coalMultiplier({})).toBe(1)
		expect(StoreRules.coalMultiplier({ TwoXLoot = true })).toBe(2)
		expect(StoreRules.coalMultiplier({}, true)).toBe(2)
		expect(StoreRules.coalMultiplier({ TwoXLoot = true }, true)).toBe(4)
	end)
end)
