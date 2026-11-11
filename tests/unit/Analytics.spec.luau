--[[
	Player analytics rules (server/Analytics.luau) in a headless world with a
	stand-in saved-data store: the rate-limit share, steps reached before
	saved data loads, unknown data staying out, the Shop funnel's visits,
	FirstPurchase once, Coal and Jingle events, and nothing sent from Studio.
]]

local function setup(options: any?)
	local opts = options or {}
	local world = headless()
	local engine = world.engine
	local Analytics = world.load("ServerScriptService.Server.Analytics")
	local Telemetry = world.load("ServerScriptService.Server.Telemetry")
	local Config = world.load("ReplicatedStorage.Shared.Config")
	local calls = {}
	local service = engine:service("AnalyticsService")
	service.LogOnboardingFunnelStepEvent = function(_, player, step, name)
		table.insert(calls, { kind = "Onboarding", player = player, step = step, name = name })
	end
	service.LogFunnelStepEvent = function(_, player, funnel, session, step, name, fields)
		table.insert(calls, {
			kind = "Funnel",
			player = player,
			funnel = funnel,
			session = session,
			step = step,
			name = name,
			fields = fields,
		})
	end
	service.LogEconomyEvent = function(_, player, flowType, currency, amount, balance, transaction, sku)
		table.insert(calls, {
			kind = "Economy",
			flow = tostring(flowType),
			currency = currency,
			amount = amount,
			balance = balance,
			transaction = transaction,
			sku = sku,
		})
	end
	service.LogCustomEvent = function(_, player, name, value, fields)
		table.insert(calls, { kind = "Custom", player = player, name = name, value = value, fields = fields })
	end

	-- A saved-data stand-in; a player's data loads at loadAt[player] (engine time).
	local datas, loadAt = {}, {}
	local loaded = setmetatable({}, {
		__index = function(_, player)
			return loadAt[player] ~= nil and engine.now >= loadAt[player]
		end,
	})
	local store = {
		get = function(player)
			return if loaded[player] then datas[player] else nil
		end,
		waitFor = function(player)
			while not loaded[player] do
				engine.task.wait(0.1)
			end
			return datas[player]
		end,
		update = function(player, fn)
			if not loaded[player] then
				return false
			end
			fn(datas[player])
			return true
		end,
		isPersistent = function()
			return opts.persistent ~= false
		end,
	}
	local function join(name: string, data: any?, loadAfter: number?)
		local player = engine:addPlayer(name)
		datas[player] = data
			or {
				playSeconds = 0,
				coal = 0,
				analytics = { onboarding = 0, runs = 0, bought = false },
			}
		loadAt[player] = engine.now + (loadAfter or 0)
		return player
	end
	Analytics._reset()
	return world, engine, Analytics, Telemetry, Config, calls, store, join, datas
end

local function of(calls, kind: string, name: string?): { any }
	local out = {}
	for _, c in calls do
		if c.kind == kind and (name == nil or c.name == name or c.funnel == name) then
			table.insert(out, c)
		end
	end
	return out
end

