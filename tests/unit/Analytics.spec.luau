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
			local cfg = Config.Analytics
			local limit = (cfg.PerMinuteBase + cfg.PerMinutePerPlayer) * cfg.WindowSeconds / 60
			local before = #calls
			for _ = 1, limit + 10 do
				Analytics.custom(ann, "Spam")
			end
			expect(#calls).toBe(limit)
			expect(before <= limit).toBeTruthy()
			expect(Telemetry.totals().AnalyticsDropped).toBe(10 + before)
			world.wait(Config.Analytics.WindowSeconds + 1) -- a new window
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
				return { jingle = 325 }
			end)
			Analytics.stopLeft(run, 2, { ann }, function()
				return { jingle = 325 }
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

-- A stand-in Run: just the fields Analytics reads.
local function fakeRun(players: { Player }, stats: { [Player]: any })
	local run = { order = players, mapId = "SnowyStreet", stopIndex = 1, phase = "Sneak", ended = false }
	local function statsOf(player)
		return stats[player]
	end
	return run, statsOf
end

describe("Analytics in-run detail", function()
	it("reports each stop per player: grabs, loot, first grab, incidents, missed sleigh", function()
		local world, engine, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Run", store)
			local ann, bob = join("Ann"), join("Bob")
			world.wait(0.5)
			local stats = {
				[ann] = { jingle = 500, grabs = 0, banked = 0, sackValue = 0 },
				[bob] = { jingle = 500, grabs = 0, banked = 0, sackValue = 0 },
			}
			local run, statsOf = fakeRun({ ann, bob }, stats)
			Analytics.runStarted(run)
			Analytics.stopReached(run, 1, statsOf)
			world.wait(7)
			Analytics.grabbed(run, ann, 20, "Regrab") -- a dropped present: not the first grab
			world.wait(1)
			Analytics.grabbed(run, ann, 20, "Presents")
			Analytics.grabbed(run, ann, 20, "Presents")
			stats[ann].grabs, stats[ann].jingle = 3, 560
			Analytics.note(run, ann, "Spotted")
			Analytics.note(run, ann, "Spotted")
			Analytics.note(run, bob, "DogBump")
			Analytics.note(run, bob, "Made up") -- not an incident kind: never sent
			-- Ann banks 300 on board; Bob missed it carrying a present.
			stats[ann].banked = 300
			stats[bob].grabs, stats[bob].sackValue = 1, 120
			Analytics.stopLeft(run, 1, { ann }, statsOf)
			-- After the sleigh left, notes go nowhere until the next stop.
			Analytics.note(run, ann, "Spotted")
			_ = engine
		end)
		local function one(name, player)
			local out = {}
			for _, c in calls do
				if c.kind == "Custom" and c.name == name and (player == nil or c.player.Name == player) then
					table.insert(out, c)
				end
			end
			return out
		end
		local first = one("FirstGrab", "Ann")
		expect(#first).toBe(1)
		expect(first[1].value).toBe(8)
		expect(first[1].fields.CustomField01).toBe("Stop 1")
		expect(first[1].fields.CustomField02).toBe("First game")
		local grabs = one("StopGrabs", "Ann")
		expect(grabs[1].value).toBe(3)
		expect(grabs[1].fields.CustomField03).toBe("Aboard")
		expect(one("StopLoot", "Ann")[1].value).toBe(300)
		expect(#one("StopLoot", "Bob")).toBe(0)
		local missed = one("MissedSleigh", "Bob")
		expect(#missed).toBe(1)
		expect(missed[1].fields.CustomField03).toBe("Had loot")
		expect(#one("MissedSleigh", "Ann")).toBe(0)
		local spotted = one("Spotted", "Ann")
		expect(#spotted).toBe(1)
		expect(spotted[1].value).toBe(2)
		expect(spotted[1].fields.CustomField03).toBe("Crew of 2")
		expect(#one("DogBump", "Bob")).toBe(1)
		expect(#one("Made up")).toBe(0)
		expect(#one("Hid")).toBe(0) -- zero counts aren't sent
	end)

	it("logs how a snatched Santa got free and how long Krampus held them", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Run", store)
			local ann = join("Ann")
			world.wait(0.5)
			local run, statsOf = fakeRun({ ann }, { [ann] = { jingle = 0, grabs = 0, banked = 0 } })
			run.stopIndex = 3
			Analytics.runStarted(run)
			Analytics.stopReached(run, 3, statsOf)
			Analytics.snatched(run, ann)
			world.wait(4)
			Analytics.freedBy(ann, "Wiggled free")
			Analytics.released(run, ann)
			Analytics.released(run, ann) -- a second release does nothing
			Analytics.freedBy(ann, "Bells rung") -- not captive: ignored
			Analytics.snatched(run, ann)
			world.wait(2)
			Analytics.released(run, ann) -- no reason given
		end)
		local freed = {}
		for _, c in calls do
			if c.kind == "Custom" and c.name == "Freed" then
				table.insert(freed, c)
			end
		end
		expect(#freed).toBe(2)
		expect(freed[1].fields.CustomField01).toBe("Wiggled free")
		expect(freed[1].fields.CustomField02).toBe("Lair")
		expect(freed[1].value).toBe(4)
		expect(freed[2].fields.CustomField01).toBe("Krampus let go")
		expect(freed[2].value).toBe(2)
	end)

	it("sends crew moments once per run, not once per player", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Run", store)
			local ann, bob = join("Ann"), join("Bob")
			world.wait(0.5)
			local run = fakeRun({ ann, bob }, {})
			run.phase = "LightsOn"
			Analytics.runStarted(run)
			Analytics.crewMoment(run, "NoiseAlarm", run.phase)
		end)
		local alarms = of(calls, "Custom", "NoiseAlarm")
		expect(#alarms).toBe(1)
		expect(alarms[1].fields.CustomField01).toBe("Stop 1")
		expect(alarms[1].fields.CustomField02).toBe("LightsOn")
		expect(alarms[1].fields.CustomField03).toBe("Crew of 2")
	end)

	it("sends the run's loot with the results", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Run", store)
			local ann = join("Ann")
			world.wait(0.5)
			local run, statsOf = fakeRun({ ann }, { [ann] = { jingle = 0, grabs = 0, banked = 0 } })
			Analytics.runStarted(run)
			run.stopIndex = 3
			Analytics.stopReached(run, 3, statsOf)
			Analytics.stopLeft(run, 3, { ann }, statsOf)
			Analytics.runFinished(run, function()
				return 1234.6
			end)
		end)
		local loot = of(calls, "Custom", "RunLoot")
		expect(#loot).toBe(1)
		expect(loot[1].value).toBe(1234)
		expect(loot[1].fields.CustomField03).toBe("Escaped")
	end)
end)

describe("Analytics quitting", function()
	it("logs Quit with time on the server, but not for a teleport", function()
		local world, engine, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann, bob = join("Ann"), join("Bob")
			world.wait(30)
			Analytics.teleporting({ bob }, true)
			engine:removePlayer(ann)
			engine:removePlayer(bob)
			world.wait(0.5)
		end)
		local quits = of(calls, "Custom", "Quit")
		expect(#quits).toBe(1)
		expect(quits[1].player.Name).toBe("Ann")
		expect(quits[1].value).toBe(30)
		expect(quits[1].fields.CustomField01).toBe("Lobby")
		expect(quits[1].fields.CustomField03).toBe("No runs")
	end)

	it("a failed teleport means a later leave is a quit again", function()
		local world, engine, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann = join("Ann")
			world.wait(1)
			Analytics.teleporting({ ann }, true)
			Analytics.teleporting({ ann }, false)
			engine:removePlayer(ann)
			world.wait(0.5)
		end)
		expect(#of(calls, "Custom", "Quit")).toBe(1)
	end)
end)

describe("Analytics client reports", function()
	it("takes one Hello: the device and load time", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Lobby", store)
			local ann, bob = join("Ann"), join("Bob")
			world.wait(0.5)
			Analytics.clientStats(ann, { kind = "Hello", device = "Phone", load = 14.4 })
			Analytics.clientStats(ann, { kind = "Hello", device = "Computer", load = 2 }) -- ignored
			Analytics.clientStats(bob, { kind = "Hello", device = "Toaster", load = -3 })
			Analytics.clientStats(bob, "junk")
		end)
		local devices = of(calls, "Custom", "Device")
		expect(#devices).toBe(2)
		expect(devices[1].fields.CustomField01).toBe("Phone")
		expect(devices[2].fields.CustomField01).toBe("Unknown")
		local loads = of(calls, "Custom", "LoadTime")
		expect(#loads).toBe(1) -- Bob's -3 s is junk
		expect(loads[1].value).toBe(14)
		expect(loads[1].fields.CustomField01).toBe("10-20 s")
		expect(loads[1].fields.CustomField02).toBe("Phone")
	end)

	it("logs each cutscene's frame rate, freezes and skips, and ignores made-up scenes", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		local Cutscenes = world.load("ReplicatedStorage.Shared.Cutscenes")
		local scene = Cutscenes.get("KrampusArrives")
		world.run(function()
			Analytics.start("Run", store)
			local ann = join("Ann")
			world.wait(0.5)
			Analytics.clientStats(ann, { kind = "Hello", device = "Tablet" })
			local full = { seconds = scene.seconds, fps = 24, worstMs = 2300, hitches = 3, freezes = 1 }
			Analytics.clientStats(ann, { kind = "Cutscene", id = "KrampusArrives" }) -- no numbers: junk
			local report = table.clone(full)
			report.kind, report.id = "Cutscene", "KrampusArrives"
			Analytics.clientStats(ann, report)
			local skipped = {
				kind = "Cutscene",
				id = "KrampusArrives",
				seconds = 1,
				fps = 60,
				worstMs = 20,
				hitches = 0,
				freezes = 0,
			}
			Analytics.clientStats(ann, skipped)
			local fake = table.clone(report)
			fake.id = "NotAScene"
			Analytics.clientStats(ann, fake)
		end)
		local perf = of(calls, "Custom", "CutscenePerf")
		expect(#perf).toBe(2) -- the report with no numbers and the fake scene are dropped
		expect(perf[1].value).toBe(2300)
		expect(perf[1].fields.CustomField01).toBe("KrampusArrives")
		expect(perf[1].fields.CustomField02).toBe("15-30 fps")
		expect(perf[1].fields.CustomField03).toBe("Tablet")
		local freezes = of(calls, "Custom", "CutsceneFreeze")
		expect(#freezes).toBe(1)
		expect(freezes[1].value).toBe(1)
		local skips = of(calls, "Custom", "CutsceneSkipped")
		expect(#skips).toBe(1)
		expect(skips[1].fields.CustomField01).toBe("KrampusArrives")
	end)

	it("logs frame rate by area, at most every PerfMinSeconds", function()
		local world, _, Analytics, _, _, calls, store, join = setup()
		world.run(function()
			Analytics.start("Run", store)
			local ann = join("Ann")
			world.wait(0.5)
			local perf = { kind = "Perf", seconds = 60, fps = 55, worstMs = 1200, hitches = 0, freezes = 1 }
			Analytics.clientStats(ann, perf) -- between runs
			Analytics.clientStats(ann, perf) -- too soon: dropped
			local run, statsOf = fakeRun({ ann }, { [ann] = { jingle = 0, grabs = 0, banked = 0 } })
			Analytics.runStarted(run)
			Analytics.stopReached(run, 1, statsOf)
			world.wait(Analytics.PerfMinSeconds + 1)
			Analytics.clientStats(ann, perf)
		end)
		local fps = of(calls, "Custom", "Fps")
		expect(#fps).toBe(2)
		expect(fps[1].fields.CustomField01).toBe("Waiting")
		expect(fps[2].fields.CustomField01).toBe("Stop 1")
		expect(fps[2].value).toBe(55)
		expect(#of(calls, "Custom", "Freeze")).toBe(2)
	end)

	it("counts long server frames, blamed on the cutscene playing", function()
		local world, engine, Analytics, Telemetry, _, _, store = setup()
		world.run(function()
			Analytics.start("Run", store)
			Analytics.moment("KrampusArrives", 5)
			engine:step(0.8)
			world.wait(6)
			engine:step(1.5)
			engine:step(0.1)
		end)
		local pending = Telemetry.pending().ServerHitch
		expect(pending["KrampusArrives 0.5-1 s"]).toBe(1)
		expect(pending["Other 1-2 s"]).toBe(1)
	end)
end)
