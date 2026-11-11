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
	inWater: boolean?, -- swimming or frozen in the Lair lake: Krampus never swims
	iced: boolean?, -- in a Frost Zap ice cube: he can still walk over and snatch them
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

-- A Santa he can sense: not hidden, not in his basket, not on the sleigh,
-- not in the water, not just dropped.
local function sensed(c: Candidate, now: number): boolean
	return not (c.hidden or c.captive or c.aboard or c.inWater) and now >= (c.ignoreUntil or 0)
end

-- Nearest Santa he can sense.
function KrampusBrain.pickTarget(from: Vector3, candidates: { Candidate }, now: number): Candidate?
	local best, bestDistance = nil, K.SenseRange
	for _, c in candidates do
		if sensed(c, now) then
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

function KrampusBrain.wiggleNeeded(): number
	return K.WiggleTaps
end

-- Which animation his state shows, falling back to what the rig has:
-- "waiting" (warning hold / intro), "dizzy" (bells rung), "sniffing" (heading
-- for the last noise), "moving" (chasing, wandering, carrying), "still".
local CLIPS = {
	waiting = { "Scheme", "Idle" },
	dizzy = { "Dizzy", "Idle" },
	sniffing = { "Sniff", "Tiptoe", "Idle" },
	moving = { "Tiptoe", "Idle" },
	still = { "Idle" },
}

function KrampusBrain.clipFor(state: string, has: (string) -> boolean): string?
	for _, clip in CLIPS[state] or CLIPS.still do
		if has(clip) then
			return clip
		end
	end
	return nil
end

----------------------------------------------------------------------------
-- Magic tricks and the Grumpy Meter (Josh, 6 Nov 2026)
----------------------------------------------------------------------------

local M = K.Magic

-- 1 Grumpy, 2 Cross, 3 Furious: by time since he arrived, plus one per bell ring.
function KrampusBrain.grumpyLevel(sinceArrival: number, bellRings: number): number
	local level = 1
	for i, at in M.Grumpy.At do
		if sinceArrival >= at then
			level = i
		end
	end
	return math.min(#M.Grumpy.At, level + bellRings)
end

function KrampusBrain.speedFor(level: number): number
	return M.Grumpy.Speed[level] or K.WalkSpeed
end

export type TrickContext = {
	now: number,
	level: number,
	lastCastAt: number,
	lastTrick: string?,
	from: Vector3,
	candidates: { Candidate },
	hitAt: { [any]: number }, -- when each Santa was last hit by a trick
	noiseAt: Vector3?, -- the latest noise, for Bell Blink
	safe: (Vector3) -> boolean, -- true where he must not land (the Sleigh Stop)
}

-- Distance on the floor plan, ignoring height.
function KrampusBrain.flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local flat = KrampusBrain.flat

-- Where Bell Blink drops him: LandBeside studs from the Santa, towards where he was.
function KrampusBrain.blinkSpot(from: Vector3, target: Vector3): Vector3
	local away = Vector3.new(from.X - target.X, 0, from.Z - target.Z)
	local dir = if away.Magnitude > 1e-3 then away.Unit else Vector3.zAxis
	return target + dir * M.BellBlink.LandBeside
end

-- The lowest-scoring sensed Santa, not hit by a trick within RehitSeconds,
-- whose distance from him passes `fits`.
local function best(
	ctx: TrickContext,
	measure: (Vector3, Vector3) -> number,
	fits: (Candidate, number) -> boolean,
	score: ((Candidate, number) -> number)?
): Candidate?
	local found, lowest = nil, math.huge
	for _, c in ctx.candidates do
		if sensed(c, ctx.now) and ctx.now - (ctx.hitAt[c.player] or -math.huge) >= M.RehitSeconds then
			local d = measure(c.position, ctx.from)
			if fits(c, d) then
				local v = if score then score(c, d) else d
				if v < lowest then
					found, lowest = c, v
				end
			end
		end
	end
	return found
end

local function along(a: Vector3, b: Vector3): number
	return (a - b).Magnitude
end

local chooser = {}

function chooser.FrostZap(ctx: TrickContext): Candidate?
	local z = M.FrostZap
	return best(ctx, along, function(c, d)
		return not c.iced and d >= z.MinRange and d <= z.MaxRange
	end)
end

function chooser.FrostStomp(ctx: TrickContext): Candidate?
	return best(ctx, flat, function(c, d)
		return not c.iced and d <= M.FrostStomp.Trigger
	end)
end

-- The Santa nearest the latest noise (the noisiest one), out of his reach.
function chooser.BellBlink(ctx: TrickContext): Candidate?
	local b = M.BellBlink
	local focus = ctx.noiseAt or ctx.from
	return best(ctx, flat, function(c, d)
		return d >= b.MinRange
			and d <= b.MaxRange
			and not ctx.safe(KrampusBrain.blinkSpot(ctx.from, c.position))
	end, function(c)
		return (c.position - focus).Magnitude
	end)
end

export type SummonContext = {
	now: number,
	from: Vector3,
	candidates: { Candidate },
	hitAt: { [any]: number },
	safe: (Vector3) -> boolean,
}

-- The Cuckoo Watch's spotted Santa, if he can Bell Blink to them now: sensed,
-- not hit by a trick within RehitSeconds, far enough away that a blink means
-- something (CuckooWatch.SummonMinRange), within the BellBlink range, and not
-- landing by the Sleigh Stop.
function KrampusBrain.summonTarget(ctx: SummonContext, player: any): Candidate?
	for _, c in ctx.candidates do
		if c.player == player then
			if not sensed(c, ctx.now) or c.iced then
				return nil
			end
			if ctx.now - (ctx.hitAt[c.player] or -math.huge) < M.RehitSeconds then
				return nil
			end
			local d = flat(c.position, ctx.from)
			if d < Config.CuckooWatch.SummonMinRange or d > M.BellBlink.MaxRange then
				return nil
			end
			if ctx.safe(KrampusBrain.blinkSpot(ctx.from, c.position)) then
				return nil
			end
			return c
		end
	end
	return nil
end

-- Which trick to cast now, and on whom; nil while on cooldown or nobody fits.
-- Tries the level's tricks in order, but the one he just used goes last.
function KrampusBrain.pickTrick(ctx: TrickContext): (string?, Candidate?)
	if not M.Enabled or ctx.now - ctx.lastCastAt < (M.Grumpy.Cooldown[ctx.level] or math.huge) then
		return nil, nil
	end
	local tricks = M.Grumpy.Tricks[ctx.level] or {}
	local i = ctx.lastTrick and table.find(tricks, ctx.lastTrick)
	if i then
		tricks = table.clone(tricks)
		table.insert(tricks, table.remove(tricks, i))
	end
	for _, trick in tricks do
		local target = chooser[trick](ctx)
		if target then
			return trick, target
		end
	end
	return nil, nil
end

-- Frost Stomp: the ring catches a Santa on the ground as its edge rolls past.
function KrampusBrain.stompHits(distance: number, radius: number, airborne: boolean): boolean
	return not airborne and math.abs(distance - radius) <= M.FrostStomp.RingWidth
end

-- The ring's radius t seconds after the stomp.
function KrampusBrain.stompRadius(t: number): number
	local s = M.FrostStomp
	return s.Radius * math.clamp(t / s.Seconds, 0, 1)
end

-- A Santa's walk speed while skidding on frost.
function KrampusBrain.skidSpeed(speed: number): number
	return speed * M.FrostStomp.SkidSpeed
end

return KrampusBrain
