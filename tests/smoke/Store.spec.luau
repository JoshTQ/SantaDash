--[[
	Saved player data and the Robux store on the real server (Main) in a
	headless world, with stand-ins for DataStoreService, MarketplaceService
	and PolicyService: session locks, receipts granted exactly once and only
	once saved, the 3-minute rule, PolicyService, Santa's Blessing, and the
	perks inside a run (Bigger Sack, 2X Loot, Instant Break-out).
]]

local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 120)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

-- An in-memory DataStore: UpdateAsync only (all PlayerData uses).
local function fakeDataStore()
	local ds = { saved = {}, fail = false, writes = 0 }
	function ds.UpdateAsync(_, key, fn)
		if ds.fail then
			error("DataStore request was rejected")
		end
		local new = fn(deepCopy(ds.saved[key]))
		if new ~= nil then
			ds.saved[key] = deepCopy(new)
			ds.writes += 1
		end
		return new
	end
	return ds
end

local IDS = {
	StarterSack = 201,
	InstantBreakout = 202,
	SantasBlessing = 203,
	LuckySack = 204,
	TwoXLoot = 101,
	BiggerSack2 = 102,
	FastSneak = 103,
	SharkySuit = 205,
}

-- options: { storeFails, policy = table | false (lookup errors), ownsPass, saved, before(Config) }
local function boot(options: any?)
	local opts = options or {}
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
	for _, item in Config.Store.Items do
		item.assetId = IDS[item.id] or item.assetId
	end
	if opts.before then
		opts.before(Config)
	end

	local ds = fakeDataStore()
	ds.fail = opts.storeFails == true
	for key, value in opts.saved or {} do
		ds.saved[key] = value
	end
	engine:service("DataStoreService").GetDataStore = function()
		return ds
	end

	local market = engine:service("MarketplaceService")
	local prompts = {}
	market.PromptProductPurchase = function(_, player, id)
		table.insert(prompts, { player = player, kind = "Product", id = id })
	end
	market.PromptGamePassPurchase = function(_, player, id)
		table.insert(prompts, { player = player, kind = "Pass", id = id })
	end
	market.UserOwnsGamePassAsync = function(_, _userId, id)
		return opts.ownsPass ~= nil and opts.ownsPass[id] == true
	end
	engine:service("PolicyService").GetPolicyInfoForPlayerAsync = function()
		if opts.policy == false then
			error("policy lookup failed")
		end
		return opts.policy or { ArePaidRandomItemsRestricted = false }
	end

	local me = engine:addPlayer("Me", { userId = 77 })
	engine:setLocalPlayer(me)
	world.run(function()
		world.runScript("ServerScriptService.Server.Main")
		world.wait(1)
	end)
	local mods = {
		Config = Config,
		PlayerData = world.load("ServerScriptService.Server.PlayerData"),
		Store = world.load("ServerScriptService.Server.Store"),
		Remotes = world.load("ReplicatedStorage.Shared.Remotes"),
	}
	return world, engine, me, mods, ds, prompts, market
end

local function storeMessages(engine, player, kind)
	local out = {}
	for _, entry in engine.clientLog[player] or {} do
		if entry.remote == "Store" and entry.args[1] == kind then
			table.insert(out, entry.args[2])
		end
	end
	return out
end

