--[[
	One crew's run: take-off, the house stops and Krampus's Lair, then results.

	Each stop: 0:00-0:45 sneak, 0:45 lights on (the noise meter creeps up), 1:30 horn,
	2:00 the sleigh leaves with or without you. Miss it and you run to the next
	stop on foot. Krampus comes from Stop 3 (Config.Krampus.FirstStop), so in
	the launch slice he is only in his Lair. Escaping the Lair doubles loot,
	but only with the Naughty List aboard (NaughtyList, CuckooWatch).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Cutscenes = require(ReplicatedStorage.Shared.Cutscenes)
local Maps = require(ReplicatedStorage.Shared.Maps)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)
local Puppets = require(ReplicatedStorage.Shared.Puppets)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local AlarmDogs = require(script.Parent.AlarmDogs)
local YardDogs = require(script.Parent.YardDogs)
local Assets = require(script.Parent.Assets)
local ElfBot = require(script.Parent.ElfBot)
local ElfBrain = require(script.Parent.ElfBrain)
local Loot = require(script.Parent.Loot)
local CuckooWatch = require(script.Parent.CuckooWatch)
local ListBrain = require(script.Parent.ListBrain)
local NaughtyList = require(script.Parent.NaughtyList)
local KrampusBrain = require(script.Parent.KrampusBrain)
local Krampus = require(script.Parent.Krampus)
local MapBuilder = require(script.Parent.MapBuilder)
local Analytics = require(script.Parent.Analytics)
local MapEventBrain = require(script.Parent.MapEventBrain)
local MapEvents = require(script.Parent.MapEvents)
local MapFeatures = require(script.Parent.MapFeatures)
local NoiseAlarm = require(script.Parent.NoiseAlarm)
local HouseChecks = require(script.Parent.HouseChecks)
local LightsCheck = require(script.Parent.LightsCheck)
local Onboarding = require(script.Parent.Onboarding)
local SantaCharacter = require(script.Parent.SantaCharacter)
local HouseKit = require(script.Parent.HouseKit)
local LairBuilder = require(script.Parent.LairBuilder)
local Store = require(script.Parent.Store)
local ServerWardrobe = require(script.Parent.Wardrobe)
local StoreRules = require(ReplicatedStorage.Shared.StoreRules)
local Wardrobe = require(ReplicatedStorage.Shared.Wardrobe)
local BodyHeat = require(ReplicatedStorage.Shared.BodyHeat)

local now, rootOf, humanoidOf = Util.now, Util.rootOf, Util.humanoidOf

-- Run-only fields on top of Loot.PlayerState.
type PlayerState = Loot.PlayerState & {
	perks: { [string]: boolean },
	fastSneak: boolean, -- Fast Sneak pass
	hidden: any?, -- the MapBuilder.HideSpot they are in
	captive: boolean,
	breath: number,
	lastTapAt: number,
	characterConnection: RBXScriptConnection,
	wardrobe: { [string]: boolean }, -- warm gear owned this run (shared/Wardrobe)
	swimming: boolean?, -- in the Lair lake's water (server/Swimming)
	frozen: boolean?, -- stuck in an ice cube after running out of body heat
	soggyUntil: number?, -- slow after thawing
	iced: boolean?, -- in a Frost Zap ice cube (server/KrampusMagic)
	skidUntil: number?, -- skidding on Frost Stomp frost
	carryingList: boolean?, -- Marked: the Naughty List hovers over their head
	bones: number?, -- dog treats bought this run (Config.DogAI.Bone)
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
	self.snores = {} :: { SoundPlayer.Loop } -- sleeping parents this stop
	self.ended = false
	self.featureCleanups = {} :: { () -> () }
	self.noiseScale = 1 -- map events can muffle (or boost) all street noise
	self.eventCleanup = nil :: (() -> ())?
	self.eventInput = nil :: ((player: Player, action: string) -> ())?
	self.flightSeats = nil :: { [BasePart]: CFrame }? -- set while the sleigh is flying
	self.times = { departAt = 0 }
	self.list = nil -- the finale's NaughtyList while that stop plays
	self.cuckoo = nil -- the Lair's CuckooWatch while Krampus is home

	local rng = Random.new()
	local map = Maps.get(Maps.pick(rng, lastMap))
	self.mapId = map.id
	local stopCount = #Config.Run.StopKinds
	local plans, onFoot = {}, {}
	for i = 1, stopCount do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots, map.layout.StopSlots)
		if i < stopCount then
			onFoot[i] = Loot.planOnFoot(rng)
		end
	end
	self.route = MapBuilder.buildRoute(workspace, slot, rng, plans, onFoot, {
		yieldEach = task.wait, -- spread the build over frames so the server doesn't stall
		map = map,
		dressing = Assets.mapDressing(map.dressing),
		cocoa = Assets.clone("CocoaMachine", { "Body", "BuyPrompt" }),
		houseKit = {
			houses = HouseKit.variants(Assets.folder()),
			-- The approved Cuckoo Clock Den, built from parts unless Assets has a KrampusLair.
			lair = Assets.clone("KrampusLair", { "Floor", "ListPedestal", "KrampusSpawn" })
				or LairBuilder.template(),
			vaultDoor = Assets.clone("VaultDoor", { "Frame", "Door" }),
		},
		presents = HouseKit.presentVariants(Assets.folder()),
		naughtyList = Assets.get("NaughtyList"),
		sleigh = Assets.clone("Sleigh", { "Body", "Seat1", "Hitch" }),
		reindeer = Assets.get("Reindeer"),
	})
	self.deck = self.route.startDeck
	self.eventPlan = MapEventBrain.plan(rng, map, Config.Run.StopKinds)

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
	-- A Break-out bought while snatched frees the Santa straight away.
	self.unbindBreakout = Store.onBreakout(function(player)
		local st = self.players[player]
		if st and st.captive and self.krampus and Store.useBreakout(player) then
			self:_breakOut(player)
			return true
		end
		return false
	end)
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

-- Plays a cutscene (Cutscenes.luau) for one player, a list of players, or
-- the whole crew when target is nil. Clients run the camera and can skip; the
-- server never waits on them. Returns the scene length, or 0 when it is off.
function Run:_cutscene(id: string, target: Player | { Player } | nil, data: { [string]: any }): number
	local scene = Cutscenes.get(id)
	if not scene or not Config.Cutscenes.Enabled then
		return 0
	end
	data.id = id
	data.startedAt = now()
	Analytics.moment(id, scene.seconds) -- a long server frame now is blamed on this scene
	if type(target) == "table" then
		for _, player in target do
			self:_send(player, "Cutscene", data)
		end
	else
		self:_send(target, "Cutscene", data)
	end
	return scene.seconds
end

function Run:_banner(target: Player?, text: string, seconds: number?)
	self:_send(target, "Banner", { text = text, seconds = seconds or 3 })
end

-- A 2D sound for one player (or everyone): buzzers and other UI feedback.
-- Sent as the Hud kind "Sfx" { key }; Audio.client.luau plays it.
function Run:_sfx(target: Player?, key: string)
	self:_send(target, "Sfx", { key = key })
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
			sackCapacity = st.sackCapacity,
		})
	end
