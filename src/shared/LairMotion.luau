--[[
	How Krampus's Lair (the Cuckoo Clock Den, LairBuilder) moves, as pure
	functions of time so they can be unit tested. LairAnimator.client applies
	them on each player's machine; nothing here touches Instances.

	The server stamps two attributes on the Lair model (server clock, Util.now):
	  CuckooAt  the sleigh horn: the cuckoo doors fly open, a little Krampus
	            pops out on his spring, and every bell shakes. The Cuckoo
	            Watch (server/CuckooWatch) stamps it too, with CuckooHold set
	            to its short look
	  BellsAt   Krampus wakes up: the seven bells light up one by one and ring
]]

local LairMotion = {}

LairMotion.BellDrop = 2.6 -- studs from a bell's centre up to where its strap hangs
LairMotion.CuckooOpenSeconds = 0.4
LairMotion.CuckooHoldSeconds = 4
LairMotion.BellsLightGap = 0.35 -- seconds between bells lighting up
LairMotion.BellsRingSeconds = 6
LairMotion.Range = 220 -- studs from the camera; further away nothing moves

local TAU = 2 * math.pi

-- Clock hands (radians, clockwise from 12), ticking once a second. The minute
-- hand goes round once a minute so players see it move during a stop.
function LairMotion.hands(t: number): (number, number)
	local tick = math.floor(t)
	local minute = (tick % 60) / 60 * TAU
	local hour = (tick % 720) / 720 * TAU
	return hour, minute
end

-- Gear i turns slowly, small gears faster, neighbours in opposite directions.
function LairMotion.gear(t: number, i: number, radius: number): number
	local direction = if i % 2 == 0 then -1 else 1
	return direction * t * 0.5 / radius
end

-- 0 shut .. 1 wide open, `since` seconds after the horn (nil = never).
-- hold: seconds it stays wide open (default CuckooHoldSeconds); the Cuckoo
-- Watch stamps a short one (CuckooHold) so it shuts when the look ends.
function LairMotion.cuckoo(since: number?, hold: number?): number
	if not since or since < 0 then
		return 0
	end
	local o, h = LairMotion.CuckooOpenSeconds, hold or LairMotion.CuckooHoldSeconds
	if since < o then
		return since / o
	elseif since < o + h then
		return 1
	end
	return math.max(0, 1 - (since - o - h) / o)
end

-- How far the little Krampus is out of his house (0..1), from the doors' opening.
function LairMotion.pop(open: number): number
	return math.clamp((open - 0.4) / 0.6, 0, 1)
end

-- Bell i's swing (radians) and whether it glows.
function LairMotion.bell(
	t: number,
	i: number,
	sinceCuckoo: number?,
	sinceBells: number?,
	cuckooHold: number?
): (number, boolean)
	local swing = math.sin(t * 1.5 + i) * 0.05
	local open = LairMotion.cuckoo(sinceCuckoo, cuckooHold)
	if open > 0 then
		swing = open * math.sin(t * 10 + i) * 0.35
	end
	local lit = false
	if sinceBells and sinceBells >= 0 and sinceBells < LairMotion.BellsRingSeconds then
		lit = sinceBells >= (i - 1) * LairMotion.BellsLightGap
		if lit then
			swing = math.sin(t * 12 + i) * 0.3
		end
	end
	return swing, lit
end

-- Glowing eyes in the corners blink now and then (true = open).
function LairMotion.eyesOpen(t: number, i: number): boolean
	local c = (t * 0.6 + i * 0.37) % 1
	return not (c > 0.9 and c < 0.97)
end

return LairMotion
