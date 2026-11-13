--[[
	Stop gate: only the stop the sleigh is parked at can be robbed (Josh,
	13 Nov 2026: running ahead on foot let you loot later stops, the Naughty
	List included, before the sleigh got there).

	Two layers, both server-side:
	  1. Locks: Run asks canUse() before every grab, buy, hide and search.
	     This is the one that matters; a barrier alone can be skated past.
	  2. Ward: a Santa inside a street the sleigh hasn't reached is bounced
	     back towards the path (and put back on it if they're deep inside).

	Pure rules (CFrame maths only, no Instances), so unit tests run outside
	Roblox. Numbers in Config.StopGate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local StopGate = {}

-- The phases while the sleigh is parked at a stop (Run's NOISY_PHASES).
local LIVE_PHASES = { Sneak = true, LightsOn = true, Horn = true }

function StopGate.parked(phase: string): boolean
	return LIVE_PHASES[phase] == true
end

-- Stop `index` can be robbed only while the sleigh is parked there.
function StopGate.stopLive(index: number, current: number, phase: string): boolean
	if not Config.StopGate.Enabled then
		return true
	end
	return index == current and StopGate.parked(phase)
end

-- The on-foot gap `gap` runs from stop gap to stop gap+1. It opens once the
-- sleigh has reached stop gap (so Santas who missed it can loot on the way)
-- and stays open after.
function StopGate.gapLive(gap: number, current: number): boolean
	if not Config.StopGate.Enabled then
		return true
	end
	return current >= 1 and gap <= current
end

-- Whether a present can be grabbed: by the stop or gap it belongs to.
-- Untagged presents (a dog's knocked-out regrab) only need the sleigh parked.
function StopGate.presentLive(present: any, current: number, phase: string): boolean
	if present.stopIndex then
		return StopGate.stopLive(present.stopIndex, current, phase)
	elseif present.footGap then
		return StopGate.gapLive(present.footGap, current)
	end
	return not Config.StopGate.Enabled or StopGate.parked(phase)
end

-- Streets the sleigh hasn't reached are warded while it's parked somewhere.
-- (In flight it's heading for the next one, and riders pass through it.)
function StopGate.warded(index: number, current: number, phase: string): boolean
	return Config.StopGate.Enabled and StopGate.parked(phase) and index > current
end

-- The ward in stop space: x within HalfWidth, z from just past the path to
-- Length further down. Returns the box's local bounds.
local function bounds(footPathZ: number): (number, number, number)
	local G = Config.StopGate
	local start = footPathZ + G.PathClearance
	return G.HalfWidth, start, start + G.Length
end

-- How deep `position` is inside stop space `origin`'s ward (studs to its
-- nearest edge), or nil outside. footPathZ: the map's FootPathZ.
function StopGate.depth(origin: CFrame, footPathZ: number, position: Vector3): number?
	local half, z0, z1 = bounds(footPathZ)
	local p = origin:PointToObjectSpace(position)
	if math.abs(p.X) > half or p.Z < z0 or p.Z > z1 then
		return nil
	end
	return math.min(half - math.abs(p.X), p.Z - z0, z1 - p.Z)
end

-- The push out of a ward: straight out of its nearest edge, with a hop. From
-- the street that's back to the path; from the back lane (Frozen Canal's
-- loop behind every street) it's back along the lane, never through the street.
function StopGate.pushVelocity(origin: CFrame, footPathZ: number, position: Vector3): Vector3
	local half, z0, z1 = bounds(footPathZ)
	local p = origin:PointToObjectSpace(position)
	local out = Vector3.new(0, 0, -1)
	local best = p.Z - z0
	if half - math.abs(p.X) < best then
		best = half - math.abs(p.X)
		out = Vector3.new(if p.X < 0 then -1 else 1, 0, 0)
	end
	if z1 - p.Z < best then
		out = Vector3.new(0, 0, 1)
	end
	local world = origin:VectorToWorldSpace(out)
	return Vector3.new(world.X, 0, world.Z).Unit * Config.StopGate.PushSpeed
		+ Vector3.new(0, Config.Knockback.Lift, 0)
end

-- Where a Santa deep inside a ward is put back: on the path, level with them.
function StopGate.safeSpot(origin: CFrame, footPathZ: number, position: Vector3): Vector3
	local p = origin:PointToObjectSpace(position)
	return (origin * CFrame.new(p.X, 3, footPathZ)).Position
end

-- Tags every built present with the stop (stopIndex) or on-foot gap
-- (footGap) it belongs to. gapSizes[i]: how many presents gap i holds,
-- in the order MapBuilder.buildRoute appended them to onFootPresents.
function StopGate.tag(route: any, gapSizes: { number })
	for i, stop in route.stops do
		for _, present in stop.presents do
			present.stopIndex = i
		end
	end
	local n = 0
	for gap, size in gapSizes do
		for _ = 1, size do
			n += 1
			local present = route.onFootPresents[n]
			if present then
				present.footGap = gap
			end
		end
	end
end

-- The banner for a Santa who tries something at a locked stop.
function StopGate.lockedText(index: number, current: number): string
	if index > current then
		return "Too early! That street's still asleep. Wait for the sleigh!"
	end
	return "The sleigh's left this street. Follow the path to the next stop!"
end

return StopGate
