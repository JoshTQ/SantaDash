--[[
	Makes the approved Meshy Santa (ServerStorage.Assets.Santa) everyone's
	character: a clone becomes StarterPlayer.StarterCharacter, with the sack
	(ServerStorage.Assets.SantaSack) on his back. Clips are played by each
	player's client (client/SantaAnimate.client.luau); the server only says
	when to sneak, grab or cheer (shared/SantaMoves.luau).

	Without a usable Santa (no model yet, or no Idle/Walk clips) players keep
	their own Roblox avatar, as in the greybox.

	Santa  Humanoid, HumanoidRootPart, mesh "Body" on a Motor6D, an
	       Animations folder (Idle, Walk, Sneak, Grab, Cheer)
]]

local StarterPlayer = game:GetService("StarterPlayer")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)
local Assets = require(script.Parent.Assets)

local SantaCharacter = {}

SantaCharacter.REQUIRED = { "Humanoid", "HumanoidRootPart", "Animations" }
-- Where the sack's pivot (the bottom of its 2.5-stud bag) sits, from Santa's
-- root: his feet are 3 below the root, his back about 1.2 behind (+Z).
-- First guess from the spec sizes; check it in Studio (docs/PLAYTEST.md).
SantaCharacter.SACK_OFFSET = CFrame.new(0, -0.9, 1.2)

-- Why this Santa can't be the player character, or nil if it can.
function SantaCharacter.problem(model: Model?): string?
	if not model then
		return "no Santa model in ServerStorage.Assets"
	end
	for _, name in SantaCharacter.REQUIRED do
		if not model:FindFirstChild(name) then
			return "Santa has no " .. name
		end
	end
	local animations = model:FindFirstChild("Animations") :: Instance
	for _, clip in SantaMoves.REQUIRED do
		if not animations:FindFirstChild(clip) then
			return "Santa has no " .. clip .. " animation"
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return "Santa's Humanoid isn't R15 (HipHeight would be ignored)"
	end
	return nil
end

-- Welds a clone of the sack to Santa's back (unanchored, no collisions, massless).
function SantaCharacter.addSack(santa: Model, sack: Model?)
	local root = santa:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not sack or not root then
		return
	end
	local copy = sack:Clone()
	copy.Name = "Sack"
	-- Move by hand (no PivotTo): every part keeps its place relative to the pivot.
	local primary = copy.PrimaryPart or copy:FindFirstChildWhichIsA("BasePart", true)
	local pivot = if primary then primary.CFrame * primary.PivotOffset else CFrame.new()
	local move = root.CFrame * SantaCharacter.SACK_OFFSET * pivot:Inverse()
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = move * part.CFrame
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	copy.Parent = santa
end

-- The StarterCharacter to install, or nil (and why) to keep default avatars.
function SantaCharacter.build(): (Model?, string?)
	local template = Assets.get("Santa")
	local problem = SantaCharacter.problem(template)
	if problem then
		return nil, problem
	end
	local santa = (template :: Model):Clone()
	santa.Name = "StarterCharacter"
	santa:SetAttribute(SantaMoves.SANTA_ATTRIBUTE, true)
	santa:SetAttribute(SantaMoves.SKIN_ATTRIBUTE, "Classic") -- server/Skins.luau swaps the suit
	for _, part in santa:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	SantaCharacter.addSack(santa, Assets.get("SantaSack"))
	return santa, nil
end

-- Called once at boot, before anyone spawns.
function SantaCharacter.install(): boolean
	local santa, problem = SantaCharacter.build()
	if not santa then
		print("[SantaCharacter] players keep their own avatars: " .. tostring(problem))
		return false
	end
	local old = StarterPlayer:FindFirstChild("StarterCharacter")
	if old then
		old:Destroy()
	end
	santa.Parent = StarterPlayer
	return true
end

-- Tiptoe while the stop is in its sneak phase.
function SantaCharacter.setSneaking(player: Player, sneaking: boolean)
	player:SetAttribute(SantaMoves.SNEAK_ATTRIBUTE, sneaking)
end

return SantaCharacter
