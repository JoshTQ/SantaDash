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

-- Christmas Eve night.
Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.OutdoorAmbient = Color3.fromRGB(90, 100, 130)
Lighting.Ambient = Color3.fromRGB(90, 100, 130)

local hub = LobbyMap.build(workspace)
if Handoff.isRunPlace(game.PlaceId, workspace:GetAttribute("RunPlace")) then
	RunHost.start(hub) -- GREYBOX: crews wait in the hub between runs
else
	Lobby.start(hub)
end