end

function Run:_sendStop()
	local stop = self.route.stops[self.stopIndex]
	for _, player in self.order do
		SantaCharacter.setSneaking(player, self.phase == "Sneak") -- Santas tiptoe
		self:_applyPerks(player) -- Fast Sneak only counts while sneaking
	end
	self:_send(nil, "Stop", {
		stop = self.stopIndex,
		isFinale = stop ~= nil and stop.plan.escapeMultiplier ~= nil,
		phase = self.phase,
		departAt = self.times.departAt,
		-- Where the sleigh is waiting: everyone's gold guide line points here
		-- (Josh, 6 Nov 2026: Santas who missed it couldn't find the next stop).
		sleighAt = if stop and self.phase ~= "Flight" then stop.deckCFrame.Position else nil,
		-- What a full noise meter brings here (the HUD says so under the meter).
		noiseThreat = if stop == nil
			then nil
			elseif NoiseAlarm.applies(self.stopIndex, stop.plan.kindName) then "dogs"
			elseif self.stopIndex >= Config.Krampus.NoiseArrivalFrom then "krampus"
			else nil,
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
	local owned = Store.owned(player)
	st.sackCapacity = StoreRules.sackCapacity(owned)
	st.fastSneak = owned.FastSneak == true
	st.captive = false
	st.breath = 1
	st.lastTapAt = 0
	st.bones = 0
	st.wardrobe = {}
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
			if self.list then
				self.list:forget(player) -- the old body took the book down with it
			end
			self:_applyPerks(player)
			ServerWardrobe.dress(player, st.wardrobe) -- warm gear survives a respawn
			local root = character:FindFirstChild("HumanoidRootPart")
			if self.flightSeats and root then
				-- Mid-flight: ride the rest of the way in a seat, not fall off.
				local seat = self.route.seatOffsets[1]
				self.flightSeats[root] = seat
				root.Anchored = true
				root.CFrame = self.deck * seat
			else
				Util.teleport(player, self.deck * self.route.seatOffsets[1])
			end
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
	if self.list then
		self.list:forget(player)
	end
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

-- A Santa's own WalkSpeed with their perks (map features may add to it).
function Run:baseWalkSpeed(st: PlayerState): number
	local speed = if st.perks.PeppermintRush
		then Config.Buys.PeppermintRush.WalkSpeed
		else Config.Player.WalkSpeed
	if st.fastSneak and self.phase == "Sneak" then
		speed += Config.Store.FastSneakBonus
	end
	if st.swimming then
		speed += Wardrobe.swimSpeed(st.wardrobe)
	end
	if st.carryingList then
		speed = ListBrain.carrierSpeed(speed)
	end
	if (st.soggyUntil or 0) > now() then
		speed = math.min(speed, Config.BodyHeat.SoggyWalkSpeed)
	end
	if (st.skidUntil or 0) > now() then
		speed = KrampusBrain.skidSpeed(speed)
	end
	return speed
end

function Run:_applyPerks(player: Player)
	local st = self.players[player]
	local humanoid = humanoidOf(player)
	if st and humanoid then
		humanoid.WalkSpeed = self:baseWalkSpeed(st)
	end
end

function Run:_resetCharacter(player: Player)
	SantaCharacter.setSneaking(player, false)
	player:SetAttribute(BodyHeat.ATTRIBUTE, nil)
	player:SetAttribute(BodyHeat.FROZEN_ATTRIBUTE, nil)
	ServerWardrobe.undress(player) -- warm gear is for this run only
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
	if st and not st.captive and not st.hidden and not st.frozen and not st.iced and not self.ended then
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
		if stop.bonePrompt then
			on(stop.bonePrompt, function(player)
				self:_buyBone(player)
			end)
		end
		for id, prompt in stop.wardrobePrompts or {} do
			on(prompt, function(player)
				ServerWardrobe.buy(self, player, id)
			end)
		end
		if stop.vaultPrompt then
			on(stop.vaultPrompt, function(player)
				self:_buyVault(player, stop)
			end)
		end
		for _, chimney in stop.chimneys do
			on(chimney.down, function(player)
				if self:_free(player) then
					Util.teleport(player, chimney.inside)
					SoundPlayer.at("ChimneySlide", chimney.inside.Position)
				end
			end)
			on(chimney.up, function(player)
				if self:_free(player) then
					Util.teleport(player, chimney.roof)
					SoundPlayer.at("ChimneyClimb", chimney.roof.Position)
				end
			end)
		end
		for _, spot in stop.hideSpots do
			on(spot.prompt, function(player)
				self:_hide(player, spot)
			end)
		end
		for _, secret in stop.secrets or {} do
			-- A soft bell twinkle from the hiding place, heard from the next room.
			secret.hum = SoundPlayer.loop("SecretHum", secret.trigger)
			on(secret.prompt, function(player)
				self:_findSecret(player, stop, secret)
			end)
		end
		for _, spot in stop.searchSpots or {} do
			on(spot.prompt, function(player)
				self:_searchSpot(player, stop, spot)
			end)
		end
		for _, door in stop.doors do
			on(door.prompt, function(player)
				if self:_free(player) then
					door.open = not door.open
					door.door.CFrame = HouseKit.doorCFrame(door.closed, door.door.Size, door.open)
					door.door.CanCollide = not door.open
					door.prompt.ActionText = if door.open then "Close" else "Open"
					SoundPlayer.at(if door.open then "DoorOpen" else "DoorClose", door.door)
				end
			end)
		end
	end
	wirePresents(self.route.onFootPresents)
end

function Run:_grab(player: Player, present)
	if present.plan.naughtyList and self.list and self.list.present == present then
		if self:_free(player) then
			self.list:take(player)
			Onboarding.complete(player, "Grab")
		end
		return
	end
	local st = self:_free(player)
	local root = rootOf(player)
	if st and root then
		local before = st.sackCount
		self:_collect(player, st, present, root.Position)
		if st.sackCount > before then
			SantaMoves.play(player.Character, "Grab")
			Onboarding.complete(player, "Grab")
			Onboarding.teach(player, "Carry")
			self:_teachCocoa(player, st)
		end
	end
end

----------------------------------------------------------------------------
-- First-time player tips (Onboarding, shared/Tutorial)
----------------------------------------------------------------------------

local function partAt(instance: Instance?): Vector3?
	if not instance then
		return nil
	elseif instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return partAt(instance.Parent)
end

-- The closest door of this street to `from` (where the sleigh landed).
function Run._nearestDoor(stop, from: Vector3): Vector3?
	local best, bestDistance = nil, math.huge
	for _, door in stop.doors do
		local at = door.door.CFrame.Position
		local distance = (at - from).Magnitude
		if distance < bestDistance then
			best, bestDistance = at, distance
		end
	end
	return best
end

function Run._naughtyListAt(stop): Vector3?
	for _, present in stop.presents do
		if present.plan.naughtyList and not present.taken then
			return partAt(present.prompt)
		end
	end
	return nil
end

-- Landing tips: sneak to the nearest door, or (in the Lair) go for the List.
function Run:_teachLanding(stop)
	local deckAt = stop.deckCFrame.Position
	for _, player in self.order do
		if stop.plan.escapeMultiplier then
			Onboarding.teach(player, "Lair", Run._naughtyListAt(stop))
		else
			Onboarding.teach(player, "Sneak", Run._nearestDoor(stop, deckAt))
		end
		Onboarding.teach(player, "Grab")
	end
end

function Run:_teachCocoa(player: Player, st: PlayerState)
	local stop = self.route.stops[self.stopIndex]
	if
		stop
		and stop.cocoaPrompt
		and not st.perks.PeppermintRush
		and st.jingle >= Config.Buys.PeppermintRush.Cost
	then
		Onboarding.teach(player, "Cocoa", partAt(stop.cocoaPrompt))
	end
end

-- A present goes into player's sack (grabbed by them or fetched by their elf).
function Run:_collect(player: Player, st: PlayerState, present, from: Vector3)
	if present.taken then
		return
	end
	local jingleBefore = st.jingle
	if not Loot.grab(st, present.plan) then
		self:_banner(player, "Sack full! Get back on the sleigh to bank it.", 2)
		SoundPlayer.at("SackFull", from)
		return
	end
	present.taken = true
	Analytics.grabbed(
		self,
		player,
		st.jingle - jingleBefore,
		if present.plan.naughtyList then "NaughtyList" elseif present.plan.regrab then "Regrab" else "Presents"
	)
	self.lastNoisePos = from
	present.model:Destroy()
	if present.house then
		local stop = self.route.stops[self.stopIndex]
		MapBuilder.refreshMarker(
			present.house,
			stop ~= nil and stop.vaultPrompt ~= nil and stop.vaultPrompt.Enabled
		)
	end
	SoundPlayer.at(if present.plan.naughtyList then "NaughtyListGrab" else "PresentGrab", from)
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
		and st.sackCount < st.sackCapacity
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
			-- Secret-room presents stay for Santas: an elf can't climb into a cellar.
			if
				not present.taken
				and not present.hidden
				and not present.plan.secret
				and not (present.plan.naughtyList and self.list)
				and not (present.plan.floor and present.plan.floor > 0) -- mansion upstairs: Santas only
				and not (present.inVault and vaultShut)
			then
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

-- Spends Jingle on sku (for analytics); returns true on success. Callers
-- send the Player update.
function Run:_spend(player: Player, cost: number, sku: string?): boolean
	local st = self:_free(player)
	if not st then
		return false
	end
	if st.jingle < cost then
		self:_banner(player, "Need " .. (cost - st.jingle) .. " more Jingle", 2)
		self:_sfx(player, "Nope")
		return false
	end
	st.jingle -= cost
	Analytics.spendJingle(player, cost, st.jingle, sku or "Other")
	self:_addNoise(Config.Noise.PerBuy)
	return true
end

function Run:_buyPeppermintRush(player: Player)
	local st = self.players[player]
	if st and st.perks.PeppermintRush then
		self:_banner(player, "You already have Peppermint Rush", 2)
		self:_sfx(player, "Nope")
	elseif st and self:_spend(player, Config.Buys.PeppermintRush.Cost, "PeppermintRush") then
		st.perks.PeppermintRush = true
		local root = rootOf(player)
		if root then
			SoundPlayer.at("CocoaSlurp", root.Position)
		end
		self:_applyPerks(player)
		self:_sendPlayer(player)
		self:_banner(player, "Peppermint Rush! You're faster until Krampus catches you.", 3)
	end
end

-- Dog treats (Config.DogAI.Bone): buy at the Sleigh Stop, throw with G.
function Run:_sendBones(player: Player)
	local st = self.players[player]
	if st then
		self:_send(player, "Bones", { count = st.bones or 0 })
	end
end

function Run:_buyBone(player: Player)
	local st = self.players[player]
	local B = Config.DogAI.Bone
	if st and (st.bones or 0) >= B.Max then
		self:_banner(player, "Your pockets are full of bones (" .. B.Max .. ")", 2)
		self:_sfx(player, "Nope")
	elseif st and self:_spend(player, B.Cost, "DogBone") then
		st.bones = (st.bones or 0) + 1
		self:_sendPlayer(player)
		self:_sendBones(player)
		self:_banner(player, "Dog treat! Press G (or the BONE button) to throw it and distract the dogs.", 3)
	end
end

-- Throws a bone ahead of the Santa; dogs near where it lands go and chew it.
function Run:_throwBone(player: Player)
	local st = self:_free(player)
	local root = rootOf(player)
	if not st or not root or (st.bones or 0) <= 0 then
		return
	end
	st.bones -= 1
	self:_sendBones(player)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local landing = root.Position + flat * Config.DogAI.Bone.Throw - Vector3.new(0, 2.5, 0)
	local bone = Instance.new("Part") -- GREYBOX bone (art round pending)
	bone.Name = "DogBone"
	bone.Size = Vector3.new(1.6, 0.5, 0.5)
	bone.Color = Color3.fromRGB(245, 235, 210)
	bone.Anchored = true
	bone.CanCollide = false
	bone.CFrame = CFrame.new(landing + Vector3.new(0, 0.3, 0))
	bone.Parent = self.route.model
	task.delay(Config.DogAI.Bone.ChewSeconds + Config.DogAI.Bone.GiveUp, function()
		bone:Destroy()
	end)
	local dogs = 0
	for _, pack in self.dogPacks or {} do
		dogs += pack.distract(landing)
	end
	self:_banner(
		player,
		if dogs > 0 then "Fetch, doggy! The dogs are after the bone." else "Bone thrown... no dogs near it.",
		2
	)
end

function Run:_buyVault(player: Player, stop)
	local prompt = stop.vaultPrompt
	if prompt.Enabled and self:_spend(player, Config.Buys.VaultDoor.Cost, "VaultDoor") then
		prompt.Enabled = false
		for _, house in stop.houses or {} do
			if house.locked then
				MapBuilder.refreshMarker(house, false)
			end
		end
		local vaultDoor = stop.vaultDoor
		vaultDoor.CFrame = HouseKit.doorCFrame(vaultDoor.CFrame, vaultDoor.Size, true)
		vaultDoor.CanCollide = false
		if stop.vaultBlocker then
			stop.vaultBlocker.CanCollide = false
		end
		SoundPlayer.at("VaultOpen", vaultDoor)
		self:_sendPlayer(player)
		self:_banner(nil, player.DisplayName .. " opened the vault!", 3)
	end
end

-- Someone held Search on a secret room's bookcase / rug / hatch (Room Mix
-- houses, Josh 6 Nov 2026): it opens, glows gold for the whole crew, the
-- Big present inside can be grabbed, and the finder gets a Jingle bonus.
function Run:_findSecret(player: Player, stop, secret)
	local st = self:_free(player)
	if not st or secret.found then
		return
	end
	secret.found = true
	secret.prompt.Enabled = false
	if secret.hum then
		secret.hum.stop(0.5)
		secret.hum = nil
	end
	for _, d in secret.model:GetDescendants() do
		if d:IsA("BasePart") then
			local open = d:GetAttribute("Open")
			if typeof(open) == "CFrame" then
				d.CFrame = d.CFrame * open
			end
			if d.Name == "SecretReveal" then
				d.Transparency = 0
			elseif d.Name == "SecretGlow" then
				d.Transparency = 0.35
			end
		elseif d:IsA("PointLight") then
			d.Enabled = true
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	if secret.climb then
		secret.climb.down.Enabled = true
		secret.climb.up.Enabled = true
	end
	local present = secret.present
	if present and not present.taken then
		present.hidden = nil
		present.prompt.Enabled = true
	end
	for _, house in stop.houses or {} do
		if house.secret == secret then
			MapBuilder.refreshMarker(house, stop.vaultPrompt ~= nil and stop.vaultPrompt.Enabled)
		end
	end
	st.jingle += Config.Houses.Secret.FinderJingle
	Analytics.earnJingle(player, Config.Houses.Secret.FinderJingle, "SecretRoom")
	Analytics.secretFound(self, player, secret.kind)
	SoundPlayer.at("SecretFound", secret.trigger)
	self:_sfx(player, "JingleGain")
	self:_sendPlayer(player)
	self:_banner(nil, player.DisplayName .. " found a secret room! The best gift in the house is inside.", 3)
end

-- Someone held Search on a Gingerbread Mansion spot (HouseKit.wireSearch).
-- It opens and glows gold for the crew. A hidden gift becomes grabbable; an
-- empty spot gives a dust puff and a small tip; a decoy box under the tree
-- goes POP and the piano is a noisy trap.
function Run:_searchSpot(player: Player, stop, spot)
	local st = self:_free(player)
	if not st or spot.searched then
		return
	end
	local M = Config.Mansion
	spot.searched = true
	spot.prompt.Enabled = false
	if spot.kind == "Piano" then
		SoundPlayer.at("PianoPlonk", spot.trigger)
		self:_addNoise(M.PianoNoise)
		self:_banner(player, "PLONK! The piano was a trap. The whole house heard that.", 3)
		return
	end
	local function emit(name: string, count: number, colour: Color3?)
		local fx = spot.trigger:FindFirstChild(name)
		if fx and fx:IsA("ParticleEmitter") then
			if colour then
				fx.Color = ColorSequence.new(colour)
			end
			fx:Emit(count)
		end
	end
	if spot.kind == "TreeBox" then
		for _, d in spot.model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
		spot.model.Transparency = 1
		spot.model.CanCollide = false
		spot.model:SetAttribute("Wobble", nil)
	else
		for _, d in spot.model:GetDescendants() do
			if d:IsA("BasePart") then
				local open = d:GetAttribute("Open")
				if typeof(open) == "CFrame" then
					d.CFrame = d.CFrame * open
				end
			end
		end
		local glow = spot.trigger:FindFirstChild("Searched")
		if glow and glow:IsA("ParticleEmitter") then
			glow.Enabled = true
		end
	end
	local present = spot.present
	if present and not present.taken then
		present.hidden = nil
		present.prompt.Enabled = true
		SoundPlayer.at("SecretFound", spot.trigger)
		self:_banner(player, "A gift! Grab it.", 2)
	elseif spot.kind == "TreeBox" then
		emit("Puff", 24, Color3.fromRGB(255, 120, 200))
		SoundPlayer.at("GiftPop", spot.trigger)
		self:_addNoise(M.PopNoise)
		self:_banner(player, "POP! Just confetti. That was loud.", 2.5)
	else
		emit("Puff", 14)
		SoundPlayer.at("DustPuff", spot.trigger)
		st.jingle += M.EmptyJingle
		Analytics.earnJingle(player, M.EmptyJingle, "MansionSearch")
		self:_sfx(player, "JingleGain")
		self:_sendPlayer(player)
		self:_banner(player, "Just dust... +" .. M.EmptyJingle .. " Jingle", 2)
	end
	for _, house in stop.houses or {} do
		if house.plan == spot.house then
			MapBuilder.refreshMarker(house, stop.vaultPrompt ~= nil and stop.vaultPrompt.Enabled)
		end
	end
end

function Run:_hide(player: Player, spot)
	local st = self:_free(player)
	local root = rootOf(player)
	if not st or not root or spot.occupant then
		return
	end
	if st.carryingList then
		self:_banner(player, "The Naughty List rattles too much to hide! Pass it to a friend (Q).", 2)
		self:_sfx(player, "Nope")
		return
	end
	spot.occupant = player
	st.hidden = spot
	st.breath = 1
	root.Anchored = true
	root.CFrame = spot.inside
	SoundPlayer.at("HideIn", spot.inside.Position)
	Analytics.note(self, player, "Hid")
	self:_send(player, "Hide", { hidden = true, breath = 1 })
	Onboarding.teach(player, "Hide")
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
	SoundPlayer.at("HideOut", spot.exit.Position)
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
	elseif action == "Breakout" then
		if st.captive and self.krampus then
			if Store.useBreakout(player) then
				self:_breakOut(player)
			else
				Store.prompt(player, "InstantBreakout") -- the receipt frees them
			end
		end
	elseif action == "Tap" then
		local t = now()
		if not KrampusBrain.tapAllowed(st.lastTapAt, t) then
			return
		end
		st.lastTapAt = t
		if st.captive and self.krampus then
			self.krampus:wiggle(player)
		elseif st.iced and self.krampus then
			self.krampus.magic:crack(player)
		elseif st.hidden then
			st.breath = KrampusBrain.tapBreath(st.breath)
			self:_send(player, "Hide", { hidden = true, breath = st.breath })
		end
	elseif action == "PassList" then
		if self.list and self:_free(player) then
			self.list:pass(player)
		end
	elseif action == "Bone" then
		self:_throwBone(player)
	elseif self.eventInput then
		self.eventInput(player, action) -- e.g. "Throw" during a Blizzard
	end
end

function Run:_addNoise(amount: number)
	if not NOISY_PHASES[self.phase] then
		return
	end
	self.noise = math.min(Config.Noise.Max, self.noise + amount * self.noiseScale)
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
				inWater = st.swimming == true or st.frozen == true,
				iced = st.iced == true,
				ignoreUntil = ignore[player],
			})
		end
	end
	return list
