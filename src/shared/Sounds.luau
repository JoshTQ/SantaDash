--[[
	Sleigh Heist sound catalogue and the pure rules for when sounds play.

	Every sound has a key. Where the audio comes from, first match wins:
	  1. A Sound named after the key in ReplicatedStorage.SoundAssets (drag one
	     in from the Creator Store in Studio; its SoundId, Volume and
	     PlaybackSpeed are kept, the 3D range below is applied).
	  2. `id` below (a Roblox audio asset id).
	  3. Nothing: the sound is silent and the game works the same.

	`id = 0` means "not picked yet". `find` is what to search for in the
	Creator Store (Audio, filter Creator: Roblox, so the audio is free and
	licensed for any experience). Josh confirms each pick.

	Fields:
	  group    Sfx | Music | Ambience | Ui (Config.Audio.Groups volumes)
	  volume   0-1 before the group volume; kept low for phone speakers
	  pitch    { min, max } random playback speed, so repeats don't grate
	  range    3D only: { min, max } studs (full volume within min, silent past max)
	  looped   true for loops (bells, snores, music)
	  cooldown seconds before the same key can play again from the same place
]]

local Sounds = {}

export type Def = {
	id: number,
	find: string,
	group: string,
	volume: number,
	pitch: { number }?,
	range: { number }?,
	looped: boolean?,
	cooldown: number?,
}

