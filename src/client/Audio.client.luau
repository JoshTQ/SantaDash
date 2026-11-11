--[[
	The local player's sound layer: music, the sleigh's leave warning, Krampus
	proximity (heartbeat), loot and UI sounds. It listens to the same Hud
	events as the HUD. World sounds (snoring parents, dogs, Krampus's bells,
	presents) are 3D and played by the server (SoundPlayer.at / loop).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Sounds = require(ReplicatedStorage.Shared.Sounds)
local Util = require(ReplicatedStorage.Shared.Util)

local player = Players.LocalPlayer
local hud = Remotes.get("Hud")

local inRun = false
local phase: string? = nil
local departAt: number? = nil
local lastCued: number? = nil
local krampusModel: Model? = nil
local lastPlayer = nil
local lastNoise = 0
local lastWiggles = 0

----------------------------------------------------------------------------
-- Loops: one music track at a time, plus flight bells, heartbeat, ambience
----------------------------------------------------------------------------

local music: { key: string?, loop: SoundPlayer.Loop? } = { key = nil, loop = nil }

local function setMusic(key: string?)
	if music.key == key then
		return
	end
	if music.loop then
		music.loop.stop(Config.Audio.MusicFade)
	end
	music.key = key
	music.loop = if key then SoundPlayer.loop(key, SoundService) else nil
end

local function refreshMusic()
	setMusic(Sounds.musicFor(inRun, phase, krampusModel ~= nil))
end

local flightBells: SoundPlayer.Loop? = nil
local heartbeat: SoundPlayer.Loop? = nil
local heartbeatBase = 0
local ambience: SoundPlayer.Loop? = nil

local function stopLoop(loop: SoundPlayer.Loop?, fade: number?): nil
	if loop then
		loop.stop(fade)
	end
	return nil
end

local function setInRun(value: boolean)
	if inRun == value then
		return
	end
	inRun = value
	if inRun then
		ambience = SoundPlayer.loop("NightAmbience", SoundService)
	else
		ambience = stopLoop(ambience, 1)
		flightBells = stopLoop(flightBells)
		phase, departAt, lastCued, lastPlayer = nil, nil, nil, nil
	end
	refreshMusic()
end

----------------------------------------------------------------------------
-- Hud events
----------------------------------------------------------------------------

local handlers = {}

function handlers.Stop(data)
	setInRun(true)
	local before = phase
	phase = data.phase
	departAt = data.departAt
	if phase == before then
		return
	end
	if phase == "Flight" then
		SoundPlayer.ui("SleighTakeoff")
		flightBells = stopLoop(flightBells)
		flightBells = SoundPlayer.loop("FlightBells", SoundService)
	elseif before == "Flight" then
		flightBells = stopLoop(flightBells, 0.5)
		SoundPlayer.ui("SleighLand")
	end
	if phase == "Sneak" then
		lastCued, lastNoise = nil, 0
	elseif phase == "LightsOn" then
		SoundPlayer.ui("LightsOn")
	elseif phase == "Horn" then
		SoundPlayer.ui("SleighHorn")
	end
	refreshMusic()
end

function handlers.Noise(data)
	local cue = Sounds.noiseCue(lastNoise, data.value, Config.Noise.Max)
	lastNoise = data.value
	if cue then
		SoundPlayer.ui(cue)
	end
end

function handlers.Player(data)
	setInRun(true)
	for _, cue in Sounds.lootCues(lastPlayer, data) do
		SoundPlayer.ui(cue)
	end
	lastPlayer = data
end

function handlers.Krampus(data)
	local arriving = data.model ~= nil and krampusModel == nil
	krampusModel = data.model
	if arriving then
		SoundPlayer.ui("KrampusComing")
		heartbeat = SoundPlayer.loop("KrampusHeartbeat", SoundService)
		heartbeatBase = if heartbeat.sound then heartbeat.sound.Volume else 0
		if heartbeat.sound then
			heartbeat.sound.Volume = 0
		end
	elseif not krampusModel then
		heartbeat = stopLoop(heartbeat, 0.5)
	end
	refreshMusic()
end

function handlers.KrampusTease()
	SoundPlayer.ui("KrampusTease")
end

function handlers.Hide(data)
	if data.hidden and data.breath and data.breath < 0.3 then
		SoundPlayer.ui("BreathStrain")
	end
end

function handlers.Captive(data)
	if data.captive then
		if data.wiggles > lastWiggles then
			SoundPlayer.ui("Wiggle")
		end
		lastWiggles = data.wiggles
	else
		lastWiggles = 0
	end
end

function handlers.Results(data)
	local mine
	for _, row in data.rows do
		if if row.userId then row.userId == player.UserId else row.name == player.DisplayName then
			mine = row
		end
	end
	SoundPlayer.ui(if mine and mine.escaped then "ResultsWin" else "ResultsMiss")
	phase = "Results"
	refreshMusic()
end

function handlers.RunEnd()
	handlers.Krampus({})
	setInRun(false)
end

function handlers.Sfx(data)
	if type(data) == "table" and type(data.key) == "string" and Sounds.Defs[data.key] then
		SoundPlayer.ui(data.key)
	end
end

hud.OnClientEvent:Connect(function(kind: string, data)
	local handler = handlers[kind]
	if handler then
		handler(data)
	end
end)

refreshMusic()

-- The HUD's Music button (saved by server/Settings as this attribute).
local function applyMusicSetting()
	SoundPlayer.setGroupMuted("Music", player:GetAttribute("MusicOff") == true)
end
player:GetAttributeChangedSignal("MusicOff"):Connect(applyMusicSetting)
applyMusicSetting()

----------------------------------------------------------------------------
-- Ten times a second: the sleigh countdown and Krampus's heartbeat
----------------------------------------------------------------------------

while true do
	task.wait(0.1)
	if phase == "Horn" and departAt then
		local left = math.ceil(departAt - Util.now())
		local cue = Sounds.leaveCue(left, lastCued)
		if cue then
			SoundPlayer.ui(cue, if cue == "CountdownTick" then Sounds.tickPitch(left) else nil)
		end
		lastCued = left
	end
	local sound = heartbeat and heartbeat.sound
	if sound then
		local root = Util.rootOf(player)
		local distance = if krampusModel
				and krampusModel.Parent
				and root
			then (krampusModel:GetPivot().Position - root.Position).Magnitude
			else nil
		local mix = Sounds.krampusMix(distance)
		sound.Volume = heartbeatBase * mix.heartbeat
		sound.PlaybackSpeed = mix.speed
	end
end
