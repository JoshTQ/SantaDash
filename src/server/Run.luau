--[[
	One crew's run: take-off, 4 stops of 2:00, results.

	Each stop: 0:00-0:45 sneak, 0:45 lights on (Heat rises), 1:30 horn,
	2:00 the sleigh leaves with or without you. Miss it and you run to the next
	stop on foot. Stop 4 is the finale; escaping it doubles your loot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Loot = require(script.Parent.Loot)
local MapBuilder = require(script.Parent.MapBuilder)

type PlayerState = {
	jingle: number,
	sackCount: number,
	sackValue: number,
	banked: number,
	grabs: number,
	perks: { [string]: boolean },
	escaped: boolean,
}

local Run = {}
Run.__index = Run

local TICK = 0.25

local function now(): number
	return workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Run.new(slot: number, crew: { Player }, onFinished: (run: any, survivors: { Player }) -> ())
	local self = setmetatable({}, Run)
	self.slot = slot
	self.rng = Random.new()
	self.route = MapBuilder.buildRoute(slot, self.rng)
	self.onFinished = onFinished
	self.hud = Remotes.get("Hud")
	self.players = {} :: { [Player]: PlayerState }
	self.order = {} :: { Player } -- join order, for seats
	self.connections = {} :: { RBXScriptConnection }
	self.stopIndex = 0
	self.phase = "Takeoff"
	self.noise = 0
	self.deck = self.route.startDeck
	self.ended = false
	self.times = { lightsAt = 0, hornAt = 0, departAt = 0 }
	self.vaultOpened = {} :: { [number]: boolean }

	for _, player in crew do
		self:_addPlayer(player)
	end
	self:_wirePrompts()
	return self
end

----------------------------------------------------------------------------
-- Messaging
----------------------------------------------------------------------------

function Run:_send(player: Player, kind: string, data: any)
	if player.Parent == Players then
		self.hud:FireClient(player, kind, data)
	end
end

function Run:_sendAll(kind: string, data: any)
	for player in self.players do
		self:_send(player, kind, data)
	end
end

function Run:_banner(player: Player?, text: string, seconds: number?)
	local data = { text = text, seconds = seconds or 3 }
	if player then
		self:_send(player, "Banner", data)
	else
		self:_sendAll("Banner", data)
	end
end

function Run:_sendPlayer(player: Player)
	local st = self.players[player]
	if not st then
		return
	end
	self:_send(player, "Player", {
		jingle = st.jingle,
		sackCount = st.sackCount,
		sackCapacity = Config.Sack.Capacity,
		sackValue = st.sackValue,
		banked = st.banked,
		perks = st.perks,
	})
end

function Run:_sendStop(player: Player?)
	local data = {
		stop = self.stopIndex,
		total = Config.Run.Stops,
		isFinale = self.stopIndex == Config.Run.Stops,
		phase = self.phase,
		lightsAt = self.times.lightsAt,
		hornAt = self.times.hornAt,
		departAt = self.times.departAt,
	}
	if player then
		self:_send(player, "Stop", data)
	else
		self:_sendAll("Stop", data)
	end
end

----------------------------------------------------------------------------
-- Players
----------------------------------------------------------------------------

function Run:_addPlayer(player: Player)
	self.players[player] = {
		jingle = Config.Jingle.Start,
		sackCount = 0,
		sackValue = 0,
		banked = 0,
		grabs = 0,
		perks = {},
		escaped = false,
	}
	table.insert(self.order, player)
	-- Respawns (reset button, falling off the map) put you back on the sleigh.
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 5)
			if self.ended or not self.players[player] then
				return
			end
			self:_applyPerks(player)
			MapBuilder.teleportCharacter(player, self.deck * MapBuilder.SeatOffsets[1])
		end)
	)
end

function Run:hasPlayer(player: Player): boolean
	return self.players[player] ~= nil
end

function Run:removePlayer(player: Player)
	if not self.players[player] then
		return
	end
	self.players[player] = nil
	local index = table.find(self.order, player)
	if index then
		table.remove(self.order, index)
	end
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

----------------------------------------------------------------------------
-- Grabs, buys, noise
----------------------------------------------------------------------------

function Run:_wirePrompts()
	local function wirePresent(present)
		table.insert(
			self.connections,
			present.prompt.Triggered:Connect(function(player)
				self:_grab(player, present)
			end)
		)
	end
	for _, stop in self.route.stops do
		for _, present in stop.presents do
			wirePresent(present)
		end
		table.insert(
			self.connections,
			stop.cocoaPrompt.Triggered:Connect(function(player)
				self:_buyPeppermintRush(player)
			end)
		)
		if stop.vaultPrompt then
			table.insert(
				self.connections,
				stop.vaultPrompt.Triggered:Connect(function(player)
					self:_buyVault(player, stop)
				end)
			)
		end
	end
	for _, present in self.route.onFootPresents do
		wirePresent(present)
	end
