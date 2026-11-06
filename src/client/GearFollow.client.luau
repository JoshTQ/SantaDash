--[[
	Moves worn gear (boots, scarves, mittens: shared/GearAttach.luau) with
	Santa's animated bones, on every client for every Santa in range. The
	server welds each piece to HumanoidRootPart; here, each frame, the weld's
	C0 follows the bone's TransformedWorldCFrame. Works with any suit: bones
	are looked up again whenever the Body mesh changes (a suit swap).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local GearAttach = require(ReplicatedStorage.Shared.GearAttach)
local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)

type Piece = { weld: Weld, bone: string, offset: CFrame? }
type Entry = { body: Instance?, bones: { [string]: Instance? }, pieces: { Piece }, dirty: boolean }

local tracked: { [Model]: Entry } = {}

local function rebuild(character: Model, entry: Entry)
	entry.dirty = false
	entry.body = character:FindFirstChild("Body")
	entry.bones = {}
	entry.pieces = {}
	local folder = character:FindFirstChild(GearAttach.FOLDER)
	if not folder then
		return
	end
	for _, d in folder:GetDescendants() do
		local bone = d:IsA("BasePart") and d:GetAttribute(GearAttach.BONE_ATTRIBUTE)
		local weld = typeof(bone) == "string" and d:FindFirstChild(GearAttach.WELD)
		if weld and weld:IsA("Weld") then
			if entry.bones[bone] == nil then
				entry.bones[bone] = (GearAttach.findBone(character, bone) or false) :: any
			end
			table.insert(entry.pieces, { weld = weld, bone = bone })
		end
	end
end

local function watch(character: Model)
	if tracked[character] then
		return
	end
	local entry: Entry = { body = nil, bones = {}, pieces = {}, dirty = true }
	tracked[character] = entry
	local function mark()
		entry.dirty = true
	end
	character.DescendantAdded:Connect(function(d)
		if d.Name == "Body" or d.Name == GearAttach.FOLDER or d:IsA("Weld") then
			mark()
		end
	end)
	character.DescendantRemoving:Connect(function(d)
		if d.Name == "Body" or d:IsA("Weld") then
			mark()
		end
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			tracked[character] = nil
		end
	end)
end

local function onPlayer(player: Player)
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

RunService.PreSimulation:Connect(function()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	for character, entry in tracked do
		if entry.dirty then
			rebuild(character, entry)
		end
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if #entry.pieces == 0 or not root or character:GetAttribute(SantaMoves.SANTA_ATTRIBUTE) ~= true then
			continue
		end
		if eye and (root.Position - eye).Magnitude > Config.Gear.FollowDistance then
			continue
		end
		local rootCF = root.CFrame
		local suit = character:GetAttribute(SantaMoves.SKIN_ATTRIBUTE)
		for _, piece in entry.pieces do
			local bone = entry.bones[piece.bone] :: any
			if not bone or not piece.weld.Parent then
				continue
			end
			if not piece.offset then
				local part = piece.weld.Part1 :: BasePart
				local explicit = part:GetAttribute(GearAttach.PART_OFFSET_ATTRIBUTE)
				local rest = part:GetAttribute(GearAttach.REST_ATTRIBUTE)
				piece.offset = GearAttach.partOffset(
					rootCF:Inverse() * bone.WorldCFrame,
					if typeof(rest) == "CFrame" then rest else piece.weld.C0,
					if typeof(explicit) == "CFrame" then explicit else nil
				)
			end
			piece.weld.C0 = GearAttach.weldC0(
				rootCF,
				bone.TransformedWorldCFrame * GearAttach.nudge(suit :: string?, piece.bone),
				piece.offset :: CFrame
			)
		end
	end
end)
