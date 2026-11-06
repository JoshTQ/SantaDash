--[[
	Skating look for every Santa gliding on canal ice (character attribute
	"Skating", set by server/CanalTown): a forward lean and a side-to-side
	sway on the root joint, layered over the walk clip (which SantaAnimate
	slows to long strides), plus a spray of ice from the feet.

	Runs on every client for every character, after the Animator has posed
	the rig each frame (PreSimulation), so everyone sees everyone skate
	without a new animation asset. Pose maths: shared/SantaMoves.skatePose.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)

local SPRAY = "SkateSpray"

-- The joint that carries the whole body: the Meshy Santa's Body "Root"
-- motor, or a default R15 avatar's LowerTorso "Root".
local function rootJoint(character: Model): Motor6D?
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == "Root" then
			return d
		end
	end
	return nil
end

local function spray(root: BasePart): ParticleEmitter
	local existing = root:FindFirstChild(SPRAY)
	if existing then
		return (existing :: Instance):FindFirstChildOfClass("ParticleEmitter") :: ParticleEmitter
	end
	local at = Instance.new("Attachment")
	at.Name = SPRAY
	at.Position = Vector3.new(0, -2.8, 0.6) -- by the heels
	at.Parent = root
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.fromRGB(225, 245, 255))
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(0.25, 0.5)
	e.Speed = NumberRange.new(4, 8)
	e.SpreadAngle = Vector2.new(35, 15)
	e.EmissionDirection = Enum.NormalId.Back
	e.Rate = 0
	e.Parent = at
	return e
end

local joints: { [Model]: Motor6D } = {}
-- What we wrote to each joint last frame, and the pose under it: if the
-- Animator doesn't drive a joint, its Transform keeps our last value, so the
-- lean must not stack frame after frame.
local written: { [Motor6D]: { base: CFrame, pose: CFrame } } = {}

local function same(a: CFrame, b: CFrame): boolean
	return a.Position:FuzzyEq(b.Position, 1e-4)
		and a.LookVector:FuzzyEq(b.LookVector, 1e-4)
		and a.UpVector:FuzzyEq(b.UpVector, 1e-4)
end

local function pose(joint: Motor6D, offset: CFrame?)
	local last = written[joint]
	local base = if last and same(joint.Transform, last.pose) then last.base else joint.Transform
	if offset then
		-- offset is in the root part's space (-Z forward); the joint's C0 may
		-- be turned (the Meshy body is yawed 180), so turn it into C0's space.
		local r = joint.C0.Rotation
		local p = (r:Inverse() * offset * r) * base
		joint.Transform = p
		written[joint] = { base = base, pose = p }
	elseif last then
		joint.Transform = base
		written[joint] = nil
	end
end

RunService.PreSimulation:Connect(function()
	local t = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			continue
		end
		local skating = character:GetAttribute(SantaMoves.SKATE_ATTRIBUTE) == true
		local joint = joints[character]
		if not joint or not joint.Parent then
			joint = rootJoint(character)
			joints[character] = joint :: any
		end
		local emitter = if skating or root:FindFirstChild(SPRAY) then spray(root) else nil
		if not skating then
			if emitter then
				emitter.Rate = 0
			end
			if joint then
				pose(joint, nil)
			end
			continue
		end
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local lean, sway, phase = SantaMoves.skatePose(t, speed)
		if joint then
			-- Added on top of whatever the Animator set this frame.
			pose(joint, CFrame.Angles(-lean, 0, sway))
		end
		if emitter then
			emitter.Rate = 20 + 40 * math.abs(phase) -- a burst on each push
		end
	end
	for character, joint in joints do
		if not character.Parent then
			joints[character] = nil
			written[joint] = nil
		end
	end
end)
