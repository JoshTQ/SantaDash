--[[
	Gear that goes ON TOP of any Santa suit: boots, scarves, mittens and the
	like (Josh, 6 Nov 2026: "build once, applied to each"). Every suit shares
	the classic Santa's rig and bone names (server/Skins.luau only swaps the
	"Body" mesh), so a piece that follows a bone fits every suit.

	A gear model in ServerStorage.Assets is modelled around the classic
	Santa in his bind pose, with its PrimaryPart (or pivot) where his
	HumanoidRootPart is. Then:
	  - each BasePart, or a child Model, or the gear model itself, may carry
	    the attribute FollowBone ("LeftFoot", "RightHand", ...). A part uses
	    the nearest FollowBone at or above it; with none it rides the root.
	  - optional attribute Offset (CFrame) beside FollowBone: where the piece
	    sits relative to the bone. Without it, the piece keeps the place it
	    was modelled at around the classic Santa's bind pose.
	  So mittens are one model with two child models (FollowBone LeftHand and
	  RightHand), and boots are one model with LeftBoot and RightBoot.

	Server: GearAttach.equip(character, model, id?) clones the model into the
	character's "Gear" folder, massless and non-colliding, each part welded
	to HumanoidRootPart (so physics and other servers see it near the right
	place). Client (client/GearFollow.client.luau): every frame each weld's
	C0 is moved to the bone's animated pose, on every client for every Santa.
	A suit change mid-run keeps the gear: the welds are on the root, and the
	bones are found again in the new Body.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local GearAttach = {}

GearAttach.FOLDER = "Gear"
GearAttach.BONE_ATTRIBUTE = "FollowBone"
GearAttach.OFFSET_ATTRIBUTE = "Offset" -- CFrame, bone space
GearAttach.WELD = "GearWeld"
GearAttach.ID_ATTRIBUTE = "GearId"
GearAttach.REST_ATTRIBUTE = "GearRest" -- CFrame: the part in root space at the bind pose
GearAttach.PART_OFFSET_ATTRIBUTE = "GearOffset" -- CFrame: the part in bone space, if set

-- The names a bone may go by in an imported rig (Config.Gear.BoneNames),
-- the canonical name first.
function GearAttach.boneNames(bone: string): { string }
	local names = { bone }
	local aliases = Config.Gear.BoneNames[bone]
	if aliases then
		for _, alias in aliases do
			if alias ~= bone then
				table.insert(names, alias)
			end
		end
	end
	return names
end

-- The Bone (or any instance with a TransformedWorldCFrame / CFrame) called
-- `bone` or one of its aliases inside the character's Body, or nil.
function GearAttach.findBone(character: Instance, bone: string): Instance?
	local body = character:FindFirstChild("Body")
	if not body then
		return nil
	end
	local wanted = {}
	for _, name in GearAttach.boneNames(bone) do
		wanted[string.lower(name)] = true
	end
	for _, d in body:GetDescendants() do
		if d:IsA("Bone") and wanted[string.lower(d.Name)] then
			return d
		end
	end
	return nil
end

-- Per-suit nudge for a bone (bulky suits like Chrome Puffer), identity if none.
function GearAttach.nudge(suit: string?, bone: string?): CFrame
	local bySuit = suit and Config.Gear.SuitNudge[suit]
	local n = bySuit and bone and bySuit[bone]
	return if n then n else CFrame.new()
end

-- The weld C0 (root space) that puts a piece at `offset` from the bone's
-- animated world pose.
function GearAttach.weldC0(rootCFrame: CFrame, boneWorld: CFrame, offset: CFrame): CFrame
	return rootCFrame:Inverse() * boneWorld * offset
end

--[[
	The part's place in bone space. With an explicit offset (set from the
	model's Offset attribute) that's it; otherwise it's worked out from the
	bind pose: where the part was modelled (restC0, root space) relative to
	where the bone sits at rest (restBone, root space, from Bone.WorldCFrame,
	which leaves the animation out).
]]
function GearAttach.partOffset(restBone: CFrame, restC0: CFrame, explicit: CFrame?): CFrame
	if explicit then
		return explicit
	end
	return restBone:Inverse() * restC0
end

-- The FollowBone at or above `inst`, stopping at `top` (inclusive).
function GearAttach.boneFor(inst: Instance, top: Instance): (string?, Instance?)
	local at: Instance? = inst
	while at do
		local bone = at:GetAttribute(GearAttach.BONE_ATTRIBUTE)
		if typeof(bone) == "string" and bone ~= "" then
			return bone, at
		end
		if at == top then
			break
		end
		at = at.Parent
	end
	return nil, nil
end

local function referenceCFrame(holder: Instance, part: BasePart): CFrame
	if holder:IsA("BasePart") then
		return holder.CFrame
	elseif holder:IsA("Model") and holder.PrimaryPart then
		return holder.PrimaryPart.CFrame
	end
	return part.CFrame
end

--[[
	Puts a copy of `model` on a Santa. `id` names it (default: the model's
	name), so equipping the same id again replaces it. Returns the copy, or
	nil without a root. Server only.
]]
function GearAttach.equip(character: Model, model: Model, id: string?): Model?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local gearId = id or model.Name
	GearAttach.unequip(character, gearId)
	local folder = character:FindFirstChild(GearAttach.FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = GearAttach.FOLDER
		folder.Parent = character
	end
	local copy = model:Clone()
	copy:SetAttribute(GearAttach.ID_ATTRIBUTE, gearId)
	for _, d in copy:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	-- Where the model sits in its own space: its pivot is placed at the root,
	-- so a piece without a bone (or before the client moves it) is modelled
	-- around Santa's root, the same as the bind pose.
	local pivot = CFrame.new()
	if copy.PrimaryPart then
		pivot = copy.PrimaryPart.CFrame
	else
		local ok, world = pcall(function()
			return copy.WorldPivot
		end)
		if ok and typeof(world) == "CFrame" then
			pivot = world
		end
	end
	-- Work out every part's place from the untouched model first, then move.
	local plan = {}
	for _, part in copy:GetDescendants() do
		if part:IsA("BasePart") then
			local bone, holder = GearAttach.boneFor(part, copy)
			local entry =
				{ part = part, bone = bone, rest = pivot:Inverse() * part.CFrame, offset = nil :: CFrame? }
			local offset = holder and holder:GetAttribute(GearAttach.OFFSET_ATTRIBUTE)
			if holder and typeof(offset) == "CFrame" then
				-- the holder sits at Offset from the bone; the part keeps its
				-- place inside the holder
				entry.offset = offset * (referenceCFrame(holder, part):Inverse() * part.CFrame)
			end
			table.insert(plan, entry)
		end
	end
	for _, entry in plan do
		local part = entry.part :: BasePart
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CFrame = root.CFrame * entry.rest
		local weld = Instance.new("Weld")
		weld.Name = GearAttach.WELD
		weld.Part0 = root
		weld.Part1 = part
		weld.C0 = entry.rest
		weld.C1 = CFrame.new()
		weld.Parent = part
		if entry.bone then
			part:SetAttribute(GearAttach.BONE_ATTRIBUTE, entry.bone)
			part:SetAttribute(GearAttach.REST_ATTRIBUTE, entry.rest)
			if entry.offset then
				part:SetAttribute(GearAttach.PART_OFFSET_ATTRIBUTE, entry.offset)
			end
		end
	end
	copy.Parent = folder
	return copy
end

-- Takes gear `id` off a Santa. Returns true if it was on.
function GearAttach.unequip(character: Model, id: string): boolean
	local folder = character:FindFirstChild(GearAttach.FOLDER)
	if not folder then
		return false
	end
	local found = false
	for _, child in folder:GetChildren() do
		if child:GetAttribute(GearAttach.ID_ATTRIBUTE) == id then
			child:Destroy()
			found = true
		end
	end
	return found
end

-- The ids of the gear a Santa wears, sorted.
function GearAttach.worn(character: Model): { string }
	local ids = {}
	local folder = character:FindFirstChild(GearAttach.FOLDER)
	if folder then
		for _, child in folder:GetChildren() do
			local id = child:GetAttribute(GearAttach.ID_ATTRIBUTE)
			if typeof(id) == "string" then
				table.insert(ids, id)
			end
		end
	end
	table.sort(ids)
	return ids
end

return GearAttach
