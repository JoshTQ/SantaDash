--[[
	Player settings saved in PlayerData ("settings"): for now only the HUD's
	Music button. The client asks with Input("Music", on); the server saves it
	and mirrors it as the player attribute MusicOff, which the client's sound
	layer reads (so it also applies the moment saved data loads, in both
	places).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)

local Settings = {}

Settings.MUSIC_OFF_ATTRIBUTE = "MusicOff"

local function musicOff(data: any): boolean
	return type(data) == "table" and type(data.settings) == "table" and data.settings.musicOff == true
end

function Settings.apply(player: Player, data: any)
	player:SetAttribute(Settings.MUSIC_OFF_ATTRIBUTE, musicOff(data))
end

-- on = music on. Anything but a boolean is ignored (it comes from a client).
function Settings.setMusic(player: Player, on: any)
	if type(on) ~= "boolean" then
		return
	end
	player:SetAttribute(Settings.MUSIC_OFF_ATTRIBUTE, not on)
	PlayerData.update(player, function(data)
		if type(data.settings) ~= "table" then
			data.settings = {}
		end
		data.settings.musicOff = not on
	end)
end

function Settings.start()
	local function added(player: Player)
		local data = PlayerData.waitFor(player)
		if data and player.Parent == Players then
			Settings.apply(player, data)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end
	Remotes.get("Input").OnServerEvent:Connect(function(player, action, value)
		if action == "Music" then
			Settings.setMusic(player, value)
		end
	end)
end

return Settings
