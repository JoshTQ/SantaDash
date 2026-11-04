--[[
	Knockback that actually moves a character. Santas' bodies are simulated
	by their own client (network ownership), so setting
	AssemblyLinearVelocity on the server is overwritten on the next physics
	step and the bump does nothing (the corgi bug, 4 Nov 2026). A
	LinearVelocity constraint is an Instance: it replicates to the owning
	client, which simulates it, and it beats the Humanoid's ground friction
	for its short life. Server-owned rigs (elf bots, tests) get the same push.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Knockback = {}

local NAME = "SleighHeistKnockback"

-- The push for a Santa `offset` (flat) from a hazard that faces `facing`:
-- straight away from it, or along its facing when they're right on top of it,
-- plus a little hop so they leave the ground.
function Knockback.velocity(offset: Vector3, facing: Vector3, strength: number): Vector3
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local away = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(facing.X, 0, facing.Z)
	if away.Magnitude < 1e-3 then
		away = Vector3.zAxis
	end
	return away.Unit * strength + Vector3.new(0, Config.Knockback.Lift, 0)
end

-- Pushes `root` at `velocity` for Config.Knockback.Seconds. A second push
-- replaces the first. Returns the constraint (tests read it).
function Knockback.apply(root: BasePart, velocity: Vector3): LinearVelocity
	local old = root:FindFirstChild(NAME)
	if old then
		old:Destroy()
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = NAME
	local push = Instance.new("LinearVelocity")
	push.Name = "Push"
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	push.VectorVelocity = velocity
	push.MaxForce = Config.Knockback.MaxForce
	push.Parent = attachment
	attachment.Parent = root
	root.AssemblyLinearVelocity = velocity -- server-owned rigs move at once
	task.delay(Config.Knockback.Seconds, function()
		if attachment.Parent then
			attachment:Destroy()
		end
	end)
	return push
end

return Knockback
