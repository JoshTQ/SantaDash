--[[
	Security dogs a full noise meter lets loose (Config.Noise.Alarm, Josh 6 Nov
	2026). They run in from the far end of the street and chase the nearest
	Santa who isn't safe at the Sleigh Stop. A bump works like the Christmas
	Market dogs (DogBump): a corgi knocks a present out of your sack, a tin dog
	bonks you and winds down. They stay until the sleigh leaves.

	Body: the approved DogCorgi / DogTin models (ServerStorage.Assets), else a
	coloured block stand-in. Both walk with a Humanoid along a path (Mover).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Util = require(ReplicatedStorage.Shared.Util)
local Assets = require(script.Parent.Assets)
local CanalRules = require(script.Parent.CanalRules)
local DogBump = require(script.Parent.DogBump)
local MapBuilder = require(script.Parent.MapBuilder)
local Mover = require(script.Parent.Mover)
local NoiseAlarm = require(script.Parent.NoiseAlarm)
local RigAnimator = require(script.Parent.RigAnimator)

local A = Config.Noise.Alarm
local TICK = 0.2

local AlarmDogs = {}

local function standIn(kind: string, cframe: CFrame): Model
	local corgi = kind == "DogCorgi"
	local fur = if corgi then Color3.fromRGB(225, 140, 60) else Color3.fromRGB(185, 190, 200)
	local model = Instance.new("Model")
	model.Name = kind .. "StandIn"
	local hip = 1
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 1.6, 3)
	root.CFrame = cframe
	root.Transparency = 1
	root.Parent = model
	local function piece(name: string, size: Vector3, offset: Vector3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe * CFrame.new(offset)
		part.Color = fur
		part.CanCollide = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
	piece("Body", Vector3.new(2, 1.6, if corgi then 3.4 else 4.4), Vector3.zero)
	piece("Head", Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 1, -2.2))
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hip
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

local function buildDog(parent: Instance, kind: string, cframe: CFrame)
	local model = Assets.clone(kind, { "Humanoid", "HumanoidRootPart" }) or standIn(kind, cframe)
	model:PivotTo(cframe)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart", true) :: BasePart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	humanoid.WalkSpeed = A.ChaseSpeed
	model.Parent = parent
	pcall(function()
		root:SetNetworkOwner(nil) -- the server drives the dogs
	end)
	return {
		kind = kind,
		model = model,
		humanoid = humanoid,
		root = root,
		anim = RigAnimator.new(model), -- no-op on the stand-in
		mover = Mover.new(
			humanoid,
			root,
			{ AgentRadius = 2, AgentHeight = 3, AgentCanJump = true },
			A.RepathSeconds
		),
		pausedUntil = 0,
		hitAt = {} :: { [Player]: number },
	}
end

-- Lets the dogs loose for this stop. Returns their cleanup.
function AlarmDogs.start(run, stop): () -> ()
	local parent = run.route.model
	local release = stop.krampusSpawn -- the far end of the street
	local dogs = {}
	for i, kind in A.Dogs do
		local at = release * CFrame.new(NoiseAlarm.spawnOffset(i, #A.Dogs))
		local ok, dog = pcall(buildDog, parent, kind, at)
		if ok then
			table.insert(dogs, dog)
		else
			warn("[AlarmDogs] couldn't build " .. kind .. ": " .. tostring(dog))
		end
	end
	local dropper = DogBump.dropper(run, parent)
	local alive = true

	local function think()
		local t = Util.now()
		local santas = {}
		for player in run.players do
			local root = Util.rootOf(player)
			if root and run:_free(player) then
				table.insert(santas, {
					player = player,
					root = root,
					position = root.Position,
					safe = MapBuilder.isAboard(stop.deckCFrame, root.Position),
				})
			end
		end
		for _, dog in dogs do
			if not dog.model.Parent then
				continue
			end
			local pos = dog.root.Position
			if dog.pausedUntil > t then
				dog.mover:stop()
				dog.anim:play("Idle")
				continue
			end
			local santa = NoiseAlarm.target(pos, santas)
			if not santa then
				dog.mover:stop()
				dog.anim:play("Idle")
				continue
			end
			dog.mover:moveTo(santa.position)
			dog.anim:play("Walk")
			local root = santa.root
			local offset = (root.Position - pos) * Vector3.new(1, 0, 1)
			local corgi = dog.kind == "DogCorgi"
			if Sounds.dogWarns(offset.Magnitude, A.HitRadius, Config.Canal.Dogs.WarnRadius) then
				SoundPlayer.at(if corgi then "CorgiGrowl" else "TinDogWhirr", dog.root)
			end
			if
				(dog.hitAt[santa.player] or 0) + A.Cooldown < t
				and CanalRules.inReach(root.Position, pos, A.HitRadius)
			then
				dog.hitAt[santa.player] = t
				local facing = dog.root.CFrame.LookVector
				local pause = DogBump.hit(run, dropper, dog.kind, santa.player, root, pos, facing, dog.root)
				if pause > 0 then
					dog.pausedUntil = t + pause
				end
			end
		end
	end

	task.spawn(function()
		while alive do
			local ok, err = pcall(think)
			if not ok then
				warn("[AlarmDogs] " .. tostring(err))
			end
			task.wait(TICK)
		end
	end)

	return function()
		alive = false
		for _, dog in dogs do
			dog.model:Destroy()
		end
		dropper.cleanup()
	end
end

return AlarmDogs