end

-- Inside the Sleigh Stop (plus `margin` studs): Krampus's tricks never land there.
function Run:nearSleighStop(at: Vector3, margin: number): boolean
	return self.deck ~= nil and MapBuilder.inSleighStop(self.deck, at, margin)
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
				SoundPlayer.at("Gasp", spot.exit.Position)
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
	if self.list and self.list.carrier == player then
		self.list:drop(
			false,
			"Krampus snatched " .. player.DisplayName .. ". The Naughty List fell on the floor!"
		)
	end
	Analytics.snatched(self, player)
	st.captive = true
	st.perks = {} -- cocoa perks are lost when snatched
	self:_applyPerks(player)
	self:_sendPlayer(player)
	local root = rootOf(player)
	if root then
		root.Anchored = true
		SoundPlayer.at("KrampusSnatch", root.Position)
	end
	self:_banner(nil, "Krampus snatched " .. player.DisplayName .. "! Ring the bells behind him!", 3)
	if self.krampus then
		self:_cutscene(
			"Snatched",
			player,
			{ anchor = self.krampus.body.root.CFrame, follow = self.krampus.body.model }
		)
	end
	self:_send(player, "Captive", {
		captive = true,
		wiggles = 0,
		needed = KrampusBrain.wiggleNeeded(),
		breakout = Store.breakoutOffer(player),
	})
	Onboarding.teach(player, "Snatched")
