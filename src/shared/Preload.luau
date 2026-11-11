--[[
	Warm the client's content cache before the heavy moments.

	Krampus only exists from the moment he wakes in the Lair: the server clones
	his Meshy model then, in the same frame the KrampusArrives cutscene starts.
	Before this, every client had to download and decode his mesh and texture
	right then, which froze the game at the start of the intro. Cutscene
	sounds had the same problem on their first play.

	So the server lists the content ids inside the models that appear late
	(ServerStorage.Assets is invisible to clients) on a ReplicatedStorage
	attribute, and client/Preload.client loads those plus the cutscene sounds
	in the background as soon as the player joins.
]]

local Preload = {}

Preload.Attribute = "PreloadContent"
-- Approved models that are only cloned into the world mid-run.
Preload.LateModels = { "Krampus" }
-- SoundAssets keys worth having ready before they first play.
Preload.SoundPrefixes = { "Cutscene", "Krampus" }

-- Content properties by class (checked with IsA, so subclasses count).
local PROPERTIES: { { className: string, props: { string } } } = {
	{ className = "MeshPart", props = { "MeshId", "TextureID" } },
	{ className = "SpecialMesh", props = { "MeshId", "TextureId" } },
	{ className = "Decal", props = { "Texture" } }, -- Texture is a Decal subclass
	{ className = "SurfaceAppearance", props = { "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" } },
	{ className = "Animation", props = { "AnimationId" } },
	{ className = "Sound", props = { "SoundId" } },
}

local function asId(value: any): string?
	if type(value) == "string" then
		return if value ~= "" then value else nil
	end
	-- Newer Content values: their uri, if they have one.
	local ok, uri = pcall(function()
		return value.Uri
	end)
	return if ok and type(uri) == "string" and uri ~= "" then uri else nil
end

-- Every distinct content id in `root` and its descendants, in a stable order.
function Preload.contentIds(root: Instance): { string }
	local seen, list = {}, {}
	local all = root:GetDescendants()
	table.insert(all, 1, root)
	for _, instance in all do
		for _, entry in PROPERTIES do
			if instance:IsA(entry.className) then
				for _, prop in entry.props do
					local ok, value = pcall(function()
						return (instance :: any)[prop]
					end)
					local id = ok and asId(value)
					if id and not seen[id] then
						seen[id] = true
						table.insert(list, id)
					end
				end
			end
		end
	end
	return list
end

-- Attribute strings are capped, so ids are space-joined and capped too.
local MAX_IDS = 200
function Preload.encode(ids: { string }): string
	return table.concat(ids, " ", 1, math.min(#ids, MAX_IDS))
end

function Preload.decode(text: any): { string }
	local list = {}
	if type(text) == "string" then
		for id in string.gmatch(text, "%S+") do
			table.insert(list, id)
		end
	end
	return list
end

local function wanted(key: string): boolean
	for _, prefix in Preload.SoundPrefixes do
		if string.sub(key, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- Catalogue ids (shared/Sounds Defs) for the keys worth preloading, sorted.
function Preload.soundIds(defs: { [string]: { id: number } }): { string }
	local keys = {}
	for key, def in defs do
		if wanted(key) and def.id > 0 then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local list = {}
	for _, key in keys do
		table.insert(list, "rbxassetid://" .. defs[key].id)
	end
	return list
end

-- Sounds in `folder` whose names start with one of SoundPrefixes.
function Preload.sounds(folder: Instance?): { Instance }
	local list = {}
	for _, child in if folder then folder:GetChildren() else {} do
		if child:IsA("Sound") and wanted(child.Name) then
			table.insert(list, child)
		end
	end
	return list
end

return Preload
