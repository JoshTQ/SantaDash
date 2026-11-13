--[[
	Builds one KeyframeSequence per clip from build/meshy/<Name>/anims.json
	(tools/meshy/anims.py), ready to upload as Animation assets:

	  lune run tools/meshy/anim_rbxm <Name>

	  -> build/meshy/<Name>/anim_<Clip>.rbxm

	Pose tree: HumanoidRootPart > <mesh part> > the bone hierarchy, the path the
	Animator walks (to_rbxm joins the mesh to the root with a Motor6D). Bone
	poses are offsets from the rest pose, as Bone.Transform expects.

	Fails if the model Roblox imported has no bones or lacks one of its
	bones, so a clip that can't play never gets uploaded. The exception is leaf
	"_end" bones (head_end), which Roblox drops on import: they're left out.
	Also fails if an imported bone's rest rotation isn't the one anims.py
	turned the poses for (half a turn about +Y from the GLB): poses written in
	the wrong frame bend every joint the wrong way.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local CFrame = roblox.CFrame

local function fail(message: string): never
	print("::error::" .. message)
	process.exit(1)
	error(message)
end

local name = process.args[1]
if not name or not string.match(name, "^%w+$") then
	fail("usage: lune run tools/meshy/anim_rbxm <Name>")
end
local dir = "build/meshy/" .. name
local spec = serde.decode("json", fs.readFile("art/meshy/" .. name .. ".json"))
local meshName = spec.assemble and spec.assemble.mesh and spec.assemble.mesh.name or name
local data = serde.decode("json", fs.readFile(dir .. "/anims.json"))

-- The imported rig must have the bones the clips drive.
local imported = {}
local importedRest = {}
if fs.isFile(dir .. "/imported.rbxm") then
	for _, root in roblox.deserializeModel(fs.readFile(dir .. "/imported.rbxm")) do
		for _, d in root:GetDescendants() do
			if d:IsA("Bone") then
				imported[d.Name] = true
				importedRest[d.Name] = d.CFrame
			end
		end
		if root:IsA("Bone") then
			imported[root.Name] = true
			importedRest[root.Name] = root.CFrame
		end
	end
	-- The frame check: the turned GLB rest rotation must match the import's.
	local wrong = {}
	for bone, info in data.bones do
		local got = importedRest[bone]
		local rest = info.rest
		if got and rest then
			local want = CFrame.new(0, 0, 0, rest[1], rest[2], rest[3], rest[4])
			local _, angle = (want:Inverse() * got.Rotation):ToAxisAngle()
			if math.abs(angle) > math.rad(2) then
				table.insert(wrong, ("%s (%.0f deg off)"):format(bone, math.deg(angle)))
			end
		end
	end
	if #wrong > 0 then
		table.sort(wrong)
		fail(
			name
				.. ": the imported bones aren't in the frames anims.py turned the poses into, so the clips would bend the wrong way: "
				.. table.concat(wrong, ", ")
		)
	end
	-- Roblox drops the leaf "_end" bones (head_end) on import. They carry no
	-- skin, so leave them out of the clips; any other missing bone fails.
	local hasChildren = {}
	for _, info in data.bones do
		if info.parent then
			hasChildren[info.parent] = true
		end
	end
	local missing = {}
	for bone in data.bones do
		if not imported[bone] then
			if hasChildren[bone] or not string.match(bone, "_end$") then
				table.insert(missing, bone)
			else
				print("(the imported rig dropped the end bone " .. bone .. ": leaving it out of the clips)")
				data.bones[bone] = nil
			end
		end
	end
	if next(imported) == nil then
		fail(name .. ": Roblox imported the rig without bones, so the clips have nothing to move")
	elseif #missing > 0 then
		table.sort(missing)
		fail(name .. ": imported rig lacks bones " .. table.concat(missing, ", "))
	end
else
	print("(no imported.rbxm yet: skipping the bone check)")
end

local children: { [string]: { string } } = {}
local roots = {}
for bone, info in data.bones do
	if info.parent then
		children[info.parent] = children[info.parent] or {}
		table.insert(children[info.parent], bone)
	else
		table.insert(roots, bone)
	end
end

local function pose(poseName: string, cf, parent)
	local p = Instance.new("Pose")
	p.Name = poseName
	p.CFrame = cf
	p.Weight = 1
	p.Parent = parent
	return p
end

local written = {}
for clipName, clip in data.clips do
	local sequence = Instance.new("KeyframeSequence")
	sequence.Name = clipName
	sequence.Loop = clip.loop
	sequence.Priority = if clip.loop
		then roblox.Enum.AnimationPriority.Movement
		else roblox.Enum.AnimationPriority.Action
	for _, frame in clip.frames do
		local keyframe = Instance.new("Keyframe")
		keyframe.Time = frame.t
		local rootPose = pose("HumanoidRootPart", CFrame.new(), keyframe)
		local meshPose = pose(meshName, CFrame.new(), rootPose)
		local function add(bone: string, parent)
			local v = frame.poses[bone]
			local cf = if v then CFrame.new(v[1], v[2], v[3], v[4], v[5], v[6], v[7]) else CFrame.new()
			local p = pose(bone, cf, parent)
			for _, child in children[bone] or {} do
				add(child, p)
			end
		end
		for _, bone in roots do
			add(bone, meshPose)
		end
		keyframe.Parent = sequence
	end
	local file = dir .. "/anim_" .. clipName .. ".rbxm"
	fs.writeFile(file, roblox.serializeModel({ sequence }))
	table.insert(written, clipName)
	print(
		string.format(
			"Wrote %s: %d keyframes, %.2fs, loop %s",
			file,
			#clip.frames,
			clip.duration,
			tostring(clip.loop)
		)
	)
end
table.sort(written)
fs.writeFile(dir .. "/anims_built.json", serde.encode("json", written))