end

-- Instant Break-out (already paid for): out of the basket now.
function Run:_breakOut(player: Player)
	if self.krampus then
		Analytics.freedBy(player, "Break-out")
		self.krampus:release()
		self:_banner(nil, player.DisplayName .. " burst out of the basket!", 2)
	end
end

function Run:onReleased(player: Player, at: CFrame)
	local st = self.players[player]
	if not st then
		return
	end
	st.captive = false
	Analytics.released(self, player)
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	Util.teleport(player, at)
	SoundPlayer.at("Boing", at.Position)
	self:_send(player, "Captive", { captive = false })
end

function Run:_startKrampus(stop)
	for _, light in stop.lights do
		light.Enabled = true
		light.Color = Color3.fromRGB(255, 60, 60)
	end
	local intro = Cutscenes.get("KrampusArrives")
	local introSeconds = if Config.Cutscenes.Enabled and intro then intro.seconds else 0
	local hold = if introSeconds > 0
		then introSeconds + Config.Cutscenes.KrampusGrace
		else Config.Krampus.WarningSeconds
	self:_banner(nil, "KRAMPUS IS COMING!", hold)
	Analytics.crewMoment(self, "KrampusArrived", if self.noiseFull then "Too noisy" else "On time")
	self.krampus = Krampus.new(self, stop, hold)
	self:_lairCue(stop, "BellsAt")
	self.cuckoo = CuckooWatch.start(self, stop, now() + hold + Config.CuckooWatch.FirstAfter)
	self:_send(nil, "Krampus", { model = self.krampus.body.model })
	Onboarding.teachAll(self.order, "Krampus")
	if introSeconds > 0 then
		self.krampus:playIntro(introSeconds)
		self:_cutscene(
			"KrampusArrives",
			nil,
			{ anchor = stop.krampusSpawn, follow = self.krampus.body.model }
		)
	end
