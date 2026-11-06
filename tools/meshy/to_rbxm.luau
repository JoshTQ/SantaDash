--[[
	Turns the model Roblox imported (build/meshy/<Name>/imported.rbxm, from
	upload.py) into the file the deploy ships: assets/models/<Name>.rbxm.

	  lune run tools/meshy/to_rbxm <Name>

	- one root Model named <Name> (the deploy names ServerStorage.Assets.<Name>
	  after the file, the game looks the model up by its Name)
	- every MeshPart gets the uploaded colour texture (TextureContent)
	- removes what Open Cloud can't publish (SurfaceAppearance, unions,
	  Editable*, wraps) and the PackageLink the asset upload adds
	- fails if anything unpublishable is left, so a bad file never reaches main
	- if the spec has an "assemble" block, builds the part contract the game
	  expects (src/server/Assets.luau): turns and scales the mesh to the
	  stand-in's size, adds the named helper parts (seats, hitch, Humanoid,
	  prompts...) and pulls in component meshes (Krampus's basket)
	- prints what's inside (parts, bones, size) for the approval PR

	"assemble" (all positions in studs, model space; the model's pivot is the
	origin and forward is -Z, as the stand-ins):
	  mesh       { name, yaw, fit = { axis = "X"|"Y"|"Z"|"max", studs },
	               bottom = {x,y,z} | center = {x,y,z} }
	  include    { <PartName> = { from = <component spec>, ...same as mesh } }
	  parts      { <Name> = { size, at, class?, shape?, color?, material?,
	               transparency?, neon? } }  (invisible unless a colour is given)
	  attachments { <Name> = { on, at } }
	  particles  { on = <attachment>, color, rate }
	  attributes { <PartName> = { <Attribute> = value } }  (e.g. FollowBone on gear)
	  primary    part name (PrimaryPart; pivot = origin)
	  humanoid   { hip, root = {x,y,z} }  (adds HumanoidRootPart + Humanoid,
	             welds everything to the root, unanchored)
	  anchored   true for props the game places by pivot
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

-- Same list as tools/deploy.luau.
local UNPUBLISHABLE = {
	"SurfaceAppearance",
	"PartOperation",
	"UnionOperation",
	"NegateOperation",
	"IntersectOperation",
	"EditableImage",
	"EditableMesh",
	"BaseWrap",
	"WrapLayer",
	"WrapTarget",
}
local STRIP = { "SurfaceAppearance", "PackageLink", "EditableImage", "EditableMesh", "BaseWrap" }

local function fail(message: string): never
	print("::error::" .. message)
	process.exit(1)
	error(message)
end

local name = process.args[1]
if not name or not string.match(name, "^%w+$") then
	fail("usage: lune run tools/meshy/to_rbxm <Name>")
end

local function readSpec(specName: string)
	local path = "art/meshy/" .. specName .. ".json"
	if not fs.isFile(path) then
		fail("No spec " .. path)
	end
	return serde.decode("json", fs.readFile(path))
end

local function isAny(instance, classes): boolean
	for _, className in classes do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local counts = { MeshPart = 0, Bone = 0, Stripped = 0 }

-- The imported meshes of one Meshy run, textured and cleaned, unparented.
local function loadMeshes(runName: string): { any }
	local dir = "build/meshy/" .. runName
	if not fs.isFile(dir .. "/imported.rbxm") then
		fail(("Missing %s/imported.rbxm: run generate.py and upload.py for %s first"):format(dir, runName))
	end
	local ids = serde.decode("json", fs.readFile(dir .. "/roblox.json"))
	local texture = "rbxassetid://" .. tostring(ids.imageAssetId)
	local ok, roots = pcall(roblox.deserializeModel, fs.readFile(dir .. "/imported.rbxm"))
	if not ok then
		fail("Couldn't read the model Roblox imported for " .. runName .. ": " .. tostring(roots))
	end
	local holder = Instance.new("Model")
	for _, root in roots do
		root.Parent = holder
	end
	for _, instance in holder:GetDescendants() do
		if instance.Parent and isAny(instance, STRIP) then
			instance:Destroy()
			counts.Stripped += 1
		end
	end
	local meshes = {}
	for _, instance in holder:GetDescendants() do
		if instance:IsA("MeshPart") then
			-- Lune drops writes to the legacy TextureID on save; the file
			-- (and Roblox) read TextureContent.
			instance.TextureContent = roblox.Content.fromUri(texture)
			table.insert(meshes, instance)
		end
	end
	if #meshes == 0 then
		fail("The model imported for " .. runName .. " has no MeshParts")
	end
	return meshes
end

local function bounds(parts: { any }): (any, any)
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in parts do
		-- Rotated parts: take the box of all eight corners.
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
					low = Vector3.new(
						math.min(low.X, corner.X),
						math.min(low.Y, corner.Y),
						math.min(low.Z, corner.Z)
					)
					high = Vector3.new(
						math.max(high.X, corner.X),
						math.max(high.Y, corner.Y),
						math.max(high.Z, corner.Z)
					)
				end
			end
		end
	end
	return low, high
end

local function vec(t, default): any
	if t == nil then
		return default
	end
	return Vector3.new(t[1], t[2], t[3])
end

-- Turns (yaw, degrees about +Y), scales and moves a set of meshes as one.
-- Bones and attachments under them scale with them.
local function place(parts: { any }, opts)
	local low, high = bounds(parts)
	local size = high - low
	local centre = (low + high) / 2
	local turn = CFrame.Angles(0, math.rad(opts.yaw or 0), 0)
	-- A quarter turn swaps X and Z.
	local quarter = math.abs(((opts.yaw or 0) / 90) % 2) == 1
	local turned = if quarter then Vector3.new(size.Z, size.Y, size.X) else size
	local scale = 1
	if opts.fit then
		local axis = opts.fit.axis
		local measured = if axis == "X"
			then turned.X
			elseif axis == "Y" then turned.Y
			elseif axis == "Z" then turned.Z
			else math.max(turned.X, turned.Y, turned.Z)
		if measured <= 0 then
			fail("Mesh has zero size on " .. tostring(axis))
		end
		scale = opts.fit.studs / measured
	end
	local finalSize = turned * scale
	local target
	if opts.center then
		target = vec(opts.center)
	else
		target = vec(opts.bottom, Vector3.new(0, 0, 0)) + Vector3.new(0, finalSize.Y / 2, 0)
	end
	for _, part in parts do
		local cf = part.CFrame - centre
		local rel = turn * cf
		part.CFrame = CFrame.new(target + rel.Position * scale) * rel.Rotation
		part.Size = part.Size * scale
		for _, d in part:GetDescendants() do
			if d:IsA("Attachment") then -- Bones are Attachments
				d.CFrame = CFrame.new(d.CFrame.Position * scale) * d.CFrame.Rotation
			end
		end
	end
	return finalSize
end

local spec = readSpec(name)
if spec.component then
	fail(name .. " is a component (pulled into another model), not a model of its own")
end
local plan = spec.assemble or {}

local model = Instance.new("Model")
model.Name = name

local meshes = loadMeshes(name)
local meshOpts = plan.mesh or {}
local meshSize = place(meshes, meshOpts)
for i, part in meshes do
	part.Parent = model
	if meshOpts.name then
		part.Name = if #meshes == 1 then meshOpts.name else meshOpts.name .. i
	end
end

local visuals = table.clone(meshes)
for partName, opts in plan.include or {} do
	local parts = loadMeshes(opts.from)
	place(parts, opts)
	for i, part in parts do
		part.Name = if #parts == 1 then partName else partName .. i
		part.Parent = model
		table.insert(visuals, part)
	end
end

local helpers = {}
for partName, opts in plan.parts or {} do
	local part = Instance.new(opts.class or "Part")
	part.Name = partName
	part.Size = vec(opts.size, Vector3.new(1, 1, 1))
	part.CFrame = CFrame.new(vec(opts.at, Vector3.new(0, 0, 0)))
	if opts.shape == "Ball" then
		part.Shape = Enum.PartType.Ball
	elseif opts.shape == "Cylinder" then
		part.Shape = Enum.PartType.Cylinder
		part.CFrame = part.CFrame * CFrame.Angles(0, 0, math.rad(90)) -- flat, like a disc
	end
	if opts.color then
		part.Color = Color3.fromRGB(opts.color[1], opts.color[2], opts.color[3])
		part.Transparency = opts.transparency or 0
		if opts.material then
			part.Material = (Enum.Material :: any)[opts.material]
		end
	else
		part.Transparency = 1
	end
	part.CanCollide = opts.collide == true
	part.CanTouch = false
	part.CanQuery = opts.color ~= nil or opts.class == "Seat"
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	helpers[partName] = part
end

for _, part in visuals do
	part.CanCollide = plan.collide == true
	part.CanTouch = false
end

local function find(partName: string)
	local part = model:FindFirstChild(partName)
	if not part then
		fail(("assemble refers to %q, which %s doesn't have"):format(partName, name))
	end
	return part
end

for attName, opts in plan.attachments or {} do
	local on = find(opts.on)
	local attachment = Instance.new("Attachment")
	attachment.Name = attName
	attachment.CFrame = on.CFrame:Inverse() * CFrame.new(vec(opts.at))
	attachment.Parent = on
end

-- Attributes on parts, e.g. FollowBone for gear (shared/GearAttach.luau).
for partName, attrs in plan.attributes or {} do
	local on = find(partName)
	for key, value in attrs do
		on:SetAttribute(key, value)
	end
end

if plan.particles then
	local p = plan.particles
	local host = model:FindFirstChild(p.on, true)
	if not host then
		fail("particles.on " .. tostring(p.on) .. " not found")
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkle"
	emitter.Color = roblox.ColorSequence.new(Color3.fromRGB(p.color[1], p.color[2], p.color[3]))
	emitter.LightEmission = 1
	emitter.Rate = p.rate or 4
	emitter.Lifetime = roblox.NumberRange.new(1, 2)
	emitter.Speed = roblox.NumberRange.new(1, 2)
	emitter.Size = roblox.NumberSequence.new(0.25, 0)
	emitter.SpreadAngle = roblox.Vector2.new(30, 30)
	emitter.Parent = host
end

local primaryName = plan.primary
local primary = if primaryName then find(primaryName) else nil
if not primary then
	local largest, volume = nil, 0
	for _, part in meshes do
		local v = part.Size.X * part.Size.Y * part.Size.Z
		if v > volume then
			largest, volume = part, v
		end
	end
	primary = largest
end
model.PrimaryPart = primary
-- Pivot at the origin (the stand-in's pivot), wherever the primary part sits.
primary.PivotOffset = primary.CFrame:Inverse()

if plan.humanoid then
	local h = plan.humanoid
	local root = helpers.HumanoidRootPart
	if not root then
		root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = vec(h.root, Vector3.new(2, 2, 1))
		root.CFrame = CFrame.new(0, 0, 0)
		root.Transparency = 1
		root.CanCollide = true
		root.Parent = model
	end
	root.Anchored = false
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			if part == meshes[1] then
				-- A Motor6D, not a weld: the Animator walks root > mesh > bones.
				local motor = Instance.new("Motor6D")
				motor.Name = "Root"
				motor.Part0 = root
				motor.Part1 = part
				motor.C0 = root.CFrame:Inverse() * part.CFrame
				motor.C1 = CFrame.new()
				motor.Parent = part
			else
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
	local humanoid = Instance.new("Humanoid")
	-- R15: custom rigs ride on HipHeight (an R6 Humanoid ignores it and
	-- looks for R6 legs), and the Animator drives the Motor6D/bone tree.
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = h.hip or 2
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new()
	primary = root
else
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = plan.anchored ~= false
		end
	end
end

-- Animation assets uploaded by upload.py --animations, by the names the game plays.
local uploaded = serde.decode("json", fs.readFile("build/meshy/" .. name .. "/roblox.json")).animations
if spec.animations then
	if not uploaded then
		fail(name .. " has animations in its spec but none were uploaded (upload.py --animations)")
	end
	local folder = Instance.new("Folder")
	folder.Name = "Animations"
	for clip, assetId in uploaded do
		local animation = Instance.new("Animation")
		animation.Name = clip
		animation.AnimationId = "rbxassetid://" .. tostring(assetId)
		animation:SetAttribute("Loop", table.find(spec.animations.loop or {}, clip) ~= nil)
		animation.Parent = folder
	end
	folder.Parent = model
end

for _, instance in model:GetDescendants() do
	if isAny(instance, UNPUBLISHABLE) then
		fail("Still unpublishable after cleanup: " .. instance:GetFullName())
	end
	if instance:IsA("MeshPart") then
		counts.MeshPart += 1
	elseif instance:IsA("Bone") then
		counts.Bone += 1
	end
end

local all = {}
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(all, d)
	end
end
local low, high = bounds(all)
local size = high - low
local ids = serde.decode("json", fs.readFile("build/meshy/" .. name .. "/roblox.json"))
local function round(v)
	return { math.round(v.X * 10) / 10, math.round(v.Y * 10) / 10, math.round(v.Z * 10) / 10 }
end
local partNames = {}
for _, child in model:GetChildren() do
	table.insert(partNames, child.Name)
end
table.sort(partNames)
local summary = {
	name = name,
	modelAssetId = ids.modelAssetId,
	imageAssetId = ids.imageAssetId,
	meshParts = counts.MeshPart,
	bones = counts.Bone,
	removed = counts.Stripped,
	meshStuds = round(meshSize),
	sizeStuds = round(size),
	primaryPart = model.PrimaryPart and model.PrimaryPart.Name,
	children = partNames,
}

-- "folder": variants the game reads as a set (e.g. Presents -> ServerStorage.Assets.Presents).
local outDir = if spec.folder then "assets/models/" .. spec.folder else "assets/models"
fs.writeDir(outDir)
fs.writeFile(outDir .. "/" .. name .. ".rbxm", roblox.serializeModel({ model }))
fs.writeFile("build/meshy/" .. name .. "/summary.json", serde.encode("json", summary, true))
print(
	string.format(
		"Wrote assets/models/%s.rbxm: %d MeshParts, %d bones, %.1f x %.1f x %.1f studs, removed %d",
		name,
		counts.MeshPart,
		counts.Bone,
		size.X,
		size.Y,
		size.Z,
		counts.Stripped
	)
)
