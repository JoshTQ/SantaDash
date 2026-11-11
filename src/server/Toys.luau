--[[
	Toys to fight back (Josh, 11 Nov 2026: "Can we use the toys against them,
	like snow guns etc" ... "Build them"). Config.Toys, rules in ToyBrain.

	  Snowball Launcher  bought at the toy stand by every Sleigh Stop (a full
	                     load, then refills). R / ButtonX lobs a snowball at
	                     the nearest guard dog or Krampus in front of you
	                     (soft auto-aim). Dogs are knocked over for GuardDown;
	                     Krampus only flinches (any wind-up is cancelled), at
	                     most once per KrampusCooldown for the whole crew, and
	                     never drops his basket. Hits on the crew do nothing.
	  Glitter Bomb       T / ButtonY throws it ahead: a sparkly cloud where
	                     dogs and the cuckoo can't see anyone. Krampus can.

	The looks are GREYBOX stand-ins until Josh picks them
	(models/toys/toys-options.html). Clouds live in run.glitterClouds;
	GuardDogs and CuckooWatch ask run:inGlitter(position).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local Onboarding = require(script.Parent.Onboarding)
local ToyBrain = require(script.Parent.ToyBrain)

local T = Config.Toys
local SNOW = Color3.fromRGB(240, 248, 255)
local GLITTER = Color3.fromRGB(255, 120, 220)

local Toys = {}

function Toys.send(run, player: Player)
	local st = run.players[player]
	if st then
		run:_send(player, "Toys", {
			launcher = st.launcher == true,
			snowballs = st.snowballs or 0,
			glitters = st.glitters or 0,
		})
	end
end

-- The toy stand's launcher prompt: the launcher and a full load, then refills.
function Toys.buyLauncher(run, player: Player)
	local st = run.players[player]
	if not st then
		return
	end
	local L = T.Launcher
	if st.launcher and (st.snowballs or 0) >= L.Ammo then
		run:_banner(player, "Your launcher is already full (" .. L.Ammo .. " snowballs)", 2)
		run:_sfx(player, "Nope")
		return
	end
	local refill = st.launcher == true
	if
		run:_spend(
			player,
			if refill then L.Refill else L.Cost,
			if refill then "LauncherRefill" else "Launcher"
		)
	then
		st.launcher = true
		st.snowballs = L.Ammo
		run:_sendPlayer(player)
		Toys.send(run, player)
		run:_banner(
			player,
			if refill
				then "Launcher refilled!"
				else "Snowball Launcher! Press R (or LAUNCH) to knock over guards and make Krampus flinch.",
			3
		)
		Onboarding.teach(player, "Toys")
	end
end

function Toys.buyGlitter(run, player: Player)
	local st = run.players[player]
	if not st then
		return
	end
	local G = T.Glitter
	if (st.glitters or 0) >= G.Max then
		run:_banner(player, "Your pockets are full of glitter (" .. G.Max .. ")", 2)
		run:_sfx(player, "Nope")
	elseif run:_spend(player, G.Cost, "GlitterBomb") then
		st.glitters = (st.glitters or 0) + 1
		run:_sendPlayer(player)
		Toys.send(run, player)
		run:_banner(player, "Glitter Bomb! Press T (or GLITTER) to hide in a sparkly cloud.", 3)
	end
end

-- Everything a snowball can hit: Krampus (if he's out) and every dog that's up.
function Toys.targets(run): { ToyBrain.Target }
	local list = {}
	local krampus = run.krampus
	if krampus and krampus.alive and krampus.body and krampus.body.root.Parent then
		table.insert(list, {
			kind = "Krampus",
			position = krampus.body.root.Position,
			hit = function()
				if krampus.alive and krampus:flinch(Util.now()) then
					run:_banner(nil, "SPLAT! Krampus flinched!", 1.5)
				end
			end,
		})
	end
	for _, pack in run.dogPacks or {} do
		if pack.targets then
			for _, target in pack.targets() do
				table.insert(list, target)
			end
		end
	end
	return list
end

-- GREYBOX snowball: an anchored ball tweened to where it's going.
local function lob(run, from: Vector3, to: Vector3, seconds: number)
	local ball = Instance.new("Part")
	ball.Name = "LauncherSnowball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.2, 1.2, 1.2)
	ball.Color = SNOW
	ball.Material = Enum.Material.Snow
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CFrame = CFrame.new(from)
	ball.Parent = run.route.model
	TweenService:Create(ball, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) })
		:Play()
	task.delay(seconds, function()
		ball:Destroy()
	end)
end

function Toys.launch(run, player: Player)
	local st = run:_free(player)
	local root = Util.rootOf(player)
	if not st or not root or not st.launcher then
		return
	end
	local t = Util.now()
	if t - (st.lastLaunchAt or -math.huge) < T.Launcher.Cooldown then
		return
	end
	if (st.snowballs or 0) <= 0 then
		run:_banner(player, "Out of snowballs! Refill at the toy stand.", 2)
		run:_sfx(player, "Nope")
		return
	end
	st.lastLaunchAt = t
	st.snowballs -= 1
	Toys.send(run, player)
	local from = root.Position + Vector3.new(0, 1.5, 0)
	local look = root.CFrame.LookVector
	local target = ToyBrain.aim(root.Position, look, Toys.targets(run))
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local to = if target then target.position else from + flat * T.Launcher.Range
	local seconds = ToyBrain.flightSeconds(from, to)
	SoundPlayer.at("Boing", root)
	lob(run, from, to, seconds)
	if target then
		task.delay(seconds, function()
			if run.ended then
				return
			end
			SoundPlayer.at("DustPuff", to)
			if target.hit then
				target.hit(T.Launcher.GuardDown)
			end
		end)
	end
end

-- GREYBOX cloud: a see-through pink ball of sparkles.
local function cloudPart(run, at: Vector3): BasePart
	local G = T.Glitter
	local puff = Instance.new("Part")
	puff.Name = "GlitterCloud"
	puff.Shape = Enum.PartType.Ball
	puff.Size = Vector3.new(G.Radius * 2, G.Radius * 2, G.Radius * 2)
	puff.Color = GLITTER
	puff.Material = Enum.Material.Neon
	puff.Transparency = 0.75
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.CastShadow = false
	puff.CFrame = CFrame.new(at)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(GLITTER)
	sparkles.LightEmission = 0.8
	sparkles.Size = NumberSequence.new(0.5, 0)
	sparkles.Lifetime = NumberRange.new(0.6, 1.4)
	sparkles.Speed = NumberRange.new(2, 6)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 60
	sparkles.Parent = puff
	puff.Parent = run.route.model
	return puff
end

function Toys.glitter(run, player: Player)
	local st = run:_free(player)
	local root = Util.rootOf(player)
	if not st or not root or (st.glitters or 0) <= 0 then
		return
	end
	st.glitters -= 1
	Toys.send(run, player)
	local G = T.Glitter
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local at = root.Position + flat * G.Throw
	local t = Util.now()
	run.glitterClouds = run.glitterClouds or {}
	ToyBrain.prune(run.glitterClouds, t)
	table.insert(run.glitterClouds, { position = at, untilT = t + G.Seconds })
	local puff = cloudPart(run, at)
	task.delay(G.Seconds, function()
		puff:Destroy()
	end)
	SoundPlayer.at("GiftPop", at)
	run:_banner(nil, player.DisplayName .. " threw a Glitter Bomb! The guards can't see in the sparkles.", 2)
end

-- Inside a live glitter cloud: guards and the cuckoo can't see you.
function Toys.inGlitter(run, at: Vector3): boolean
	return ToyBrain.inCloud(run.glitterClouds or {}, at, Util.now())
end

return Toys