end

function Run:_grab(player: Player, present)
	local st = self.players[player]
	if not st or present.taken or self.ended then
		return
	end
	if st.sackCount >= Config.Sack.Capacity then
		self:_banner(player, "Sack full! Get back on the sleigh to bank it.", 2)
		return
	end
	present.taken = true
	present.model:Destroy()

	st.sackCount += 1
	st.sackValue += present.value
	st.grabs += 1
	st.jingle += Loot.jingleForGrab(present.ringMultiplier)
	self:_addNoise(Loot.noiseForGrab(math.max(self.stopIndex, 1), present.threats))
	self:_sendPlayer(player)

	if present.kind == "NaughtyList" then
		self:_banner(nil, player.DisplayName .. " stole the Naughty List! Get to the sleigh!", 4)
	end
end

-- Spends Jingle; returns true on success.
function Run:_spend(player: Player, cost: number): boolean
	local st = self.players[player]
	if not st or self.ended then
		return false
	end
	if st.jingle < cost then
		self:_banner(player, "Need " .. (cost - st.jingle) .. " more Jingle", 2)
		return false
	end
	st.jingle -= cost
	self:_addNoise(Config.Noise.PerBuy)
	self:_sendPlayer(player)
	return true
end

function Run:_buyPeppermintRush(player: Player)
	local st = self.players[player]
	if not st then
		return
	end
	if st.perks.PeppermintRush then
		self:_banner(player, "You already have Peppermint Rush", 2)
		return
	end
	if self:_spend(player, Config.Buys.PeppermintRush.Cost) then
		st.perks.PeppermintRush = true
		self:_applyPerks(player)
		self:_sendPlayer(player)
		self:_banner(player, "Peppermint Rush! You're faster for the rest of the run.", 3)
	end
end

function Run:_buyVault(player: Player, stop)
	if self.vaultOpened[stop.index] then
		return
	end
	if self:_spend(player, Config.Buys.VaultDoor.Cost) then
		self.vaultOpened[stop.index] = true
		local door = stop.vaultDoor
		if door then
			door.CanCollide = false
			door.Transparency = 0.85
		end
		if stop.vaultPrompt then
			stop.vaultPrompt.Enabled = false
		end
		self:_banner(nil, player.DisplayName .. " opened the vault!", 3)
	end
end

function Run:_addNoise(amount: number)
	if self.phase == "Takeoff" or self.phase == "Flight" or self.phase == "Results" then
		return
	end
	self.noise = math.min(Config.Noise.Max, self.noise + amount)
	if self.noise >= Config.Noise.Max and not self.noiseFull then
		self.noiseFull = true
		self:_onNoiseFull()
	end
end

function Run:_onNoiseFull()
	-- GREYBOX placeholder until Krampus exists: the horn blows early.
	if Config.Noise.OnFull == "EarlyHorn" then
		local t = now()
		self.times.hornAt = math.min(self.times.hornAt, t)
		self.times.departAt = math.min(self.times.departAt, t + Config.Noise.EarlyHornSeconds)
		self:_banner(nil, "TOO NOISY! The sleigh is spooked and leaving early!", 3)
		self:_sendStop()
	end
end

-- Hook for the Krampus system (not built: his model is awaiting approval).
function Run:_startKrampus(_stop)
	-- Intentionally empty. Config.Krampus.FirstStop decides which stop calls this.
end

----------------------------------------------------------------------------
-- Sleigh flight
----------------------------------------------------------------------------

