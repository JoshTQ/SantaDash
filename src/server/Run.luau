--[[
	One crew's run: take-off, the house stops and Krampus's Lair, then results.

	Each stop: 0:00-0:45 sneak, 0:45 lights on (Heat rises), 1:30 horn,
	2:00 the sleigh leaves with or without you. Miss it and you run to the next
	stop on foot. Krampus comes from Stop 3 (Config.Krampus.FirstStop), so in
	the launch slice he is only in his Lair. Escaping the Lair doubles loot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Maps = require(ReplicatedStorage.Shared.Maps)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local Assets = require(script.Parent.Assets)
local ElfBot = require(script.Parent.ElfBot)
local ElfBrain = require(script.Parent.ElfBrain)
local Loot = require(script.Parent.Loot)
local KrampusBrain = require(script.Parent.KrampusBrain)
local Krampus = require(script.Parent.Krampus)
local MapBuilder = require(script.Parent.MapBuilder)
local MapFeatures = require(script.Parent.MapFeatures)

local now, rootOf, humanoidOf = Util.now, Util.rootOf, Util.humanoidOf

-- Run-only fields on top of Loot.PlayerState.
type PlayerState = Loot.PlayerState & {
	perks: { [string]: boolean },
	hidden: any?, -- the MapBuilder.HideSpot they are in
	captive: boolean,
	breath: number,
	lastTapAt: number,
	characterConnection: RBXScriptConnection,
}

local TICK = 0.25
local NOISY_PHASES = { Sneak = true, LightsOn = true, Horn = true }

local Run = {}
Run.__index = Run

-- lastMap: the map this crew just played, so the next run picks another.
function Run.new(
	slot: number,
	crew: { Player },
	onFinished: (run: any, survivors: { Player }) -> (),
	lastMap: string?
)
	local self = setmetatable({}, Run)
	self.slot = slot
	self.hud = Remotes.get("Hud")
	self.onFinished = onFinished
	self.players = {} :: { [Player]: PlayerState }
	self.order = {} :: { Player } -- join order, for seats
	self.phase = "Takeoff"
	self.stopIndex = 0
	self.noise = 0
	self.sentNoise = -1
	self.noiseFull = false
	self.lastNoisePos = nil :: Vector3?
	self.krampus = nil
	self.ended = false
	self.featureCleanups = {} :: { () -> () }
	self.times = { departAt = 0 }

	local rng = Random.new()
	local map = Maps.get(Maps.pick(rng, lastMap))
	self.mapId = map.id
	local stopCount = #Config.Run.StopKinds
	local plans, onFoot = {}, {}
	for i = 1, stopCount do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots)
		if i < stopCount then
			onFoot[i] = Loot.planOnFoot(rng)
		end
	end
	self.route = MapBuilder.buildRoute(workspace, slot, rng, plans, onFoot, {
		yieldEach = task.wait, -- spread the build over frames so the server doesn't stall
		map = map,
		dressing = Assets.mapDressing(map.dressing),
		cocoa = Assets.clone("CocoaMachine", { "Body", "BuyPrompt" }),
		sleigh = Assets.clone("Sleigh", { "Body", "Seat1", "Hitch" }),
		reindeer = Assets.get("Reindeer"),
	})
	self.deck = self.route.startDeck

	for _, player in crew do
		self:_addPlayer(player)
	end
	-- Solo: elf bots (a mix of designs A and D) fill in for friends, at 80% loot.
	self.elves = {}
	self.elfVariants = {}
	if ElfBrain.wantsBots(#crew) then
		self.elfVariants = ElfBrain.pickVariants(rng, Config.ElfBots.Count)
		for _, st in self.players do
			st.lootMultiplier = Config.ElfBots.SoloLootMultiplier
		end
	end
	self:_wirePrompts()
	return self
end

----------------------------------------------------------------------------
-- Messaging
----------------------------------------------------------------------------

-- target nil = everyone in the run.
function Run:_send(target: Player?, kind: string, data: any)
	if target then
		if target.Parent == Players then
			self.hud:FireClient(target, kind, data)
		end
		return
	end
	for player in self.players do
		self:_send(player, kind, data)
	end
end

function Run:_banner(target: Player?, text: string, seconds: number?)
	self:_send(target, "Banner", { text = text, seconds = seconds or 3 })
end

function Run:_sendPlayer(player: Player)
	local st = self.players[player]
	if st then
		self:_send(player, "Player", {
			jingle = st.jingle,
			sackCount = st.sackCount,
			sackValue = st.sackValue,
			banked = st.banked,
			rush = st.perks.PeppermintRush == true,
		})
	end
end

function Run:_sendStop()
	local stop = self.route.stops[self.stopIndex]
	self:_send(nil, "Stop", {
		stop = self.stopIndex,
		isFinale = stop ~= nil and stop.plan.escapeMultiplier ~= nil,
		phase = self.phase,
		departAt = self.times.departAt,
	})
end

function Run:_sendNoise()
	local rounded = math.floor(self.noise)
	if rounded ~= self.sentNoise then
		self.sentNoise = rounded
		self:_send(nil, "Noise", { value = rounded })
	end
end

----------------------------------------------------------------------------
-- Players
----------------------------------------------------------------------------

function Run:_addPlayer(player: Player)
	local st = Loot.newPlayerState() :: PlayerState
	st.perks = {}
	st.captive = false
	st.breath = 1
	st.lastTapAt = 0
	-- Respawns (reset button, falling off the map) put you back on the sleigh.
	st.characterConnection = player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		if self.players[player] == st then
			if st.hidden then
				st.hidden.occupant = nil
				st.hidden = nil
			end
			if st.captive and self.krampus then
				self.krampus:release()
			end
			self:_applyPerks(player)
			Util.teleport(player, self.deck * self.route.seatOffsets[1])
		end
	end)
	self.players[player] = st
	table.insert(self.order, player)
end

function Run:hasPlayer(player: Player): boolean
	return self.players[player] ~= nil
end

function Run:removePlayer(player: Player)
	local st = self.players[player]
	if not st then
		return
	end
	if st.captive and self.krampus then
		self.krampus:release()
	end
	self:_unhide(player)
	self:_removeElves(player)
	st.characterConnection:Disconnect()
	self.players[player] = nil
	Util.removeValue(self.order, player)
	self:_resetCharacter(player)
	self:_send(player, "RunEnd", {})
end

function Run:_isEmpty(): boolean
	return next(self.players) == nil
end

function Run:_applyPerks(player: Player)
	local st = self.players[player]
	local humanoid = humanoidOf(player)
	if st and humanoid then
		humanoid.WalkSpeed = if st.perks.PeppermintRush
			then Config.Buys.PeppermintRush.WalkSpeed
			else Config.Player.WalkSpeed
	end
end

function Run:_resetCharacter(player: Player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.WalkSpeed = Config.Player.WalkSpeed
	end
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
end

-- The state of a Santa who is free to act (not snatched, not in a wardrobe).
function Run:_free(player: Player): PlayerState?
	local st = self.players[player]
	if st and not st.captive and not st.hidden and not self.ended then
		return st
	end
	return nil
end

----------------------------------------------------------------------------
-- Prompts: grabs, buys, chimneys, hiding
----------------------------------------------------------------------------

function Run:_wirePrompts()
	-- Prompts live under the route model, so destroying it disconnects these.
	local function on(prompt: ProximityPrompt, handler: (Player) -> ())
		prompt.Triggered:Connect(handler)
	end
	local function wirePresents(list)
		for _, present in list do
			on(present.prompt, function(player)
				self:_grab(player, present)
			end)
		end
	end
	for _, stop in self.route.stops do
		wirePresents(stop.presents)
		on(stop.cocoaPrompt, function(player)
			self:_buyPeppermintRush(player)
		end)
		if stop.vaultPrompt then
			on(stop.vaultPrompt, function(player)
				self:_buyVault(player, stop)
			end)
		end
		for _, chimney in stop.chimneys do
			on(chimney.down, function(player)
				if self:_free(player) then
					Util.teleport(player, chimney.inside)
				end
			end)
			on(chimney.up, function(player)
				if self:_free(player) then
					Util.teleport(player, chimney.roof)
				end
			end)
		end
		for _, spot in stop.hideSpots do
			on(spot.prompt, function(player)
				self:_hide(player, spot)
			end)
		end
	end
	wirePresents(self.route.onFootPresents)
end

function Run:_grab(player: Player, present)
	local st = self:_free(player)
	local root = rootOf(player)
	if st and root then
		self:_collect(player, st, present, root.Position)
	end
end

-- A present goes into player's sack (grabbed by them or fetched by their elf).
function Run:_collect(player: Player, st: PlayerState, present, from: Vector3)
	if present.taken then
		return
	end
	if not Loot.grab(st, present.plan) then
		self:_banner(player, "Sack full! Get back on the sleigh to bank it.", 2)
		return
	end
	present.taken = true
	self.lastNoisePos = from
	present.model:Destroy()
	self:_addNoise(Loot.noiseForGrab(math.max(self.stopIndex, 1), present.plan.threats))
	self:_sendPlayer(player)
	if present.plan.naughtyList then
		self:_banner(nil, player.DisplayName .. " stole the Naughty List! Get to the sleigh!", 4)
	end
end

-- Elf bot hooks (called by ElfBot.luau).
function Run:canElfGrab(owner: Player): boolean
	local st = self.players[owner]
	return st ~= nil
		and not self.ended
		and NOISY_PHASES[self.phase] == true
		and st.sackCount < Config.Sack.Capacity
end

function Run:elfCollect(owner: Player, present, from: Vector3)
	local st = self.players[owner]
	if st and self:canElfGrab(owner) then
		self:_collect(owner, st, present, from)
	end
end

-- Untaken presents on the current street and the paths between stops.
function Run:presentCandidates(): { ElfBrain.PresentCandidate }
	local list = {}
	local stop = self.route.stops[self.stopIndex]
	local vaultShut = stop ~= nil and stop.vaultPrompt ~= nil and stop.vaultPrompt.Enabled
	local function add(presents)
		for _, present in presents do
			if not present.taken and not (present.inVault and vaultShut) then
				table.insert(list, { present = present, position = present.model:GetPivot().Position })
			end
		end
	end
	if stop then
		add(stop.presents)
	end
	add(self.route.onFootPresents)
	return list
end

function Run:_spawnElves()
	for _, owner in self.order do
		for i, variant in self.elfVariants do
			local at = self.deck * CFrame.new(ElfBrain.followOffset(i) + Vector3.new(0, 3, 0))
			table.insert(self.elves, ElfBot.new(self, owner, variant, i, at))
		end
	end
	self.elfVariants = {} -- spawned once, then they follow their Santa all run
end

function Run:_removeElves(owner: Player?)
	for i = #self.elves, 1, -1 do
		local elf = self.elves[i]
		if not owner or elf.owner == owner then
			elf:destroy()
			table.remove(self.elves, i)
		end
	end
end

-- Spends Jingle; returns true on success. Callers send the Player update.
function Run:_spend(player: Player, cost: number): boolean
	local st = self:_free(player)
	if not st then
		return false
	end
	if st.jingle < cost then
		self:_banner(player, "Need " .. (cost - st.jingle) .. " more Jingle", 2)
		return false
	end
	st.jingle -= cost
	self:_addNoise(Config.Noise.PerBuy)
	return true
end

function Run:_buyPeppermintRush(player: Player)
	local st = self.players[player]
	if st and st.perks.PeppermintRush then
		self:_banner(player, "You already have Peppermint Rush", 2)
	elseif st and self:_spend(player, Config.Buys.PeppermintRush.Cost) then
		st.perks.PeppermintRush = true
		self:_applyPerks(player)
		self:_sendPlayer(player)
		self:_banner(player, "Peppermint Rush! You're faster until Krampus catches you.", 3)
	end
end

function Run:_buyVault(player: Player, stop)
	local prompt = stop.vaultPrompt
	if prompt.Enabled and self:_spend(player, Config.Buys.VaultDoor.Cost) then
		prompt.Enabled = false
		stop.vaultDoor.CanCollide = false
		stop.vaultDoor.Transparency = 0.85
		self:_sendPlayer(player)
		self:_banner(nil, player.DisplayName .. " opened the vault!", 3)
	end
end

function Run:_hide(player: Player, spot)
	local st = self:_free(player)
	local root = rootOf(player)
	if not st or not root or spot.occupant then
		return
	end
	spot.occupant = player
	st.hidden = spot
	st.breath = 1
	root.Anchored = true
	root.CFrame = spot.inside
	self:_send(player, "Hide", { hidden = true, breath = 1 })
end

function Run:_unhide(player: Player)
	local st = self.players[player]
	if not st or not st.hidden then
		return
	end
	local spot = st.hidden
	spot.occupant = nil
	st.hidden = nil
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	Util.teleport(player, spot.exit)
	self:_send(player, "Hide", { hidden = false })
end

-- Client input: taps (breath while hiding, wiggling while snatched) and leaving a hiding spot.
function Run:onInput(player: Player, action: string)
	local st = self.players[player]
	if not st or self.ended then
		return
	end
	if action == "Unhide" then
		self:_unhide(player)
	elseif action == "Tap" then
		local t = now()
		if not KrampusBrain.tapAllowed(st.lastTapAt, t) then
			return
		end
		st.lastTapAt = t
		if st.captive and self.krampus then
			self.krampus:wiggle(player)
		elseif st.hidden then
			st.breath = KrampusBrain.tapBreath(st.breath)
			self:_send(player, "Hide", { hidden = true, breath = st.breath })
		end
	end
end

function Run:_addNoise(amount: number)
	if not NOISY_PHASES[self.phase] then
		return
	end
	self.noise = math.min(Config.Noise.Max, self.noise + amount)
	self.noiseFull = self.noiseFull or self.noise >= Config.Noise.Max
	self:_sendNoise()
end

----------------------------------------------------------------------------
-- Krampus hooks (called by Krampus.luau)
----------------------------------------------------------------------------

function Run:krampusCandidates(ignore: { [Player]: number }): { KrampusBrain.Candidate }
	local list = {}
	for player, st in self.players do
		local root = rootOf(player)
		if root then
			table.insert(list, {
				player = player,
				position = root.Position,
				hidden = st.hidden ~= nil,
				captive = st.captive,
				aboard = MapBuilder.isAboard(self.deck, root.Position),
				ignoreUntil = ignore[player],
			})
		end
	end
	return list
end

-- Breath for every hidden Santa, given Krampus's position. Running out = a loud gasp.
function Run:krampusBreath(from: Vector3, dt: number)
	for player, st in self.players do
		local spot = st.hidden
		if spot then
			local before = st.breath
			st.breath = KrampusBrain.breathStep(st.breath, (spot.inside.Position - from).Magnitude, dt)
			if st.breath <= 0 then
				self:_unhide(player)
				self.lastNoisePos = spot.exit.Position
				self:_addNoise(Config.Noise.Gasp)
				self:_banner(nil, player.DisplayName .. " gasped for air!", 2)
			elseif st.breath ~= before then
				self:_send(player, "Hide", { hidden = true, breath = st.breath })
			end
		end
	end
end

function Run:onSnatched(player: Player)
	local st = self.players[player]
	if not st then
		return
	end
	self:_unhide(player)
	st.captive = true
	st.perks = {} -- cocoa perks are lost when snatched
	self:_applyPerks(player)
	self:_sendPlayer(player)
	local root = rootOf(player)
	if root then
		root.Anchored = true
	end
	self:_banner(nil, "Krampus snatched " .. player.DisplayName .. "! Ring the bells behind him!", 3)
	self:_send(player, "Captive", { captive = true, wiggles = 0, needed = KrampusBrain.wiggleNeeded() })
end

function Run:onReleased(player: Player, at: CFrame)
	local st = self.players[player]
	if not st then
		return
	end
	st.captive = false
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	Util.teleport(player, at)
	self:_send(player, "Captive", { captive = false })
end

function Run:_startKrampus(stop)
	self:_banner(nil, "KRAMPUS IS COMING!", Config.Krampus.WarningSeconds)
	for _, light in stop.lights do
		light.Enabled = true
		light.Color = Color3.fromRGB(255, 60, 60)
	end
	self.krampus = Krampus.new(self, stop)
	self:_send(nil, "Krampus", { model = self.krampus.body.model })
end

function Run:_stopKrampus()
	if self.krampus then
		self.krampus:destroy()
		self.krampus = nil
		self:_send(nil, "Krampus", {})
	end
end

-- Map features with runtime behaviour (MapFeatures start hooks) for one stop.
function Run:_startFeatures(stop)
	for _, feature in self.route.map.features do
		local entry = MapFeatures[feature.kind]
		if entry and entry.start then
			local ok, cleanup = pcall(entry.start, { run = self, stop = stop, feature = feature })
			if not ok then
				warn("[Run] map feature " .. feature.kind .. " failed to start: " .. tostring(cleanup))
			elseif cleanup then
				table.insert(self.featureCleanups, cleanup)
			end
		end
	end
end

function Run:_stopFeatures()
	for _, cleanup in self.featureCleanups do
		local ok, err = pcall(cleanup)
		if not ok then
			warn("[Run] map feature cleanup failed: " .. tostring(err))
		end
	end
	self.featureCleanups = {}
end

----------------------------------------------------------------------------
-- Sleigh flight
----------------------------------------------------------------------------

function Run:_fly(fromDeck: CFrame, toDeck: CFrame, riders: { Player })
	self.phase = "Flight"
	self:_sendStop()

	local seats: { [BasePart]: CFrame } = {}
	for i, player in riders do
		local root = rootOf(player)
		if root then
			local offsets = self.route.seatOffsets
			seats[root] = offsets[(i - 1) % #offsets + 1]
			root.Anchored = true
		end
	end

	local sleigh = self.route.sleigh
	local function place(deck: CFrame)
		self.deck = deck
		sleigh:PivotTo(deck)
		for root, seat in seats do
			if root.Parent then
				root.CFrame = deck * seat
			end
		end
	end

	local started = os.clock()
	local connection = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - started) / Config.Run.FlightSeconds, 0, 1)
		place(fromDeck:Lerp(toDeck, a) + Vector3.yAxis * math.sin(a * math.pi) * Config.Run.FlightArcHeight)
	end)
	task.wait(Config.Run.FlightSeconds)
	connection:Disconnect()
	place(toDeck)
	for root in seats do
		root.Anchored = false
	end