local function lastCatalog(engine, player)
	local list = storeMessages(engine, player, "Catalog")
	return list[#list]
end

local function receipt(player, productId, purchaseId)
	return { PlayerId = player.UserId, ProductId = productId, PurchaseId = purchaseId, CurrencySpent = 0 }
end

local function playFor(mods, player, seconds)
	mods.PlayerData.update(player, function(d)
		d.playSeconds = seconds
	end)
end

local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet

describe("saved player data", function()
	it("loads defaults, holds a session lock, saves and unlocks on leaving", function()
		local world, engine, me, mods, ds = boot()
		world.run(function()
			local data = mods.PlayerData.waitFor(me, 5)
			expect(data).never.toBeNil()
			expect(data.coal).toBe(0)
			expect(data.tutorial.tipsOff).toBe(false)
			expect(mods.PlayerData.isPersistent(me)).toBe(true)
			expect(ds.saved.p_77.lock.jobId).toBe("headless")

			mods.PlayerData.update(me, function(d)
				d.coal = 123
			end)
			expect(mods.PlayerData.saveNow(me)).toBe(true)
			expect(ds.saved.p_77.data.coal).toBe(123)

			engine:removePlayer(me)
			world.wait(0.5)
			expect(ds.saved.p_77.lock).toBeNil()
			expect(ds.saved.p_77.data.coal).toBe(123)
		end)
	end)

	it("counts time played and keeps it across saves", function()
		local world, _, me, mods, ds = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			world.wait(30)
			expect(mods.PlayerData.get(me).playSeconds >= 29).toBeTruthy()
			mods.PlayerData.saveNow(me)
			expect(ds.saved.p_77.data.playSeconds >= 29).toBeTruthy()
		end)
	end)

	it("fills new fields into an older save and keeps its values", function()
		local world, _, me, mods = boot({ saved = { p_77 = { data = { coal = 900, playSeconds = 400 } } } })
		world.run(function()
			local data = mods.PlayerData.waitFor(me, 5)
			expect(data.coal).toBe(900)
			expect(data.playSeconds >= 400).toBeTruthy()
			expect(type(data.inventory)).toBe("table")
			expect(type(data.tutorial.done)).toBe("table")
		end)
	end)

	it("waits for another server's fresh lock, then takes over a stuck one", function()
		local saved = { p_77 = { data = { coal = 5 }, lock = { jobId = "other", time = 1_700_000_000 } } }
		local world, _, me, mods, ds = boot({ saved = saved })
		world.run(function()
			-- Not loaded straight away: the other server still holds it.
			expect(mods.PlayerData.get(me)).toBeNil()
			local data = mods.PlayerData.waitFor(me, 30)
			expect(data.coal).toBe(5)
			expect(ds.saved.p_77.lock.jobId).toBe("headless")
		end)
	end)

	it("never overwrites data after another server took the lock", function()
		local world, _, me, mods, ds = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			ds.saved.p_77.lock = { jobId = "other", time = 1_700_000_000 }
			ds.saved.p_77.data.coal = 999
			expect(mods.PlayerData.saveNow(me)).toBe(false)
			expect(ds.saved.p_77.data.coal).toBe(999)
			expect(mods.PlayerData.isPersistent(me)).toBe(false)
		end)
	end)

	it("a DataStore outage gives fresh defaults, saves nothing and closes the shop", function()
		local world, engine, me, mods, ds, prompts = boot({ storeFails = true })
		world.run(function()
			local data = mods.PlayerData.waitFor(me, 30)
			expect(data).never.toBeNil()
			expect(data.tutorial.tipsOff).toBe(false)
			expect(mods.PlayerData.isPersistent(me)).toBe(false)
			expect(mods.PlayerData.saveNow(me)).toBe(false)
			playFor(mods, me, 600)
			local ok, reason = mods.Store.prompt(me, "InstantBreakout")
			expect(ok).toBe(false)
			expect(reason).toBe("notSaving")
			expect(#prompts).toBe(0)
			expect(mods.Store.processReceipt(receipt(me, IDS.InstantBreakout, "p1"))).toBe(NotYet)
			expect(ds.writes).toBe(0)
			expect(#storeMessages(engine, me, "Notice")).toBe(1)
		end)
	end)
end)

describe("the store", function()
	it("prompts nothing in the first 3 minutes, then prompts from the server", function()
		local world, engine, me, mods, _, prompts = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			local store = mods.Remotes.get("Store")
			store:FireServer("Buy", "StarterSack")
			store:FireServer("Buy", "TwoXLoot")
			world.wait(0.1)
			expect(#prompts).toBe(0)
			expect(#storeMessages(engine, me, "Notice")).toBe(2)
			store:FireServer("Open")
			world.wait(0.1)
			local early = lastCatalog(engine, me)
			expect(#early.items).toBe(0)
			expect(early.opensIn > 0).toBeTruthy()

			world.wait(181) -- real play time, not a shortcut
			store:FireServer("Open")
			world.wait(0.1)
			local open = lastCatalog(engine, me)
			expect(open.opensIn).toBe(0)
			expect(#open.items > 0).toBeTruthy()
			store:FireServer("Buy", "StarterSack")
			store:FireServer("Buy", "TwoXLoot")
			store:FireServer("Buy", 42) -- junk from a modified client is ignored
			world.wait(0.1)
			expect(#prompts).toBe(2)
			expect(prompts[1].kind).toBe("Product")
			expect(prompts[1].id).toBe(IDS.StarterSack)
			expect(prompts[2].kind).toBe("Pass")
			expect(prompts[2].id).toBe(IDS.TwoXLoot)
		end)
	end)

	it("never lists items that aren't built yet or created on the dashboard", function()
		local world, engine, me, mods = boot({
			before = function(Config)
				for _, item in Config.Store.Items do
					if item.id == "FastSneak" then
						item.assetId = 0
					end
				end
			end,
		})
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			playFor(mods, me, 600)
			mods.Store.sendCatalog(me)
			local ids = {}
			for _, item in lastCatalog(engine, me).items do
				ids[item.id] = item
			end
			expect(ids.NaughtyPass).toBeNil()
			expect(ids.LuckySack).toBeNil() -- not ready until rarities exist
			expect(ids.HolidayBundle).toBeNil() -- art not approved, and not December
			expect(ids.FastSneak.buyable).toBe(false) -- listed as "Soon"
			expect(ids.TwoXLoot.buyable).toBe(true)
		end)
	end)

	it("grants a product once per purchase, only after it is saved", function()
		local world, _, me, mods, ds = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			expect(mods.Store.processReceipt(receipt(me, IDS.StarterSack, "a1"))).toBe(Granted)
			expect(ds.saved.p_77.data.coal).toBe(1000)
			expect(ds.saved.p_77.data.inventory.InstantBreakout).toBe(2)
			-- Roblox retries the same receipt: no double grant.
			expect(mods.Store.processReceipt(receipt(me, IDS.StarterSack, "a1"))).toBe(Granted)
			expect(mods.PlayerData.get(me).coal).toBe(1000)
			-- A different purchase of a consumable stacks.
			expect(mods.Store.processReceipt(receipt(me, IDS.InstantBreakout, "a2"))).toBe(Granted)
			expect(mods.PlayerData.get(me).inventory.InstantBreakout).toBe(3)
		end)
	end)

	it("rolls back and asks Roblox to retry when the save fails", function()
		local world, _, me, mods, ds = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			ds.fail = true
			expect(mods.Store.processReceipt(receipt(me, IDS.StarterSack, "b1"))).toBe(NotYet)
			local data = mods.PlayerData.get(me)
			expect(data.coal).toBe(0)
			expect(data.owned.StarterSack).toBeNil()
			expect(#data.receipts).toBe(0)
		end)
	end)

	it("leaves unknown products and absent players for a retry", function()
		local world, _, me, mods = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			expect(mods.Store.processReceipt(receipt(me, 999999, "c1"))).toBe(NotYet)
			expect(
				mods.Store.processReceipt({ PlayerId = 5, ProductId = IDS.StarterSack, PurchaseId = "c2" })
			).toBe(NotYet)
		end)
	end)

	it("Santa's Blessing doubles everyone's Coal for 10 minutes and names the buyer", function()
		local world, engine, me, mods = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			expect(mods.Store.creditRun(me, 100)).toBe(100)
			expect(mods.Store.processReceipt(receipt(me, IDS.SantasBlessing, "d1"))).toBe(Granted)
			expect(mods.Store.isBlessed()).toBe(true)
			expect(mods.Store.blessing().by).toBe("Me")
			local banners = engine:hudMessages(me, "Banner")
			expect(string.find(banners[#banners].data.text, "Santa's Blessing", 1, true) ~= nil).toBeTruthy()
			expect(mods.Store.creditRun(me, 100)).toBe(200)
			expect(mods.PlayerData.get(me).coal).toBe(300)
			world.wait(601)
			expect(mods.Store.isBlessed()).toBe(false)
			expect(mods.Store.creditRun(me, 100)).toBe(100)
		end)
	end)

	it("game passes bought anywhere count, and an in-game pass purchase is granted", function()
		local world, _, me, mods = boot({ ownsPass = { [IDS.TwoXLoot] = true } })
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			world.wait(0.5)
			expect(mods.Store.owned(me).TwoXLoot).toBe(true)
			expect(mods.Store.creditRun(me, 50)).toBe(100)
			local market = world.engine:service("MarketplaceService")
			market.PromptGamePassPurchaseFinished:Fire(me, IDS.FastSneak, true)
			world.wait(0.1)
			expect(mods.Store.owned(me).FastSneak).toBe(true)
			market.PromptGamePassPurchaseFinished:Fire(me, IDS.BiggerSack2, false)
			world.wait(0.1)
			expect(mods.Store.owned(me).BiggerSack2).toBeNil()
		end)
	end)
end)

describe("Santa suits", function()
	local function suits(engine, me)
		local byId = {}
		for _, row in lastCatalog(engine, me).skins do
			byId[row.id] = row
		end
		return byId
	end

	it("wears only unlocked suits, from the first minute, and saves the choice", function()
		local world, engine, me, mods, ds = boot({
			before = function(Config)
				for _, item in Config.Store.Items do
					if item.id == "SharkySuit" then
						item.ready = true
					end
				end
			end,
		})
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			local store = mods.Remotes.get("Store")
			store:FireServer("Open")
			world.wait(0.1)
			local before = suits(engine, me)
			expect(before.Classic.equipped).toBe(true)
			expect(before.SharkySuit.unlocked).toBe(false)

			-- A modified client can't wear a locked suit.
			store:FireServer("Equip", "SharkySuit")
			store:FireServer("Equip", { "junk" })
			world.wait(0.1)
			expect(mods.PlayerData.get(me).skin).toBe("Classic")

			expect(mods.Store.processReceipt(receipt(me, IDS.SharkySuit, "s1"))).toBe(Granted)
			expect(suits(engine, me).SharkySuit.unlocked).toBe(true)
			store:FireServer("Equip", "SharkySuit") -- inside the first 3 minutes: not a purchase
			world.wait(0.1)
			local after = suits(engine, me)
			expect(after.SharkySuit.equipped).toBe(true)
			expect(after.Classic.equipped).toBe(false)
			expect(mods.PlayerData.saveNow(me)).toBe(true)
			expect(ds.saved.p_77.data.skin).toBe("SharkySuit")
		end)
	end)
end)

describe("paid random items and PolicyService", function()
	local function readyLucky(Config)
		for _, item in Config.Store.Items do
			if item.id == "LuckySack" then
				item.ready = true
			end
		end
	end

	local function luckyIn(engine, me, mods)
		playFor(mods, me, 600)
		mods.Store.sendCatalog(me)
		for _, item in lastCatalog(engine, me).items do
			if item.id == "LuckySack" then
				return item
			end
		end
		return nil
	end

	it("shows the Lucky Sack with its odds to unrestricted players", function()
		local world, engine, me, mods = boot({ before = readyLucky })
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			world.wait(0.5)
			local lucky = luckyIn(engine, me, mods)
			expect(lucky).never.toBeNil()
			expect(#lucky.odds).toBe(5)
		end)
	end)

	it("hides it from restricted players", function()
		local world, engine, me, mods, _, prompts = boot({
			before = readyLucky,
			policy = { ArePaidRandomItemsRestricted = true },
		})
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			world.wait(0.5)
			expect(luckyIn(engine, me, mods)).toBeNil()
			mods.Store.prompt(me, "LuckySack")
			expect(#prompts).toBe(0)
		end)
	end)

	it("hides it when the policy lookup fails", function()
		local world, engine, me, mods = boot({ before = readyLucky, policy = false })
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			world.wait(0.5)
			expect(luckyIn(engine, me, mods)).toBeNil()
		end)
	end)
end)

describe("perks in a run", function()
	local function seated(player): boolean
		local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
		return humanoid ~= nil and humanoid.SeatPart ~= nil
	end

	local function boardPublic(world, player)
		local StationClock = world.load("ReplicatedStorage.Shared.StationClock")
		waitUntil(world, function()
			local p = StationClock.phaseAt("Public", 1, world.engine.now)
			return p.name == "Boarding" and p.endsAt - world.engine.now >= 4
		end, 120, "Public boarding")
		local zone = world.engine.workspace:FindFirstChild("PublicZone", true)
		world.engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
		waitUntil(world, function()
			return seated(player)
		end, 5, "sitting on the sleigh")
	end

	local function lastHud(engine, player, kind)
		local list = engine:hudMessages(player, kind)
		local last = list[#list]
		return last and last.data
	end

	it("Bigger Sack raises the sack and 2X Loot doubles the saved Coal", function()
		local world, engine, me, mods =
			boot({ ownsPass = { [IDS.BiggerSack2] = true, [IDS.TwoXLoot] = true } })
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			world.wait(0.5)
			boardPublic(world, me)
			waitUntil(world, function()
				local p = lastHud(engine, me, "Player")
				return p ~= nil
			end, 60, "player stats")
			expect(lastHud(engine, me, "Player").sackCapacity).toBe(mods.Config.Sack.Capacity * 2)
			waitUntil(world, function()
				return lastHud(engine, me, "Results") ~= nil
			end, 400, "results")
			local row = lastHud(engine, me, "Results").rows[1]
			local loot = row.loot
			expect(row.coal).toBe(loot * 2)
			expect(mods.PlayerData.get(me).coal).toBe(loot * 2)
		end)
	end)

	it("Fast Sneak speeds a Santa up only while the house sleeps", function()
		local world, engine, me, mods = boot({ ownsPass = { [IDS.FastSneak] = true } })
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			world.wait(0.5)
			boardPublic(world, me)
			local humanoid = me.Character:FindFirstChild("Humanoid")
			local base = mods.Config.Player.WalkSpeed
			waitUntil(world, function()
				local s = lastHud(engine, me, "Stop")
				return s ~= nil and s.phase == "Sneak"
			end, 60, "sneak phase")
			expect(humanoid.WalkSpeed).toBe(base + mods.Config.Store.FastSneakBonus)
			waitUntil(world, function()
				local s = lastHud(engine, me, "Stop")
				return s ~= nil and s.phase == "LightsOn"
			end, 60, "lights on")
			expect(humanoid.WalkSpeed).toBe(base)
		end)
	end)

	it("an owned Instant Break-out frees a snatched Santa", function()
		local world, engine, me, mods = boot()
		world.run(function()
			mods.PlayerData.waitFor(me, 5)
			mods.Store.processReceipt(receipt(me, IDS.InstantBreakout, "e1"))
			world.wait(0.5)
			boardPublic(world, me)
			-- Walk into Krampus in his Lair until he grabs us.
			waitUntil(world, function()
				local k = lastHud(engine, me, "Krampus")
				if k and k.model and k.model.PrimaryPart then
					engine:teleport(me, k.model.PrimaryPart.Position + Vector3.new(0, 0, 3))
				end
				local c = lastHud(engine, me, "Captive")
				return c ~= nil and c.captive == true
			end, 400, "being snatched")
			local offer = lastHud(engine, me, "Captive").breakout
			expect(offer.owned).toBe(1)
			mods.Remotes.get("Input"):FireServer("Breakout")
			world.wait(0.2)
			expect(lastHud(engine, me, "Captive").captive).toBe(false)
			expect(mods.PlayerData.get(me).inventory.InstantBreakout).toBe(0)
		end)
	end)
end)