end

-- Cues the Lair's clockwork (LairAnimator.client, LairMotion): the cuckoo
-- pops out on the horn, the seven bells light up when Krampus wakes.
function Run:_lairCue(stop, attribute: string)
	if not stop.plan.escapeMultiplier then
		return
	end
	local lair = self.route.model:FindFirstChild("LairHouse", true)
	if lair then
		lair:SetAttribute(attribute, now())
		if attribute == "CuckooAt" then
			lair:SetAttribute("CuckooHold", nil) -- the horn's long cuckoo, not the watch's
		end
	end
end

function Run:_stopCuckoo()
	if self.cuckoo then
		self.cuckoo:destroy()
		self.cuckoo = nil
	end
end

function Run:_stopKrampus()
	self:_stopCuckoo()
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
		if entry and entry.start and Maps.featureOnStop(feature, stop.plan.index) then
			local ok, cleanup = pcall(entry.start, { run = self, stop = stop, feature = feature })
			if not ok then
				warn("[Run] map feature " .. feature.kind .. " failed to start: " .. tostring(cleanup))
			elseif cleanup then
				table.insert(self.featureCleanups, cleanup)
			end
		end
	end
end

-- Parents asleep in every house during the sneak phase: snores you can
-- follow (and tiptoe past) until the lights come on.
function Run:_startSnores(stop)
	if stop.plan.kindName == "Finale" then
		return -- nobody sleeps in Krampus's Lair
	end
	for _, light in stop.lights do
		local lamp = light.Parent
		if lamp and lamp:IsA("BasePart") then
			table.insert(self.snores, SoundPlayer.loop("ParentSnore", lamp))
		end
	end
