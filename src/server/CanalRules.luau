--[[
	Pure rules for Frozen Canal Town (no Instances, so they run in unit tests):
	skating speed, how canal ice is split into Thin Ice segments, the floe
	layout when ice breaks, the nearest floe after a splash, and where the
	moving hazards (security dogs, the rink's ice polisher) are at a time.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local CanalRules = {}

-- WalkSpeed for a Santa: a hoop boost beats skating, skating beats walking,
-- and nothing ever slows a Santa below their own speed (Peppermint Rush).
function CanalRules.walkSpeed(base: number, onIce: boolean, boosted: boolean): number
	local C = Config.Canal
	if boosted then
		return math.max(base, C.HoopSpeed)
	elseif onIce then
		return math.max(base, C.SkateSpeed)
	end
	return base
end

export type Segment = { from: number, to: number, crack: boolean }

-- Splits canal ice running from `from` to `to` (studs along the canal) into
-- pieces of about SegmentLength. Pieces within StopEndClear of either end
-- (the stops) are their own short pieces and never CrackZone.
function CanalRules.segments(from: number, to: number): { Segment }
	local C = Config.Canal
	local list = {}
	local length = to - from
	local clear = math.min(C.StopEndClear, length / 2)
	table.insert(list, { from = from, to = from + clear, crack = false })
	local middle = length - 2 * clear
	if middle > 0 then
		local count = math.max(1, math.floor(middle / C.SegmentLength + 0.5))
		local step = middle / count
		for i = 1, count do
			local a = from + clear + (i - 1) * step
			table.insert(list, { from = a, to = a + step, crack = true })
		end
	end
	table.insert(list, { from = to - clear, to = to, crack = false })
	return list
end

export type Floe = { x: number, z: number, sizeX: number, sizeZ: number }
export type Keepout = { x: number, z: number, radius: number?, halfX: number?, halfZ: number? }

local function blocked(x: number, z: number, reach: number, keepouts: { Keepout }): boolean
	for _, k in keepouts do
		if k.radius then
			local dx, dz = x - k.x, z - k.z
			if dx * dx + dz * dz < (k.radius + reach) ^ 2 then
				return true
			end
		elseif math.abs(x - k.x) < (k.halfX or 0) + reach and math.abs(z - k.z) < (k.halfZ or 0) + reach then
			return true
		end
	end
	return false
end

-- Floes covering a sheet of ice sizeX by sizeZ (centred on 0, 0), on a
-- jittered grid with gaps a Santa can hop, leaving keepouts (an island, a
-- bridge) clear. Positions are relative to the sheet's centre.
function CanalRules.floeLayout(sizeX: number, sizeZ: number, rng: Random, keepouts: { Keepout }?): { Floe }
	local cell = Config.Canal.FloeCell
	local floes = {}
	local nx = math.max(1, math.floor(sizeX / cell))
	local nz = math.max(1, math.floor(sizeZ / cell))
	local pitchX, pitchZ = sizeX / nx, sizeZ / nz
	for i = 1, nx do
		for j = 1, nz do
			local sx = pitchX - rng:NextNumber(3, 4)
			local sz = pitchZ - rng:NextNumber(3, 4)
			local x = -sizeX / 2 + (i - 0.5) * pitchX + rng:NextNumber(-0.5, 0.5)
			local z = -sizeZ / 2 + (j - 0.5) * pitchZ + rng:NextNumber(-0.5, 0.5)
			if not blocked(x, z, math.max(sx, sz) / 2, keepouts or {}) then
				table.insert(floes, { x = x, z = z, sizeX = sx, sizeZ = sz })
			end
		end
	end
	return floes
end

-- The index of the floe (world positions) nearest to `position`, or nil.
function CanalRules.nearest(points: { Vector3 }, position: Vector3): number?
	local best, bestDistance = nil, math.huge
	for i, p in points do
		local d = ((p - position) * Vector3.new(1, 0, 1)).Magnitude
		if d < bestDistance then
			best, bestDistance = i, d
		end
	end
	return best
end

-- Where a patrolling dog is `t` seconds in: back and forth along the points.
function CanalRules.patrolAt(points: { Vector3 }, speed: number, t: number): (Vector3, Vector3)
	if #points < 2 then
		return points[1], Vector3.zAxis
	end
	local lengths, total = {}, 0
	for i = 1, #points - 1 do
		lengths[i] = (points[i + 1] - points[i]).Magnitude
		total += lengths[i]
	end
	local d = (t * speed) % (2 * total)
	local backwards = d > total
	if backwards then
		d = 2 * total - d
	end
	for i = 1, #points - 1 do
		if d <= lengths[i] or i == #points - 1 then
			local a, b = points[i], points[i + 1]
			local along = math.clamp(d / math.max(lengths[i], 1e-3), 0, 1)
			local facing = (b - a).Unit
			return a:Lerp(b, along), if backwards then -facing else facing
		end
		d -= lengths[i]
	end
	error("unreachable: the last segment always returns")
end

-- The rink polisher circles the rink centre.
function CanalRules.polisherAt(centre: Vector3, radius: number, t: number): (Vector3, Vector3)
	local a = t * Config.Canal.Polisher.AngularSpeed
	local p = centre + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
	local facing = Vector3.new(-math.sin(a), 0, math.cos(a))
	return p, facing
end

return CanalRules
