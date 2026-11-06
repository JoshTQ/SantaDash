-- Boots: bought once with Coal and kept, worn over any suit, faster on ice.
-- Robux styles are cosmetic only and need the Coal boots for the speed.
local BootRules = load("ReplicatedStorage.Shared.BootRules")
local PlayerDefaults = load("ReplicatedStorage.Shared.PlayerDefaults")
local CanalRules = load("ServerScriptService.Server.CanalRules")
local Config = load("ReplicatedStorage.Shared.Config")

local STYLE = {
	id = "TestStyle",
	name = "Test Style",
	model = "TestStyle",
	style = true,
	base = "SkateBoots",
	ready = true,
}

local function withReady(fn)
	local boot = BootRules.get("SkateBoots")
	local was = boot.ready
	boot.ready = true
	table.insert(Config.Boots.List, STYLE)
	local ok, err = pcall(fn)
	boot.ready = was
	table.remove(Config.Boots.List, table.find(Config.Boots.List, STYLE))
	if not ok then
		error(err, 0)
	end
end

describe("BootRules", function()
	it("hides boots that aren't ready, and never sells them", function()
		local boot = BootRules.get("SkateBoots")
		expect(boot).never.toBeNil()
		local was = boot.ready
		boot.ready = false
		local data = PlayerDefaults.new()
		data.coal = 99999
		expect(select(2, BootRules.buy(data, "SkateBoots"))).toBe("notReady")
		expect(#BootRules.list(data)).toBe(0)
		expect(data.coal).toBe(99999)
		boot.ready = was
	end)

	it("starts players with no boots", function()
		local data = PlayerDefaults.new()
		expect(data.boots).toBe("")
		expect(BootRules.current(data)).toBeNil()
		expect((BootRules.speeds(data))).toBeNil()
	end)

	it("sells boots for Coal only once, and puts the first pair on", function()
		withReady(function()
			local data = PlayerDefaults.new()
			local price = BootRules.get("SkateBoots").coal
			data.coal = price - 1
			expect(select(2, BootRules.buy(data, "SkateBoots"))).toBe("coal")
			expect(data.coal).toBe(price - 1)
			data.coal = price + 10
			expect((BootRules.buy(data, "SkateBoots"))).toBe(true)
			expect(data.coal).toBe(10)
			expect(data.owned.SkateBoots).toBe(true)
			expect(data.boots).toBe("SkateBoots")
			data.coal = 99999
			expect(select(2, BootRules.buy(data, "SkateBoots"))).toBe("owned")
			expect(data.coal).toBe(99999)
		end)
	end)

	it("never sells a Robux style for Coal, and rejects nonsense ids", function()
		withReady(function()
			local data = PlayerDefaults.new()
			data.coal = 99999
			expect(select(2, BootRules.buy(data, "TestStyle"))).toBe("notForCoal")
			expect(select(2, BootRules.buy(data, "GoldBoots"))).toBe("unknown")
			expect(select(2, BootRules.buy(data, 7))).toBe("unknown")
			expect(data.coal).toBe(99999)
		end)
	end)

	it("wears only owned boots, and can take them off", function()
		withReady(function()
			local data = PlayerDefaults.new()
			expect(select(2, BootRules.equip(data, "SkateBoots"))).toBe("locked")
			expect(select(2, BootRules.equip(data, "Nope"))).toBe("unknown")
			data.owned.SkateBoots = true
			expect((BootRules.equip(data, "SkateBoots"))).toBe(true)
			expect(BootRules.current(data).id).toBe("SkateBoots")
			expect((BootRules.equip(data, ""))).toBe(true)
			expect(BootRules.current(data)).toBeNil()
			data.boots = "SkateBoots"
			data.owned.SkateBoots = nil -- refunded or tampered save
			expect(BootRules.current(data)).toBeNil()
		end)
	end)

	it("gives the boots' ice speeds, and a style only with its base boots", function()
		withReady(function()
			local data = PlayerDefaults.new()
			local base = BootRules.get("SkateBoots")
			data.owned.TestStyle = true
			BootRules.equip(data, "TestStyle")
			expect((BootRules.speeds(data))).toBeNil() -- cosmetic only, no pay-to-win
			data.owned.SkateBoots = true
			local skate, hoop = BootRules.speeds(data)
			expect(skate).toBe(base.skateSpeed)
			expect(hoop).toBe(base.hoopSpeed)
		end)
	end)

	it("lists ready boots with price, owned and wearing", function()
		withReady(function()
			local data = PlayerDefaults.new()
			data.coal = 2000
			local rows = BootRules.list(data)
			expect(#rows).toBe(2)
			expect(rows[1].id).toBe("SkateBoots")
			expect(rows[1].canAfford).toBe(true)
			expect(rows[1].owned).toBe(false)
			expect(rows[2].coal).toBeNil() -- a style has no Coal price
			BootRules.buy(data, "SkateBoots")
			rows = BootRules.list(data)
			expect(rows[1].owned).toBe(true)
			expect(rows[1].wearing).toBe(true)
		end)
	end)

	it("makes boots faster than plain skating, and never slower", function()
		local C = Config.Canal
		local boot = BootRules.get("SkateBoots")
		expect(boot.skateSpeed > C.SkateSpeed).toBe(true)
		expect(boot.hoopSpeed > C.HoopSpeed).toBe(true)
		expect(CanalRules.walkSpeed(16, true, false, boot.skateSpeed, boot.hoopSpeed)).toBe(boot.skateSpeed)
		expect(CanalRules.walkSpeed(16, true, true, boot.skateSpeed, boot.hoopSpeed)).toBe(boot.hoopSpeed)
		expect(CanalRules.walkSpeed(16, false, false, boot.skateSpeed, boot.hoopSpeed)).toBe(16)
		expect(CanalRules.walkSpeed(16, true, false, 5, 5)).toBe(C.SkateSpeed)
		expect(CanalRules.walkSpeed(16, true, false)).toBe(C.SkateSpeed)
	end)
end)
