--[[
	Player analytics: where players drop off, above all in their first game.
	Sends Roblox's built-in AnalyticsService events, so everything shows in
	the Creator Dashboard (Analytics) with no outside service. The funnels,
	steps and labels are in shared/Funnels.luau; where to find each chart is
	in docs/ANALYTICS.md. Crash and error counts stay in Telemetry.luau.

	What is sent (all from the server; Roblox ignores clients and Studio):
	- Funnels: Onboarding (first game, once per player), Lobby (every visit),
	  Run (every run), Shop (every store visit).
	- Economy: Coal (saved; earned from runs and Robux packs, spent on boots)
	  and Jingle (in-run; earned from presents and secret rooms, spent at the
	  cocoa booth, vault and wardrobe). Present grabs are added up and sent
	  once per stop, to stay well inside the rate limit.
	- Custom events: TipShown / TipDone / TipsOff (which tip), LeftRun (where
	  in a run someone quit), LeftLobby (what they were doing), RunEnd
	  (escaped or missed the last sleigh), Purchase and FirstPurchase.

	The first-game funnel needs to remember a player's step between the lobby
	and run places, so it lives in saved data: data.analytics (PlayerDefaults).

	Kid safety: no names, user ids or chat text, only fixed labels.

	Called by: Main (start), Onboarding (loaded in, tips), Lobby and
	Matchmaker (boarded, crew found, left), Run and RunHost (run steps,
	Jingle, left), Store and Boots (shop funnel, Coal, purchases).
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Funnels = require(ReplicatedStorage.Shared.Funnels)
local Util = require(ReplicatedStorage.Shared.Util)
local Telemetry = require(script.Parent.Telemetry)

export type Store = {
	get: (player: Player) -> any,
	waitFor: (player: Player, timeout: number?) -> any,
	update: (player: Player, fn: (data: any) -> ()) -> any,
	isPersistent: (player: Player) -> boolean,
}

type PlayerState = {
	status: string?, -- Funnels.status, nil while saved data loads
	early: number, -- highest onboarding step reached before the status was known
	lobby: { id: string, step: number, since: number, boardedAt: number?, done: boolean }?,
	shop: { id: string, step: number, at: number }?,
	tips: { [string]: boolean },
	lastTip: string?,
	jingle: { [string]: number }, -- Jingle earned since the last economy event, by source
}

type RunState = {
	id: string,
	map: string,
	crew: string,
	steps: { [Player]: number },
	runs: { [Player]: number },
	escaped: { [Player]: boolean },
}

local Analytics = {}

Analytics.LoadTimeout = 30
Analytics.ShopSessionSeconds = 120 -- re-opening the store within this is the same visit
Analytics.ForgetSeconds = 5 -- a leaving player's state is kept this long

local store: Store? = nil
local placeKind = "Lobby"
local started = false
local states: { [Player]: PlayerState } = {}
local runs: { [any]: RunState } = setmetatable({}, { __mode = "k" }) :: any
local window = { startedAt = -math.huge, sent = 0 }
local sentLog: { { kind: string, name: string } } = {} -- tests: what went out

local FLOW = {}
local function flow(name: string): any
	if FLOW[name] == nil then
		local ok, value = pcall(function()
			return (Enum :: any).AnalyticsEconomyFlowType[name]
		end)
		FLOW[name] = if ok and value ~= nil then value else name
	end
	return FLOW[name]
end

local function transaction(name: string): string
	local ok, value = pcall(function()
		return (Enum :: any).AnalyticsEconomyTransactionType[name].Name
	end)
	return if ok and type(value) == "string" then value else name
end

local function fields(a: string?, b: string?, c: string?): { [string]: string }?
	if not (a or b or c) then
		return nil
	end
	local out = {}
	if a then
		out.CustomField01 = a
	end
	if b then
		out.CustomField02 = b
	end
	if c then
		out.CustomField03 = c
	end
	return out
end

-- Sends one event if the server is inside its share of Roblox's limit.
local function send(kind: string, name: string, call: () -> ()): boolean
	if not Config.Analytics.Enabled then
		return false
	end
	local t = Util.now()
	if t - window.startedAt >= 60 then
		window.startedAt = t
		window.sent = 0
	end
	local limit = Config.Analytics.PerMinuteBase + Config.Analytics.PerMinutePerPlayer * #Players:GetPlayers()
	if window.sent >= limit then
		Telemetry.count("AnalyticsDropped", kind)
		return false
	end
	window.sent += 1
	table.insert(sentLog, { kind = kind, name = name })
	if #sentLog > 500 then
		table.remove(sentLog, 1)
	end
	if RunService:IsStudio() then
		if Config.Analytics.PrintInStudio then
			print("[Analytics] " .. kind .. ": " .. name)
		end
		return true -- Roblox records nothing from Studio
	end
	local ok = pcall(call)
	if not ok then
		Telemetry.count("AnalyticsFailed", kind) -- counted, never warned (warnings are telemetry too)
	end
	return ok
end

local function stateOf(player: Player): PlayerState?
	return states[player]
end

local function dataOf(player: Player): any
	local s = store
	local data = s and s.get(player)
	return if type(data) == "table" and type(data.analytics) == "table" then data else nil
end

local function experience(player: Player): string
	local st = states[player]
	return Funnels.experienceLabel(if st then st.status else nil)
end

----------------------------------------------------------------------------
-- Onboarding (first game)
----------------------------------------------------------------------------

local function logOnboarding(player: Player, step: number)
	local info = Funnels.Onboarding[step]
	local extra = if step == 1 then fields(placeKind) else nil
	send("Onboarding", step .. " " .. info.name, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, info.name, extra)
	end)
end

local function advance(player: Player, step: number)
	local st = states[player]
	local data = dataOf(player)
	if not st or st.status ~= "active" or not data then
		return
	end
	if not Funnels.shouldLog(data.analytics.onboarding, step) then
		return
	end
	store.update(player, function(d)
		d.analytics.onboarding = step
	end)
	logOnboarding(player, step)
	if step >= #Funnels.Onboarding then
		st.status = "done"
	end
end

-- A first-game step by id (Funnels.Onboarding). Safe for anyone: veterans
-- and players whose data isn't loaded are ignored (or caught up later).
function Analytics.reach(player: Player, id: string)
	local step = Funnels.step(Funnels.Onboarding, id)
	local st = states[player]
	if not step or not st then
		return
	end
	if st.status == nil then
		st.early = math.max(st.early, step)
		return
	end
	advance(player, step)
end

-- Works out whether a player is new once their saved data loads.
local function decide(player: Player)
	local st = states[player]
	local s = store
	if not st or not s then
		return
	end
	local ok, data = pcall(s.waitFor, player, Analytics.LoadTimeout)
	if states[player] ~= st or player.Parent ~= Players then
		return
	end
	if not ok or type(data) ~= "table" or type(data.analytics) ~= "table" then
		st.status = "unknown"
		return
	end
	local status = Funnels.status(data.analytics.onboarding, data.playSeconds, s.isPersistent(player))
	if status == "new" then
		s.update(player, function(d)
			d.analytics.onboarding = 1
		end)
		st.status = "active"
		logOnboarding(player, 1)
	else
		st.status = status
		if status == "veteran" and data.analytics.onboarding == 0 then
			s.update(player, function(d)
				d.analytics.onboarding = -1 -- decided for good
			end)
		end
	end
	if st.early > 1 then
		advance(player, st.early)
	end
end

----------------------------------------------------------------------------
-- Lobby
----------------------------------------------------------------------------

local function lobbyStep(player: Player, id: string)
	local st = states[player]
	if not st or placeKind ~= "Lobby" then
		return
	end
	local step = Funnels.step(Funnels.Lobby, id) :: number
	local session = st.lobby
	if not session or session.done then
		session = { id = HttpService:GenerateGUID(false), step = 0, since = Util.now(), done = false }
		st.lobby = session
	end
	local s = session :: any
	if step <= s.step then
		return
	end
	s.step = step
	if id == "Boarded" then
		s.boardedAt = Util.now()
	end
	local name = Funnels.Lobby[step].name
	local extra = if step == 1 then fields(experience(player)) else nil
	send("Lobby", step .. " " .. name, function()
		AnalyticsService:LogFunnelStepEvent(player, Funnels.Names.Lobby, s.id, step, name, extra)
	end)
	if step == #Funnels.Lobby then
		s.done = true
	end
end

-- The player's client has loaded (its Tips script said TipsReady).
function Analytics.loadedIn(player: Player)
	Analytics.reach(player, "LoadedIn")
	lobbyStep(player, "LoadedIn")
end

-- Sat down in a station sleigh (any bay).
function Analytics.boarded(player: Player)
	Analytics.reach(player, "Boarded")
	lobbyStep(player, "Boarded")
end

-- A crew including these players is leaving (teleport or same-server run).
function Analytics.crewFound(players: { Player })
	for _, player in players do
		local st = states[player]
		local session = st and st.lobby
		-- How long they sat in a sleigh before the crew left (the queue wait).
		local waited = if session
				and not session.done
				and session.boardedAt
			then Util.now() - session.boardedAt
			else nil
		Analytics.reach(player, "CrewFound")
		lobbyStep(player, "CrewFound")
		if waited then
			Analytics.custom(
				player,
				"CrewWait",
				math.floor(waited),
				Funnels.waitLabel(waited),
				experience(player)
			)
		end
	end
end

-- A player quit the game from the lobby. doing: a short fixed label.
function Analytics.leftLobby(player: Player, doing: string)
	local st = states[player]
	if not st or (st.lobby and st.lobby.done) then
		return -- after a crew was found, leaving is the teleport to the run
	end
	local since = if st.lobby then st.lobby.since else nil
	Analytics.custom(
		player,
		"LeftLobby",
		1,
		doing,
		experience(player),
		if since then Funnels.waitLabel(Util.now() - since) else nil
	)
end

----------------------------------------------------------------------------
-- Runs
----------------------------------------------------------------------------

local function runStep(run, player: Player, id: string)
	local r = runs[run]
	local step = Funnels.step(Funnels.Run, id)
	if not r or not step or (r.steps[player] or 0) >= step then
		return
	end
	r.steps[player] = step
	local name = Funnels.Run[step].name
	local extra = if step == 1 then fields(Funnels.runsLabel(r.runs[player] or 1), r.map, r.crew) else nil
	send("Run", step .. " " .. name, function()
		AnalyticsService:LogFunnelStepEvent(player, Funnels.Names.Run, r.id, step, name, extra)
	end)
end

-- Jingle earned since the last economy event goes out as one event per source.
local function flushJingle(player: Player, balance: number)
	local st = states[player]
	if not st then
		return
	end
	for sku, amount in st.jingle do
		if amount > 0 then
			send("Economy", "Jingle +" .. amount .. " " .. sku, function()
				AnalyticsService:LogEconomyEvent(
					player,
					flow("Source"),
					"Jingle",
					amount,
					balance,
					transaction("Gameplay"),
					sku
				)
			end)
		end
	end
	table.clear(st.jingle)
end

-- run: a Run (uses run.order, run.mapId). Call when the take-off begins.
function Analytics.runStarted(run)
	local r: RunState = {
		id = HttpService:GenerateGUID(false),
		map = tostring(run.mapId or "?"),
		crew = Funnels.crewLabel(#run.order),
		steps = {},
		runs = {},
		escaped = {},
	}
	runs[run] = r
	for _, player in run.order do
		local n = 1
		if
			store
			and store.update(player, function(d)
				if type(d.analytics) == "table" then
					d.analytics.runs = (d.analytics.runs or 0) + 1
					n = d.analytics.runs
				end
			end)
		then
			r.runs[player] = n
		end
		runStep(run, player, "RunStarted")
		Analytics.reach(player, "RunStarted")
		if n >= 2 then
			Analytics.reach(player, "SecondRun")
		end
	end
end

-- The sleigh landed at a stop (index from 1; the Lair is the last).
function Analytics.stopReached(run, index: number)
	for _, player in run.order do
		runStep(run, player, Funnels.stopId(index))
		Analytics.reach(player, Funnels.stopId(index))
	end
end

-- The sleigh left a stop. jingleOf(player) = their Jingle now.
function Analytics.stopLeft(run, index: number, aboard: { Player }, jingleOf: (Player) -> number?)
	local r = runs[run]
	local last = index >= #Config.Run.StopKinds
	for _, player in run.order do
		local balance = jingleOf(player)
		if balance then
			flushJingle(player, balance)
		end
		if r and last then
			r.escaped[player] = table.find(aboard, player) ~= nil
		end
	end
end

-- The results screen is up: these players finished the run.
function Analytics.runFinished(run)
	local r = runs[run]
	for _, player in run.order do
		runStep(run, player, "Finished")
		Analytics.reach(player, "Finished")
		if r then
			Analytics.custom(
				player,
				"RunEnd",
				1,
				if r.escaped[player] then "Escaped" else "Missed the last sleigh",
				Funnels.runsLabel(r.runs[player] or 1),
				r.map
			)
		end
	end
	runs[run] = nil
end

-- A player left a run before the results. how: "Quit the game" or "Left the crew".
function Analytics.leftRun(player: Player, run, how: string, jingle: number?)
	if not runs[run] or run.ended then
		return
	end
	if jingle then
		flushJingle(player, jingle)
	end
	Analytics.custom(
		player,
		"LeftRun",
		1,
		Funnels.runSpot(run.stopIndex or 0, run.phase),
		experience(player),
		how
	)
end

-- Jingle earned (added up; sent when the sleigh leaves the stop).
function Analytics.earnJingle(player: Player, amount: number, source: string)
	local st = states[player]
	if st and amount > 0 then
		st.jingle[source] = (st.jingle[source] or 0) + amount
	end
end

-- Jingle spent on something (sent at once; buys are rare).
function Analytics.spendJingle(player: Player, amount: number, balance: number, sku: string)
	if amount <= 0 or not states[player] then
		return
	end
	send("Economy", "Jingle -" .. amount .. " " .. sku, function()
		AnalyticsService:LogEconomyEvent(
			player,
			flow("Sink"),
			"Jingle",
			amount,
			balance,
			transaction(if sku == "VaultDoor" then "Gameplay" else "Shop"),
			sku
		)
	end)
end

----------------------------------------------------------------------------
-- Coal, the store and purchases
----------------------------------------------------------------------------

-- Coal in (Source) or out (Sink). kind: "Gameplay", "Shop" or "IAP".
function Analytics.coal(
	player: Player,
	flowType: string,
	amount: number,
	balance: number,
	kind: string,
	sku: string
)
	if amount <= 0 then
		return
	end
	local sign = if flowType == "Sink" then "-" else "+"
	send("Economy", "Coal " .. sign .. amount .. " " .. sku, function()
		AnalyticsService:LogEconomyEvent(
			player,
			flow(flowType),
			"Coal",
			amount,
			balance,
			transaction(kind),
			sku
		)
	end)
end

local function shopStep(player: Player, id: string)
	local st = states[player]
	if not st then
		return
	end
	local step = Funnels.step(Funnels.Shop, id) :: number
	local t = Util.now()
	local session = st.shop
	local stale = session and (session.step >= #Funnels.Shop or t - session.at > Analytics.ShopSessionSeconds)
	if id == "Opened" and session and not stale then
		session.at = t
		return -- toggled the panel: same visit
	end
	if not session or stale then
		session = { id = HttpService:GenerateGUID(false), step = 0, at = t }
		st.shop = session
	end
	local s = session :: any
	s.at = t
	if step <= s.step then
		return
	end
	s.step = step
	local name = Funnels.Shop[step].name
	local data = dataOf(player)
	local extra = if step == 1
		then fields(
			experience(player),
			Funnels.playtimeLabel(if data then data.playSeconds or 0 else 0),
			placeKind
		)
		else nil
	send("Shop", step .. " " .. name, function()
		AnalyticsService:LogFunnelStepEvent(player, Funnels.Names.Shop, s.id, step, name, extra)
	end)
end

function Analytics.shopOpened(player: Player)
	shopStep(player, "Opened")
end

function Analytics.shopPrompted(player: Player, _itemId: string)
	shopStep(player, "Prompted")
end

-- A Robux purchase was granted (products and passes). item: Config.Store item.
function Analytics.purchased(player: Player, item: any)
	if not states[player] then
		return
	end
	shopStep(player, "Bought")
	local data = dataOf(player)
	local played = Funnels.playtimeLabel(if data then data.playSeconds or 0 else 0)
	local price = if type(item.price) == "number" then item.price else 1
	Analytics.custom(player, "Purchase", price, item.id, played, placeKind)
	if data and not data.analytics.bought then
		store.update(player, function(d)
			d.analytics.bought = true
		end)
		Analytics.custom(
			player,
			"FirstPurchase",
			price,
			item.id,
			played,
			Funnels.runsLabel(data.analytics.runs or 0)
		)
	end
end

----------------------------------------------------------------------------
-- Tips and custom events
----------------------------------------------------------------------------

-- A custom event for one player (Creator Dashboard > Analytics > Custom).
function Analytics.custom(player: Player, name: string, value: number?, a: string?, b: string?, c: string?)
	local extra = fields(a, b, c)
	send("Custom", name .. (if a then " " .. a else ""), function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, extra)
	end)
end

-- kind: "Shown" (once per tip per server), "Done", or "Off" (switched tips off).
function Analytics.tip(player: Player, kind: string, id: string?)
	local st = states[player]
	if not st then
		return
	end
	if kind == "Shown" and id then
		st.lastTip = id
		if st.tips[id] then
			return
		end
		st.tips[id] = true
		Analytics.custom(player, "TipShown", 1, id, placeKind)
	elseif kind == "Done" and id then
		Analytics.custom(player, "TipDone", 1, id, placeKind)
	elseif kind == "Off" then
		Analytics.custom(player, "TipsOff", 1, st.lastTip or "None", placeKind)
	end
end

----------------------------------------------------------------------------
-- Setup
----------------------------------------------------------------------------

local function added(player: Player)
	if states[player] then
		return
	end
	states[player] = { status = nil, early = 0, tips = {}, jingle = {} }
	decide(player)
end

-- kind: "Lobby" or "Run". s: the shared PlayerData module.
function Analytics.start(kind: string, s: Store)
	placeKind = kind
	store = s
	if started then
		return
	end
	started = true
	for _, problem in Funnels.validate() do
		warn("[Analytics] " .. problem)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(added, player) -- waits for saved data
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- Lobby and RunHost log where the player left from in their own
		-- PlayerRemoving handlers, which may run after this one.
		local st = states[player]
		task.delay(Analytics.ForgetSeconds, function()
			if states[player] == st then
				states[player] = nil
			end
		end)
	end)
end

-- Tests: what was sent (kind and a readable name), oldest first.
function Analytics._sent(): { { kind: string, name: string } }
	return table.clone(sentLog)
end

function Analytics._state(player: Player): PlayerState?
	return stateOf(player)
end

function Analytics._reset()
	store = nil
	placeKind = "Lobby"
	started = false
	states = {}
	runs = setmetatable({}, { __mode = "k" }) :: any
	window = { startedAt = -math.huge, sent = 0 }
	sentLog = {}
end

return Analytics
