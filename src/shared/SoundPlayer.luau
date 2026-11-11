--[[
	Plays catalogue sounds (Sounds.luau) on the server or a client.

	Server: 3D sounds at a place or on a part (`at`, `loop`). They replicate,
	so everyone near hears them (routes are 1,600 studs apart, far past any
	sound's range). Client: the same, plus 2D `ui` sounds only that player hears.

	A key with no SoundAssets override and no id is silent (Studio warns once),
	so the game runs before every sound is picked.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Config)
local Sounds = require(script.Parent.Sounds)

local SoundPlayer = {}

local rng = Random.new()
local warned: { [string]: boolean } = {}
local voices: { [string]: number } = {}
local lastAt: { [any]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local terrainLast: { [string]: number } = {}

local function group(name: string): SoundGroup
	local full = "SleighHeist" .. name
	local existing = SoundService:FindFirstChild(full)
	if existing then
		return existing :: SoundGroup
	end
	local g = Instance.new("SoundGroup")
	g.Name = full
	g.Volume = Config.Audio.Groups[name] or 0.7
	g.Parent = SoundService
	return g
end

-- Client: mute or restore a whole group (the HUD's Music button).
function SoundPlayer.setGroupMuted(name: string, muted: boolean)
	group(name).Volume = if muted then 0 else (Config.Audio.Groups[name] or 0.7)
end

local function template(key: string): Sound?
	local folder = ReplicatedStorage:FindFirstChild(Config.Audio.FolderName)
	local found = folder and folder:FindFirstChild(key)
	return if found and found:IsA("Sound") then found else nil
end

-- A ready-to-play Sound for `key` under `parent`, or nil if it has no audio.
function SoundPlayer.make(key: string, parent: Instance): Sound?
	if not Config.Audio.Enabled then
		return nil
	end
	local def = Sounds.get(key)
	if def.group == "Music" and not Config.Audio.MusicEnabled then
		return nil
	end
	local base = template(key)
	local sound: Sound
	if base then
		sound = base:Clone()
		sound.PlaybackSpeed = sound.PlaybackSpeed * Sounds.pitchFor(key, rng)
	elseif def.id > 0 then
		sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. def.id
		sound.Volume = def.volume
		sound.PlaybackSpeed = Sounds.pitchFor(key, rng)
	else
		if not warned[key] and RunService:IsStudio() then
			warned[key] = true
			warn("[Sound] " .. key .. " has no audio yet (search: " .. def.find .. ")")
		end
		return nil
	end
	sound.Name = key
	sound.Looped = def.looped == true
	sound.SoundGroup = group(def.group)
	if def.range then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = def.range[1]
		sound.RollOffMaxDistance = def.range[2]
	end
	sound.Parent = parent
	return sound
end

local function playOnce(key: string, parent: Instance, cleanup: Instance?): Sound?
	if (voices[key] or 0) >= Sounds.MaxVoicesPerKey then
		return nil
	end
	local sound = SoundPlayer.make(key, parent)
	if not sound then
		if cleanup then
			cleanup:Destroy()
		end
		return nil
	end
	voices[key] = (voices[key] or 0) + 1
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		voices[key] -= 1
		(cleanup or sound):Destroy()
	end
	sound.Ended:Once(finish)
	task.delay(12, finish) -- in case it never loads or ends
	sound:Play()
	return sound
end

-- One-shot 3D sound on a part / attachment, or at a world position.
-- Cooldowns are per key and per part (positions share one per key).
function SoundPlayer.at(key: string, where: Vector3 | Instance): Sound?
	local t = os.clock()
	local last = if typeof(where) == "Instance" then lastAt[where] else terrainLast
	if last and not Sounds.ready(key, last[key], t) then
		return nil
	end
	if typeof(where) == "Instance" then
		if not where.Parent then
			return nil
		end
		lastAt[where] = lastAt[where] or {}
		lastAt[where][key] = t
		return playOnce(key, where)
	end
	terrainLast[key] = t
	local attachment = Instance.new("Attachment")
	attachment.Name = "Sound_" .. key
	attachment.WorldPosition = where :: Vector3
	attachment.Parent = workspace.Terrain
	return playOnce(key, attachment, attachment)
end

-- Client: a 2D sound only the local player hears. `speed` overrides the pitch.
function SoundPlayer.ui(key: string, speed: number?): Sound?
	if RunService:IsServer() then
		return nil -- 2D sounds on the server would play for the whole server
	end
	local t = os.clock()
	if not Sounds.ready(key, terrainLast["ui:" .. key], t) then
		return nil
	end
	terrainLast["ui:" .. key] = t
	local sound = playOnce(key, SoundService)
	if sound and speed then
		sound.PlaybackSpeed = speed
	end
	return sound
end

export type Loop = { sound: Sound?, stop: (fade: number?) -> () }

-- A looping sound on `parent` (a part for 3D, SoundService for 2D on clients).
function SoundPlayer.loop(key: string, parent: Instance): Loop
	local sound = SoundPlayer.make(key, parent)
	if sound then
		sound:Play()
	end
	local loop = { sound = sound }
	function loop.stop(fade: number?)
		local s = loop.sound
		loop.sound = nil
		if not s then
			return
		end
		if fade and fade > 0 then
			local from = s.Volume
			task.spawn(function()
				local t0 = os.clock()
				while s.Parent and os.clock() - t0 < fade do
					s.Volume = from * (1 - (os.clock() - t0) / fade)
					task.wait()
				end
				s:Destroy()
			end)
		else
			s:Destroy()
		end
	end
	return loop
end

return SoundPlayer
