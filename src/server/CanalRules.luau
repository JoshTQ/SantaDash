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

-- A floe is one big disc of ice and sometimes a smaller lobe poking out
-- toward a corner of its cell, so floes are round and lumpy, never a grid
-- of rectangles (Josh's playtest, 6 Nov 2026). x, z is the main disc's
-- centre; sizeX, sizeZ the floe's footprint.
export type Disc = { x: number, z: number, r: number }
export type Floe = { x: number, z: number, sizeX: number, sizeZ: number, discs: { Disc } }
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

-- Floes covering a sheet of ice sizeX by sizeZ (centred on 0, 0), one per
-- cell of a jittered grid, leaving keepouts (an island, a bridge) clear.
-- Each floe stays inside its cell less half a gap, so neighbours are always
-- at least Config.Canal.FloeGap[1] apart, and the biggest gap between two
-- main discs stays a hop. Positions are relative to the sheet's centre.
function CanalRules.floeLayout(sizeX: number, sizeZ: number, rng: Random, keepouts: { Keepout }?): { Floe }
	local C = Config.Canal
	local cell = C.FloeCell
	local floes = {}
	local nx = math.max(1, math.floor(sizeX / cell))
	local nz = math.max(1, math.floor(sizeZ / cell))
	local pitchX, pitchZ = sizeX / nx, sizeZ / nz
	for i = 1, nx do
		for j = 1, nz do
			local gap = rng:NextNumber(C.FloeGap[1], C.FloeGap[2])
			local jx, jz = rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.5, 0.5)
			-- half the square this floe may fill, after the gap and the jitter
			local room = math.min(pitchX, pitchZ) / 2 - gap / 2 - 0.5
			local x = -sizeX / 2 + (i - 0.5) * pitchX + jx
			local z = -sizeZ / 2 + (j - 0.5) * pitchZ + jz
			local r0 = room * rng:NextNumber(C.FloeRadius[1], C.FloeRadius[2])
			local discs = { { x = x, z = z, r = r0 } }
			local minX, maxX, minZ, maxZ = x - r0, x + r0, z - r0, z + r0
			if rng:NextNumber() < C.FloeLobeChance then
				local rl = r0 * rng:NextNumber(0.45, 0.65)
				local a = (rng:NextInteger(0, 3) + 0.5) * math.pi / 2 + rng:NextNumber(-0.35, 0.35)
				local ca, sa = math.cos(a), math.sin(a)
				-- as far toward the corner as the square allows
				local d = (room - rl) / math.max(math.abs(ca), math.abs(sa))
				local lx, lz = x + ca * d, z + sa * d
				table.insert(discs, { x = lx, z = lz, r = rl })
				minX, maxX = math.min(minX, lx - rl), math.max(maxX, lx + rl)
				minZ, maxZ = math.min(minZ, lz - rl), math.max(maxZ, lz + rl)
			end
			local reach = math.max(maxX - minX, maxZ - minZ) / 2
			if not blocked((minX + maxX) / 2, (minZ + maxZ) / 2, reach, keepouts or {}) then
				table.insert(floes, { x = x, z = z, sizeX = maxX - minX, sizeZ = maxZ - minZ, discs = discs })
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
	if total < 1e-3 then
		return points[1], Vector3.zAxis -- every point the same: stand still, no NaN
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
			local facing = if lengths[i] > 1e-3 then (b - a).Unit else Vector3.zAxis
			return a:Lerp(b, along), if backwards then -facing else facing
		end
		d -= lengths[i]
	end
	error("unreachable: the last segment always returns")
end

export type Rect = { x0: number, x1: number, z0: number, z1: number }
export type Hill = { x: number, z: number, radius: number, height: number }
export type Tree = { x: number, z: number, y: number, height: number, lit: boolean }

local function inRect(x: number, z: number, r: Rect, pad: number): boolean
	return x > r.x0 - pad and x < r.x1 + pad and z > r.z0 - pad and z < r.z1 + pad
end

-- Height of the snow at (x, z): flat ground (0) or the top of a hill. Hills
-- are spheres sunk so only a gentle cap of `height` shows.
function CanalRules.groundHeight(hills: { Hill }, x: number, z: number): number
	local y = 0
	for _, h in hills do
		local dx, dz = x - h.x, z - h.z
		local d2 = dx * dx + dz * dz
		if d2 < h.radius * h.radius then
			local sphere = (h.radius * h.radius + h.height * h.height) / (2 * h.height)
			local top = h.height - sphere + math.sqrt(sphere * sphere - d2)
			y = math.max(y, top)
		end
	end
	return y
end

