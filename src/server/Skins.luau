--[[
	Puts each player's chosen Santa suit on their character. The rules (what
	is unlocked, what's equipped) live in shared/SkinRules.luau; the choice
	is saved as PlayerData's "skin".

	All suits share the classic Santa's rig, so a suit is just a different
	"Body" mesh (with its bones) on the same HumanoidRootPart Motor6D. The
	Humanoid, Animations folder and sack stay put, so the clips keep playing
	and a suit can change at any time, even mid-run, without a respawn.

	Each suit also gets a Trail on the root (shown while moving). Cheer
	bursts and phone trimming are on the client (client/SkinEffects.client.luau),
	which reads the character's "SantaSkin" attribute.

	Without the suit's model in ServerStorage.Assets (not imported yet) the
	player keeps the classic look; their choice is still saved.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)
local SkinRules = require(ReplicatedStorage.Shared.SkinRules)
local Assets = require(script.Parent.Assets)
local PlayerData = require(script.Parent.PlayerData)

local Skins = {}

Skins.ATTRIBUTE = SantaMoves.SKIN_ATTRIBUTE
local TRAIL = "SkinTrail"

local started = false

local function bodyOf(model: Instance?): BasePart?
	local body = model and model:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		return body
	end
	return nil
end

local function setTrail(root: BasePart, skin: SkinRules.Skin)
	for _, name in { TRAIL, TRAIL .. "Top", TRAIL .. "Bottom" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	if not skin.trail then
		return
	end
	local top = Instance.new("Attachment")
	top.Name = TRAIL .. "Top"
	top.Position = Vector3.new(0, -1.6, 0.6)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = TRAIL .. "Bottom"
	bottom.Position = Vector3.new(0, -2.8, 0.6)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = TRAIL
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(skin.trail[1], skin.trail[#skin.trail])
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = 0.6
	trail.MinLength = 0.2
	trail.LightEmission = 0.6
	trail.FaceCamera = true
	trail.Parent = root
end

-- Dresses a Santa character in a suit. Returns the suit actually shown
-- (classic when the suit's model isn't imported), or nil for a non-Santa.
function Skins.apply(character: Model, id: string): string?
	if character:GetAttribute(SantaMoves.SANTA_ATTRIBUTE) ~= true then
		return nil -- a default Roblox avatar (no Santa model yet)
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local oldBody = bodyOf(character)
	if not root or not oldBody then
		return nil
	end
	local skin = SkinRules.get(id) or (SkinRules.get(Config.Skins.Default) :: SkinRules.Skin)
	local source = bodyOf(Assets.get(skin.model or "Santa"))
	if not source then
		skin = SkinRules.get(Config.Skins.Default) :: SkinRules.Skin
		source = bodyOf(Assets.get("Santa"))
	end
	if character:GetAttribute(Skins.ATTRIBUTE) == skin.id then
		return skin.id
	end
	if source then
		local oldMotor = oldBody:FindFirstChildOfClass("Motor6D")
		local body = (source :: BasePart):Clone()
		for _, d in body:GetDescendants() do
			if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
				d:Destroy()
			end
		end
		body.Anchored = false
		body.Massless = true
		body.CanCollide = false
		body.CFrame = oldBody.CFrame
		local motor = Instance.new("Motor6D")
		motor.Name = "Root"
		motor.Part0 = root
		motor.Part1 = body
		motor.C0 = if oldMotor then oldMotor.C0 else root.CFrame:Inverse() * oldBody.CFrame
		motor.C1 = if oldMotor then oldMotor.C1 else CFrame.new()
		motor.Parent = body
		oldBody:Destroy()
		body.Parent = character
	end
	setTrail(root, skin)
	character:SetAttribute(Skins.ATTRIBUTE, skin.id)
	return skin.id
end

-- Wears the player's current suit on their current character.
function Skins.refresh(player: Player)
	local character = player.Character
	local data = PlayerData.get(player)
	if character and data then
		Skins.apply(character, SkinRules.current(data))
	end
end

-- The player picks a suit. Saved on the next autosave (or when they leave).
function Skins.equip(player: Player, id: any): (boolean, string?)
	local ok, reason = false, "loading"
	PlayerData.update(player, function(data)
		ok, reason = SkinRules.equip(data, id)
	end)
	return ok, reason
end

function Skins.list(player: Player): { any }
	return SkinRules.list(PlayerData.get(player))
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		if PlayerData.waitFor(player, 30) and player.Character == character then
			Skins.refresh(player)
		end
	end)
	if player.Character then
		task.spawn(Skins.refresh, player)
	end
end

function Skins.start()
	if started then
		return
	end
	started = true
	-- Equip, a purchase or a refund: put the right suit on.
	PlayerData.onChanged(function(player)
		Skins.refresh(player)
	end)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
end

-- Tests.
function Skins._reset()
	started = false
end

return Skins