end

----------------------------------------------------------------------------
-- Stops
----------------------------------------------------------------------------

function Run:_allAboard(deck: CFrame): boolean
	for player in self.players do
		local root = rootOf(player)
		if not root or not MapBuilder.isAboard(deck, root.Position) then
			return false
		end
	end
	return true
end

-- Plays one stop and returns the players on board when the sleigh leaves.
function Run:_playStop(stop): { Player }
	local plan = stop.plan
	local t0 = now()
	self.stopIndex = plan.index
	self.noise = 0
	self.noiseFull = false
	self.lastNoisePos = nil
	self.phase = "Sneak"
	self.times = { departAt = t0 + Config.Run.StopSeconds }
	self:_sendStop()
	self:_sendNoise()
	self:_banner(nil, plan.banner, 4)
	if #self.elfVariants > 0 then
		self:_spawnElves() -- elves hop off with their Santa at the first stop
	end
	self:_startFeatures(stop)

	-- Timed phases, entered in order once their time has passed.
	local phases = {
		{
			at = t0 + Config.Run.LightsOnAt,
			phase = "LightsOn",
			enter = function()
				for _, light in stop.lights do
					light.Enabled = true
				end
				self:_banner(nil, "The lights are on! Heat is rising.", 3)
			end,
		},
		{
			at = t0 + Config.Run.HornAt,
			phase = "Horn",
			enter = function()
				local left = Config.Run.StopSeconds - Config.Run.HornAt
				self:_banner(nil, "HONK! The sleigh leaves in " .. left .. " seconds!", 3)
			end,
		},
	}
	local nextPhase = 1
	local teased = false

	while true do
		task.wait(TICK)
		if self.ended or self:_isEmpty() then
			break
		end
		local t = now()
		while phases[nextPhase] and t >= phases[nextPhase].at do
			local p = phases[nextPhase]
			nextPhase += 1
			self.phase = p.phase
			p.enter()
			self:_sendStop()
		end
		if self.phase ~= "Sneak" then
			self:_addNoise(Config.Noise.LightsOnPerSecond * TICK)
		end
		if not self.krampus then
			if KrampusBrain.shouldArrive(plan.index, plan.kindName, t - t0, self.noiseFull) then
				self:_startKrampus(stop)
			elseif not teased and KrampusBrain.shouldTease(plan.index, t - t0) then
				teased = true -- heard, not seen: no chase yet
				self:_banner(nil, "Distant sleigh bells... something big is out there. Stay quiet!", 4)
				self:_send(nil, "KrampusTease", {})
			end
		end
		if t >= self.times.departAt then
			break
		end
		if self.phase == "Horn" and self:_allAboard(stop.deckCFrame) then
			break -- the whole crew is on: no need to wait
		end
	end

	self:_stopFeatures()
	self:_stopKrampus()
	local aboard = {}
	for _, player in table.clone(self.order) do
		local st = self.players[player]
		local root = rootOf(player)
		self:_unhide(player)
		if st and root and MapBuilder.isAboard(stop.deckCFrame, root.Position) then
			table.insert(aboard, player)
			Loot.bank(st, plan.escapeMultiplier)
			self:_sendPlayer(player)
		elseif st and plan.escapeMultiplier then
			Loot.bankMissed(st)
			self:_sendPlayer(player)
			self:_banner(player, "You missed the last sleigh! Half your sack fell out.", 4)
		elseif st then
			self:_banner(player, "You missed the sleigh! Follow the path to the next stop.", 4)
		end
	end
	return aboard
