--[[
	How the sleigh flies between two decks, like a real sleigh takes off
	(Josh, 4 Nov 2026: the straight up-and-down arc looked unnatural).

	1. Ground run: the reindeer pull it along the snow, speeding up.
	2. Lift-off and climb, nose up.
	3. Cruise, banking into any turn.
	4. Glide down, nose down, touch down on the runners and slide to a stop.

	The ground track is a smooth curve that leaves along the start deck's
	facing and arrives along the end deck's facing (models face -Z). Pure
	maths, so Run.luau and the tests share it.
]]

local SleighFlight = {}

-- Fractions of the route (by distance along the curve).
SleighFlight.LiftOffAt = 0.2 -- end of the ground run
SleighFlight.CruiseAt = 0.45 -- top of the climb
SleighFlight.DescendAt = 0.68 -- start of the glide down
SleighFlight.TouchDownAt = 0.985 -- runners back on the snow
SleighFlight.MaxBank = math.rad(25)
SleighFlight.MaxPitch = math.rad(20) -- a gentle nose-up/down, even on a steep climb

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- Progress along the route at time fraction u: slow start, slow finish.
function SleighFlight.progress(u: number): number
	u = math.clamp(u, 0, 1)
	return (1 - math.cos(u * math.pi)) / 2
end

-- Height above the route at progress s (0 on the ground).
function SleighFlight.height(s: number, peak: number): number
	if s <= SleighFlight.LiftOffAt or s >= SleighFlight.TouchDownAt then
		return 0
	end
	if s < SleighFlight.CruiseAt then
		return peak * smooth((s - SleighFlight.LiftOffAt) / (SleighFlight.CruiseAt - SleighFlight.LiftOffAt))
	end
	if s < SleighFlight.DescendAt then
		return peak
	end
	return peak
		* (1 - smooth((s - SleighFlight.DescendAt) / (SleighFlight.TouchDownAt - SleighFlight.DescendAt)))
end

-- Ground track: a cubic Bezier from `from` to `to`, leaving and arriving
-- along each deck's forward (-Z) direction.
local function controls(from: CFrame, to: CFrame): (Vector3, Vector3, Vector3, Vector3)
	local p0, p3 = from.Position, to.Position
	local reach = math.max((p3 - p0).Magnitude / 3, 1)
	local f0 = Vector3.new(from.LookVector.X, 0, from.LookVector.Z)
	local f1 = Vector3.new(to.LookVector.X, 0, to.LookVector.Z)
	f0 = if f0.Magnitude > 1e-3 then f0.Unit else Vector3.new(0, 0, -1)
	f1 = if f1.Magnitude > 1e-3 then f1.Unit else Vector3.new(0, 0, -1)
	return p0, p0 + f0 * reach, p3 - f1 * reach, p3
end

local function bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, s: number): (Vector3, Vector3)
	local m = 1 - s
	local point = p0 * (m * m * m) + p1 * (3 * m * m * s) + p2 * (3 * m * s * s) + p3 * (s * s * s)
	local tangent = (p1 - p0) * (3 * m * m) + (p2 - p1) * (6 * m * s) + (p3 - p2) * (3 * s * s)
	return point, tangent
end

-- Heading (radians, around Y) of a flat direction, for bank angles.
local function heading(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- The deck at time t of a flight lasting `seconds`, cruising `peak` studs up.
function SleighFlight.deckAt(from: CFrame, to: CFrame, t: number, seconds: number, peak: number): CFrame
	if t <= 0 then
		return from
	end
	if t >= seconds then
		return to
	end
	local p0, p1, p2, p3 = controls(from, to)
	local s = SleighFlight.progress(t / seconds)
	local ground, tangent = bezier(p0, p1, p2, p3, s)
	local y = p0.Y + (p3.Y - p0.Y) * s + SleighFlight.height(s, peak)

	-- Nose follows the climb and glide: rise over run along the curve.
	local ds = 0.01
	local rise = SleighFlight.height(math.min(s + ds, 1), peak)
		- SleighFlight.height(math.max(s - ds, 0), peak)
	local flat = Vector3.new(tangent.X, 0, tangent.Z)
	if flat.Magnitude < 1e-4 then
		flat = Vector3.new(from.LookVector.X, 0, from.LookVector.Z)
	end
	local run = flat.Magnitude * (math.min(s + ds, 1) - math.max(s - ds, 0))
	local pitch =
		math.clamp(math.atan2(rise, math.max(run, 1e-3)), -SleighFlight.MaxPitch, SleighFlight.MaxPitch)

	-- Bank into turns, only while airborne.
	local _, ahead = bezier(p0, p1, p2, p3, math.min(s + ds, 1))
	local _, behind = bezier(p0, p1, p2, p3, math.max(s - ds, 0))
	local turn = wrapAngle(heading(ahead) - heading(behind))
	local airborne = math.clamp(SleighFlight.height(s, peak) / math.max(peak * 0.3, 1e-3), 0, 1)
	local bank = math.clamp(turn * 4, -SleighFlight.MaxBank, SleighFlight.MaxBank) * airborne

	local position = Vector3.new(ground.X, y, ground.Z)
	return CFrame.lookAt(position, position + flat.Unit) * CFrame.Angles(pitch, 0, bank)
end

return SleighFlight
