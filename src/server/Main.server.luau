--[[
	Sleigh Heist server entry point (greybox). The same build runs in both
	places: the run place hosts one crew (RunHost); anywhere else this is the
	Sleigh Station lobby. Until the places are published (Config.Places),
	the lobby also runs the runs itself, all in one server.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Handoff = require(ReplicatedStorage.Shared.Handoff)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Lobby = require(script.Parent.Lobby)
local LobbyMap = require(script.Parent.LobbyMap)
local RunHost = require(script.Parent.RunHost)

Remotes.init()

-- Christmas Eve night, always (Josh, 2 Nov): a bright moon so kids can see,
-- stars, and bloom so the Christmas lights glow. Lighting.Technology is
-- Future (Josh, 4 Nov), set in the project files: scripts can't change it,
-- and Roblox drops to simpler lighting by itself on low graphics quality.
Lighting.ClockTime = 0
Lighting.Brightness = 1.2
Lighting.OutdoorAmbient = Color3.fromRGB(95, 110, 150)
Lighting.Ambient = Color3.fromRGB(80, 90, 125)
Lighting.EnvironmentDiffuseScale = 0.4
local function effect(className: string, props: { [string]: any })
	local instance = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
	for k, v in props do
		(instance :: any)[k] = v
	end
	instance.Parent = Lighting
end
effect("Sky", { StarCount = 3000, MoonAngularSize = 14, CelestialBodiesShown = true })
effect("Atmosphere", {
	Density = 0.28,
	Offset = 0.1,
	Color = Color3.fromRGB(110, 125, 170),
	Decay = Color3.fromRGB(40, 45, 80),
	Glare = 0,
	Haze = 1.2,
})
effect("BloomEffect", { Intensity = 0.8, Size = 30, Threshold = 0.9 })
effect(
	"ColorCorrectionEffect",
	{ Saturation = 0.12, Contrast = 0.06, TintColor = Color3.fromRGB(235, 240, 255) }
)

local hub = LobbyMap.build(workspace)
if Handoff.isRunPlace(game.PlaceId, workspace:GetAttribute("RunPlace")) then
	RunHost.start(hub) -- GREYBOX: crews wait in the hub between runs
else
	Lobby.start(hub)
end
