-- Santa suits: who may wear what, refunds fall back to Classic, and every
-- paid suit is unlocked by a real store item.
local SkinRules = load("ReplicatedStorage.Shared.SkinRules")
local PlayerDefaults = load("ReplicatedStorage.Shared.PlayerDefaults")
local Config = load("ReplicatedStorage.Shared.Config")

describe("SkinRules", function()
	it("starts everyone in the free Classic suit", function()
		local data = PlayerDefaults.new()
		expect(data.skin).toBe("Classic")
		expect(SkinRules.current(data)).toBe("Classic")
		expect(SkinRules.owns(data.owned, "Classic")).toBe(true)
	end)

	it("only lets you wear a suit you've unlocked", function()
		local data = PlayerDefaults.new()
		local ok, why = SkinRules.equip(data, "SharkySuit")
		expect(ok).toBe(false)
		expect(why).toBe("locked")
		expect(data.skin).toBe("Classic")
		data.owned.SharkySuit = true
		expect((SkinRules.equip(data, "SharkySuit"))).toBe(true)
		expect(SkinRules.current(data)).toBe("SharkySuit")
	end)

	it("rejects unknown and non-string ids", function()
		local data = PlayerDefaults.new()
		expect(select(2, SkinRules.equip(data, "GoldSuit"))).toBe("unknown")
		expect(select(2, SkinRules.equip(data, 42))).toBe("unknown")
		expect(select(2, SkinRules.equip(data, nil))).toBe("unknown")
		expect(data.skin).toBe("Classic")
	end)

	it("falls back to Classic when a worn suit is refunded", function()
		local data = PlayerDefaults.new()
		data.owned.ChromeSuit = true
		SkinRules.equip(data, "ChromeSuit")
		data.owned.ChromeSuit = nil
		expect(SkinRules.current(data)).toBe("Classic")
		data.skin = "NotASuit" -- an old or tampered save
		expect(SkinRules.current(data)).toBe("Classic")
		expect(SkinRules.current(nil)).toBe("Classic")
	end)

	it("lists every suit with unlocked, equipped and how to get it", function()
		local data = PlayerDefaults.new()
		data.owned.HolidaySuit = true
		SkinRules.equip(data, "HolidaySuit")
		local rows = SkinRules.list(data)
		expect(#rows).toBe(#Config.Skins.List)
		local byId = {}
		for _, row in rows do
			byId[row.id] = row
		end
		expect(byId.HolidaySuit.equipped).toBe(true)
		expect(byId.Classic.equipped).toBe(false)
		expect(byId.Classic.unlocked).toBe(true)
		expect(byId.SharkySuit.unlocked).toBe(false)
		expect(byId.SharkySuit.howTo).never.toBeNil()
		expect(byId.HolidaySuit.howTo).toBeNil()
	end)

	it("buying the Holiday Bundle unlocks the Ugly Jumper", function()
		local StoreRules = load("ReplicatedStorage.Shared.StoreRules")
		local data = PlayerDefaults.new()
		for _, id in { "HolidayBundle", "ChristmasEveSuit", "SharkySuit", "ChromeSuit" } do
			StoreRules.grant(data, StoreRules.item(id))
		end
		for _, skin in Config.Skins.List do
			expect(SkinRules.owns(data.owned, skin.id)).toBe(true)
		end
	end)

	it("has a valid catalog: each paid suit has a model and a store item", function()
		expect(#SkinRules.validate(Config.Store.Items)).toBe(0)
		local problems = SkinRules.validate({})
		expect(#problems).toBe(4) -- the four paid suits lose their store items
	end)

	it("sells each single suit for 149 Robux", function()
		local StoreRules = load("ReplicatedStorage.Shared.StoreRules")
		for _, id in { "ChristmasEveSuit", "SharkySuit", "ChromeSuit" } do
			local item = StoreRules.item(id)
			expect(item.price).toBe(149)
			expect(item.once).toBe(true)
			expect(item.paidRandom).toBeNil()
		end
	end)
end)