end

----------------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------------

function Run:start()
	task.spawn(function()
		local ok, err = pcall(self._main, self)
		if not ok then
			warn("[Run] slot " .. self.slot .. " crashed: " .. tostring(err))
		end
		self:_finish()
	end)
end

function Run:_main()
	self:_banner(
		nil,
		"Take-off for " .. self.route.map.name .. "! Rob the houses, then escape Krampus's Lair.",
		4
	)
	for player in self.players do
		self:_sendPlayer(player)
	end

	local stops = self.route.stops
	self:_fly(self.route.startDeck, stops[1].deckCFrame, table.clone(self.order))
	for i, stop in stops do
		if self.ended or self:_isEmpty() then
			return
		end
		local aboard = self:_playStop(stop)
		if stops[i + 1] and not self:_isEmpty() then
			self:_fly(stop.deckCFrame, stops[i + 1].deckCFrame, aboard)
		end
	end

	if not self:_isEmpty() then
		self.phase = "Results"
		local entries = {}
		for player, st in self.players do
			table.insert(entries, { player.DisplayName, st })
		end
		self:_send(nil, "Results", {
			rows = Loot.results(entries),
			endsAt = now() + Config.Run.ResultsSeconds + Config.Run.RequeueSeconds,
		})
		task.wait(Config.Run.ResultsSeconds)
	end
end

function Run:_finish()
	if self.ended then
		return
	end
	self:_stopFeatures()
	self:_stopKrampus()
	self:_removeElves()
	self.ended = true
	local survivors = {}
	for _, player in self.order do
		self.players[player].characterConnection:Disconnect()
		if player.Parent == Players then
			table.insert(survivors, player)
			self:_resetCharacter(player)
			self:_send(player, "RunEnd", {})
		end
	end
	self.players = {}
	self.route.model:Destroy()
	self.onFinished(self, survivors)
end

return Run