end

-- Lights on: the snoring stops and each house grumbles awake.
function Run:_wakeParents(stop)
	local woke = #self.snores > 0
	self:_stopSnores()
	if not woke then
		return
	end
	for _, light in stop.lights do
		local lamp = light.Parent
		if lamp and lamp:IsA("BasePart") then
			task.delay(math.random() * 0.6, SoundPlayer.at, "ParentWake", lamp)
		end
	end
end

-- Lights on: every lit house starts its "Who's there?!" checks (HouseChecks).
function Run:_startHouseChecks(stop)
	if not LightsCheck.applies(stop.plan.kindName) then
		return
	end
	local ok, cleanup = pcall(HouseChecks.start, self, stop)
	if ok then
		table.insert(self.featureCleanups, cleanup)
	else
		warn("[Run] house checks failed to start: " .. tostring(cleanup))
	end
end

function Run:_stopSnores()
	for _, snore in self.snores do
		snore.stop(0.3)
	end
	self.snores = {}
end

function Run:_stopFeatures()
	self:_stopEvent()
	for _, cleanup in self.featureCleanups do
		local ok, err = pcall(cleanup)
		if not ok then
			warn("[Run] map feature cleanup failed: " .. tostring(err))
		end
	end
	self.featureCleanups = {}
end

-- Random map event (MapEvents), if this run rolled one for this stop.
function Run:_startEvent(stop, endsAt: number)
	local plan = self.eventPlan
	local ok, cleanup = pcall(MapEvents[plan.kind].start, {
		run = self,
		stop = stop,
		entry = plan.entry,
		endsAt = endsAt,
	})
	if not ok then
		warn("[Run] map event " .. plan.kind .. " failed to start: " .. tostring(cleanup))
		self.noiseScale = 1
		self.eventInput = nil
		return
	end
	self.eventCleanup = cleanup
	Analytics.crewMoment(self, "MapEvent", plan.kind)
	self:_send(nil, "MapEvent", { label = Config.MapEvents.Events[plan.kind].Label, endsAt = endsAt })
end

-- Ends the event early or on time; safe to call when none is running.
function Run:_stopEvent()
	local cleanup = self.eventCleanup
	if not cleanup then
		return
	end
	self.eventCleanup = nil
	local ok, err = pcall(cleanup)
	if not ok then
		warn("[Run] map event cleanup failed: " .. tostring(err))
	end
	self.noiseScale = 1
	self.eventInput = nil
	self:_send(nil, "MapEvent", {})
end

-- Warn, start and end phases for this stop's map event (none if not rolled).
function Run:_eventPhases(stop, t0: number): { any }
	local plan = self.eventPlan
	if not plan or plan.stop ~= stop.plan.index then
		return {}
	end
	local def = Config.MapEvents.Events[plan.kind]
	return {
		{
			at = t0 + plan.warnAt,
			enter = function()
				self:_banner(nil, string.format(def.Warning, plan.startAt - plan.warnAt), 4)
			end,
		},
		{
			at = t0 + plan.startAt,
			enter = function()
				self:_startEvent(stop, t0 + plan.endAt)
			end,
		},
		{
			at = t0 + plan.endAt,
			enter = function()
				self:_stopEvent()
			end,
		},
	}
end

