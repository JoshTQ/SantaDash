--[[
	What happens when a security dog reaches a Santa, shared by the Christmas
	Market patrols (CanalTown) and the alarm dogs a full noise meter lets loose
	(AlarmDogs): a knockback, plus
	  corgi     knocks one present out of the sack, dropped on the snow to grab back
	  tin dog   bonks, then winds down for a moment so you can sneak past
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Knockback = require(script.Parent.Knockback)
local Loot = require(script.Parent.Loot)

local C = Config.Canal

local DogBump = {}

export type Dropper = {
	drop: (at: Vector3, value: number) -> (),
	cleanup: () -> (),
}

-- Drops knocked-out presents into `parent` for anyone to grab back (no
-- Jingle for the re-grab, and it doesn't count as another grab).
function DogBump.dropper(run, parent: Instance): Dropper
	local dropped = {}
	local function drop(at: Vector3, value: number)
		local box = Instance.new("Part")
		box.Name = "DroppedPresent"
		box.Size = Vector3.one * 1.8
		box.CFrame = CFrame.new(at + Vector3.new(0, 0.9, 0))
		box.Color = Color3.fromRGB(230, 50, 60)
		box.Anchored = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Grab"
		prompt.ObjectText = "Present"
		prompt.HoldDuration = Config.Presents.GrabHoldSeconds
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = box
		local model = Instance.new("Model")
		model.Name = "DroppedPresent"
		box.Parent = model
		model.PrimaryPart = box
		model.Parent = parent
		local present = {
			model = model,
			prompt = prompt,
			plan = { size = 1, value = value, ringMultiplier = 0, threats = 0, regrab = true },
		}
		prompt.Triggered:Connect(function(by)
			run:_grab(by, present)
		end)
		table.insert(dropped, model)
	end
	local function cleanup()
		for _, model in dropped do
			model:Destroy()
		end
		table.clear(dropped)
	end
	return { drop = drop, cleanup = cleanup }
end

-- A dog of `kind` at `dogPos` (facing `facing`) bumps `player`. Returns the
-- seconds the dog should pause afterwards (a tin dog winds down).
function DogBump.hit(
	run,
	dropper: Dropper,
	kind: string,
	player: Player,
	root: BasePart,
	dogPos: Vector3,
	facing: Vector3,
	emitter: any
): number
	local corgi = kind == "DogCorgi"
	local offset = (root.CFrame.Position - dogPos) * Vector3.new(1, 0, 1)
	local push = Knockback.velocity(offset, facing, C.Dogs.Knockback)
	local away = Vector3.new(push.X, 0, push.Z).Unit
	Knockback.apply(root, push)
	SoundPlayer.at(if corgi then "CorgiWoof" else "TinDogBonk", emitter)
	if not corgi then
		run:_banner(player, "BONK! The tin dog winds down... sneak past now!", 2)
		return C.Dogs.TinWindDown
	end
	local st = run.players[player]
	local value = st and Loot.dropOne(st)
	if value then
		run:_sendPlayer(player)
		dropper.drop(root.CFrame.Position + away * 6 - Vector3.new(0, 2.5, 0), value)
		run:_banner(player, "WOOF! A corgi knocked a present out of your sack. Grab it back!", 2.5)
	else
		run:_banner(player, "WOOF! The corgi bumped you. Your sack is empty, lucky!", 2)
	end
	return 0
end

return DogBump