-- Ranked by how much they add to the launch slice (see sounds/sound-plan.md
-- in the project files). Tier 1 = must have for 15 Nov.
Sounds.Defs = {
	--------------------------------------------------------------------
	-- Tier 1: the sleigh is leaving
	--------------------------------------------------------------------
	SleighHorn = { id = 103337759957552, find = "cartoon car horn beep beep", group = "Ui", volume = 0.9 },
	LastCall = { id = 132613047546185, find = "fast double horn beep", group = "Ui", volume = 0.95 },
	CountdownTick = { id = 72124849536326, find = "sleigh bell single jingle", group = "Ui", volume = 0.45 },
	SleighTakeoff = { id = 137526023064114, find = "sleigh bells whoosh", group = "Sfx", volume = 0.55 },
	SleighLand = { id = 87613514400200, find = "soft snow thump", group = "Sfx", volume = 0.5 },
	FlightBells = {
		id = 124768513358645,
		find = "sleigh bells loop",
		group = "Sfx",
		volume = 0.3,
		looped = true,
	},

	--------------------------------------------------------------------
	-- Tier 1: Krampus
	--------------------------------------------------------------------
	KrampusComing = { id = 78454732737770, find = "cartoon monster roar funny", group = "Ui", volume = 0.6 },
	KrampusBells = {
		id = 135219766274112,
		find = "jingle bells shaking loop",
		group = "Sfx",
		volume = 0.8,
		range = { 12, 140 },
		looped = true,
	},
	KrampusHeartbeat = {
		id = 124053169424945,
		find = "heartbeat loop",
		group = "Ui",
		volume = 0.5,
		looped = true,
	},
	KrampusSnatch = {
		id = 137537717230164,
		find = "cartoon evil laugh",
		group = "Sfx",
		volume = 0.8,
		range = { 15, 120 },
		cooldown = 2,
	},
	KrampusSniff = {
		id = 89583237679405,
		find = "cartoon sniff sniff",
		group = "Sfx",
		volume = 0.6,
		pitch = { 0.85, 0.95 },
		range = { 10, 70 },
		cooldown = 6,
	},
	BellBonk = {
		id = 114059483688596,
		find = "bell clang cartoon",
		group = "Sfx",
		volume = 0.8,
		range = { 12, 110 },
		cooldown = 0.5,
	},
	KrampusDizzy = {
		id = 87432656866406,
		find = "cartoon dizzy birds tweet",
		group = "Sfx",
		volume = 0.6,
		range = { 10, 80 },
	},
	Boing = {
		id = 96145230303089,
		find = "cartoon boing",
		group = "Sfx",
		volume = 0.85,
		pitch = { 0.95, 1.1 },
		range = { 10, 80 },
	},
	Wiggle = {
		id = 72114778853774,
		find = "cloth shuffle rustle",
		group = "Ui",
		volume = 0.35,
		pitch = { 0.9, 1.3 },
	},
	KrampusTease = { id = 106027454357073, find = "distant sleigh bells", group = "Ui", volume = 0.35 },
	KrampusStomp = {
		id = 71692941615552,
		find = "giant stomp ice crack",
		group = "Sfx",
		volume = 0.9,
		range = { 30, 220 },
	},

	--------------------------------------------------------------------
	-- Tier 1: presents and loot
	--------------------------------------------------------------------
	PresentGrab = {
		id = 103923669951431,
		find = "paper rustle pop",
		group = "Sfx",
		volume = 0.5,
		pitch = { 0.9, 1.15 },
		range = { 8, 60 },
	},
	NaughtyListGrab = {
		id = 118785204214396,
		find = "chain rattle dramatic sting",
		group = "Sfx",
		volume = 0.8,
		range = { 20, 160 },
	},
	SackFull = {
		id = 98909911567144,
		find = "cartoon grunt thud",
		group = "Sfx",
		volume = 0.5,
		range = { 6, 40 },
		cooldown = 1.5,
	},
	JingleGain = {
		id = 120845024202412,
		find = "coin jingle short",
		group = "Ui",
		volume = 0.3,
		pitch = { 1, 1.2 },
		cooldown = 0.15,
	},
	Bank = { id = 134560111889844, find = "cash register ka-ching", group = "Ui", volume = 0.5 },
	SackSpill = { id = 128197119438736, find = "presents tumble cartoon", group = "Ui", volume = 0.5 },

	--------------------------------------------------------------------
	-- Tier 1: parents (house occupants) and the noise meter
	--------------------------------------------------------------------
	ParentSnore = {
		id = 117621130195035,
		find = "cartoon snore loop",
		group = "Sfx",
		volume = 0.55,
		pitch = { 0.85, 1.1 },
		range = { 6, 45 },
		looped = true,
	},
	ParentWake = {
		id = 77235121182574,
		find = "cartoon huh who's there grumble",
		group = "Sfx",
		volume = 0.7,
		pitch = { 0.9, 1.1 },
		range = { 10, 90 },
	},
	LightsOn = { id = 100845290563185, find = "light switch click uh oh", group = "Ui", volume = 0.5 },
	NoiseWarn = { id = 140446725193598, find = "three warning beeps", group = "Ui", volume = 0.45 },
	NoiseFull = { id = 77854624593363, find = "cartoon alarm siren short", group = "Ui", volume = 0.5 },

	--------------------------------------------------------------------
	-- Tier 1: security dogs (Frozen Canal Town market)
	--------------------------------------------------------------------
	CorgiGrowl = {
		id = 106855818049896,
		find = "small dog growl",
		group = "Sfx",
		volume = 0.55,
		pitch = { 1.05, 1.25 },
		range = { 8, 55 },
		cooldown = 3,
	},
	CorgiWoof = {
		id = 97880853607845,
		find = "small dog bark",
		group = "Sfx",
		volume = 0.7,
		pitch = { 1.05, 1.25 },
		range = { 10, 80 },
	},
	TinDogWhirr = {
		id = 122218651051829,
		find = "wind up toy clockwork",
		group = "Sfx",
		volume = 0.45,
		range = { 8, 50 },
		cooldown = 3,
	},
	TinDogBonk = {
		id = 138399806651117,
		find = "metal bonk spring wind down",
		group = "Sfx",
		volume = 0.7,
		range = { 10, 80 },
	},

	--------------------------------------------------------------------
	-- Tier 2: doors, hiding, buys
	--------------------------------------------------------------------
	DoorOpen = {
		id = 98551566833572,
		find = "door creak short",
		group = "Sfx",
		volume = 0.45,
		pitch = { 0.9, 1.1 },
		range = { 6, 45 },
	},
	DoorClose = {
		id = 137636984511563,
		find = "door close soft",
		group = "Sfx",
		volume = 0.4,
		range = { 6, 45 },
	},
	ChimneySlide = {
		id = 74892954452519,
		find = "slide whistle down",
		group = "Sfx",
		volume = 0.5,
		range = { 8, 60 },
	},
	ChimneyClimb = {
		id = 131541787159529,
		find = "slide whistle up",
		group = "Sfx",
		volume = 0.5,
		range = { 8, 60 },
	},
	HideIn = {
		id = 99023424781977,
		find = "wardrobe door shut",
		group = "Sfx",
		volume = 0.45,
		range = { 6, 40 },
	},
	HideOut = {
		id = 136486322601624,
		find = "wardrobe door open creak",
		group = "Sfx",
		volume = 0.45,
		range = { 6, 40 },
	},
	Gasp = {
		id = 140257255510764,
		find = "cartoon gasp for air",
		group = "Sfx",
		volume = 0.8,
		range = { 10, 90 },
	},
	BreathStrain = {
		id = 77840586659884,
		find = "holding breath strain",
		group = "Ui",
		volume = 0.35,
		cooldown = 2,
	},
	CocoaSlurp = {
		id = 131712508847511,
		find = "slurp drink cartoon",
		group = "Sfx",
		volume = 0.5,
		range = { 6, 40 },
	},
	VaultOpen = {
		id = 129863531248065,
		find = "vault door unlock heavy",
		group = "Sfx",
		volume = 0.7,
		range = { 15, 120 },
	},
	Nope = { id = 107307875294014, find = "cartoon error buzz", group = "Ui", volume = 0.35, cooldown = 0.5 },

	--------------------------------------------------------------------
	-- Tier 2: Frozen Canal Town
	--------------------------------------------------------------------
	Splash = { id = 83405834336067, find = "cartoon splash", group = "Sfx", volume = 0.7, range = { 10, 80 } },
	HoopBoost = {
		id = 133896540097512,
		find = "magic chime whoosh",
		group = "Sfx",
		volume = 0.45,
		range = { 6, 40 },
		cooldown = 1,
	},
	PolisherHum = {
		id = 79023675449506,
		find = "machine hum loop",
		group = "Sfx",
		volume = 0.4,
		range = { 8, 60 },
		looped = true,
	},
	-- Secret rooms (Room Mix houses): a soft bell twinkle that loops at the
	-- bookcase / rug / hatch, heard from the next room, and a chime when found.
	SecretHum = {
		id = 72124849536326, -- the single sleigh-bell jingle, pitched up and looped
		find = "music box twinkle loop",
		group = "Sfx",
		volume = 0.35,
		pitch = { 1.3, 1.45 },
		range = { 4, 26 },
		looped = true,
	},
	SecretFound = {
		id = 133896540097512, -- the boost hoops' magic chime
		find = "magic sparkle reveal chime",
		group = "Sfx",
		volume = 0.7,
		pitch = { 1.1, 1.1 },
		range = { 10, 90 },
	},
	-- Gingerbread Mansion: placeholders reusing catalogue ids until real ones
	-- are picked (the find text says what to look for).
	GiftPop = {
		id = 96145230303089, -- the cartoon boing
		find = "party popper confetti pop",
		group = "Sfx",
		volume = 0.8,
		pitch = { 1.3, 1.5 },
		range = { 12, 120 },
	},
	DustPuff = {
		id = 72114778853774, -- the cloth rustle
		find = "dust puff poof",
		group = "Sfx",
		volume = 0.5,
		pitch = { 0.8, 0.9 },
		range = { 6, 40 },
	},
	PianoPlonk = {
		id = 96145230303089, -- the cartoon boing, pitched down
		find = "cartoon piano key bang crash",
		group = "Sfx",
		volume = 0.9,
		pitch = { 0.6, 0.7 },
		range = { 20, 200 },
	},
	PolisherScoop = {
		id = 134317366455068,
		find = "cartoon whoosh",
		group = "Sfx",
		volume = 0.6,
		range = { 10, 70 },
	},
	IceCrack = { id = 116993069675338, find = "ice crack", group = "Sfx", volume = 0.7, range = { 20, 200 } },

	--------------------------------------------------------------------
	-- Tier 3: music, ambience and results
	--------------------------------------------------------------------
	NightAmbience = {
		id = 93735883297301,
		find = "winter night wind ambience loop",
		group = "Ambience",
		volume = 0.35,
		looped = true,
	},
	SneakMusic = {
		id = 127321626193735,
		find = "sneaky pizzicato loop",
		group = "Music",
		volume = 0.4,
		looped = true,
	},
	HurryMusic = {
		id = 73523632783469,
		find = "fast christmas chase loop",
		group = "Music",
		volume = 0.45,
		looped = true,
	},
	KrampusMusic = {
		id = 134476419640377,
		find = "spooky funny chase loop",
		group = "Music",
		volume = 0.45,
		looped = true,
	},
	LobbyMusic = {
		id = 134377198278111,
		find = "cheerful christmas loop",
		group = "Music",
		volume = 0.35,
		looped = true,
	},
	ResultsWin = { id = 90369196928217, find = "fanfare short cartoon", group = "Ui", volume = 0.55 },
	ResultsMiss = { id = 87891117529186, find = "sad trombone", group = "Ui", volume = 0.5 },
	--------------------------------------------------------------------
	-- Cutscenes (PR #10): played by Cutscenes.luau at fixed times, 2D
	--------------------------------------------------------------------
	CutsceneGiddyup = {
		id = 90349951287982,
		find = "reins snap giddy up hooves",
		group = "Ui",
		volume = 0.75,
	},
	CutsceneThump = { id = 100556334656882, find = "heavy landing thump", group = "Ui", volume = 0.7 },
	CutsceneBells = {
		id = 97200000992781,
		find = "distant bells approaching heartbeat",
		group = "Ui",
		volume = 0.7,
	},
	CutsceneClonk = { id = 132445915364990, find = "horns hit metal gate clonk", group = "Ui", volume = 0.75 },
	CutsceneRoar = { id = 96187228588309, find = "goofy monster roar", group = "Ui", volume = 0.75 },
	CutsceneStrain = { id = 74283549886584, find = "cartoon strain grunt", group = "Ui", volume = 0.6 },
	CutsceneFlump = { id = 85511195489701, find = "belly flop into snow", group = "Ui", volume = 0.75 },
	CutsceneFireworks = {
		id = 109975744914275,
		find = "fireworks whistle burst crackle",
		group = "Ui",
		volume = 0.7,
	},
	CutsceneStamp = { id = 78994682624294, find = "rubber stamp ding", group = "Ui", volume = 0.7 },
	CutsceneYoink = { id = 116483177192462, find = "slide whistle up", group = "Ui", volume = 0.6 },
	CutsceneBonk = { id = 134355592844133, find = "cartoon bonk", group = "Ui", volume = 0.65 },
	CutsceneHonk = { id = 83513324563804, find = "car horn beep beep distant", group = "Ui", volume = 0.7 },
	CutsceneRaspberry = { id = 102071129137442, find = "raspberry blow", group = "Ui", volume = 0.6 },
	CutsceneMusicTakeoff = {
		id = 77599959432521,
		find = "heist overture pizzicato bells",
		group = "Music",
		volume = 0.55,
	},
	CutsceneMusicKrampus = {
		id = 104206400356788,
		find = "comic spooky tuba creep",
		group = "Music",
		volume = 0.55,
	},
	CutsceneMusicGetaway = {
		id = 94956338149476,
		find = "triumphant caper fanfare",
		group = "Music",
		volume = 0.55,
	},
	CutsceneMusicSnatched = {
		id = 118055443260956,
		find = "slide whistle sting",
		group = "Music",
		volume = 0.55,
	},
	CutsceneMusicLeftBehind = {
		id = 81996971263690,
		find = "sad trombone short",
		group = "Music",
		volume = 0.55,
	},
} :: { [string]: Def }

Sounds.Groups = { "Sfx", "Music", "Ambience", "Ui" }

-- Never more than this many copies of one key playing at once in a place.
Sounds.MaxVoicesPerKey = 4

function Sounds.get(key: string): Def
	local def = Sounds.Defs[key]
	assert(def, "Unknown sound " .. tostring(key))
	return def
end

function Sounds.is3D(key: string): boolean
	return Sounds.get(key).range ~= nil
end

-- A random playback speed inside the def's pitch range (1 when it has none).
function Sounds.pitchFor(key: string, rng: Random): number
	local pitch = Sounds.get(key).pitch
	if not pitch then
		return 1
	end
	return rng:NextNumber(pitch[1], pitch[2])
end

-- True if `key` may play again, last played at `lastAt` (nil = never).
function Sounds.ready(key: string, lastAt: number?, t: number): boolean
	local cooldown = Sounds.get(key).cooldown or 0
	return lastAt == nil or t - lastAt >= cooldown
end

----------------------------------------------------------------------------
-- Cues: pure decisions the client and server turn into sounds
----------------------------------------------------------------------------

-- The sleigh's leave warning. Called with whole seconds left before it
-- leaves (counting down) and the last second it already cued (nil at first).
-- Returns a key to play now, or nil. The horn itself plays on entering the
-- Horn phase; this adds a last-call honk at 10 s and bell ticks from 5 to 1.
Sounds.LastCallAt = 10
Sounds.TicksFrom = 5

function Sounds.leaveCue(secondsLeft: number, lastCued: number?): string?
	if secondsLeft == lastCued or secondsLeft < 1 then
		return nil
	end
	if secondsLeft == Sounds.LastCallAt then
		return "LastCall"
	elseif secondsLeft <= Sounds.TicksFrom then
		return "CountdownTick"
	end
	return nil
end

-- Countdown ticks rise in pitch as the sleigh is about to go: 5 -> 1.0, 1 -> 1.4.
function Sounds.tickPitch(secondsLeft: number): number
	return 1 + (Sounds.TicksFrom - math.clamp(secondsLeft, 1, Sounds.TicksFrom)) * 0.1
end

-- The noise meter: a squeak crossing WarnFraction, an alarm when it fills.
Sounds.NoiseWarnFraction = 0.75

function Sounds.noiseCue(before: number, after: number, max: number): string?
	if after >= max and before < max then
		return "NoiseFull"
	elseif after >= max * Sounds.NoiseWarnFraction and before < max * Sounds.NoiseWarnFraction then
		return "NoiseWarn"
	end
	return nil
end

-- Loot changes from one Player update to the next (nil before = first update).
function Sounds.lootCues(before: { jingle: number, banked: number, sackCount: number }?, after): { string }
	local cues = {}
	if not before then
		return cues
	end
	-- Banking and the missed-final spill are cued by the server (Sfx), which
	-- knows which one happened; here only what a Player update alone shows.
	if after.banked > before.banked then
		return cues
	elseif after.sackCount < before.sackCount then
		table.insert(cues, "SackSpill") -- a corgi knocked one out
	elseif after.jingle > before.jingle then
		table.insert(cues, "JingleGain")
	end
	return cues
end

-- Krampus proximity mix for the local Santa: heartbeat volume (0-1) and
-- speed. The bells themselves are a 3D loop on his body; this layers a
-- heartbeat that only kicks in when he is close (matches the HUD's 30/70).
Sounds.HeartbeatNear = 30
Sounds.HeartbeatFar = 70

function Sounds.krampusMix(distance: number?): { heartbeat: number, speed: number }
	if not distance or distance >= Sounds.HeartbeatFar then
		return { heartbeat = 0, speed = 1 }
	end
	local near = Sounds.HeartbeatNear
	local closeness = 1 - math.clamp((distance - near) / (Sounds.HeartbeatFar - near), 0, 1)
	return { heartbeat = 0.35 + 0.65 * closeness, speed = 1 + 0.4 * closeness }
end

-- Which music loop fits the run right now (nil = no music).
function Sounds.musicFor(inRun: boolean, phase: string?, krampusActive: boolean): string?
	if not inRun then
		return "LobbyMusic"
	elseif krampusActive then
		return "KrampusMusic"
	elseif phase == "Horn" then
		return "HurryMusic"
	elseif phase == "Sneak" or phase == "LightsOn" then
		return "SneakMusic"
	end
	return nil -- flights and take-off: sleigh bells instead
end

-- Should a patrolling dog warn a Santa this close (growl / clockwork whirr)?
-- Warns from WarnRadius out, before the bump at hitRadius.
function Sounds.dogWarns(distance: number, hitRadius: number, warnRadius: number): boolean
	return distance >= hitRadius and distance < warnRadius
end

return Sounds
