--[[
	Sleigh Heist server entry point (greybox).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(script.Parent.MapBuilder)
local Lobby = require(script.Parent.Lobby)

Remotes.init()

-- Christmas Eve night.
Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.OutdoorAmbient = Color3.fromRGB(90, 100, 130)
Lighting.Ambient = Color3.fromRGB(90, 100, 130)

local hub = MapBuilder.buildHub()
Lobby.start(hub)
