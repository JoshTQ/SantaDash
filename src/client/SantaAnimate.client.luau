--[[
	Plays the Meshy Santa's clips on this player's own character (client-owned
	tracks replicate to everyone). Only runs on a Santa character (the server
	marks it IsSanta, see server/SantaCharacter.luau); a default avatar keeps
	Roblox's own Animate script.

	Loops: Idle / Walk / Sneak by ground speed and the "Sneaking" attribute.
	One-shots: Grab and Cheer when the server sets "SantaMove".
	Rules live in shared/SantaMoves.luau.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)

local player = Players.LocalPlayer
local FADE = 0.2

local function attach(character: Model)
	if character:GetAttribute(SantaMoves.SANTA_ATTRIBUTE) ~= true then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local folder = character:WaitForChild("Animations", 10)
	if not humanoid or not folder then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Roblox's default Animate would fight our clips (and has no R15 limbs to move).
	local function dropDefault(child: Instance)
		if child.Name == "Animate" and child:IsA("LocalScript") then
			child.Enabled = false
			child:Destroy()
		end
	end
	for _, child in character:GetChildren() do
		dropDefault(child)
	end
	local childAdded = character.ChildAdded:Connect(dropDefault)

	local tracks: { [string]: AnimationTrack } = {}
	local has: { [string]: boolean } = {}
	for _, animation in folder:GetChildren() do
		if animation:IsA("Animation") then
			local ok, track = pcall(animator.LoadAnimation, animator, animation)
			if ok and track then
				track.Looped = table.find(SantaMoves.LOOPS, animation.Name) ~= nil
				tracks[animation.Name] = track
				has[animation.Name] = true
			else
				warn("[SantaAnimate] couldn't load " .. animation.Name .. ": " .. tostring(track))
			end
		end
	end

	local current: string? = nil
	local stepped = RunService.Heartbeat:Connect(function()
		local root = humanoid.RootPart
		if not root then
			return
		end
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		if humanoid.MoveDirection.Magnitude < 0.05 then
			speed = 0 -- knockbacks and sleigh rides aren't walking
		end
		local clip = SantaMoves.loopFor(speed, player:GetAttribute(SantaMoves.SNEAK_ATTRIBUTE) == true, has)
		if clip ~= current then
			if current and tracks[current] then
				tracks[current]:Stop(FADE)
			end
			current = clip
			if tracks[clip] then
				tracks[clip]:Play(FADE)
			end
		end
		local track = tracks[clip]
		if track then
			track:AdjustSpeed(SantaMoves.loopSpeed(clip, speed))
		end
	end)

	local moved = character:GetAttributeChangedSignal(SantaMoves.MOVE_ATTRIBUTE):Connect(function()
		local move = SantaMoves.decode(character:GetAttribute(SantaMoves.MOVE_ATTRIBUTE))
		local track = move and tracks[move]
		if track then
			track:Play(0.1, 1, SantaMoves.ONE_SHOTS[move :: string].speed)
		end
	end)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			stepped:Disconnect()
			moved:Disconnect()
			childAdded:Disconnect()
		end
	end)
end

player.CharacterAdded:Connect(attach)
if player.Character then
	task.spawn(attach, player.Character)
end
