--[[
	Krampus in one stop: hunts the nearest Santa he can sense, snatches them
	into his basket, carries them around, and drops them when a teammate rings
	the bells behind him (or the captive wiggles free). Hidden Santas run out of
	breath while he is near. Decisions live in KrampusBrain; this file moves him.

	Body: a Model named "Krampus" in ServerStorage.Assets if present (needs a
	Humanoid, a HumanoidRootPart and a part named "Basket"), else the greybox
	stand-in from MapBuilder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Cutscenes = require(ReplicatedStorage.Shared.Cutscenes)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local KrampusBrain = require(script.Parent.KrampusBrain)
local MapBuilder = require(script.Parent.MapBuilder)
local Mover = require(script.Parent.Mover)

local K = Config.Krampus
local TICK = 0.25

local Krampus = {}
Krampus.__index = Krampus

local function buildBody(parent: Instance, spawn: CFrame): MapBuilder.KrampusBody
	local assets = ServerStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Krampus")
	if template then
		local model = template:Clone() :: Model
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		local root = model:FindFirstChild("HumanoidRootPart", true) :: BasePart
		local basket = model:FindFirstChild("Basket", true) :: BasePart
		if humanoid and root and basket then
			model:PivotTo(spawn)
			humanoid.WalkSpeed = K.WalkSpeed
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Ring bells"
			prompt.ObjectText = "Krampus"
			prompt.HoldDuration = 0.3
			prompt.RequiresLineOfSight = false
			prompt.Parent = basket
			model.Parent = parent
			return { model = model, humanoid = humanoid, root = root, basket = basket, bellPrompt = prompt }
		end
		warn(
			"[Krampus] ServerStorage.Assets.Krampus needs Humanoid, HumanoidRootPart and Basket; using stand-in"
		)
	end
	return MapBuilder.buildKrampus(parent, spawn)
end

-- holdSeconds: how long he stands still on arrival (warning or intro cutscene).
function Krampus.new(run, stop, holdSeconds: number?)
	local self = setmetatable({}, Krampus)
	self.run = run
	self.stop = stop
	self.body = buildBody(run.route.model, stop.krampusSpawn)
	pcall(function()
		self.body.root:SetNetworkOwner(nil) -- server drives him
	end)
	self.mover = Mover.new(
		self.body.humanoid,
		self.body.root,
		{ AgentRadius = 3, AgentHeight = K.Height, AgentCanJump = false },
		K.RepathSeconds
	)
	self.captive = nil :: Player?
	self.wiggles = 0
	self.ignore = {} :: { [Player]: number }
	local t = Util.now()
	self.stunnedUntil = t + (holdSeconds or K.WarningSeconds) -- stands still while the warning shows
	self.lastBellAt = -math.huge
	self.alive = true
	-- His bells give him away: a 3D loop on his body that everyone nearby hears.
	-- It goes when his model is destroyed.
	SoundPlayer.loop("KrampusBells", self.body.root)

	self.connections = {
		self.body.bellPrompt.Triggered:Connect(function(player)
			self:_ringBells(player)
		end),
		-- Captives ride in the basket.
		RunService.Heartbeat:Connect(function()
			local root = self.captive and Util.rootOf(self.captive)
			if root then
				root.CFrame = self.body.basket.CFrame * CFrame.new(0, 2.5, 0)
			end
		end),
	}
	task.spawn(function()
		while self.alive do
			local ok, err = pcall(self._think, self, TICK)
			if not ok then
				warn("[Krampus] " .. tostring(err))
			end
			task.wait(TICK)
		end
	end)
	return self
end

----------------------------------------------------------------------------
-- Cutscene choreography (the camera side lives in CutscenePlayer)
----------------------------------------------------------------------------

-- Drives his pivot from a pure path (Cutscenes.krampusIntro / krampusFlop)
-- for `seconds`, anchored so the Humanoid can't fight it.
function Krampus:_puppet(seconds: number, pivotAt: (t: number) -> CFrame, keepAnchored: boolean?)
	local root = self.body.root
	root.Anchored = true
	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not self.alive then
			connection:Disconnect()
			return
		end
		local t = os.clock() - started
		self.body.model:PivotTo(pivotAt(math.min(t, seconds)))
		if t >= seconds then
			connection:Disconnect()
			if not keepAnchored then
				root.Anchored = false
			end
		end
	end)
end

-- KrampusArrives: tiptoe in from behind his spawn, clonk, roar.
function Krampus:playIntro(seconds: number)
	local spawn = self.stop.krampusSpawn
	self:_puppet(seconds, function(t)
		return spawn * Cutscenes.krampusIntro(t)
	end)
end

-- Getaway: he gives up the hunt, leaps for the sleigh and belly-flops.
function Krampus:playFlop(seconds: number, deck: Vector3)
	self:release()
	self.stunnedUntil = math.huge
	self.mover:stop()
	local start = self.body.model:GetPivot()
	self:_puppet(seconds, function(t)
		return Cutscenes.krampusFlop(t, start, deck)
	end, true)
end

function Krampus:destroy()
	if not self.alive then
		return
	end
	self:release()
	self.alive = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.body.model:Destroy()
end

----------------------------------------------------------------------------
-- Movement
----------------------------------------------------------------------------

function Krampus:_moveTo(goal: Vector3)
	self.mover:moveTo(goal)
end

-- With nobody to chase he patrols the loot that's left.
function Krampus:_wanderGoal(): Vector3
	if not self.wanderGoal or (self.wanderGoal - self.body.root.Position).Magnitude < 8 then
		local remaining = {}
		for _, present in self.stop.presents do
			if not present.taken then
				table.insert(remaining, present.model:GetPivot().Position)
			end
		end
		self.wanderGoal = if #remaining > 0
			then remaining[math.random(1, #remaining)]
			else self.stop.krampusSpawn.Position
	end
	return self.wanderGoal
end

----------------------------------------------------------------------------
-- Behaviour
----------------------------------------------------------------------------

function Krampus:_think(dt: number)
	local run = self.run
	local root = self.body.root
	local t = Util.now()
	run:krampusBreath(root.Position, dt)

	if t < self.stunnedUntil then
		self.mover:stop()
		return
	end

	if self.captive then
		self.body.humanoid.WalkSpeed = K.CarrySpeed
		self:_moveTo(self:_wanderGoal())
		return
	end
	self.body.humanoid.WalkSpeed = K.WalkSpeed

	local target = KrampusBrain.pickTarget(root.Position, run:krampusCandidates(self.ignore), t)
	if target then
		if KrampusBrain.canCatch(root.Position, target.position) then
			self:_snatch(target.player)
		else
			self:_moveTo(target.position)
		end
	elseif run.lastNoisePos then
		self:_moveTo(run.lastNoisePos) -- sniffs toward the latest noise
		SoundPlayer.at("KrampusSniff", root)
	else
		self:_moveTo(self:_wanderGoal())
	end
end

function Krampus:_snatch(player: Player)
	self.captive = player
	self.wiggles = 0
	self.run:onSnatched(player)
end

-- Drops the captive (if any) just behind him.
function Krampus:release()
	local player = self.captive
	if not player then
		return
	end
	self.captive = nil
	self.ignore[player] = Util.now() + K.ReleaseGrace
	self.run:onReleased(player, self.body.root.CFrame * CFrame.new(0, 0, 8))
end

function Krampus:wiggle(player: Player)
	if player ~= self.captive then
		return
	end
	self.wiggles += 1
	local needed = KrampusBrain.wiggleNeeded()
	if self.wiggles >= needed then
		self:release()
		self.run:_banner(nil, player.DisplayName .. " wiggled free!", 2)
	else
		self.run:_send(player, "Captive", { captive = true, wiggles = self.wiggles, needed = needed })
	end
end

function Krampus:_ringBells(player: Player)
	local run = self.run
	local root = Util.rootOf(player)
	if not run:_free(player) or not root then
		return
	end
	local t = Util.now()
	if t - self.lastBellAt < K.BellCooldown then
		return
	end
	if not KrampusBrain.isBehind(self.body.root.CFrame, root.Position) then
		run:_banner(player, "Get behind him to ring the bells!", 2)
		return
	end
	self.lastBellAt = t
	self.stunnedUntil = t + K.StunSeconds
	-- He spins round to find the bells.
	self.body.root.CFrame *= CFrame.Angles(0, math.pi, 0)
	SoundPlayer.at("BellBonk", self.body.root)
	SoundPlayer.at("KrampusDizzy", self.body.root)
	local captive = self.captive
	if captive then
		self:release()
		run:_banner(
			nil,
			player.DisplayName .. " rang the bells! Krampus dropped " .. captive.DisplayName .. "!",
			3
		)
	else
		run:_banner(nil, player.DisplayName .. " rang the bells! Krampus is dizzy!", 2)
	end
end

return Krampus