----------------------------------------------------------------------------
-- Sleigh flight
----------------------------------------------------------------------------

function Run:_fly(fromDeck: CFrame, toDeck: CFrame, riders: { Player })
	self.phase = "Flight"
	self:_sendStop()
	self:_ride(riders, {
		path = "flight",
		base = fromDeck,
		to = toDeck,
		peak = Config.Run.FlightArcHeight,
		seconds = Config.Run.FlightSeconds,
	})
end

-- Moves the sleigh along a Puppets path (a flight or the Getaway) for its
-- seconds, carrying the riders in their seats, and leaves it at the path's
-- end. keepSeated leaves riders anchored in the sleigh (the Getaway ends in
-- the sky; _finish frees them). The crew's clients pose the same path
-- themselves (client/PuppetPlayer), so the sleigh glides instead of stepping
-- at the network rate.
function Run:_ride(riders: { Player }, path: Puppets.Puppet, keepSeated: boolean?)
	local seconds = path.seconds
	local function deckAt(t: number): CFrame
		return Puppets.poseAt(path, t)
	end
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

	self.flightSeats = seats -- respawns mid-flight are seated too
	-- One clock for the server and the clients' copies (Util.now is server time).
	local started = now()
	local deckPuppet = table.clone(path) :: any
	deckPuppet.target = sleigh
	local puppets = { deckPuppet }
	for root, seat in seats do
		local rider = table.clone(path) :: any
		rider.target, rider.offset = root, seat
		table.insert(puppets, rider)
	end
	self:_send(nil, "Puppets", { startedAt = started, puppets = puppets })
	local connection = RunService.Heartbeat:Connect(function()
		place(deckAt(now() - started))
	end)
	task.wait(seconds)
	connection:Disconnect()
	place(deckAt(seconds))
	self.flightSeats = nil
	if not keepSeated then
		for root in seats do
			root.Anchored = false
		end
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
	Analytics.stopReached(self, plan.index, function(player)
		return self.players[player]
	end)
	self:_startFeatures(stop)
	if YardDogs.applies(plan.index, plan.kindName) then
		local ok, cleanup = pcall(YardDogs.start, self, stop)
		if not ok then
			warn("[Run] yard dogs failed to start: " .. tostring(cleanup))
		elseif cleanup then
			table.insert(self.featureCleanups, cleanup)
		end
	end
	self:_startSnores(stop)
	self:_teachLanding(stop)
	if plan.escapeMultiplier then
		self.list = NaughtyList.find(self, stop)
	end

	-- The horn: at HornAt, or early when a full noise meter sets off the alarm
	-- (NoiseAlarm). It sounds once per stop and only ever brings departure closer.
	local hornSounded = false
	local function soundHorn(banner: string?)
		if hornSounded then
			return
		end
		hornSounded = true
		self.times.departAt = NoiseAlarm.departAt(now(), self.times.departAt)
		local left = math.max(0, math.ceil(self.times.departAt - now()))
		self:_banner(nil, (banner or "HONK! The sleigh leaves in %d seconds!"):format(left), 3)
		self:_lairCue(stop, "CuckooAt")
		Onboarding.teachAll(self.order, "Horn", function()
			return stop.deckCFrame.Position
		end)
	end

	-- Timed phases, entered in order once their time has passed.
	local phases = {
		{
			at = t0 + Config.Run.LightsOnAt,
			phase = "LightsOn",
			enter = function()
				for _, light in stop.lights do
					light.Enabled = true
				end
				self:_wakeParents(stop)
				self:_startHouseChecks(stop)
				if not hornSounded then -- the alarm horn's countdown banner wins
					self:_banner(nil, "Lights on! Grown-ups are checking every house. Don't get spotted!", 3)
				end
				Onboarding.teachAll(self.order, "LightsOn")
			end,
		},
		{
			at = t0 + Config.Run.HornAt,
			phase = "Horn",
			enter = function()
				soundHorn()
			end,
		},
	}
	for _, p in self:_eventPhases(stop, t0) do
		table.insert(phases, p)
	end
	table.sort(phases, function(a, b)
		return a.at < b.at
	end)
	local nextPhase = 1
	local teased = false
	local alarmed = false

	while true do
		task.wait(TICK)
		if self.ended or self:_isEmpty() then
			break
		end
		local t = now()
		while phases[nextPhase] and t >= phases[nextPhase].at do
			local p = phases[nextPhase]
			nextPhase += 1
			-- Map event phases keep the stop's phase, and an early alarm horn
			-- isn't undone by the lights coming on afterwards.
			self.phase = if p.phase then NoiseAlarm.nextPhase(self.phase, p.phase) else self.phase
			p.enter()
			if p.phase then
				self:_sendStop()
			end
		end
		if self.phase ~= "Sneak" then
			self:_addNoise(Config.Noise.LightsOnPerSecond * TICK)
		end
		if self.list then
			self.list:tick(TICK)
		end
		if self.cuckoo then
			self.cuckoo:tick(t)
		end
		if self.noiseFull and not alarmed and NoiseAlarm.applies(plan.index, plan.kindName) then
			alarmed = true
			Analytics.crewMoment(self, "NoiseAlarm", self.phase)
			local ok, cleanup = pcall(AlarmDogs.start, self, stop)
			if ok then
				table.insert(self.featureCleanups, cleanup)
			else
				warn("[Run] alarm dogs failed to start: " .. tostring(cleanup))
			end
			if hornSounded then
				self:_banner(nil, "TOO NOISY! Security dogs are loose!", 3)
			else
				soundHorn("TOO NOISY! Security dogs are loose, and the sleigh leaves in %d seconds!")
				self.phase = "Horn"
				self:_sendStop()
			end
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
	if not plan.escapeMultiplier then
		self:_stopKrampus() -- at the finale he stays for the Getaway belly-flop
	end
	self:_stopSnores()
	self:_stopCuckoo()
	-- The finale's bonus needs the Naughty List on the sleigh (Config.NaughtyList).
	local escapeMultiplier = plan.escapeMultiplier
	local listAboard = false
	if escapeMultiplier and self.list then
		listAboard = self.list:aboard(stop.deckCFrame)
		escapeMultiplier = ListBrain.escapeMultiplier(escapeMultiplier, listAboard)
		local carrier = self.list.carrier
		local carrierSt = listAboard and carrier and self.players[carrier]
		if carrierSt then
			carrierSt.sackValue += self.list.present.plan.value -- the book's own loot
			carrierSt.sackCount += 1
			carrierSt.grabs += 1
		end
		self.listEscaped = listAboard
		self:_banner(
			nil,
			if listAboard
				then "You got away with the Naughty List! LOOT x" .. plan.escapeMultiplier .. "!"
				else "No Naughty List on the sleigh... no bonus this time.",
			4
		)
		self.list:destroy()
		self.list = nil
	end
	local aboard = {}
	for _, player in table.clone(self.order) do
		local st = self.players[player]
		local root = rootOf(player)
		self:_unhide(player)
		Onboarding.clearGuide(player)
		if st and root and MapBuilder.isAboard(stop.deckCFrame, root.Position) then
			table.insert(aboard, player)
			if st.sackCount > 0 then
				self:_sfx(player, "Bank")
				SantaMoves.play(player.Character, "Cheer")
				Onboarding.teach(player, "Bank")
			end
			Loot.bank(st, escapeMultiplier)
			self:_sendPlayer(player)
		elseif st and plan.escapeMultiplier then
			if st.sackCount > 0 then
				self:_sfx(player, "SackSpill")
			end
			Loot.bankMissed(st)
			self:_sendPlayer(player)
			self:_banner(player, "You missed the last sleigh! Half your sack fell out.", 4)
			self:_leftBehind(player, stop)
		elseif st then
			self:_banner(player, "You missed the sleigh! Follow the path to the next stop.", 4)
			Onboarding.teach(player, "Missed")
			self:_leftBehind(player, stop)
		end
	end
	Analytics.stopLeft(self, plan.index, aboard, function(player)
		return self.players[player]
	end)
	return aboard
