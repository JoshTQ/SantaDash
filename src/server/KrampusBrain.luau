--[[
	Pure Krampus decisions (no Instances), so they can be unit tested:
	when he arrives, who he chases, whether a bell ringer is behind him,
	breath while hiding, and wiggling free.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local K = Config.Krampus

local KrampusBrain = {}

export type Candidate = {
	player: any,
	position: Vector3,
	hidden: boolean,
	captive: boolean,
	aboard: boolean,
	ignoreUntil: number?,
}

-- He is always home in his Lair, arrives on a full noise meter from
-- NoiseArrivalFrom, and from FirstStop once ArriveAt seconds have passed.
function KrampusBrain.shouldArrive(
	stopIndex: number,
	kindName: string,
	elapsed: number,
	noiseFull: boolean
): boolean
	if kindName == "Finale" then
		return true
	end
	if noiseFull and stopIndex >= K.NoiseArrivalFrom then
		return true
	end
	return stopIndex >= K.FirstStop and elapsed >= K.ArriveAt
end

-- Before he can arrive, he is only heard: distant bells, no chase.
function KrampusBrain.shouldTease(stopIndex: number, elapsed: number): boolean
	return K.TeaseEnabled and stopIndex >= K.TeaseFrom and elapsed >= K.TeaseAt
end

-- Nearest Santa he can sense: not hidden, not in his basket, not on the sleigh.
function KrampusBrain.pickTarget(from: Vector3, candidates: { Candidate }, now: number): Candidate?
	local best, bestDistance = nil, K.SenseRange
	for _, c in candidates do
		if not (c.hidden or c.captive or c.aboard) and now >= (c.ignoreUntil or 0) then
			local distance = (c.position - from).Magnitude
			if distance <= bestDistance then
				best, bestDistance = c, distance
			end
		end
	end
	return best
end

function KrampusBrain.canCatch(from: Vector3, target: Vector3): boolean
	return (target - from).Magnitude <= K.CatchRange
end

-- Bells only work rung from behind him (his back is local +Z).
function KrampusBrain.isBehind(krampus: CFrame, position: Vector3): boolean
	local rel = krampus:PointToObjectSpace(position)
	return rel.Z > 0 and rel.Magnitude <= K.BellRange
end

-- Breath drains while he is within BreathRange, and recovers when he leaves.
function KrampusBrain.breathStep(breath: number, distance: number, dt: number): number
	local rate = dt / K.BreathSeconds
	if distance <= K.BreathRange then
		return math.max(0, breath - rate)
	end
	return math.min(1, breath + rate)
end

function KrampusBrain.tapBreath(breath: number): number
	return math.min(1, breath + K.BreathPerTap)
end

function KrampusBrain.tapAllowed(lastTapAt: number, now: number): boolean
	return now - lastTapAt >= 1 / K.MaxTapsPerSecond
end

function KrampusBrain.wiggleNeeded(crewSize: number): number
	return if crewSize <= 1 then K.WiggleSolo else K.WiggleCrew
end

return KrampusBrain
