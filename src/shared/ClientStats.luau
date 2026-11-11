--[[
	How smooth the game runs on each player's device: frame rate, hitches and
	freezes, above all during cutscenes (Josh, 11 Nov 2026: "the cutscenes are
	glitchy, especially Krampus. Causes game freezes"). Pure so it runs in
	tests: client/ClientStats.client.luau measures and sends a report, and
	server/Analytics.luau checks it (clients can send anything) and logs it.

	Reports (ClientStats remote, client -> server):
	  { kind = "Hello", device, load }     once: device type, seconds to load in
	  { kind = "Cutscene", id, ... }       when a cutscene ends (or is skipped)
	  { kind = "Perf", ... }               every ReportSeconds outside cutscenes
	Cutscene and Perf carry a segment summary: seconds, fps, worstMs,
	hitches (frames over HitchSeconds), freezes (frames over FreezeSeconds).
]]

local ClientStats = {}

ClientStats.ReportSeconds = 60
ClientStats.HitchSeconds = 0.25 -- a frame this long is a visible stutter
ClientStats.FreezeSeconds = 1 -- a frame this long is a freeze
ClientStats.Devices = { Phone = true, Tablet = true, Computer = true, Console = true, VR = true }

export type Segment = {
	seconds: number,
	frames: number,
	worst: number, -- longest frame, seconds
	hitches: number,
	freezes: number,
}

export type Summary = {
	seconds: number,
	fps: number,
	worstMs: number,
	hitches: number,
	freezes: number,
}

-- input: UserInputService (or a stand-in). viewport: the camera's ViewportSize.
function ClientStats.device(input: any, viewport: Vector2?): string
	local function has(name: string): boolean
		local ok, value = pcall(function()
			return input[name]
		end)
		return ok and value == true
	end
	if has("VREnabled") then
		return "VR"
	end
	local touch, keyboard, gamepad = has("TouchEnabled"), has("KeyboardEnabled"), has("GamepadEnabled")
	if gamepad and not touch and not keyboard then
		return "Console"
	end
	if touch and not keyboard then
		local short = if viewport then math.min(viewport.X, viewport.Y) else 0
		return if short >= 600 then "Tablet" else "Phone"
	end
	return "Computer"
end

function ClientStats.newSegment(): Segment
	return { seconds = 0, frames = 0, worst = 0, hitches = 0, freezes = 0 }
end

function ClientStats.addFrame(segment: Segment, dt: number)
	segment.seconds += dt
	segment.frames += 1
	segment.worst = math.max(segment.worst, dt)
	if dt >= ClientStats.FreezeSeconds then
		segment.freezes += 1
	elseif dt >= ClientStats.HitchSeconds then
		segment.hitches += 1
	end
end

function ClientStats.summary(segment: Segment): Summary
	return {
		seconds = math.floor(segment.seconds * 10 + 0.5) / 10,
		fps = if segment.seconds > 0 then math.floor(segment.frames / segment.seconds + 0.5) else 0,
		worstMs = math.floor(segment.worst * 1000 + 0.5),
		hitches = segment.hitches,
		freezes = segment.freezes,
	}
end

local function number(v: any, max: number): number?
	if type(v) ~= "number" or v ~= v or v < 0 or v > max then
		return nil
	end
	return v
end

-- A clean copy of a summary a client sent, or nil if it is junk.
function ClientStats.readSummary(raw: any): Summary?
	if type(raw) ~= "table" then
		return nil
	end
	local seconds = number(raw.seconds, 3600)
	local fps = number(raw.fps, 1000)
	local worstMs = number(raw.worstMs, 600000)
	local hitches = number(raw.hitches, 100000)
	local freezes = number(raw.freezes, 100000)
	if not (seconds and fps and worstMs and hitches and freezes) then
		return nil
	end
	return {
		seconds = seconds,
		fps = math.floor(fps),
		worstMs = math.floor(worstMs),
		hitches = math.floor(hitches),
		freezes = math.floor(freezes),
	}
end

return ClientStats
