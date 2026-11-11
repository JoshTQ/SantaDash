--[[
	Krampus's magic tricks (Josh, 6 Nov 2026: "Krampus is too easy").

	  Frost Zap    glowing blue hands, then a snowflake orb; a hit turns that
	               Santa into a sliding ice cube for a moment. Teammates smash
	               it (3 hits), or the frozen Santa taps their way out. He can
	               still walk over and snatch an ice cube, which is the threat.
	  Frost Stomp  hoof up, then a ring of frost rolls out along the floor.
	               Jump it or skid at half speed; it leaves skiddy patches.
	  Bell Blink   a ring of gold bells lights up beside the noisiest Santa who
	               has got away; he vanishes in soot and pops out there.

	The Grumpy Meter (KrampusBrain.grumpyLevel) unlocks the tricks over the
	Lair and speeds him up. Decisions are pure (KrampusBrain); this file does
	the effects. While a trick is winding up he stands still, and ringing his
	bells cancels it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local KrampusBrain = require(script.Parent.KrampusBrain)
local Onboarding = require(script.Parent.Onboarding)
local Swimming = require(script.Parent.Swimming)

local M = Config.Krampus.Magic
local FROST = Color3.fromRGB(127, 227, 255)
local GOLD = Color3.fromRGB(255, 209, 102)
local SOOT = Color3.fromRGB(70, 60, 90)

local Magic = {}
Magic.__index = Magic

export type Cube = { part: BasePart, hits: number, taps: number }

-- An invisible anchored part that holds a trick's adornments and particles.
local SUMMON_SECONDS = 2 -- a summon he can't act on by then is forgotten

local function anchor(name: string, at: CFrame): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = at
	part.Parent = workspace
	return part
end

-- A flat ring (or disc, with inner 0) lying on the floor, drawn on `on`.
local function ring(on: BasePart, color: Color3, outer: number, inner: number, offset: CFrame?): Instance
	local a = Instance.new("CylinderHandleAdornment")
	a.Adornee = on
	a.Color3 = color
	a.Transparency = 0.25
	a.Radius = outer
	a.InnerRadius = inner
	a.Height = 1.2
	a.CFrame = (offset or CFrame.new()) * CFrame.Angles(math.rad(90), 0, 0)
	a.Parent = on
	return a
end

local function sparkles(parent: Instance, color: Color3, rate: number): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Color = ColorSequence.new(color)
	p.LightEmission = 0.6
	p.Size = NumberSequence.new(0.6, 0)
	p.Lifetime = NumberRange.new(0.4, 0.9)
	p.Speed = NumberRange.new(2, 6)
	p.SpreadAngle = Vector2.new(180, 180)
	p.Rate = rate
	p.Parent = parent
	return p
end

-- Exclude-filter raycast params, or nil where there are none (the Lune test world).
local function rayParams(exclude: { Instance }): RaycastParams?
	local ok, params = pcall(function()
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = exclude
		p.RespectCanCollide = true
		return p
	end)
	return if ok then params else nil
end

local FLOOR_PARAMS = rayParams({})

local function cast(from: Vector3, by: Vector3, params: RaycastParams?): RaycastResult?
	if not params then
		return nil
	end
	local ok, hit = pcall(workspace.Raycast, workspace, from, by, params)
	return if ok then hit else nil
end

-- The floor under a point, if the world can tell us (falls back to `y`).
local function floorY(at: Vector3, y: number): number
	local hit = cast(at, Vector3.new(0, -30, 0), FLOOR_PARAMS)
	return if hit then hit.Position.Y else y
end

function Magic.new(krampus, arrivedAt: number)
	local self = setmetatable({}, Magic)
	self.krampus = krampus
	self.run = krampus.run
	self.arrivedAt = arrivedAt
	self.lastCastAt = -math.huge
	self.lastTrick = nil :: string?
	self.bellRings = 0
	self.hitAt = {} :: { [Player]: number }
	self.cubes = {} :: { [Player]: Cube }
	self.patches = {} :: { { at: Vector3, untilT: number } }
	self.casting = nil :: string?
	self.token = 0
	self.temp = {} :: { Instance } -- telegraphs and effects to clear on cancel
	self.alive = true
	self.summoned = nil :: Player? -- the Cuckoo Watch's spotted Santa (summon)
	self.summonedAt = 0
	local run = self.run
	self.safe = function(at: Vector3)
		return run:nearSleighStop(at, M.BellBlink.SafeMargin)
	end
	return self
end

function Magic:level(t: number): number
	return KrampusBrain.grumpyLevel(t - self.arrivedAt, self.bellRings)
end

-- Ringing his bells makes him grumpier, and cancels a trick mid wind-up.
function Magic:onBells()
	self.bellRings += 1
	self:cancel()
end

function Magic:_clearTemp()
	self.casting = nil
	for _, thing in self.temp do
		thing:Destroy()
	end
	table.clear(self.temp)
end

function Magic:cancel()
	self.token += 1
	self:_clearTemp()
	pcall(function()
		self.krampus.body.root.Anchored = false
	end)
end

function Magic:_keep(thing: Instance): Instance
	table.insert(self.temp, thing)
	return thing
end

-- Called every Krampus tick when he is free to act, with this tick's
-- candidates. Returns true while a trick is being cast (he stands still).
function Magic:think(t: number, candidates: { KrampusBrain.Candidate }): boolean
	self:_skidPatches(t)
	if self.casting then
		return true
	end
	local summoned, summonedAt = self.summoned, self.summonedAt
	self.summoned = nil
	if summoned and t - summonedAt <= SUMMON_SECONDS then
		local target = KrampusBrain.summonTarget({
			now = t,
			from = self.krampus.body.root.Position,
			candidates = candidates,
			hitAt = self.hitAt,
			safe = self.safe,
		}, summoned)
		if target then
			self:_cast("BellBlink", target, t)
			return true
		end
	end
	local level = self:level(t)
	if t < self.arrivedAt + M.FirstCastAfter or t - self.lastCastAt < M.Grumpy.Cooldown[level] then
		return false
	end
	local trick, target = KrampusBrain.pickTrick({
		now = t,
		level = level,
		lastCastAt = self.lastCastAt,
		lastTrick = self.lastTrick,
		from = self.krampus.body.root.Position,
		candidates = candidates,
		hitAt = self.hitAt,
		noiseAt = self.run.lastNoisePos,
		safe = self.safe,
	})
	if not trick or not target then
		return false
	end
	self:_cast(trick, target, t)
	return true
end

function Magic:_cast(trick: string, target: KrampusBrain.Candidate, t: number)
	self.lastCastAt = t
	self.lastTrick = trick
	self.casting = trick
	self.token += 1
	local token = self.token
	task.spawn(function()
		local ok, err = pcall(self["_" .. trick], self, target.player, target.position, token)
		if not ok then
			warn("[KrampusMagic] " .. trick .. ": " .. tostring(err))
		end
		if self.token == token then
			self:_clearTemp()
		end
	end)
end

-- The Cuckoo Watch spotted `player` moving: at his next free moment he Bell
-- Blinks to them, whatever his grumpiness and cooldown (KrampusBrain.summonTarget).
function Magic:summon(player: Player)
	if self.alive then
		self.summoned = player
		self.summonedAt = Util.now()
	end
end

-- Waits `seconds`; false if the trick was cancelled (bells) or he's gone.
function Magic:_wait(seconds: number, token: number): boolean
	task.wait(seconds)
	return self.alive and self.token == token
end

function Magic:_face(at: Vector3)
	local root = self.krampus.body.root
	local p = root.Position
	local look = Vector3.new(at.X, p.Y, at.Z)
	if (look - p).Magnitude > 0.1 then
		self.krampus.body.model:PivotTo(CFrame.lookAt(p, look))
	end
end

----------------------------------------------------------------------------
-- Frost Zap
----------------------------------------------------------------------------

function Magic:_FrostZap(_player: Player, aim: Vector3, token: number)
	local z = M.FrostZap
	local root = self.krampus.body.root
	self:_face(aim)
	self.krampus.anim:oneShot("Scheme", 1)
	local glow = self:_keep(Instance.new("PointLight")) :: PointLight
	glow.Color = FROST
	glow.Brightness = 3
	glow.Range = 14
	glow.Shadows = false
	glow.Parent = root
	self:_keep(sparkles(root, FROST, 40))
	SoundPlayer.at("IceCrack", root)
	if not self:_wait(z.WindUp, token) then
		return
	end
	-- The orb: a slow snowflake ball that flies straight and stops at walls.
	local start = root.Position + Vector3.new(0, 2, 0)
	local dir = Vector3.new(aim.X - start.X, 0, aim.Z - start.Z)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else root.CFrame.LookVector
	local orb = self:_keep(anchor("FrostOrb", CFrame.new(start))) :: Part
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(2.5, 2.5, 2.5)
	orb.Material = Enum.Material.Ice
	orb.Color = FROST
	orb.Transparency = 0.2
	self:_keep(sparkles(orb, FROST, 30))
	SoundPlayer.at("CutsceneYoink", orb)
	self.casting = nil -- he can move again while it flies
	local params = rayParams({ self.krampus.body.model, orb })
	local travelled, hit = 0, nil
	while travelled < z.OrbSpeed * z.OrbFlight do
		local dt = RunService.Heartbeat:Wait()
		if not self.alive or self.token ~= token then
			return
		end
		local step = dir * z.OrbSpeed * dt
		local here = orb.CFrame.Position
		local wall = cast(here, step, params)
		if wall and not Util.playerFromHit(wall.Instance) then
			break -- splats on a wall
		end
		orb.CFrame = CFrame.new(here + step)
		travelled += step.Magnitude
		hit = self:_orbHit(orb.CFrame.Position)
		if hit then
			break
		end
	end
	orb:Destroy()
	if hit then
		self:freeze(hit, dir)
	end
end

-- Any free Santa the orb is touching (not only the one he aimed at).
function Magic:_orbHit(at: Vector3): Player?
	for player in self.run.players do
		local root = Util.rootOf(player)
		if
			root
			and self.run:_free(player)
			and (root.Position - at).Magnitude <= M.FrostZap.HitRadius
			and not self.run:nearSleighStop(root.Position, 0)
		then
			return player
		end
	end
	return nil
end

function Magic:freeze(player: Player, slide: Vector3?)
	local run = self.run
	local st = run.players[player]
	local root = Util.rootOf(player)
	if not st or not root or self.cubes[player] then
		return
	end
	st.iced = true
	self.hitAt[player] = Util.now()
	root.Anchored = true
	local cube = Swimming.iceCube(root, "IcedSanta")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Smash the ice"
	prompt.ObjectText = player.DisplayName
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = cube
	local entry = { part = cube, hits = 0, taps = 0 }
	self.cubes[player] = entry
	prompt.Triggered:Connect(function(by: Player)
		if by ~= player and run:_free(by) then
			self:_smash(player, by)
		end
	end)
	SoundPlayer.at("IceCrack", root.Position)
	run:_send(player, "Iced", { iced = true, taps = 0, needed = M.FrostZap.CrackTaps })
	run:_banner(player, "FROZEN! Tap fast to crack out!", 2)
	run:_banner(nil, player.DisplayName .. " is an ice cube! Smash them out!", 2)
	Onboarding.teach(player, "IceCube")
	-- The cube skids a few studs, like a hockey puck.
	if slide and M.FrostZap.SlideStuds > 0 then
		task.spawn(function()
			local from = root.CFrame
			for i = 1, 5 do
				task.wait(0.06)
				if self.cubes[player] ~= entry then
					return
				end
				local cf = from + slide * (M.FrostZap.SlideStuds * i / 5)
				root.CFrame = cf
				cube.CFrame = CFrame.new(cf.Position)
			end
		end)
	end
	task.delay(M.FrostZap.FrozenSeconds, function()
		if self.cubes[player] == entry then
			self:thaw(player)
		end
	end)
end

function Magic:_smash(player: Player, by: Player)
	local entry = self.cubes[player]
	if not entry then
		return
	end
	entry.hits += 1
	SoundPlayer.at("BellBonk", entry.part)
	if entry.hits >= M.FrostZap.SmashHits then
		self:thaw(player)
		self.run:_banner(nil, by.DisplayName .. " smashed " .. player.DisplayName .. " out of the ice!", 2)
	end
end

-- The frozen Santa's own taps.
function Magic:crack(player: Player)
	local entry = self.cubes[player]
	if not entry then
		return
	end
	entry.taps += 1
	if entry.taps >= M.FrostZap.CrackTaps then
		self:thaw(player)
		self.run:_banner(nil, player.DisplayName .. " cracked out of the ice!", 2)
	else
		self.run:_send(player, "Iced", { iced = true, taps = entry.taps, needed = M.FrostZap.CrackTaps })
	end
end

-- Out of the ice (quiet: he is snatching them, so no banner and stay anchored).
function Magic:thaw(player: Player, quiet: boolean?)
	local entry = self.cubes[player]
	if not entry then
		return
	end
	self.cubes[player] = nil
	entry.part:Destroy()
	local run = self.run
	local st = run.players[player]
	if st then
		st.iced = false
	end
	run:_send(player, "Iced", { iced = false })
	if quiet then
		return
	end
	SoundPlayer.at("IceCrack", entry.part.Position)
	local root = Util.rootOf(player)
	if root and st and not st.captive then
		root.Anchored = false
	end
end

----------------------------------------------------------------------------
-- Frost Stomp
----------------------------------------------------------------------------

local function airborne(player: Player, root: BasePart, startY: number?): boolean
	local humanoid = Util.humanoidOf(player)
	if not humanoid then
		return true
	end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return true
	end
	return startY ~= nil and root.Position.Y - startY >= M.FrostStomp.JumpClearance
end

function Magic:_FrostStomp(_player: Player, _aim: Vector3, token: number)
	local s = M.FrostStomp
	local run = self.run
	local root = self.krampus.body.root
	self.krampus.anim:oneShot("Scheme", 1)
	local centre = root.Position
	local ground = floorY(centre, centre.Y - Config.Krampus.Height / 2)
	local base = self:_keep(anchor("FrostStomp", CFrame.new(centre.X, ground + 0.6, centre.Z)))
	self:_keep(ring(base, FROST, 9, 0)) -- the floor frosts over round his hooves
	SoundPlayer.at("CutsceneStrain", root)
	-- Where every Santa stood, so a jump counts even where states don't replicate.
	local startY: { [Player]: number } = {}
	for player in run.players do
		local r = Util.rootOf(player)
		if r then
			startY[player] = r.Position.Y
			if (r.Position - centre).Magnitude <= s.Radius + 10 then
				Onboarding.teach(player, "FrostRing")
			end
		end
	end
	if not self:_wait(s.WindUp, token) then
		return
	end
	SoundPlayer.at("KrampusStomp", root)
	local wave = ring(base, FROST, 1, 0)
	local hit: { [Player]: boolean } = {}
	local started = os.clock()
	self.casting = nil -- he can chase behind his ring
	while self.alive and self.token == token do
		local t = os.clock() - started
		local r = KrampusBrain.stompRadius(t)
		wave.Radius = math.max(1, r)
		wave.InnerRadius = math.max(0, r - s.RingWidth)
		for player in run.players do
			local pr = Util.rootOf(player)
			if pr and not hit[player] and run:_free(player) then
				local d = KrampusBrain.flat(pr.Position, centre)
				if
					KrampusBrain.stompHits(d, r, false) -- the cheap band check first
					and not airborne(player, pr, startY[player])
					and not run:nearSleighStop(pr.Position, 0)
				then
					hit[player] = true
					self.hitAt[player] = Util.now()
					self:skid(player)
				end
			end
		end
		if t >= s.Seconds then
			break
		end
		RunService.Heartbeat:Wait()
	end
	-- Skiddy frost patches, for PatchSeconds.
	local patches = anchor("FrostPatches", CFrame.new(centre.X, ground + 0.1, centre.Z))
	local untilT = Util.now() + s.PatchSeconds
	for i = 1, s.Patches do
		local angle = (i / s.Patches) * math.pi * 2 + math.random() * 0.8
		local dist = s.Radius * (0.35 + 0.4 * math.random())
		local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		local disc = ring(patches, FROST, s.PatchRadius, 0, CFrame.new(offset))
		disc.Height = 0.2
		disc.Transparency = 0.55
		table.insert(self.patches, { at = centre + offset, untilT = untilT })
	end
	task.delay(s.PatchSeconds, function()
		patches:Destroy()
	end)
end

-- Skids a Santa at half speed for SkidSeconds (more frost just extends it).
function Magic:skid(player: Player)
	local run = self.run
	local st = run.players[player]
	if not st then
		return
	end
	local skidding = (st.skidUntil or 0) > Util.now()
	st.skidUntil = Util.now() + M.FrostStomp.SkidSeconds
	if skidding then
		return
	end
	run:_applyPerks(player)
	run:_banner(player, "Whoa! Skidding on frost!", 2)
	SoundPlayer.at("CutsceneYoink", Util.rootOf(player) or self.krampus.body.root)
	task.spawn(function()
		repeat
			task.wait(math.max(0.05, (st.skidUntil or 0) - Util.now() + 0.05))
		until (st.skidUntil or 0) <= Util.now()
		if run.players[player] == st then
			run:_applyPerks(player)
		end
	end)
end

function Magic:_skidPatches(t: number)
	local patches = self.patches
	for i = #patches, 1, -1 do
		if patches[i].untilT <= t then
			table.remove(patches, i)
		end
	end
	if #patches == 0 then
		return
	end
	for player in self.run.players do
		local root = Util.rootOf(player)
		if root and self.run:_free(player) then
			local p = root.Position
			for _, patch in patches do
				if
					KrampusBrain.flat(p, patch.at) <= M.FrostStomp.PatchRadius
					and math.abs(p.Y - patch.at.Y) < 8
				then
					self:skid(player)
					break
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Bell Blink
----------------------------------------------------------------------------

function Magic:_BellBlink(player: Player, aim: Vector3, token: number)
	local b = M.BellBlink
	local krampus = self.krampus
	local root = krampus.body.root
	local spot = KrampusBrain.blinkSpot(root.Position, aim)
	local ground = floorY(spot + Vector3.new(0, 6, 0), aim.Y - 3)
	SoundPlayer.at("CutsceneBells", root)
	krampus.anim:oneShot("Scheme", 1)
	-- The warning: a jingling ring of gold bells where he'll pop out.
	local marker = self:_keep(anchor("BellBlink", CFrame.new(spot.X, ground + 0.6, spot.Z)))
	ring(marker, GOLD, 7, 5.5)
	sparkles(marker, GOLD, 25)
	SoundPlayer.at("CountdownTick", marker)
	local puff = sparkles(root, SOOT, 0)
	self:_keep(puff)
	if not self:_wait(b.WindUp * 0.4, token) then
		return
	end
	-- Poof: gone in a cloud of soot and sparkles.
	puff:Emit(40)
	SoundPlayer.at("Boing", root)
	local hidden = krampus.body.model:GetPivot()
	-- His pivot's height above the floor, so he lands standing on it.
	local lift = hidden.Position.Y - floorY(hidden.Position, hidden.Position.Y - Config.Krampus.Height / 2)
	root.Anchored = true
	krampus.mover:stop()
	krampus.body.model:PivotTo(hidden - Vector3.new(0, 200, 0))
	if not self:_wait(b.WindUp * 0.6, token) then
		krampus.body.model:PivotTo(hidden)
		return
	end
	local land = CFrame.new(spot.X, ground + lift, spot.Z)
	land = CFrame.lookAt(land.Position, Vector3.new(aim.X, land.Position.Y, aim.Z) + Vector3.new(0, 0, 1e-3))
	krampus.body.model:PivotTo(land)
	root.Anchored = false
	puff:Emit(40)
	SoundPlayer.at("CutsceneBonk", root)
	self.run:_banner(player, "DING! Krampus popped up right next to you!", 2)
	self.hitAt[player] = Util.now()
	-- A quick lunge after he lands.
	krampus.lungeUntil = Util.now() + b.LungeSeconds
end

function Magic:destroy()
	self.alive = false
	self:cancel()
	for player in table.clone(self.cubes) do
		self:thaw(player)
	end
	table.clear(self.patches)
end

return Magic
