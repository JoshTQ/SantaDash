--[[
	Player analytics (server/Analytics + shared/Funnels) on the real server
	(Main) in a headless world, with stand-ins for AnalyticsService and the
	DataStore: a brand-new player's first game logs every onboarding step
	once and in order, across two runs; veterans never enter the onboarding
	funnel; the Lobby, Run and Shop funnels, Coal and Jingle economy events,
	tip events, and where players quit.
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

local function fakeDataStore()
	local ds = { saved = {} }
	function ds.UpdateAsync(_, key, fn)
		local new = fn(deepCopy(ds.saved[key]))
		if new ~= nil then
			ds.saved[key] = deepCopy(new)
		end
		return new
	end
	return ds
end

-- Every AnalyticsService call, in order.
local function fakeAnalytics(engine)
	local calls = {}
	local service = engine:service("AnalyticsService")
	service.LogOnboardingFunnelStepEvent = function(_, player, step, name, fields)
		table.insert(
			calls,
			{ kind = "Onboarding", player = player, step = step, name = name, fields = fields }
		)
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
			player = player,
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
	return calls
end

-- options: { saved = { [key] = value }, place = "Run" }
local function boot(options: any?)
	local opts = options or {}
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
	local ds = fakeDataStore()
	for key, value in opts.saved or {} do
		ds.saved[key] = value
	end
	engine:service("DataStoreService").GetDataStore = function()
		return ds
	end
	engine:service("PolicyService").GetPolicyInfoForPlayerAsync = function()
		return { ArePaidRandomItemsRestricted = false }
	end
	local calls = fakeAnalytics(engine)
	if opts.place == "Run" then
		engine.workspace:SetAttribute("RunPlace", true)
	end
	local joinData = nil
	if opts.place == "Run" then
		local Handoff = world.load("ReplicatedStorage.Shared.Handoff")
		joinData = { TeleportData = Handoff.make("crew-1", "Public", { 77 }) }
	end
	local me = engine:addPlayer("Me", { userId = 77, joinData = joinData })
	engine:setLocalPlayer(me)
	world.run(function()
		world.runScript("ServerScriptService.Server.Main")
		world.runScript("StarterPlayer.StarterPlayerScripts.Client.Tips")
		world.wait(1)
	end)
	return world, engine, me, Config, ds, calls
end

local function onboarding(calls, player): { number }
	local steps = {}
	for _, c in calls do
		if c.kind == "Onboarding" and c.player == player then
			table.insert(steps, c.step)
		end
	end
	return steps
end

local function funnel(calls, name: string): { any }
	local out = {}
	for _, c in calls do
		if c.kind == "Funnel" and c.funnel == name then
			table.insert(out, c)
		end
	end
	return out
end

local function customs(calls, name: string): { any }
	local out = {}
	for _, c in calls do
		if c.kind == "Custom" and c.name == name then
			table.insert(out, c)
		end
	end
	return out
end

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

local function grabOne(engine, player): boolean
	for _, d in engine.workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") and d.ActionText == "Grab" and d.Enabled then
			engine.trigger(d, player)
			return true
		end
	end
	return false
end

local function results(engine, player): number
	return #engine:hudMessages(player, "Results")
end

describe("the first-game (onboarding) funnel", function()
	it("logs every step once, in order, from joining to a second run", function()
		local world, engine, me, _, ds, calls = boot()
		local Funnels = world.load("ReplicatedStorage.Shared.Funnels")
		world.run(function()
			waitUntil(world, function()
				return #onboarding(calls, me) >= 2
			end, 15, "joined and loaded in")
			boardPublic(world, me)
			waitUntil(world, function()
				return #engine:hudMessages(me, "Tip") > 0 and #funnel(calls, "Run") > 1
			end, 90, "the first stop")
			grabOne(engine, me)
			waitUntil(world, function()
				return results(engine, me) > 0
			end, 300, "the first run")
			waitUntil(world, function()
				return #funnel(calls, "Run") > #Funnels.Run
			end, 120, "the second run")
		end)
		local steps = onboarding(calls, me)
		local want = {}
		for i = 1, #Funnels.Onboarding do
			table.insert(want, i)
		end
		expect(table.concat(steps, ",")).toBe(table.concat(want, ","))
		-- Step names are the readable ones, and only step 1 carries a field.
		local first = nil
		for _, c in calls do
			if c.kind == "Onboarding" and c.step == 1 then
				first = c
			end
		end
		expect(first.name).toBe("Joined the game")
		expect(first.fields.CustomField01).toBe("Lobby")
		-- In saved data, so the run place (and the next session) carries on from here.
		local PlayerData = world.load("ServerScriptService.Server.PlayerData")
		expect(PlayerData.get(me).analytics.onboarding).toBe(#Funnels.Onboarding)
		expect(PlayerData.get(me).analytics.runs).toBe(2)
		_ = ds
	end)

	it("never puts a returning player in it (an old save), but still tracks their runs", function()
		local saved = { p_77 = { data = { coal = 40, playSeconds = 5000 } } }
		local world, engine, me, _, ds, calls = boot({ saved = saved })
		world.run(function()
			boardPublic(world, me)
			waitUntil(world, function()
				return results(engine, me) > 0
			end, 300, "the run")
		end)
		expect(#onboarding(calls, me)).toBe(0)
		expect(ds.saved.p_77.data.analytics.onboarding).toBe(-1)
		local run = funnel(calls, "Run")
		expect(run[1].step).toBe(1)
		expect(run[1].fields.CustomField01).toBe("1st run")
		expect(run[1].fields.CustomField03).toBe("Solo")
		-- Lobby funnel step 1 is split by experience.
		local lobby = funnel(calls, "Lobby")
		expect(lobby[1].fields.CustomField01).toBe("Played before")
		_ = world
	end)

	it("carries on in the run place from the step saved in the lobby, without repeating", function()
		-- The lobby logged up to Crew found (4) before the teleport.
		local saved = { p_77 = { data = { playSeconds = 90, analytics = { onboarding = 4, runs = 0 } } } }
		local world, engine, me, _, _, calls = boot({ saved = saved, place = "Run" })
		world.run(function()
			waitUntil(world, function()
				return results(engine, me) > 0
			end, 300, "the run")
		end)
		local steps = onboarding(calls, me)
		expect(steps[1]).toBe(5) -- First run started; never Joined again
		for i = 2, #steps do
			expect(steps[i]).toBe(steps[i - 1] + 1)
		end
		-- The run place has no lobby funnel.
		expect(#funnel(calls, "Lobby")).toBe(0)
		_ = world
	end)
end)

describe("lobby, run and economy events", function()
	it("logs the lobby funnel once per visit and the run funnel for every stop", function()
		local world, engine, me, Config, _, calls = boot()
		world.run(function()
			boardPublic(world, me)
			waitUntil(world, function()
				return results(engine, me) > 0
			end, 300, "the run")
		end)
		local lobby = funnel(calls, "Lobby")
		expect(#lobby).toBe(3)
		for i, c in lobby do
			expect(c.step).toBe(i)
			expect(c.session).toBe(lobby[1].session)
		end
		expect(lobby[1].fields.CustomField01).toBe("First game")
		local run = funnel(calls, "Run")
		expect(#run).toBe(#Config.Run.StopKinds + 2)
		for i, c in run do
			expect(c.step).toBe(i)
			expect(c.session).toBe(run[1].session)
		end
		expect(run[#Config.Run.StopKinds + 1].name).toBe("Reached Krampus's Lair")
		expect(run[#run].name).toBe("Run finished")
		local ends = customs(calls, "RunEnd")
		expect(#ends).toBe(1)
		expect(ends[1].fields.CustomField02).toBe("1st run")
		-- A crew was found after some time in the lobby.
		expect(#customs(calls, "CrewWait")).toBe(1)
		_ = world
	end)

	it("sends Jingle from presents once per stop, and Coal from the run", function()
		local world, engine, me, _, ds, calls = boot()
		world.run(function()
			boardPublic(world, me)
			waitUntil(world, function()
				return #funnel(calls, "Run") >= 2
			end, 90, "the first stop")
			world.wait(1)
			expect(grabOne(engine, me)).toBe(true)
			world.wait(0.5)
			expect(grabOne(engine, me)).toBe(true)
			waitUntil(world, function()
				return results(engine, me) > 0
			end, 300, "the run")
		end)
		local jingle, coal = {}, {}
		for _, c in calls do
			if c.kind == "Economy" and c.currency == "Jingle" then
				table.insert(jingle, c)
			elseif c.kind == "Economy" and c.currency == "Coal" then
				table.insert(coal, c)
			end
		end
		-- Two grabs at Stop 1, one event when the sleigh left.
		expect(#jingle).toBe(1)
		expect(jingle[1].sku).toBe("Presents")
		expect(jingle[1].amount > 0).toBeTruthy()
		expect(string.find(jingle[1].flow, "Source", 1, true)).never.toBeNil()
		expect(jingle[1].transaction).toBe("Gameplay")
		-- The grabs were banked (Santa never left the deck), so the run paid Coal.
		expect(#coal).toBe(1)
		expect(coal[1].sku).toBe("RunReward")
		expect(coal[1].balance).toBe(world.load("ServerScriptService.Server.PlayerData").get(me).coal)
		_ = ds
	end)

	it("logs tips shown, done and switched off, with the tip that was up", function()
		local world, engine, me, _, _, calls = boot()
		world.run(function()
			waitUntil(world, function()
				return engine:guiShows("Follow the trail")
			end, 15, "the Board tip")
			engine:guiButton("X").Activated:Fire()
			world.wait(0.5)
		end)
		local shown = customs(calls, "TipShown")
		expect(#shown).toBe(1)
		expect(shown[1].fields.CustomField01).toBe("Board")
		local off = customs(calls, "TipsOff")
		expect(#off).toBe(1)
		expect(off[1].fields.CustomField01).toBe("Board")
	end)

	it("records where a player quit: in the lobby, and mid-run", function()
		local world, engine, me, _, _, calls = boot()
		local friend = engine:addPlayer("Friend", { userId = 78 })
		world.run(function()
			world.wait(2)
			engine:removePlayer(friend)
			world.wait(0.5)
			boardPublic(world, me)
			waitUntil(world, function()
				return #funnel(calls, "Run") >= 2
			end, 90, "the first stop")
			world.wait(2)
			engine:removePlayer(me)
			world.wait(0.5)
		end)
		local lobby = customs(calls, "LeftLobby")
		expect(#lobby).toBe(1)
		expect(lobby[1].player).toBe(friend)
		expect(lobby[1].fields.CustomField01).toBe("Exploring")
		local run = customs(calls, "LeftRun")
		expect(#run).toBe(1)
		expect(run[1].fields.CustomField01).toBe("Stop 1: Sneak")
		expect(run[1].fields.CustomField02).toBe("First game")
		expect(run[1].fields.CustomField03).toBe("Quit the game")
	end)
end)