function Run:_fly(fromDeck: CFrame, toDeck: CFrame, riders: { Player })
	self.phase = "Flight"
	self:_sendStop()

	local seats: { [Player]: CFrame } = {}
	for i, player in riders do
		local root = rootOf(player)
		if root then
			seats[player] = MapBuilder.SeatOffsets[(i - 1) % #MapBuilder.SeatOffsets + 1]
			root.Anchored = true
			root.CFrame = fromDeck * seats[player]
		end
	end

	local sleigh = self.route.sleigh
	local duration = Config.Run.FlightSeconds
	local started = os.clock()
	local function place(deck: CFrame)
		self.deck = deck
		sleigh:PivotTo(deck)
		for player, seat in seats do
			local root = rootOf(player)
			if root and self.players[player] then
				root.CFrame = deck * seat
			end
		end
	end

	local connection = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - started) / duration, 0, 1)
		local pos = fromDeck.Position:Lerp(toDeck.Position, a)
			+ Vector3.yAxis * math.sin(a * math.pi) * Config.Run.FlightArcHeight
		place(CFrame.new(pos) * fromDeck.Rotation:Lerp(toDeck.Rotation, a))
	end)
	task.wait(duration)
	connection:Disconnect()
	place(toDeck)

	for player in seats do
		local root = rootOf(player)
		if root then
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
	local t0 = now()
	self.stopIndex = stop.index
	self.noise = 0
	self.noiseFull = false
	self.phase = "Sneak"
	self.times = {
		lightsAt = t0 + Config.Run.LightsOnAt,
		hornAt = t0 + Config.Run.HornAt,
		departAt = t0 + Config.Run.StopSeconds,
	}
	self:_sendStop()

	if stop.isFinale then
		self:_banner(nil, "KRAMPUS'S LAIR! Steal the Naughty List and escape to double your loot!", 4)
	else
		self:_banner(nil, "Stop " .. stop.index .. ": sneak in, grab presents. Further = better loot!", 4)
	end
	if Config.Krampus.Enabled and stop.index >= Config.Krampus.FirstStop then
		self:_startKrampus(stop)
	end

	while true do
		task.wait(TICK)
		if self.ended or self:_isEmpty() then
			return {}
		end
		local t = now()
		if self.phase == "Sneak" and t >= self.times.lightsAt and t < self.times.hornAt then
			self.phase = "LightsOn"
			for _, house in stop.houses do
				house.light.Enabled = true
			end
			self:_banner(nil, "The lights are on! Heat is rising.", 3)
			self:_sendStop()
		end
		if self.phase ~= "Sneak" then
			self:_addNoise(Config.Noise.LightsOnPerSecond * TICK)
		end
		if self.phase ~= "Horn" and t >= self.times.hornAt then
			self.phase = "Horn"
			local left = math.max(0, math.floor(self.times.departAt - t + 0.5))
			self:_banner(nil, "HONK! The sleigh leaves in " .. left .. " seconds!", 3)
			self:_sendStop()
		end
		self:_sendAll("Noise", { value = self.noise, max = Config.Noise.Max })

		if t >= self.times.departAt then
			break
		end
		if
			self.phase == "Horn"
			and Config.Run.LeaveEarlyWhenAllAboard
			and self:_allAboard(stop.deckCFrame)
		then
			break
		end
	end

	local aboard = {}
	for _, player in self.order do
		local st = self.players[player]
		local root = rootOf(player)
		if st and root and MapBuilder.isAboard(stop.deckCFrame, root.Position) then
			table.insert(aboard, player)
			if Config.Sack.BankOnBoard or stop.isFinale then
				st.banked += st.sackValue
				st.sackValue = 0
				st.sackCount = 0
			end
			if stop.isFinale then
				st.escaped = true
			end
			self:_sendPlayer(player)
		elseif st and not stop.isFinale then
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
		local ok, err = pcall(function()
			self:_main()
		end)
		if not ok then
			warn("[Run] slot " .. self.slot .. " crashed: " .. tostring(err))
			self:_finish()
		end
	end)
end

function Run:_main()
	self:_banner(nil, "Take-off! Rob 3 houses, then Krampus's Lair.", 4)
	for player in self.players do
		self:_sendPlayer(player)
	end

	local stops = self.route.stops
	self:_fly(self.route.startDeck, stops[1].deckCFrame, table.clone(self.order))
	for i, stop in stops do
		if self.ended or self:_isEmpty() then
			break
		end
		local aboard = self:_playStop(stop)
		if i < #stops and not self:_isEmpty() then
			self:_fly(stop.deckCFrame, stops[i + 1].deckCFrame, aboard)
		end
	end

	if not self.ended and not self:_isEmpty() then
		self:_results()
	end
	self:_finish()
end

function Run:_results()
	self.phase = "Results"
	local rows = {}
	for player, st in self.players do
		local loot = st.banked
		if st.escaped then
			loot *= Config.Run.FinaleEscapeMultiplier
		end
		table.insert(rows, {
			name = player.DisplayName,
			loot = loot,
			coal = math.floor(loot * Config.Coal.PerLootValue),
			escaped = st.escaped,
			grabs = st.grabs,
		})
	end
	table.sort(rows, function(a, b)
		return a.loot > b.loot
	end)
	self:_sendAll("Results", {
		rows = rows,
		bestThief = if rows[1] then rows[1].name else nil,
		seconds = Config.Run.ResultsSeconds,
		nextRunIn = Config.Run.RequeueSeconds,
	})
	task.wait(Config.Run.ResultsSeconds)
end

function Run:_finish()
	if self.ended then
		return
	end
	self.ended = true
	for _, connection in self.connections do
		connection:Disconnect()
	end
	local survivors = {}
	for _, player in self.order do
		if self.players[player] and player.Parent == Players then
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
