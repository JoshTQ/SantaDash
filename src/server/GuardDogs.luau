--[[
	Guard dogs on the move: the Christmas Market patrols (CanalTown) and the
	alarm dogs a full noise meter lets loose (AlarmDogs). DogBrain decides,
	this module walks them (Humanoid + Mover), shows a "?" / "!" over their
	heads, swings the tin dog's head lamp, barks, calls the pack and bumps
	Santas (DogBump).

	spec = { kind, at: CFrame, patrol: { Vector3 }?, startIndex: number?,
	         hunt: boolean?, cooldown: number }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Util = require(ReplicatedStorage.Shared.Util)
local Assets = require(script.Parent.Assets)
local CanalRules = require(script.Parent.CanalRules)
local DogBrain = require(script.Parent.DogBrain)
local DogBump = require(script.Parent.DogBump)
local Mover = require(script.Parent.Mover)
local RigAnimator = require(script.Parent.RigAnimator)

local AI = Config.DogAI
local TICK = 0.2
local CORGI = Color3.fromRGB(225, 140, 60)
local TIN = Color3.fromRGB(185, 190, 200)
local LAMP = Color3.fromRGB(255, 226, 150)
local LAMP_CHASE = Color3.fromRGB(255, 70, 60)
local QUESTION = Color3.fromRGB(255, 214, 60)
local BANG = Color3.fromRGB(255, 60, 60)

local GuardDogs = {}

-- Dog flaps (Config.DogAI.Flaps): dogs don't collide with closed front doors.
local DOG_GROUP = "SleighHeistDogs"
local FLAP_GROUP = "SleighHeistDogFlapDoors"
pcall(function()
	local PhysicsService = game:GetService("PhysicsService")
	PhysicsService:RegisterCollisionGroup(DOG_GROUP)
	PhysicsService:RegisterCollisionGroup(FLAP_GROUP)
	PhysicsService:CollisionGroupSetCollidable(DOG_GROUP, FLAP_GROUP, false)
end)

-- The front doors of a stop as dog flaps: each door's house box, a point
-- just outside and just inside it. Built once per stop, with a GREYBOX flap
-- (a dark panel at the foot of the door, swinging with it). Art round pending.
function GuardDogs.flapsFor(stop): { any }
	if stop.dogFlaps then
		return stop.dogFlaps
	end
	local flaps = {}
	if AI.Flaps then
		for _, door in stop.doors or {} do
			local part = door.door
			local frontDoor = part.Parent
			local house = if frontDoor and frontDoor.Name == "FrontDoor" then frontDoor.Parent else frontDoor
			if house and house:IsA("Model") then
				local box, size = house:GetBoundingBox()
				local at = door.closed.Position
				local out = Vector3.new(at.X - box.Position.X, 0, at.Z - box.Position.Z)
				out = if out.Magnitude > 1e-3 then out.Unit else Vector3.zAxis
				pcall(function()
					part.CollisionGroup = FLAP_GROUP
				end)
				if not part:FindFirstChild("DogFlap") then
					local flap = Instance.new("Part")
					flap.Name = "DogFlap"
					flap.Size = Vector3.new(1.8, 1.6, part.Size.Z + 0.1)
					flap.CFrame = part.CFrame * CFrame.new(0, -part.Size.Y / 2 + 0.9, 0)
					flap.Color = Color3.fromRGB(60, 45, 35)
					flap.CanCollide = false
					flap.Massless = true
					flap.Anchored = part.Anchored
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = part
					weld.Part1 = flap
					weld.Parent = flap
					flap.Parent = part
				end
				table.insert(flaps, {
					door = door,
					box = box,
					size = size,
					outside = at + out * 3,
					inside = at - out * 3,
					open = door.open == true,
				})
			end
		end
	end
	stop.dogFlaps = flaps
	return flaps
end

-- A stolen present in the corgi's mouth (GREYBOX red box, like dropped ones).
local function showCarry(dog, carrying: boolean)
	if carrying and not dog.carryPart then
		local box = Instance.new("Part")
		box.Name = "StolenPresent"
		box.Size = Vector3.one * 1.2
		box.Color = Color3.fromRGB(230, 50, 60)
		box.CanCollide = false
		box.Massless = true
		box.CFrame = dog.root.CFrame * CFrame.new(0, 0.6, -2.4)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = dog.root
		weld.Part1 = box
		weld.Parent = box
		box.Parent = dog.model
		dog.carryPart = box
	elseif not carrying and dog.carryPart then
		dog.carryPart:Destroy()
		dog.carryPart = nil
	end
end

export type Spec = {
	kind: string,
	at: CFrame,
	patrol: { Vector3 }?,
	startIndex: number?,
	hunt: boolean?,
	leash: number?,
	cooldown: number,
}

local function standIn(kind: string, cframe: CFrame): Model
	local corgi = kind == "DogCorgi"
	local fur = if corgi then CORGI else TIN
	local model = Instance.new("Model")
	model.Name = kind
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 1.6, 3)
	root.CFrame = cframe
	root.Transparency = 1
	root.Parent = model
	local function piece(name: string, size: Vector3, offset: Vector3, color: Color3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe * CFrame.new(offset)
		part.Color = color
		part.CanCollide = false
		part.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		part.Parent = model
	end
	piece("Body", Vector3.new(2, 1.6, if corgi then 3.4 else 4.4), Vector3.zero, fur)
	piece("Head", Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 1, -2.2), fur)
	if corgi then
		piece("PatrolSled", Vector3.new(2.6, 0.4, 4.4), Vector3.new(0, -1, 0), Color3.fromRGB(215, 40, 50))
	else
		piece("WindUpKey", Vector3.new(0.3, 1.4, 1.4), Vector3.new(0, 1.2, 0.8), Color3.fromRGB(240, 190, 60))
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = 1
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	model.PrimaryPart = root
	return model
end

-- "?" while it's suspicious, "!" while it chases.
local function addIndicator(root: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DogAlert"
	gui.Size = UDim2.fromOffset(44, 44)
	gui.StudsOffset = Vector3.new(0, 3.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Mark"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "?"
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = QUESTION
	label.TextStrokeTransparency = 0
	label.Parent = gui
	gui.Parent = root
	return gui, label
end

-- The tin dog's head lamp: shows players exactly where it's looking.
local function addLamp(root: BasePart, kind: string)
	if not DogBrain.kind(kind).Sweep then
		return nil, nil
	end
	local eye = Instance.new("Attachment")
	eye.Name = "DogLamp"
	eye.Position = Vector3.new(0, 0.8, -2.2)
	local light = Instance.new("SpotLight")
	light.Name = "Lamp"
	light.Angle = DogBrain.kind(kind).Fov
	light.Range = math.min(60, AI.SightRange.Lit * DogBrain.kind(kind).SightScale)
	light.Brightness = 4
	light.Color = LAMP
	light.Face = Enum.NormalId.Front
	light.Shadows = false
	light.Parent = eye
	eye.Parent = root
	return eye, light
end

local function buildDog(parent: Instance, spec: Spec)
	local model = Assets.clone(spec.kind, { "Humanoid", "HumanoidRootPart" }) or standIn(spec.kind, spec.at)
	model:PivotTo(spec.at)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart", true) :: BasePart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			pcall(function()
				part.CollisionGroup = DOG_GROUP -- through the dog flaps
			end)
		end
	end
	humanoid.WalkSpeed = Config.Canal.Dogs.Speed
	model.Parent = parent
	pcall(function()
		root:SetNetworkOwner(nil) -- the server drives the dogs
	end)
	local gui, label = addIndicator(root)
	local eye, lamp = addLamp(root, spec.kind)
	return {
		spec = spec,
		kind = spec.kind,
		model = model,
		humanoid = humanoid,
		root = root,
		anim = RigAnimator.new(model), -- no-op on the stand-in
		mover = Mover.new(
			humanoid,
			root,
			{ AgentRadius = 2, AgentHeight = 3, AgentCanJump = true },
			Config.Noise.Alarm.RepathSeconds
		),
		brain = DogBrain.new(
			spec.kind,
			{ patrol = spec.patrol, startIndex = spec.startIndex, hunt = spec.hunt, leash = spec.leash }
		),
		carrying = nil :: number?, -- a stolen present's value (Fetch)
		carryPart = nil :: BasePart?,
		carriedAt = 0,
		gui = gui,
		label = label,
		mark = "",
		eye = eye,
		lamp = lamp,
		lampChase = false,
		lastMode = "Patrol",
		hitAt = {} :: { [Player]: number },
		pathing = false,
	}
end

-- Line of sight from a dog's eyes to a Santa, ignoring dogs and Santas.
-- Bug fixed 11 Nov 2026 (Josh: "their AI is pretty poor"): only the dogs were
-- ignored, so every ray hit the Santa's own body on the way to its root and
-- read as a wall. In a real server the dogs never saw anyone, only heard.
-- setIgnore is called every think with the dogs and every Santa's character.
local function sightLine()
	local params = nil
	pcall(function()
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
	end)
	local function setIgnore(ignore: { Instance })
		if params then
			params.FilterDescendantsInstances = ignore
		end
	end
	return function(from: Vector3, to: Vector3): boolean
		if not params then
			return true
		end
		local eye = from + Vector3.new(0, 1.5, 0)
		local ok, hit = pcall(function()
			return workspace:Raycast(eye, to - eye, params)
		end)
		return not (ok and hit)
	end,
		setIgnore
end

-- The mark over its head (Josh, 11 Nov 2026: the "?" goes red on alert):
--   faint yellow "?"  it's noticed something (awareness building)
--   red "?"           on alert: coming to look, or sniffing round for you
--   red "!"           chasing
function GuardDogs.markFor(intent): string
	if intent.mode == "Chase" then
		return "!"
	elseif intent.mode == "Stunned" or intent.mode == "Fetch" or intent.mode == "Chew" then
		return "" -- winding down, off with your present, or busy with a bone
	elseif intent.mode == "Alert" or intent.mode == "Search" or intent.awareness >= AI.AlertAt then
		return "alert?"
	elseif intent.awareness >= AI.NoticeAt then
		return "?"
	end
	return ""
end

local function setMark(dog, intent)
	local mark = GuardDogs.markFor(intent)
	if mark ~= dog.mark then
		dog.mark = mark
		dog.gui.Enabled = mark ~= ""
		dog.label.Text = if mark == "!" then "!" else "?"
		dog.label.TextColor3 = if mark == "" or mark == "?" then QUESTION else BANG
		dog.gui.Size = if mark == "!" then UDim2.fromOffset(56, 56) else UDim2.fromOffset(44, 44)
	end
	if mark == "?" then
		-- fades in as it gets more suspicious
		dog.label.TextTransparency = math.clamp(0.6 - intent.awareness * 2, 0, 0.6)
	elseif dog.label.TextTransparency ~= 0 then
		dog.label.TextTransparency = 0
	end
end

-- Walks the dog toward the intent's goal. A dog chasing a Santa it can see
-- runs straight at them; otherwise it follows a path, computed in its own
-- thread so one dog's path doesn't hold up the others' thinking.
local function steer(dog, intent, pos: Vector3, clear, flaps: { any })
	local goal = intent.goal
	if not goal then
		dog.mover:stop()
		dog.anim:play("Idle")
		return
	end
	dog.humanoid.WalkSpeed = intent.speed
	dog.anim:play("Walk")
	if AI.Flaps and #flaps > 0 then
		local waypoint, straight = DogBrain.flapWaypoint(pos, goal, flaps)
		if waypoint then
			if straight then
				dog.humanoid:MoveTo(waypoint) -- through the flap (or out to it)
				return
			end
			goal = waypoint
		end
	end
	local near = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z).Magnitude <= AI.DirectChase
	if intent.direct and near and clear(pos, goal) then
		dog.humanoid:MoveTo(goal)
		return
	end
	if dog.pathing then
		return -- still working out the last path: keep walking it
	end
	dog.pathing = true
	task.spawn(function()
		pcall(dog.mover.moveTo, dog.mover, goal)
		dog.pathing = false
	end)
end

local function setLamp(dog, intent)
	if not dog.eye then
		return
	end
	local look = dog.root.CFrame:VectorToObjectSpace(intent.look)
	local yaw = math.atan2(-look.X, -look.Z)
	dog.eye.CFrame = CFrame.new(dog.eye.Position) * CFrame.Angles(0, yaw, 0)
	local chase = intent.mode == "Chase"
	if chase ~= dog.lampChase then
		dog.lampChase = chase
		dog.lamp.Color = if chase then LAMP_CHASE else LAMP
	end
	dog.lamp.Enabled = intent.mode ~= "Stunned"
end

-- Lets dogs loose on this stop. Returns their cleanup.
-- isSafe(position): aboard at the Sleigh Stop (MapBuilder.isAboard; passed in
-- because CanalTown, which MapBuilder loads, starts the market dogs).
function GuardDogs.start(
	run,
	specs: { Spec },
	parent: Instance,
	isSafe: (position: Vector3) -> boolean,
	stop: any?
): () -> ()
	local flaps = if stop then GuardDogs.flapsFor(stop) else {}
	local dogs = {}
	for _, spec in specs do
		local ok, dog = pcall(buildDog, parent, spec)
		if ok then
			table.insert(dogs, dog)
		else
			warn("[GuardDogs] couldn't build " .. spec.kind .. ": " .. tostring(dog))
		end
	end
	local clear, setIgnore = sightLine()
	local dropper = DogBump.dropper(run, parent)
	local trails: { [Player]: { DogBrain.Crumb } } = {}
	local crumbAt: { [Player]: number } = {}
	local spottedBanner: { [Player]: number } = {}
	local loud: { DogBrain.Loud } = {}
	local lastNoisePos = run.lastNoisePos
	local scentKeep = 0
	for _, kind in AI.Kinds do
		scentKeep = math.max(scentKeep, kind.ScentSeconds)
	end
	local alive = true
	local lastThink = Util.now()

	local function think()
		local t = Util.now()
		local dt = math.clamp(t - lastThink, 0, 1)
		lastThink = t
		local tiptoe = run.phase == "Sneak"
		local santas = {}
		local ignore = {}
		for _, dog in dogs do
			table.insert(ignore, dog.model)
		end
		for player in run.players do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		setIgnore(ignore)
		for player in run.players do
			local root = Util.rootOf(player)
			if root and run:_free(player) then
				local position = root.Position
				local v = root.AssemblyLinearVelocity
				local santa = {
					player = player,
					root = root,
					position = position,
					speed = Vector3.new(v.X, 0, v.Z).Magnitude,
					velocity = v,
					safe = isSafe(position),
					tiptoe = tiptoe,
				}
				table.insert(santas, santa)
				-- Scent: a crumb a second, never on canal ice or at the sleigh.
				local character = player.Character
				local skating = character ~= nil
					and character:GetAttribute(SantaMoves.SKATE_ATTRIBUTE) == true
				if
					not santa.safe
					and not skating
					and t - (crumbAt[player] or -math.huge) >= AI.ScentEvery
				then
					crumbAt[player] = t
					local trail = trails[player] or {}
					trails[player] = trail
					table.insert(trail, { position = position, at = t })
				end
			end
		end
		for player, trail in trails do
			while trail[1] and t - trail[1].at > scentKeep do
				table.remove(trail, 1)
			end
			if not run.players[player] then
				trails[player] = nil
			end
		end
		-- Grabs and gasps the run heard about since last think.
		if run.lastNoisePos and run.lastNoisePos ~= lastNoisePos then
			table.insert(loud, { position = run.lastNoisePos, at = t })
		end
		lastNoisePos = run.lastNoisePos
		while loud[1] and t - loud[1].at > 2 do
			table.remove(loud, 1)
		end

		local world = {
			now = t,
			dt = dt,
			lit = run.phase ~= "Sneak",
			noise = (run.noise or 0) / Config.Noise.Max,
			santas = santas,
			trails = trails,
			loud = loud,
			clear = clear,
		}
		for _, dog in dogs do
			if not dog.model.Parent then
				continue
			end
			local pos = dog.root.Position
			local facing = dog.root.CFrame.LookVector
			local intent = DogBrain.step(dog.brain, pos, facing, world)
			local corgi = dog.kind == "DogCorgi"
			for _, flap in flaps do
				flap.open = flap.door.open == true
			end
			steer(dog, intent, pos, clear, flaps)
			setMark(dog, intent)
			setLamp(dog, intent)

			-- "?": it heard or glimpsed something.
			if intent.mode == "Alert" and dog.lastMode ~= "Alert" then
				SoundPlayer.at(if corgi then "CorgiGrowl" else "TinDogWhirr", dog.root)
			end
			-- "!": spotted. Bark, call the pack, and the street gets noisier.
			local spotted = intent.spotted
			if spotted then
				SoundPlayer.at(if corgi then "CorgiWoof" else "TinDogWhirr", dog.root)
				table.insert(loud, { position = pos, at = t })
				for _, other in dogs do
					if other ~= dog and (other.root.Position - pos).Magnitude <= AI.PackRadius then
						DogBrain.alert(other.brain, spotted.position, t)
					end
				end
				run:_addNoise(AI.BarkNoise)
				local player = spotted.player
				if (spottedBanner[player] or -math.huge) + AI.SpottedBannerCooldown < t then
					spottedBanner[player] = t
					run:_banner(
						player,
						"SPOTTED! Break its line of sight, hide, skate the canal or get to the sleigh!",
						2.5
					)
				end
			end
			if intent.chewing then
				SoundPlayer.at("CorgiGrowl", dog.root) -- happy chewing noises
			end
			-- Fetch: someone caught the corgi, or it got bored: drop the present.
			if dog.carrying then
				local catcher = nil
				local canCatch = t - dog.carriedAt >= AI.Fetch.Grace
				for _, santa in if canCatch then santas else {} do
					if not santa.safe and CanalRules.inReach(santa.position, pos, AI.Fetch.CatchRadius) then
						catcher = santa
						break
					end
				end
				if catcher or intent.drop or intent.mode ~= "Fetch" then
					local value = dog.carrying :: number
					dog.carrying = nil
					showCarry(dog, false)
					dropper.drop(pos + Vector3.new(0, -1.5, 0), value)
					if catcher then
						DogBrain.stun(dog.brain, AI.Fetch.StunAfter, t)
						SoundPlayer.at("CorgiWoof", dog.root)
						run:_banner(
							nil,
							catcher.player.DisplayName .. " caught the corgi! Grab the present!",
							2.5
						)
					end
				end
			end
			dog.lastMode = intent.mode
			if intent.mode == "Stunned" or intent.mode == "Fetch" or intent.mode == "Chew" then
				continue
			end

			-- Bumps: any Santa it reaches (walking into a patrol counts too).
			for _, santa in santas do
				local root = santa.root
				local offset = (root.Position - pos) * Vector3.new(1, 0, 1)
				if santa.safe then
					continue
				end
				if
					Sounds.dogWarns(
						offset.Magnitude,
						Config.Canal.Dogs.HitRadius,
						Config.Canal.Dogs.WarnRadius
					)
				then
					SoundPlayer.at(if corgi then "CorgiGrowl" else "TinDogWhirr", dog.root)
				end
				if
					(dog.hitAt[santa.player] or -math.huge) + dog.spec.cooldown < t
					and CanalRules.inReach(root.Position, pos, Config.Canal.Dogs.HitRadius)
				then
					dog.hitAt[santa.player] = t
					local pause, stolen =
						DogBump.hit(run, dropper, dog.kind, santa.player, root, pos, facing, dog.root, true)
					if stolen then
						dog.carrying = stolen
						dog.carriedAt = t
						showCarry(dog, true)
						DogBrain.fetch(dog.brain, t)
						run:_banner(
							nil,
							"A corgi ran off with " .. santa.player.DisplayName .. "'s present! Catch it!",
							2.5
						)
					elseif pause > 0 then
						DogBrain.stun(dog.brain, pause, t)
					else
						DogBrain.tire(dog.brain, t)
					end
					dog.mover:stop()
					break
				end
			end
		end
	end

	-- Thrown bones (Run:_throwBone) reach every pack on the stop.
	local pack = {
		distract = function(position: Vector3): number
			local n = 0
			for _, dog in dogs do
				if dog.model.Parent and (dog.root.Position - position).Magnitude <= AI.Bone.Radius then
					DogBrain.distract(dog.brain, position, Util.now())
					n += 1
				end
			end
			return n
		end,
	}
	run.dogPacks = run.dogPacks or {}
	table.insert(run.dogPacks, pack)

	task.spawn(function()
		while alive do
			local ok, err = pcall(think)
			if not ok then
				warn("[GuardDogs] " .. tostring(err))
			end
			task.wait(TICK)
		end
	end)

	return function()
		alive = false
		if run.dogPacks then
			Util.removeValue(run.dogPacks, pack)
		end
		for _, dog in dogs do
			dog.model:Destroy()
		end
		dropper.cleanup()
	end
end

return GuardDogs
