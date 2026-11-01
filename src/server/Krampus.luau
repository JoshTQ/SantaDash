--[[
	Krampus in one stop: hunts the nearest Santa he can sense, snatches them
	into his basket, carries them around, and drops them when a teammate rings
	the bells behind him (or the captive wiggles free). Hidden Santas run out of
	breath while he is near. Decisions live in KrampusBrain; this file moves him.

	Body: a Model named "Krampus" in ServerStorage.Assets if present (needs a
	Humanoid, a HumanoidRootPart and a part named "Basket"), else the greybox
	stand-in from MapBuilder.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local KrampusBrain = require(script.Parent.KrampusBrain)
local MapBuilder = require(script.Parent.MapBuilder)

local K = Config.Krampus
local TICK = 0.25

local Krampus = {}
Krampus.__index = Krampus

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

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

function Krampus.new(run, stop)
	local self = setmetatable({}, Krampus)
	self.run = run
	self.stop = stop
	self.body = buildBody(run.route.model, stop.krampusSpawn)
	pcall(function()
		self.body.root:SetNetworkOwner(nil) -- server drives him
	end)
	self.path = PathfindingService:CreatePath({
		AgentRadius = 3,
		AgentHeight = K.Height,
		AgentCanJump = false,
	})
	self.waypoints = nil :: { PathWaypoint }?
	self.waypointIndex = 0
	self.goal = nil :: Vector3?
	self.pathAt = 0
	self.captive = nil :: Player?
	self.wiggles = 0
	self.ignore = {} :: { [Player]: number }
	local t = Util.now()
	self.stunnedUntil = t + K.WarningSeconds -- stands still while the warning shows
	self.lastBellAt = -math.huge
	self.alive = true

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
	local root = self.body.root
	local t = os.clock()
	local stale = not self.goal or (self.goal - goal).Magnitude > 6 or t - self.pathAt > K.RepathSeconds
	if stale then
		self.goal = goal
		self.pathAt = t
		local ok = pcall(function()
			self.path:ComputeAsync(root.Position, goal)
		end)
		if ok and self.path.Status == Enum.PathStatus.Success then
			self.waypoints = self.path:GetWaypoints()
			self.waypointIndex = 2
		else
			self.waypoints = nil
		end
	end
	local waypoints = self.waypoints
	if not waypoints then
		self.body.humanoid:MoveTo(goal) -- no path: walk straight at it
		return
	end
	local waypoint = waypoints[self.waypointIndex]
	while waypoint and flatDistance(waypoint.Position, root.Position) < 4 do
		self.waypointIndex += 1
		waypoint = waypoints[self.waypointIndex]
	end
	self.body.humanoid:MoveTo(if waypoint then waypoint.Position else goal)
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
		self.body.humanoid:MoveTo(root.Position)
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