-- Snowy hills and a pine forest filling `regions` (stop space), clear of the
-- `keepouts` (canals, the lake). Some trees carry Christmas lights.
function CanalRules.woodland(rng: Random, regions: { Rect }, keepouts: { Rect }): ({ Tree }, { Hill })
	local W = Config.Canal.Woodland
	local hills, trees = {}, {}
	for _, r in regions do
		local area = (r.x1 - r.x0) * (r.z1 - r.z0)
		for _ = 1, math.floor(area / W.HillArea + 0.5) do
			local radius = rng:NextNumber(W.HillRadius[1], W.HillRadius[2])
			if r.x1 - r.x0 > 2 * radius and r.z1 - r.z0 > 2 * radius then
				local x = rng:NextNumber(r.x0 + radius, r.x1 - radius)
				local z = rng:NextNumber(r.z0 + radius, r.z1 - radius)
				local clear = true
				for _, k in keepouts do
					if inRect(x, z, k, radius) then
						clear = false
					end
				end
				if clear then
					table.insert(hills, {
						x = x,
						z = z,
						radius = radius,
						height = rng:NextNumber(W.HillHeight[1], W.HillHeight[2]),
					})
				end
			end
		end
	end
	for _, r in regions do
		local x = r.x0 + W.TreeSpacing / 2
		while x < r.x1 do
			local z = r.z0 + W.TreeSpacing / 2
			while z < r.z1 do
				local tx = x + rng:NextNumber(-W.TreeSpacing / 3, W.TreeSpacing / 3)
				local tz = z + rng:NextNumber(-W.TreeSpacing / 3, W.TreeSpacing / 3)
				local clear = rng:NextNumber() < W.TreeChance and inRect(tx, tz, r, 0)
				for _, k in keepouts do
					if inRect(tx, tz, k, 6) then
						clear = false
					end
				end
				if clear then
					table.insert(trees, {
						x = tx,
						z = tz,
						y = CanalRules.groundHeight(hills, tx, tz),
						height = rng:NextNumber(W.TreeHeight[1], W.TreeHeight[2]),
						lit = rng:NextNumber() < W.LitChance,
					})
				end
				z += W.TreeSpacing
			end
			x += W.TreeSpacing
		end
	end
	return trees, hills
end

-- The rink polisher circles the rink centre.
function CanalRules.polisherAt(centre: Vector3, radius: number, t: number): (Vector3, Vector3)
	local a = t * Config.Canal.Polisher.AngularSpeed
	local p = centre + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
	local facing = Vector3.new(-math.sin(a), 0, math.cos(a))
	return p, facing
end

-- A ground hazard at `at` (dog, polisher) can only bump a Santa standing
-- near its own level: not one on a roof, a bridge or up a chimney above it.
-- Flat distance under `radius`, and the root no more than Hazards.Below under
-- or Hazards.Above over the hazard's ground point.
function CanalRules.inReach(root: Vector3, at: Vector3, radius: number): boolean
	local H = Config.Canal.Hazards
	local flat = Vector3.new(root.X - at.X, 0, root.Z - at.Z).Magnitude
	local rise = root.Y - at.Y
	return flat < radius and rise > -H.Below and rise < H.Above
end

-- radius: a round floe (a flat cylinder), measured by flat distance.
export type Box = { cframe: CFrame, size: Vector3, radius: number? }

-- Is a Santa whose root is at `root` standing in the water of a broken ice
-- zone (not on one of its floes, not mid-hop above it)? Polled by the server,
-- so walking on the water can't dodge a splash the way a held Touched could.
-- standHeight: how high their root rides over the floor (Util.standHeight).
function CanalRules.inWater(zone: Box, floes: { Box }, root: Vector3, standHeight: number): boolean
	local C = Config.Canal
	local p = zone.cframe:PointToObjectSpace(root)
	if math.abs(p.X) > zone.size.X / 2 or math.abs(p.Z) > zone.size.Z / 2 then
		return false
	end
	local rise = p.Y - zone.size.Y / 2
	if rise > standHeight + C.SplashSlack or rise < -standHeight then
		return false -- jumping between floes, or nowhere near the water
	end
	for _, floe in floes do
		if floe.radius then
			local c = floe.cframe.Position
			local dx, dz = root.X - c.X, root.Z - c.Z
			if dx * dx + dz * dz < (floe.radius + C.FloeEdgeGrace) ^ 2 then
				return false
			end
		else
			local q = floe.cframe:PointToObjectSpace(root)
			if
				math.abs(q.X) < floe.size.X / 2 + C.FloeEdgeGrace
				and math.abs(q.Z) < floe.size.Z / 2 + C.FloeEdgeGrace
			then
				return false
			end
		end
	end
	return true
end

return CanalRules
