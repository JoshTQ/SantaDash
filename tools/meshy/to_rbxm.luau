--[[
	Turns the model Roblox imported (build/meshy/<Name>/imported.rbxm, from
	upload.py) into the file the deploy ships: assets/models/<Name>.rbxm.

	  lune run tools/meshy/to_rbxm <Name>

	- one root Model named <Name> (the deploy names ServerStorage.Assets.<Name>
	  after the file, the game looks the model up by its Name)
	- every MeshPart gets the uploaded colour texture as TextureID
	- removes what Open Cloud can't publish (SurfaceAppearance, unions,
	  Editable*, wraps) and the PackageLink the asset upload adds
	- fails if anything unpublishable is left, so a bad file never reaches main
	- prints what's inside (parts, bones, size) for the approval PR
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3

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
local dir = "build/meshy/" .. name
local ids = serde.decode("json", fs.readFile(dir .. "/roblox.json"))
local texture = "rbxassetid://" .. tostring(ids.imageAssetId)

local ok, roots = pcall(roblox.deserializeModel, fs.readFile(dir .. "/imported.rbxm"))
if not ok then
	fail("Couldn't read the model Roblox imported: " .. tostring(roots))
end

local model
if #roots == 1 and roots[1]:IsA("Model") then
	model = roots[1]
else
	model = Instance.new("Model")
	for _, root in roots do
		root.Parent = model
	end
end
model.Name = name

local function isAny(instance, classes): boolean
	for _, className in classes do
		if instance:IsA(className) then
			return true
		end
	end
	return false
end

local counts = { MeshPart = 0, Bone = 0, Stripped = 0 }
local largest, largestVolume = nil, 0
local low = Vector3.new(math.huge, math.huge, math.huge)
local high = Vector3.new(-math.huge, -math.huge, -math.huge)
for _, instance in model:GetDescendants() do
	if instance.Parent and isAny(instance, STRIP) then
		instance:Destroy()
		counts.Stripped += 1
	end
end
for _, instance in model:GetDescendants() do
	if instance:IsA("MeshPart") then
		counts.MeshPart += 1
		instance.TextureID = texture
		local size = instance.Size
		local volume = size.X * size.Y * size.Z
		local at, half = instance.CFrame.Position, size / 2
		low = Vector3.new(math.min(low.X, at.X - half.X), math.min(low.Y, at.Y - half.Y), math.min(low.Z, at.Z - half.Z))
		high = Vector3.new(math.max(high.X, at.X + half.X), math.max(high.Y, at.Y + half.Y), math.max(high.Z, at.Z + half.Z))
		if volume > largestVolume then
			largest, largestVolume = instance, volume
		end
	elseif instance:IsA("Bone") then
		counts.Bone += 1
	end
end
if counts.MeshPart == 0 then
	fail("The imported model has no MeshParts")
end
if model.PrimaryPart == nil then
	model.PrimaryPart = largest
end

for _, instance in model:GetDescendants() do
	if isAny(instance, UNPUBLISHABLE) then
		fail("Still unpublishable after cleanup: " .. instance:GetFullName())
	end
end

local size = high - low -- rough, axis-aligned
local summary = {
	name = name,
	modelAssetId = ids.modelAssetId,
	imageAssetId = ids.imageAssetId,
	meshParts = counts.MeshPart,
	bones = counts.Bone,
	removed = counts.Stripped,
	sizeStuds = { math.round(size.X * 10) / 10, math.round(size.Y * 10) / 10, math.round(size.Z * 10) / 10 },
	primaryPart = model.PrimaryPart and model.PrimaryPart.Name,
}

fs.writeDir("assets/models")
fs.writeFile("assets/models/" .. name .. ".rbxm", roblox.serializeModel({ model }))
fs.writeFile(dir .. "/summary.json", serde.encode("json", summary, true))
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
