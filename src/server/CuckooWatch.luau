--[[
	Cuckoo Watch (Josh, 11 Nov 2026: "Maybe the lair has PvE?"): the Lair's
	PvE as a rule everyone already knows, red light, green light.

	About every Config.CuckooWatch.Interval seconds: tick-tock (WarnSeconds),
	then the approved cuckoo pops out of the clock and looks round the den
	(LookSeconds). Any free Santa inside the den who moves more than a shuffle
	while it looks is spotted: "CUCKOO!", noise, and Krampus Bell Blinks to
	them (KrampusMagic:summon). Hidden, snatched, iced or frozen Santas and
	anyone outside the den (or in a Glitter Bomb cloud) are safe. Rules in ListBrain.

	The cuckoo itself is LairAnimator.client: we stamp CuckooAt (and a short
	CuckooHold) on the Lair model; the HUD shows "TICK TOCK..." then "FREEZE!".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local LairMotion = require(ReplicatedStorage.Shared.LairMotion)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local ListBrain = require(script.Parent.ListBrain)
local Onboarding = require(script.Parent.Onboarding)

local C = Config.CuckooWatch

local CuckooWatch = {}
CuckooWatch.__index = CuckooWatch

-- lair: the LairHouse model (its bounding box is the den). startAt: when the
-- first warning may start (after Krampus's arrival hold).
function CuckooWatch.new(run, lair: Model, startAt: number, rng: Random?)
	local self = setmetatable({}, CuckooWatch)
	self.run = run
	self.lair = lair
	self.box, self.size = lair:GetBoundingBox()
	self.rng = rng or Random.new()
	self.warnAt = startAt
	self.warned = false
	self.looking = false
	self.last = {} :: { [Player]: Vector3 } -- where each Santa was at the last look tick
	self.lastAt = 0
	self.spotted = {} :: { [Player]: boolean }
	return self
end

-- The cuckoo on the Lair, if Run should start one for this stop.
function CuckooWatch.start(run, stop, startAt: number)
	if not C.Enabled or not stop.plan.escapeMultiplier then
		return nil
	end
	local lair = run.route.model:FindFirstChild("LairHouse", true)
	if not lair or not lair:IsA("Model") then
		return nil
	end
	return CuckooWatch.new(run, lair, startAt)
end

function CuckooWatch:_clockAt(): Vector3
	local face = self.lair:FindFirstChild("ClockFace", true)
	if face and face:IsA("BasePart") then
		return face.CFrame.Position
	end
	return self.box.Position
end

-- A Santa the cuckoo can catch: in the den and free to move.
function CuckooWatch:_watched(player: Player, st): Vector3?
	if st.hidden or st.captive or st.iced or st.frozen then
		return nil
	end
	local root = Util.rootOf(player)
	if not root then
		return nil
	end
	local at = root.CFrame.Position
	if self.run.inGlitter and self.run:inGlitter(at) then
		return nil -- lost in a Glitter Bomb cloud (server/Toys)
	end
	return if ListBrain.inDen(self.box, self.size, at) then at else nil
end

function CuckooWatch:_beginLook(t: number)
	self.looking = true
	table.clear(self.spotted)
	table.clear(self.last)
	self.lastAt = t
	for player, st in self.run.players do
		local at = self:_watched(player, st)
		if at then
			self.last[player] = at
		end
	end
	SoundPlayer.at("CuckooCall", self:_clockAt())
	self.run:_send(nil, "Cuckoo", { state = "Look", seconds = C.LookSeconds })
end

function CuckooWatch:_spot(player: Player, at: Vector3)
	self.spotted[player] = true
	local run = self.run
	run.lastNoisePos = at
	run:_addNoise(C.SpottedNoise)
	run:_banner(nil, "CUCKOO! The clock saw " .. player.DisplayName .. " move!", 2)
	run:_send(player, "Cuckoo", { state = "Spotted", seconds = 1.5 })
	if run.krampus and run.krampus.magic then
		run.krampus.magic:summon(player)
	end
end

function CuckooWatch:_look(t: number)
	local dt = t - self.lastAt
	self.lastAt = t
	for player, st in self.run.players do
		local at = self:_watched(player, st)
		local before = self.last[player]
		if at and before and not self.spotted[player] and ListBrain.moved(before, at, dt) then
			self:_spot(player, at)
		end
		self.last[player] = at
	end
end

-- Every Run tick while Krampus is in his Lair.
function CuckooWatch:tick(t: number)
	local state = ListBrain.watchState(self.warnAt, t)
	if (state == "Warn" or state == "Look") and not self.warned then
		self.warned = true
		SoundPlayer.at("CuckooTick", self:_clockAt())
		self.run:_send(nil, "Cuckoo", { state = "Warn", seconds = C.WarnSeconds })
		Onboarding.teachAll(self.run.order, "Cuckoo")
		-- The doors swing open in the last moment of the warning, so the
		-- cuckoo is fully out when the look starts and shuts as it ends.
		self.lair:SetAttribute("CuckooHold", C.LookSeconds)
		self.lair:SetAttribute("CuckooAt", self.warnAt + C.WarnSeconds - LairMotion.CuckooOpenSeconds)
	end
	if state == "Look" then
		if not self.looking then
			self:_beginLook(t)
		else
			self:_look(t)
		end
	elseif state == "Done" then
		if self.looking then
			self:_look(t) -- the last moment of the look still counts
		end
		self.run:_send(nil, "Cuckoo", { state = "Off" })
		self.warnAt = ListBrain.nextWatch(self.rng, t)
		self.warned = false
		self.looking = false
	end
end

function CuckooWatch:destroy()
	self.run:_send(nil, "Cuckoo", { state = "Off" })
	if self.lair.Parent then
		self.lair:SetAttribute("CuckooHold", nil)
	end
end

return CuckooWatch