describe("Analytics onboarding", function()
	it("catches up steps reached before saved data loaded", function()
		local world, _, Analytics, _, _, calls, store, join, datas = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann", nil, 3)
			world.wait(0.5)
			Analytics.loadedIn(ann) -- the client beat the DataStore
			Analytics.boarded(ann)
			expect(#of(calls, "Onboarding")).toBe(0)
			world.wait(4)
			local steps = of(calls, "Onboarding")
			expect(#steps).toBe(2)
			expect(steps[1].step).toBe(1)
			expect(steps[2].step).toBe(3) -- Roblox counts step 2 as done
			expect(datas[ann].analytics.onboarding).toBe(3)
		end)
	end)

	it("stays out of the funnel when saved data isn't saving", function()
		local world, _, Analytics, _, _, calls, store, join, datas = setup({ persistent = false })
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.loadedIn(ann)
			world.wait(0.5)
			expect(#of(calls, "Onboarding")).toBe(0)
			expect(datas[ann].analytics.onboarding).toBe(0) -- decided next time it can save
			-- Other funnels still work.
			expect(#of(calls, "Funnel", "Lobby")).toBe(1)
		end)
	end)

	it("ignores unknown steps and players it never saw", function()
		local world, engine, Analytics, _, _, calls, store = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ghost = engine:addPlayer("Ghost")
			Analytics._reset()
			Analytics.reach(ghost, "Joined")
			Analytics.reach(ghost, "NotAStep")
			Analytics.tip(ghost, "Shown", "Board")
			Analytics.purchased(ghost, { id = "StarterSack", price = 25 })
		end)
		expect(#calls).toBe(0)
	end)
end)

describe("Analytics rate limit", function()
	it("keeps each server inside its share and counts what it dropped", function()
		local world, _, Analytics, Telemetry, Config, calls, store, join = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(0.5)
			local limit = Config.Analytics.PerMinuteBase + Config.Analytics.PerMinutePerPlayer
			local before = #calls
			for _ = 1, limit + 10 do
				Analytics.custom(ann, "Spam")
			end
			expect(#calls).toBe(limit)
			expect(before <= limit).toBeTruthy()
			expect(Telemetry.totals().AnalyticsDropped).toBe(10 + before)
			world.wait(61) -- a new minute
			Analytics.custom(ann, "Spam")
			expect(#calls).toBe(limit + 1)
		end)
	end)

	it("counts a failed send without warning", function()
		local world, engine, Analytics, Telemetry, _, _, store, join = setup()
		engine:service("AnalyticsService").LogCustomEvent = function()
			error("analytics down")
		end
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.custom(ann, "Thing")
		end)
		expect(Telemetry.totals().AnalyticsFailed).toBe(1)
		expect(#engine.warnings).toBe(0)
	end)

	it("sends nothing to Roblox from Studio", function()
		local world, engine, Analytics, _, _, calls, store, join = setup()
		engine:service("RunService").IsStudio = function()
			return true
		end
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.custom(ann, "Thing")
		end)
		expect(#calls).toBe(0)
		expect(#Analytics._sent() > 0).toBeTruthy() -- still recorded for tests and PrintInStudio
	end)
end)

describe("Analytics shop and purchases", function()
	it("treats re-opening the store as one visit and a buy as its last step", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.shopOpened(ann)
			Analytics.shopOpened(ann)
			Analytics.shopPrompted(ann, "StarterSack")
			Analytics.purchased(ann, { id = "StarterSack", price = 25 })
			Analytics.shopOpened(ann) -- after buying: a new visit
			local shop = of(calls, "Funnel", "Shop")
			expect(#shop).toBe(4)
			expect(shop[1].step).toBe(1)
			expect(shop[2].step).toBe(2)
			expect(shop[3].step).toBe(3)
			expect(shop[3].session).toBe(shop[1].session)
			expect(shop[4].step).toBe(1)
			expect(shop[4].session).never.toBe(shop[1].session)
			expect(shop[1].fields.CustomField02).toBe("Under 3 min")
		end)
	end)

	it("a prompt from inside a run (Instant Break-out) starts its own visit", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Run", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.shopPrompted(ann, "InstantBreakout")
			local shop = of(calls, "Funnel", "Shop")
			expect(#shop).toBe(1)
			expect(shop[1].step).toBe(2)
		end)
	end)

	it("logs every purchase with its Robux price, and FirstPurchase only once", function()
		local world, _, Analytics, _, _, calls, store, join, datas = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.purchased(ann, { id = "StarterSack", price = 25 })
			Analytics.purchased(ann, { id = "TwoXLoot", price = 149 })
			local buys = of(calls, "Custom", "Purchase")
			expect(#buys).toBe(2)
			expect(buys[2].value).toBe(149)
			expect(buys[2].fields.CustomField01).toBe("TwoXLoot")
			local first = of(calls, "Custom", "FirstPurchase")
			expect(#first).toBe(1)
			expect(first[1].fields.CustomField01).toBe("StarterSack")
			expect(datas[ann].analytics.bought).toBe(true)
		end)
	end)
end)

describe("Analytics economy", function()
	it("logs Coal in and out with balances, and skips zero amounts", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.coal(ann, "Source", 120, 120, "Gameplay", "RunReward")
			Analytics.coal(ann, "Sink", 100, 20, "Shop", "BladeSkates")
			Analytics.coal(ann, "Source", 0, 20, "IAP", "TwoXLoot")
		end)
		local coal = of(calls, "Economy")
		expect(#coal).toBe(2)
		expect(coal[1].amount).toBe(120)
		expect(string.find(coal[1].flow, "Source", 1, true)).never.toBeNil()
		expect(coal[2].balance).toBe(20)
		expect(coal[2].sku).toBe("BladeSkates")
		expect(coal[2].transaction).toBe("Shop")
		expect(string.find(coal[2].flow, "Sink", 1, true)).never.toBeNil()
	end)

	it("adds up Jingle by source and sends it once per stop", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Run", store)
			local ann = join("Ann")
			world.wait(0.5)
			local run = { order = { ann }, mapId = "SnowyStreet", stopIndex = 1, phase = "Sneak" }
			Analytics.runStarted(run)
			Analytics.earnJingle(ann, 10, "Presents")
			Analytics.earnJingle(ann, 15, "Presents")
			Analytics.earnJingle(ann, 100, "SecretRoom")
			Analytics.spendJingle(ann, 300, 325, "PeppermintRush")
			Analytics.stopLeft(run, 1, { ann }, function()
				return 325
			end)
			Analytics.stopLeft(run, 2, { ann }, function()
				return 325
			end) -- nothing new earned
		end)
		local jingle = of(calls, "Economy")
		expect(#jingle).toBe(3)
		local bySku = {}
		for _, c in jingle do
			bySku[c.sku] = c
		end
		expect(bySku.Presents.amount).toBe(25)
		expect(bySku.SecretRoom.amount).toBe(100)
		expect(bySku.PeppermintRush.transaction).toBe("Shop")
		expect(bySku.Presents.balance).toBe(325)
	end)
end)
