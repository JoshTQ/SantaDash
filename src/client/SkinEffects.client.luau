--[[
	Santa suit effects, cosmetic only (server/Skins.luau dresses the suit and
	adds its Trail). Here, on every client, for every Santa in view:
	  - Cheer: a burst of the suit's sparkles above his head
	  - phones: half the particles and a shorter trail (Config.Skins.PhoneEffectScale)
	Reads the character attributes "SantaSkin" and "SantaMove".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)
local SkinRules = require(ReplicatedStorage.Shared.SkinRules)

local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local scale = if phone then Config.Skins.PhoneEffectScale else 1
local MAX_DISTANCE = 120 -- don't bother bursting for Santas far away

local function emitter(root: BasePart, colors: { Color3 }): ParticleEmitter
	local at = root:FindFirstChild("SkinCheer") :: Attachment?
	if not at then
		at = Instance.new("Attachment")
		at.Name = "SkinCheer"
		at.Position = Vector3.new(0, 3.2, 0)
		at.Parent = root
	end
	local e = (at :: Attachment):FindFirstChildOfClass("ParticleEmitter")
	if not e then
		e = Instance.new("ParticleEmitter")
		e.Enabled = false
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(6, 11)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Acceleration = Vector3.new(0, -8, 0)
		e.Size = NumberSequence.new(0.5, 0)
		e.LightEmission = 0.7
		e.Parent = at
	end
	(e :: ParticleEmitter).Color = ColorSequence.new(colors[1], colors[#colors])
	return e :: ParticleEmitter
end

local function watch(character: Model)
	local function trimTrail()
		local root = character:FindFirstChild("HumanoidRootPart")
		local trail = root and root:FindFirstChild("SkinTrail")
		if trail and trail:IsA("Trail") and phone then
			trail.Lifetime = 0.6 * scale
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d.Name == "SkinTrail" then
			task.defer(trimTrail)
		end
	end)
	trimTrail()

	character:GetAttributeChangedSignal(SantaMoves.MOVE_ATTRIBUTE):Connect(function()
		if SantaMoves.decode(character:GetAttribute(SantaMoves.MOVE_ATTRIBUTE)) ~= "Cheer" then
			return
		end
		local skin = SkinRules.get(character:GetAttribute(SantaMoves.SKIN_ATTRIBUTE))
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local camera = workspace.CurrentCamera
		if not skin or not skin.cheer or not root then
			return
		end
		if camera and (camera.CFrame.Position - root.Position).Magnitude > MAX_DISTANCE then
			return
		end
		emitter(root, skin.cheer.colors):Emit(math.max(1, math.floor(skin.cheer.count * scale)))
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end
