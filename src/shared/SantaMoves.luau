--[[
	The playable Santa's animation rules, shared by the server (which says
	when to sneak, grab or cheer) and each player's client (which plays the
	clips on its own character, so they replicate to everyone).

	Clips come from the Meshy pipeline (art/meshy/Santa.json): the Santa
	model in ServerStorage.Assets has an Animations folder with Idle, Walk,
	Sneak (looping) and Grab, Cheer (one-shots).

	  Player attribute "Sneaking"  true during a stop's sneak phase: moving
	                               Santas tiptoe instead of walking
	  Character attribute "SantaMove"  "<Move>#<n>": the server asks for a
	                               one-shot; n changes every time so the same
	                               move can play twice in a row
]]

local Config = require(script.Parent.Config)

local SantaMoves = {}

SantaMoves.LOOPS = { "Idle", "Walk", "Sneak" }
-- Looping clips the Meshy spec doesn't make yet: played if the model has them.
-- Swim (the Lair lake): without it he paddles along with Walk.
SantaMoves.OPTIONAL_LOOPS = { "Swim" }
SantaMoves.REQUIRED = { "Idle", "Walk" } -- without these, players keep the default avatar

-- One-shots: playback speed over the trimmed clip (Grab 2.1 s, Cheer 3.2 s).
SantaMoves.ONE_SHOTS = {
	Grab = { speed = 1.6 },
	Cheer = { speed = 1.1 },
}

SantaMoves.SNEAK_ATTRIBUTE = "Sneaking"
SantaMoves.MOVE_ATTRIBUTE = "SantaMove"
SantaMoves.SANTA_ATTRIBUTE = "IsSanta"
-- Character attribute "Skating": true while a Santa glides on canal ice
-- (server/CanalTown sets it). Clients lean and sway him and spray ice.
SantaMoves.SKATE_ATTRIBUTE = "Skating"
SantaMoves.SKIN_ATTRIBUTE = "SantaSkin" -- the suit he wears (Config.Skins id, server/Skins.luau)

-- Below this ground speed (studs/s) Santa stands still: idle.
SantaMoves.MOVING = 0.5

-- Which looping clip a Santa plays: standing, walking, tiptoeing or swimming
-- (in the Lair lake; without a Swim clip he paddles along with Walk).
function SantaMoves.loopFor(
	speed: number,
	sneaking: boolean,
	has: { [string]: boolean },
	swimming: boolean?
): string
	if swimming then
		return if has.Swim then "Swim" else "Walk"
	end
	if speed < SantaMoves.MOVING then
		return "Idle"
	end
	if sneaking and has.Sneak then
		return "Sneak"
	end
	return "Walk"
end

-- Playback speed so feet roughly match ground speed (Peppermint Rush runs
-- faster), clamped so a slow shuffle or a dog knockback doesn't look silly.
function SantaMoves.loopSpeed(clip: string, speed: number): number
	if clip == "Idle" then
		return 1
	end
	return math.clamp(speed / Config.Player.WalkSpeed, 0.6, 1.8)
end

-- Skating has no Meshy clip (the animation library has none, checked 6 Nov
-- 2026), so it is the walk played as slow, long strides plus a lean and a
-- side-to-side sway on the root joint (client/SkateLean.client.luau).
SantaMoves.SKATE_STRIDE = 0.7 -- walk clip playback speed while skating

-- The skating pose at time t (seconds) and ground speed: forward lean and
-- side sway in radians, and the stride phase (-1..1, which foot pushes).
function SantaMoves.skatePose(t: number, speed: number): (number, number, number)
	local amount = math.clamp(speed / Config.Canal.SkateSpeed, 0, 1)
	local phase = math.sin(t * math.pi * 2 * 0.9) -- about one push per foot a second
	local lean = math.rad(16) * amount
	local sway = math.rad(11) * amount * phase
	return lean, sway, phase
end

-- The attribute value that asks clients to play `move` (n counts up).
function SantaMoves.encode(move: string, n: number): string
	return move .. "#" .. tostring(n)
end

-- The move name from an attribute value, or nil for nonsense.
function SantaMoves.decode(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local move = string.match(value, "^(%a+)#%d+$")
	if move and SantaMoves.ONE_SHOTS[move] then
		return move
	end
	return nil
end

local counter = 0

-- Server: plays a one-shot on a player's Santa (no-op for default avatars).
function SantaMoves.play(character: Instance?, move: string)
	if not character or not SantaMoves.ONE_SHOTS[move] then
		return
	end
	if character:GetAttribute(SantaMoves.SANTA_ATTRIBUTE) ~= true then
		return
	end
	counter += 1
	character:SetAttribute(SantaMoves.MOVE_ATTRIBUTE, SantaMoves.encode(move, counter))
end

return SantaMoves
