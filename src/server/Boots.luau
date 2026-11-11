--[[
	Puts each player's boots on their Santa, whatever suit he wears, and
	handles buying boots with Coal. Rules: shared/BootRules.luau. Fitting:
	shared/GearAttach.luau (one model, follows the foot bones).

	The boots' speeds go on the character as attributes, which the Frozen
	Canal's skating loop reads (server/CanalTown.luau):
	  "SkateSpeed"  WalkSpeed on ice with these boots
	  "HoopSpeed"   WalkSpeed after a boost hoop
	and "SkateBoots" (the id worn). Everyone gets the skating look on ice
	(the run map's SkateLean); boots add speed and the gold trail.

	A gold scratch Trail sits under each blade; it only shows on ice
	(Boots.setOnIce, called by CanalTown).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BootRules = require(ReplicatedStorage.Shared.BootRules)
local GearAttach = require(ReplicatedStorage.Shared.GearAttach)
local Assets = require(script.Parent.Assets)
local PlayerData = require(script.Parent.PlayerData)
local Analytics = require(script.Parent.Analytics)

local Boots = {}

Boots.GEAR_ID = "Boots" -- one pair at a time, whatever the style
Boots.WORN_ATTRIBUTE = "SkateBoots"
Boots.SKATE_ATTRIBUTE = "SkateSpeed"
Boots.HOOP_ATTRIBUTE = "HoopSpeed"
Boots.ICE_ATTRIBUTE = "OnIce"
local TRAIL = "BootTrail"

local started = false

local function addTrails(copy: Model, color: Color3?)
	if not color then
		return
	end
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") and part:GetAttribute(GearAttach.BONE_ATTRIBUTE) then
			local half = part.Size.Y / 2
			local a0 = Instance.new("Attachment")
			a0.Name = TRAIL .. "Top"
			a0.Position = Vector3.new(0, -half + 0.08, 0)
			a0.Parent = part
			local a1 = Instance.new("Attachment")
			a1.Name = TRAIL .. "Bottom"
			a1.Position = Vector3.new(0, -half, 0)
			a1.Parent = part
			local trail = Instance.new("Trail")
			trail.Name = TRAIL
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(color)
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.Lifetime = 1.2
			trail.MinLength = 0.1
			trail.LightEmission = 0.5
			trail.Enabled = false
			trail.Parent = part
		end
	end
end

local function setTrails(character: Model, on: boolean)
	local folder = character:FindFirstChild(GearAttach.FOLDER)
	if not folder then
		return
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("Trail") and d.Name == TRAIL then
			d.Enabled = on
		end
	end
end

-- Dresses a character in the player's boots (or none). Returns the id worn,
-- or nil. Speeds only count for boots you own (styles need their base).
function Boots.apply(character: Model, data: { [string]: any }?): string?
	local boot = BootRules.current(data)
	local model = boot and Assets.get(boot.model)
	local worn = character:GetAttribute(Boots.WORN_ATTRIBUTE)
	local want = if boot and model then boot.id else nil
	if worn ~= want then
		GearAttach.unequip(character, Boots.GEAR_ID)
		if boot and model and model:IsA("Model") then
			local copy = GearAttach.equip(character, model, Boots.GEAR_ID)
			if copy then
				addTrails(copy, boot.trail)
				setTrails(character, character:GetAttribute(Boots.ICE_ATTRIBUTE) == true)
			else
				want = nil
			end
		end
		character:SetAttribute(Boots.WORN_ATTRIBUTE, want)
	end
	-- Speeds come from the rules even without a model, so a missing import
	-- never takes away what a player paid Coal for.
	local skate, hoop = BootRules.speeds(data)
	character:SetAttribute(Boots.SKATE_ATTRIBUTE, skate)
	character:SetAttribute(Boots.HOOP_ATTRIBUTE, hoop)
	return want
end

function Boots.refresh(player: Player)
	local character = player.Character
	local data = PlayerData.get(player)
	if character and data then
		Boots.apply(character, data)
	end
end

-- Buys boots with Coal. Returns ok, or false and BootRules' reason.
function Boots.buy(player: Player, id: any): (boolean, string?)
	local ok, reason = false, "loading"
	local spent, balance = 0, 0
	PlayerData.update(player, function(data)
		local before = data.coal or 0
		ok, reason = BootRules.buy(data, id)
		spent, balance = before - (data.coal or 0), data.coal or 0
	end)
	if ok then
		Analytics.coal(player, "Sink", spent, balance, "Shop", tostring(id))
		task.spawn(PlayerData.saveNow, player) -- Coal was spent: save straight away
	end
	return ok, reason
end

function Boots.equip(player: Player, id: any): (boolean, string?)
	local ok, reason = false, "loading"
	PlayerData.update(player, function(data)
		ok, reason = BootRules.equip(data, id)
	end)
	return ok, reason
end

function Boots.list(player: Player): { any }
	return BootRules.list(PlayerData.get(player))
end

-- The Frozen Canal's skating loop says when a Santa steps on or off ice:
-- the blades' gold trail only shows on ice.
function Boots.setOnIce(character: Model, onIce: boolean)
	if character:GetAttribute(Boots.ICE_ATTRIBUTE) ~= onIce then
		character:SetAttribute(Boots.ICE_ATTRIBUTE, onIce)
		setTrails(character, onIce)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 5)
		if PlayerData.waitFor(player, 30) and player.Character == character then
			Boots.refresh(player)
		end
	end)
	if player.Character then
		task.spawn(Boots.refresh, player)
	end
end

function Boots.start()
	if started then
		return
	end
	started = true
	PlayerData.onChanged(function(player)
		Boots.refresh(player)
	end)
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
end

-- Tests.
function Boots._reset()
	started = false
end

return Boots
