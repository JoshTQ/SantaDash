--[[
	Loads the content that would otherwise download mid-run, in the background
	right after joining: the cutscene and Krampus sounds, then Krampus's Meshy
	model (ids from the server, see shared/Preload). Without this the
	KrampusArrives intro froze while his mesh and texture loaded.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Preload = require(ReplicatedStorage.Shared.Preload)
local Sounds = require(ReplicatedStorage.Shared.Sounds)

local function preload(items: { any })
	if #items == 0 then
		return
	end
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(items)
	end)
	if not ok then
		warn("[Preload] " .. tostring(err))
	end
end

-- Sounds first: they are small, and every run opens with the Takeoff scene.
local sounds: { any } = Preload.soundIds(Sounds.Defs)
for _, sound in Preload.sounds(ReplicatedStorage:FindFirstChild(Config.Audio.FolderName)) do
	table.insert(sounds, sound)
end
preload(sounds)

-- The server sets the attribute at start-up (an empty string when there is
-- nothing to load); wait for it if this client got here first.
if ReplicatedStorage:GetAttribute(Preload.Attribute) == nil then
	ReplicatedStorage:GetAttributeChangedSignal(Preload.Attribute):Wait()
end
preload(Preload.decode(ReplicatedStorage:GetAttribute(Preload.Attribute)))