end

function Run:_leftBehind(player: Player, stop)
	self:_cutscene("LeftBehind", player, { anchor = stop.deckCFrame, follow = self.route.sleigh })
end

-- The Takeoff swoop looks down on the whole route from above its middle.
function Run:_routeCentre(): CFrame
	local sum = Vector3.zero
	for _, stop in self.route.stops do
		sum += stop.deckCFrame.Position
	end
	return CFrame.new(sum / #self.route.stops)
end

-- Getaway: the overloaded sleigh strains and shoots off with whoever made it,
-- while Krampus belly-flops behind it. Runs after the finale's loot is banked.
-- Only the riders see it; anyone who missed it is watching Left Behind.
function Run:_getaway(stop, riders: { Player })
	-- No List aboard: the stamp says so instead of LOOT x2.
	local swap = if self.listEscaped == false then { ["LOOT x2"] = "NO LIST, NO x2" } else nil
	local seconds = if #riders > 0
		then self:_cutscene(
			"Getaway",
			riders,
			{ anchor = stop.deckCFrame, follow = self.route.sleigh, swap = swap }
		)
		else 0
	if seconds <= 0 then
		self:_stopKrampus()
		return
	end
	self.phase = "Flight"
	self:_sendStop()
	if self.krampus then
		self.krampus:playFlop(seconds, stop.deckCFrame.Position)
	end
	self:_ride(riders, { path = "getawaySleigh", base = stop.deckCFrame, seconds = seconds }, true)
	self:_stopKrampus()
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
		"Take-off for "
			.. self.route.map.name
			.. "! Rob the houses, then escape Krampus's Lair."
			.. (if self.eventPlan then "\n" .. Config.MapEvents.Events[self.eventPlan.kind].Forecast else ""),
		4
	)
	for player in self.players do
		self:_sendPlayer(player)
	end
	Analytics.runStarted(self)

	local stops = self.route.stops
	local marks = {}
	for _, stop in stops do
		table.insert(marks, stop.deckCFrame.Position)
	end
	self:_cutscene("Takeoff", nil, {
		anchor = self:_routeCentre(),
		follow = self.route.sleigh,
		marks = marks,
		map = self.route.map.name,
	})
	self:_fly(self.route.startDeck, stops[1].deckCFrame, table.clone(self.order))
	for i, stop in stops do
		if self.ended or self:_isEmpty() then
			return
		end
		local aboard = self:_playStop(stop)
		if stops[i + 1] and not self:_isEmpty() then
			self:_fly(stop.deckCFrame, stops[i + 1].deckCFrame, aboard)
		elseif not stops[i + 1] and not self:_isEmpty() then
			self:_getaway(stop, aboard)
		end
	end

	if not self:_isEmpty() then
		self.phase = "Results"
		local entries = {}
		for player, st in self.players do
			-- Coal is saved here, through 2X Loot and any Santa's Blessing.
			table.insert(
				entries,
				{ player.DisplayName, st, Store.creditRun(player, Loot.finalLoot(st)), player.UserId }
			)
		end
		self:_send(nil, "Results", {
			rows = Loot.results(entries),
			endsAt = now() + Config.Run.ResultsSeconds + Config.Run.RequeueSeconds,
		})
		Onboarding.teachAll(self.order, "Done")
		Analytics.runFinished(self, function(player)
			local st = self.players[player]
			return st and Loot.finalLoot(st)
		end)
		for player, st in self.players do
			if st.banked > 0 then
				SantaMoves.play(player.Character, "Cheer") -- got away with it
			end
		end
		task.wait(Config.Run.ResultsSeconds)
	end
end

function Run:_finish()
	if self.ended then
		return
	end
	self:_stopFeatures()
	self:_stopKrampus()
	self:_stopSnores()
	if self.list then
		self.list:destroy()
		self.list = nil
	end
	self:_removeElves()
	self.unbindBreakout()
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
