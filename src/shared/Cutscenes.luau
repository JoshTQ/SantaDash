--[[
	Short slapstick cutscenes (Josh, 2 Nov 2026: build all five, one version
	each, the same every time, always skippable).

	The server decides WHEN a scene plays and who sees it (Run.luau), and moves
	any models that matter to gameplay (the sleigh, Krampus). Each client then
	plays the camera, letterbox, text pops and gags itself (CutscenePlayer), so
	every player skips on their own and the game never pauses for anyone.

	A scene is plain data plus a few pure helpers, so the timing rules are unit
	tested in Lune:
		seconds   total length (never over Config.Cutscenes.MaxSeconds)
		audience  "all" (the crew in the run) or "self" (one player)
		keys      camera keyframes { at, eye = {space, offset}, look = {space, offset}, fov? }
		          space: "anchor" (a CFrame the server sends), "follow" (a model's
		          pivot, e.g. the sleigh or Krampus) or "self" (the local Santa)
		pops      big comic text { at, hold, text, color, size? }
		cues      one-off client gags { at, kind = "sfx" | "shake" | "hatsOff" | "drop" | "marks"
		          | "fireworks" | "snowPuff", ... }
		          Every scene starts its own music cue (CutsceneMusic*) at 0. Audio
		          is made by the sounds thread (PR #9 catalogue, "Cutscenes").
		tint      optional screen wash { color, pulse }
]]

local Cutscenes = {}

export type Space = "anchor" | "follow" | "self"
export type Point = { space: Space, offset: Vector3 }
-- cut: a hard cut. The camera holds the previous key until `at`, then jumps here.
export type Key = { at: number, eye: Point, look: Point, fov: number?, cut: boolean? }
export type Pop = { at: number, hold: number, text: string, color: string, size: number? }
-- offset/color: where (anchor space) and what colour a "fireworks" burst is.
export type Cue = {
	at: number,
	kind: string,
	key: string?,
	power: number?,
	hold: number?,
	offset: Vector3?,
	color: string?,
}
export type Scene = {
	id: string,
	seconds: number,
	audience: "all" | "self",
	keys: { Key },
	pops: { Pop },
	cues: { Cue },
	tint: { color: string, pulse: number }?,
}
export type Frames = { anchor: CFrame, follow: CFrame?, self: CFrame? }

-- Pop colours, matched to the storyboard (gold, Krampus red, snow, mint).
Cutscenes.Colors = {
	gold = Color3.fromRGB(255, 200, 61),
	red = Color3.fromRGB(255, 77, 94),
	snow = Color3.fromRGB(244, 247, 255),
	mint = Color3.fromRGB(62, 230, 176),
}

local function at(space: Space, x: number, y: number, z: number): Point
	return { space = space, offset = Vector3.new(x, y, z) }
end

-- Models face -Z (sleigh, Krampus), so "in front" is a negative z offset.
local SCENES: { [string]: Scene } = {
	-- Lobby to Stop 1. Plays during the first sleigh flight, so it costs no time.
	Takeoff = {
		id = "Takeoff",
		seconds = 5,
		audience = "all",
		-- Rides along with a normal sleigh take-off (SleighFlight): low behind
		-- the team for the ground run, alongside for the lift-off, high behind
		-- for the town and the route, then the other side for the touch-down.
		keys = {
			{ at = 0, eye = at("follow", 6, 5, 20), look = at("follow", 0, 3, -10) },
			{ at = 1.3, eye = at("follow", 22, 6, 6), look = at("follow", 0, 4, -6), fov = 65 },
			{ at = 2.6, eye = at("follow", 10, 30, 55), look = at("follow", 0, -10, -60), fov = 60 },
			{ at = 3.8, eye = at("follow", -24, 10, -4), look = at("follow", 0, 2, -8) },
			{ at = 5, eye = at("follow", -16, 6, 14), look = at("follow", 0, 2, 0) },
		},
		pops = {
			{ at = 0.2, hold = 1, text = "GIDDY-UP!", color = "snow" },
			{ at = 2.6, hold = 1.2, text = "{map}", color = "gold", size = 0.8 },
			{ at = 4.6, hold = 0.4, text = "THUMP!", color = "snow" },
		},
		cues = {
			{ at = 0, kind = "sfx", key = "CutsceneMusicTakeoff" },
			{ at = 0.2, kind = "sfx", key = "CutsceneGiddyup" },
			{ at = 2.4, kind = "marks", hold = 0.9 }, -- gone before the camera drops low
			{ at = 4.6, kind = "shake", power = 0.6, hold = 0.3 },
			{ at = 4.6, kind = "sfx", key = "CutsceneThump" },
		},
	},

	-- The first time Krampus hunts (the Lair at launch). He is frozen until the
	-- scene ends, plus Config.Cutscenes.KrampusGrace, whether or not anyone skips.
	KrampusArrives = {
		id = "KrampusArrives",
		seconds = 4,
		audience = "all",
		keys = {
			{ at = 0, eye = at("self", 0, 5, 11), look = at("self", 0, 3, 0) },
			{ at = 1.1, eye = at("self", 0, 5, 11), look = at("follow", 0, 9, 0), fov = 60 },
			{ at = 1.3, eye = at("follow", 0, 10, -28), look = at("follow", 0, 8, 0) },
			{ at = 2.2, eye = at("follow", 2, 11, -20), look = at("follow", 0, 10, 0) },
			{ at = 2.8, eye = at("follow", 0, 10, -14), look = at("follow", 0, 10, 0), fov = 50 },
			{ at = 4, eye = at("follow", 0, 10, -13), look = at("follow", 0, 10, 0), fov = 50 },
		},
		pops = {
			{ at = 0.15, hold = 1, text = "jingle... JINGLE...", color = "gold", size = 0.7 },
			{ at = 2.2, hold = 0.5, text = "CLONK!", color = "snow" },
			{ at = 2.8, hold = 0.3, text = "ROAR!", color = "red" },
			{ at = 3.1, hold = 0.9, text = "KRAMPUS IS COMING!", color = "red" },
		},
		cues = {
			{ at = 0, kind = "sfx", key = "CutsceneMusicKrampus" },
			{ at = 0, kind = "sfx", key = "CutsceneBells" },
			{ at = 2.2, kind = "shake", power = 0.5, hold = 0.25 },
			{ at = 2.2, kind = "sfx", key = "CutsceneClonk" },
			{ at = 2.8, kind = "shake", power = 1.4, hold = 0.6 },
			{ at = 2.8, kind = "sfx", key = "CutsceneRoar" },
			{ at = 2.85, kind = "hatsOff" },
		},
		tint = { color = "red", pulse = 3 },
	},

	-- Escaping the finale on the last sleigh.
	Getaway = {
		id = "Getaway",
		seconds = 5,
		audience = "all",
		-- Josh, 4 Nov: more work, fireworks. The overloaded sleigh scrapes along
		-- the snow, Krampus leaps and belly-flops, then it heaves up into the
		-- sky as fireworks go off over the Lair.
		keys = {
			{ at = 0, eye = at("follow", 16, 4, 10), look = at("follow", 0, 3, -4) },
			{ at = 1.3, eye = at("follow", 18, 5, 4), look = at("follow", 0, 3, -6), fov = 65 },
			{ at = 1.35, cut = true, eye = at("anchor", 30, 9, 22), look = at("anchor", 0, 4, 0), fov = 70 },
			{ at = 2.4, eye = at("anchor", 26, 8, 26), look = at("anchor", 0, 4, 0), fov = 70 },
			{ at = 2.45, cut = true, eye = at("anchor", 0, 3, 40), look = at("follow", 0, 0, 0), fov = 60 },
			{ at = 5, eye = at("anchor", 0, 3, 44), look = at("follow", 0, 0, 0), fov = 50 },
		},
		pops = {
			{ at = 0.2, hold = 0.9, text = "hnnngh!", color = "snow", size = 0.7 },
			{ at = 2.2, hold = 0.5, text = "FLUMP!", color = "snow" },
			{ at = 3.3, hold = 1.6, text = "LOOT x2", color = "gold", size = 1.2 },
		},
		cues = {
			{ at = 0, kind = "sfx", key = "CutsceneMusicGetaway" },
			{ at = 0.2, kind = "sfx", key = "CutsceneStrain" },
			{ at = 0.3, kind = "shake", power = 0.2, hold = 1 },
			{ at = 2.2, kind = "shake", power = 1, hold = 0.4 },
			{ at = 2.2, kind = "sfx", key = "CutsceneFlump" },
			{ at = 2.6, kind = "sfx", key = "CutsceneFireworks" },
			{ at = 2.6, kind = "fireworks", offset = Vector3.new(-26, 36, -50), color = "gold" },
			{ at = 3.0, kind = "fireworks", offset = Vector3.new(22, 44, -65), color = "red" },
			{ at = 3.3, kind = "sfx", key = "CutsceneStamp" },
			{ at = 3.3, kind = "fireworks", offset = Vector3.new(0, 52, -80), color = "mint" },
			{ at = 3.7, kind = "fireworks", offset = Vector3.new(-30, 48, -75), color = "snow" },
			{ at = 4.1, kind = "fireworks", offset = Vector3.new(28, 40, -55), color = "gold" },
		},
	},

	-- Krampus catches you. Only your camera; your friends keep playing.
	Snatched = {
		id = "Snatched",
		seconds = 2,
		audience = "self",
		keys = {
			{ at = 0, eye = at("follow", -10, 9, -14), look = at("follow", 0, 8, 0) },
			{ at = 0.8, eye = at("follow", 12, 12, -10), look = at("follow", 0, 9, 2) }, -- swings round his front, never through him
			{ at = 1.4, eye = at("follow", 0, 17, 15), look = at("follow", 0, 8, 0) },
			{ at = 2, eye = at("follow", 0, 18, 16), look = at("follow", 0, 8, 0) },
		},
		pops = {
			{ at = 0.1, hold = 0.6, text = "YOINK!", color = "gold" },
			{ at = 0.8, hold = 0.5, text = "BONK", color = "snow" },
			{ at = 1.4, hold = 0.6, text = "RING BELLS TO FREE ME!", color = "gold", size = 0.7 },
		},
		cues = {
			{ at = 0, kind = "sfx", key = "CutsceneMusicSnatched" },
			{ at = 0.1, kind = "sfx", key = "CutsceneYoink" },
			{ at = 0.8, kind = "shake", power = 0.6, hold = 0.25 },
			{ at = 0.8, kind = "sfx", key = "CutsceneBonk" },
		},
		tint = { color = "red", pulse = 0 },
	},

	-- You missed the horn. Only you see it, then you walk on.
	LeftBehind = {
		id = "LeftBehind",
		seconds = 2,
		audience = "self",
		-- Josh, 4 Nov: more work. Three quick shots: you shrinking from the back
		-- of the departing sleigh, the lead reindeer's raspberry, then your face
		-- as the sleigh's snow spray and a dropped present land on you.
		keys = {
			{ at = 0, eye = at("follow", 0, 7, 16), look = at("self", 0, 3, 0) },
			{ at = 0.75, eye = at("follow", 0, 8, 18), look = at("self", 0, 3, 0) },
			{
				at = 0.76,
				cut = true,
				eye = at("follow", 6, 6, -24),
				look = at("follow", 0, 5, -12),
				fov = 55,
			},
			{ at = 1.25, eye = at("follow", 5, 6, -22), look = at("follow", 0, 5, -12), fov = 55 },
			{ at = 1.26, cut = true, eye = at("self", 0, 4.5, -9), look = at("self", 0, 3, 0), fov = 65 },
			{ at = 2, eye = at("self", 0, 4.5, -10), look = at("self", 0, 3, 0), fov = 65 },
		},
		pops = {
			{ at = 0.05, hold = 0.65, text = "HONK HONK", color = "gold" },
			{ at = 0.8, hold = 0.45, text = "PFFFBT!", color = "snow" },
			{ at = 1.45, hold = 0.25, text = "BONK!", color = "snow" },
			{ at = 1.7, hold = 0.3, text = "Follow the path!", color = "mint", size = 0.7 },
		},
		cues = {
			{ at = 0, kind = "sfx", key = "CutsceneMusicLeftBehind" },
			{ at = 0.05, kind = "sfx", key = "CutsceneHonk" },
			{ at = 0.8, kind = "sfx", key = "CutsceneRaspberry" },
			{ at = 1.05, kind = "drop" },
			{ at = 1.26, kind = "snowPuff" },
			{ at = 1.45, kind = "sfx", key = "CutsceneBonk" },
			{ at = 1.45, kind = "shake", power = 0.4, hold = 0.2 },
		},
	},
}

Cutscenes.Order = { "KrampusArrives", "Getaway", "Takeoff", "Snatched", "LeftBehind" }

function Cutscenes.get(id: string): Scene?
	return SCENES[id]
end

-- Smoothstep: gentle in, gentle out, so cuts read as camera moves.
function Cutscenes.ease(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- The two keys around time t and how far between them we are (eased).
function Cutscenes.keyPair(scene: Scene, t: number): (Key, Key, number)
	local keys = scene.keys
	if t <= keys[1].at then
		return keys[1], keys[1], 0
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t < b.at then
			if b.cut then
				return a, a, 0 -- hold until the cut
			end
			local span = b.at - a.at
			return a, b, if span > 0 then Cutscenes.ease((t - a.at) / span) else 1
		end
	end
	local last = keys[#keys]
	return last, last, 1
end

-- A keyframe point in world space. Missing frames fall back to the anchor, so
-- a scene never breaks if the followed model is gone or the Santa respawned.
function Cutscenes.resolve(point: Point, frames: Frames): Vector3
	local frame = frames[point.space] or frames.anchor
	return frame:PointToWorldSpace(point.offset)
end

-- Camera position, look-at point and field of view at time t.
function Cutscenes.camera(scene: Scene, t: number, frames: Frames): (Vector3, Vector3, number)
	local a, b, alpha = Cutscenes.keyPair(scene, t)
	local eye = Cutscenes.resolve(a.eye, frames):Lerp(Cutscenes.resolve(b.eye, frames), alpha)
	local look = Cutscenes.resolve(a.look, frames):Lerp(Cutscenes.resolve(b.look, frames), alpha)
	local fovA, fovB = a.fov or 70, b.fov or 70
	return eye, look, fovA + (fovB - fovA) * alpha
end

-- The text pop showing at time t (the latest one that started), if any.
function Cutscenes.popAt(scene: Scene, t: number): Pop?
	local showing = nil
	for _, pop in scene.pops do
		if t >= pop.at and t < pop.at + pop.hold then
			showing = pop
		end
	end
	return showing
end

-- Cues whose time falls in (from, to]. Called once a frame with the previous
-- and current time, so each cue fires exactly once even on a slow frame.
function Cutscenes.cuesBetween(scene: Scene, from: number, to: number): { Cue }
	local fired = {}
	for _, cue in scene.cues do
		if cue.at > from and cue.at <= to then
			table.insert(fired, cue)
		end
	end
	return fired
end

-- Checks the rules every scene must follow. Returns nil when fine, else why not.
function Cutscenes.problem(scene: Scene, maxSeconds: number): string?
	if scene.seconds <= 0 or scene.seconds > maxSeconds then
		return scene.id .. " is " .. scene.seconds .. " s (max " .. maxSeconds .. ")"
	end
	if scene.keys[1].at ~= 0 then
		return scene.id .. " has no camera key at 0"
	end
	if scene.keys[#scene.keys].at ~= scene.seconds then
		return scene.id .. " camera keys stop before the end"
	end
	for i = 2, #scene.keys do
		if scene.keys[i].at < scene.keys[i - 1].at then
			return scene.id .. " camera keys are out of order"
		end
	end
	for _, pop in scene.pops do
		if pop.at < 0 or pop.at + pop.hold > scene.seconds + 1e-6 then
			return scene.id .. " pop '" .. pop.text .. "' runs past the end"
		end
		if not Cutscenes.Colors[pop.color] then
			return scene.id .. " pop '" .. pop.text .. "' has unknown colour " .. pop.color
		end
	end
	for _, cue in scene.cues do
		if cue.at < 0 or cue.at > scene.seconds then
			return scene.id .. " has a " .. cue.kind .. " cue outside the scene"
		end
		if cue.color and not Cutscenes.Colors[cue.color] then
			return scene.id .. " has a " .. cue.kind .. " cue with unknown colour " .. cue.color
		end
		if cue.kind == "fireworks" and not cue.offset then
			return scene.id .. " has a fireworks cue with nowhere to burst"
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- Server-side choreography (pure, so it is tested without the engine)
----------------------------------------------------------------------------

-- Krampus tiptoes in from behind his spawn, clonks his horns, then roars.
-- Returns his pivot relative to his spawn at time t of KrampusArrives.
local TIPTOE_FROM, TIPTOE_UNTIL, CLONK_AT, ROAR_AT = 1.1, 2.2, 2.2, 2.8
function Cutscenes.krampusIntro(t: number): CFrame
	if t < TIPTOE_FROM then
		return CFrame.new(0, 0, 16) -- out of sight, behind the gate
	end
	if t < TIPTOE_UNTIL then
		local a = (t - TIPTOE_FROM) / (TIPTOE_UNTIL - TIPTOE_FROM)
		local bob = math.abs(math.sin(a * math.pi * 4)) * 1.2 -- big careful steps
		return CFrame.new(0, bob, 16 * (1 - a))
	end
	if t < ROAR_AT then
		local a = (t - CLONK_AT) / (ROAR_AT - CLONK_AT)
		return CFrame.Angles(math.rad(-14) * math.sin(a * math.pi), 0, 0) -- reels back from the clonk
	end
	local a = math.clamp((t - ROAR_AT) / 0.4, 0, 1)
	return CFrame.Angles(math.rad(8) * math.sin(a * math.pi), 0, 0) -- leans into the roar
end

-- The overloaded sleigh scrapes along the snow until Krampus has flopped,
-- then heaves up and away, nose up. Returns the deck relative to where it
-- landed (models face -Z).
local LIFT = 2.3
local MAX_CLIMB_PITCH = math.rad(18)
function Cutscenes.getawaySleigh(t: number): CFrame
	if t < LIFT then
		local a = t / LIFT
		local hop = math.abs(math.sin(t * 9)) * 0.3 -- runners juddering under the weight
		return CFrame.new(0, hop, -10 * a * a) * CFrame.Angles(0, 0, math.sin(t * 30) * 0.05)
	end
	local a = math.clamp((t - LIFT) / 2.7, 0, 1)
	local y, z = 75 * a ^ 1.7, -10 - 150 * a ^ 1.4
	local pitch = 0
	if a > 0 then
		local dy, dz = 127.5 * a ^ 0.7, 210 * a ^ 0.4 + 20 / 2.7 -- per unit a, includes the creep speed
		pitch = math.min(math.atan2(dy, dz), MAX_CLIMB_PITCH)
	end
	return CFrame.new(0, y, z) * CFrame.Angles(pitch, 0, 0)
end

-- Krampus leaps for the runners and belly-flops into the snow just short of
-- the deck. Returns his pivot at time t, from `start` towards `deck`.
local LEAP_FROM, LEAP_UNTIL, FLOP_UNTIL = 1.4, 2.2, 2.7
function Cutscenes.krampusFlop(t: number, start: CFrame, deck: Vector3): CFrame
	local flat = Vector3.new(deck.X, start.Position.Y, deck.Z)
	local toward = flat - start.Position
	local landing = if toward.Magnitude > 8 then flat - toward.Unit * 8 else start.Position
	local face = if toward.Magnitude > 0.1 then CFrame.lookAt(start.Position, flat) else start
	if t < LEAP_FROM then
		return face
	end
	local a = math.clamp((t - LEAP_FROM) / (LEAP_UNTIL - LEAP_FROM), 0, 1)
	local pos = start.Position:Lerp(landing, a) + Vector3.yAxis * math.sin(a * math.pi) * 10
	local pivot = face.Rotation + pos
	if t < LEAP_UNTIL then
		return pivot * CFrame.Angles(math.rad(-30) * a, 0, 0)
	end
	local b = math.clamp((t - LEAP_UNTIL) / (FLOP_UNTIL - LEAP_UNTIL), 0, 1)
	return pivot * CFrame.Angles(math.rad(-30 - 60 * b), 0, 0) -- face down in the snow
end

return Cutscenes
