--[[
	Pure rules for the Naughty List heist (Josh, 11 Nov 2026): the List as the
	escape bonus, its Marked carrier, and the Lair's Cuckoo Watch. No
	Instances, so it runs in unit tests. Config.NaughtyList, Config.CuckooWatch.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local L = Config.NaughtyList
local C = Config.CuckooWatch

local ListBrain = {}

-- The finale's escape multiplier: the stop's bonus only with the List aboard.
function ListBrain.escapeMultiplier(stopMultiplier: number, listAboard: boolean): number
	if not L.Enabled or listAboard then
		return stopMultiplier
	end
	return L.NoListMultiplier
end

-- A carrier's walk speed: the book is heavy, and no perk makes it lighter.
function ListBrain.carrierSpeed(speed: number): number
	return math.min(speed, L.CarrierWalkSpeed)
end

-- How long a dropped List lies there before it flies home.
function ListBrain.looseSeconds(inWater: boolean): number
	return if inWater then L.WetSeconds else L.LooseSeconds
end

export type Catcher = { player: any, position: Vector3, free: boolean }

-- Who catches a pass: the nearest free friend within PassRange.
function ListBrain.passTarget(from: Vector3, friends: { Catcher }): any?
	local best, bestDistance = nil, L.PassRange
	for _, f in friends do
		local d = (f.position - from).Magnitude
		if f.free and d <= bestDistance then
			best, bestDistance = f.player, d
		end
	end
	return best
end

----------------------------------------------------------------------------
-- Cuckoo Watch
----------------------------------------------------------------------------

-- When the next tick-tock warning starts, `after` the last look ended.
function ListBrain.nextWatch(rng: Random, after: number): number
	return after + C.Interval + rng:NextNumber(-C.Jitter, C.Jitter)
end

-- The watch's state at time t, given when the warning started.
function ListBrain.watchState(warnAt: number, t: number): string
	if t < warnAt then
		return "Idle"
	elseif t < warnAt + C.WarnSeconds then
		return "Warn"
	elseif t < warnAt + C.WarnSeconds + C.LookSeconds then
		return "Look"
	end
	return "Done"
end

-- Inside the den: within the Lair's footprint (plus DenPadding), from its
-- bounding box. Height only has to be within the box.
function ListBrain.inDen(box: CFrame, size: Vector3, at: Vector3): boolean
	local p = box:PointToObjectSpace(at)
	local pad = C.DenPadding
	return math.abs(p.X) <= size.X / 2 + pad
		and math.abs(p.Z) <= size.Z / 2 + pad
		and math.abs(p.Y) <= size.Y / 2 + pad
end

-- Moving while the cuckoo looks: faster than MoveTolerance over the floor.
function ListBrain.moved(from: Vector3, to: Vector3, dt: number): boolean
	if dt <= 0 then
		return false
	end
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	return flat / dt > C.MoveTolerance
end

return ListBrain
