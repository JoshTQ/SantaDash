--[[
	The Naughty List in Krampus's Lair (Josh, 11 Nov 2026: "make it more
	important, more challenging"). Config.NaughtyList, rules in ListBrain.

	  Home     on its pedestal; "Steal" takes it
	  Carried  hovering over its carrier's head (welded to their root). The
	           carrier is Marked: it rattles (noise each tick, and Krampus's
	           Bell Blink goes for the noisiest Santa), slows them to 15 and
	           they can't hide. "PassList" throws it to the nearest free friend.
	  Loose    dropped where its carrier was snatched (or bobbing on the lake if
	           they swam: it can't get wet). Anyone can grab it; after a while
	           it flies home.

	Run owns one of these for the finale stop and asks `aboard(deck)` when the
	last sleigh leaves: only then does the stop's escape bonus apply.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local ListBrain = require(script.Parent.ListBrain)
local Onboarding = require(script.Parent.Onboarding)
local MapBuilder = require(script.Parent.MapBuilder)

local L = Config.NaughtyList
local GOLD = Color3.fromRGB(255, 200, 70)

local NaughtyList = {}
NaughtyList.__index = NaughtyList

-- present: the Lair's BuiltPresent whose plan is the Naughty List.
function NaughtyList.new(run, present)
	local self = setmetatable({}, NaughtyList)
	self.run = run
	self.present = present
	self.model = present.model :: Model
	self.prompt = present.prompt :: ProximityPrompt
	self.home = self.model:GetPivot()
	self.state = "Home"
	self.carrier = nil :: Player?
	self.looseUntil = 0
	self.welds = {} :: { Instance }
	self.glow = nil :: Instance?
	return self
end

-- Finds the List among a stop's presents, or nil (no List, or the heist is off).
function NaughtyList.find(run, stop)
	if not L.Enabled then
		return nil
	end
	for _, present in stop.presents do
		if present.plan.naughtyList then
			return NaughtyList.new(run, present)
		end
	end
	return nil
end

local function parts(model: Model): { BasePart }
	local list = {}
	if model:IsA("BasePart") then
		table.insert(list, model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

function NaughtyList:_unweld()
	for _, weld in self.welds do
		weld:Destroy()
	end
	table.clear(self.welds)
	if self.glow then
		self.glow:Destroy()
		self.glow = nil
	end
end

-- Puts the book down (anchored) at `cframe`.
function NaughtyList:_place(cframe: CFrame)
	self:_unweld()
	for _, part in parts(self.model) do
		part.Anchored = true
	end
	self.model:PivotTo(cframe)
end

function NaughtyList:_setCarrier(player: Player?)
	local before = self.carrier
	self.carrier = player
	local run = self.run
	if before and before ~= player then
		local st = run.players[before]
		if st then
			st.carryingList = false
		end
		run:_applyPerks(before)
		run:_send(before, "List", { carrying = false })
	end
	if player then
		local st = run.players[player]
		if st then
			st.carryingList = true
		end
		run:_applyPerks(player)
		run:_send(player, "List", { carrying = true, range = L.PassRange })
		Onboarding.teach(player, "List")
	end
end

-- Hovers the book over `player`'s head, welded to their root.
function NaughtyList:_attach(player: Player): boolean
	local root = Util.rootOf(player)
	if not root then
		return false
	end
	self:_place(root.CFrame * CFrame.new(0, L.HoverHeight, 0))
	for _, part in parts(self.model) do
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		table.insert(self.welds, weld)
	end
	-- A gold glow so the whole crew (and Krampus) can see who has it.
	local primary = self.model.PrimaryPart
	if primary then
		local light = Instance.new("PointLight")
		light.Name = "ListGlow"
		light.Color = GOLD
		light.Range = 14
		light.Brightness = 2
		light.Parent = primary
		self.glow = light
	end
	self.state = "Carried"
	self.prompt.Enabled = false
	self.present.taken = true
	self:_setCarrier(player)
	return true
end

-- A Santa steals (or picks back up) the List. Run checks they're free first.
function NaughtyList:take(player: Player)
	if self.state == "Carried" then
		return
	end
	local fromHome = self.state == "Home"
	if not self:_attach(player) then
		return
	end
	local run = self.run
	local at = self.model:GetPivot().Position
	run.lastNoisePos = at
	SoundPlayer.at("NaughtyListGrab", at)
	if fromHome then
		run:_banner(
			nil,
			player.DisplayName .. " stole the Naughty List! Get it on the sleigh for LOOT x2!",
			4
		)
	else
		run:_banner(nil, player.DisplayName .. " grabbed the Naughty List!", 2)
	end
end

-- Drops it where the carrier is. inWater: it bobs on the lake for less time.
function NaughtyList:drop(inWater: boolean, why: string?)
	local player = self.carrier
	if self.state ~= "Carried" or not player then
		return
	end
	local root = Util.rootOf(player)
	local at = if root then root.CFrame.Position else self.model:GetPivot().Position
	self:_place(CFrame.new(at + Vector3.new(0, if inWater then 0.5 else -1.5, 0)))
	self.state = "Loose"
	self.looseUntil = Util.now() + ListBrain.looseSeconds(inWater)
	self.prompt.ActionText = "Grab"
	self.prompt.Enabled = true
	self:_setCarrier(nil)
	SoundPlayer.at("SackSpill", at)
	self.run:_banner(nil, why or (player.DisplayName .. " dropped the Naughty List! Grab it!"), 3)
end

-- Back on its pedestal (it flew home, or its carrier left the run).
function NaughtyList:returnHome(quiet: boolean?)
	if self.state == "Home" then
		return
	end
	self:_place(self.home)
	self.state = "Home"
	self.prompt.ActionText = "Steal"
	self.prompt.Enabled = true
	self.present.taken = false
	self:_setCarrier(nil)
	if not quiet then
		SoundPlayer.at("CutsceneYoink", self.home.Position)
		self.run:_banner(nil, "The Naughty List flew back to its pedestal!", 3)
	end
end

-- The carrier throws it to the nearest free friend within PassRange.
function NaughtyList:pass(player: Player)
	if self.carrier ~= player then
		return
	end
	local run = self.run
	local root = Util.rootOf(player)
	if not root then
		return
	end
	local friends = {}
	for other in run.players do
		local otherRoot = other ~= player and Util.rootOf(other)
		if otherRoot then
			table.insert(friends, {
				player = other,
				position = otherRoot.CFrame.Position,
				free = run:_free(other) ~= nil,
			})
		end
	end
	local target = ListBrain.passTarget(root.CFrame.Position, friends)
	if not target then
		run:_banner(
			player,
			"Nobody close enough to catch it! Get within " .. L.PassRange .. " studs of a friend.",
			2
		)
		run:_sfx(player, "Nope")
		return
	end
	self:_attach(target)
	SoundPlayer.at("CutsceneYoink", root.CFrame.Position)
	run:_banner(nil, player.DisplayName .. " passed the Naughty List to " .. target.DisplayName .. "!", 2)
end

-- Every Run tick in the finale: rattle, can't-get-wet, flying home.
function NaughtyList:tick(dt: number)
	local run = self.run
	if self.state == "Carried" then
		local player = self.carrier :: Player
		local st = run.players[player]
		local root = Util.rootOf(player)
		if not st or not root then
			self:returnHome()
		elseif st.captive then
			self:drop(
				false,
				"Krampus snatched " .. player.DisplayName .. ". The Naughty List fell on the floor!"
			)
		elseif st.swimming or st.frozen then
			self:drop(true, "The Naughty List can't get wet! It's bobbing on the lake. Fish it out!")
		else
			run.lastNoisePos = root.CFrame.Position -- the rattle: Bell Blink picks the noisiest Santa
			run:_addNoise(L.RattleNoisePerSecond * dt)
		end
	elseif self.state == "Loose" and Util.now() >= self.looseUntil then
		self:returnHome()
	end
end

-- On the sleigh as it leaves: carried by a Santa aboard, or lying on the deck.
function NaughtyList:aboard(deck: CFrame): boolean
	if self.state == "Carried" then
		local root = self.carrier and Util.rootOf(self.carrier)
		return root ~= nil and MapBuilder.isAboard(deck, root.CFrame.Position)
	elseif self.state == "Loose" then
		return MapBuilder.isAboard(deck, self.model:GetPivot().Position)
	end
	return false
end

-- A carrier who leaves or respawns: the List goes home.
function NaughtyList:forget(player: Player)
	if self.carrier == player then
		self:returnHome(true)
	end
end

function NaughtyList:destroy()
	if self.carrier then
		self:_setCarrier(nil)
	end
	self:_unweld()
end

return NaughtyList
