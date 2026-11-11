--[[
	Guard dog decisions (Config.DogAI), pure so Lune can test them. GuardDogs
	does the moving, sounds and the "?" / "!" over their heads.

	Josh's first playtest (6 Nov 2026): "I can walk by them and they don't
	find me." So a dog now senses Santas three ways:

	  sight    a cone in front of it (wide for a corgi, a narrow sweeping head
	           lamp for a tin dog), blocked by walls, much longer once the
	           street's lights are on. In view long enough (fast up close) = "!".
	  hearing  footsteps, louder as the NOISE meter fills; tiptoeing is quiet.
	           Grabs, gasps and other dogs' barks bring it over to look.
	  scent    the trail a Santa leaves (not on canal ice). A corgi follows a
	           trail up to 12 s old.

	Modes: Patrol (or Hunt, for alarm dogs) -> Alert "?" (walks over to
	look) -> Chase "!" (a burst faster than a Santa walks) -> Tired (pants:
	your window) -> Search (sniffs round where it lost you) -> Patrol.
	Stunned: a tin dog winding down after a bonk.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local NoiseAlarm = require(script.Parent.NoiseAlarm)

local AI = Config.DogAI

local DogBrain = {}

local REACHED = 3 -- studs: close enough to a spot it walked over to look at
local LOOK_SWEEP = 60 -- degrees a dog looks either side while looking round

export type Santa = {
	player: any,
	position: Vector3,
	speed: number, -- flat studs/s
	velocity: Vector3?, -- where they're heading (a chase leads them)
	safe: boolean, -- aboard at the Sleigh Stop
	tiptoe: boolean, -- the stop's sneak phase
}

export type Crumb = { position: Vector3, at: number }

export type Loud = { position: Vector3, at: number }

export type World = {
	now: number,
	dt: number,
	lit: boolean, -- the lights are on (after the sneak phase)
	noise: number, -- the NOISE meter, 0..1
	santas: { Santa },
	trails: { [any]: { Crumb } }, -- oldest crumb first
	loud: { Loud },
	clear: ((from: Vector3, to: Vector3) -> boolean)?, -- line of sight (nil = open)
}

export type Intent = {
	mode: string,
	goal: Vector3?, -- nil = stand still
	speed: number,
	look: Vector3, -- where its eyes (the tin dog's lamp) point
	awareness: number,
	spotted: Santa?, -- set on the tick a chase starts
	direct: boolean?, -- chasing a Santa it can see: steer straight, no path
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function yaw(v: Vector3, degrees: number): Vector3
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return Vector3.new(v.X * c - v.Z * s, 0, v.X * s + v.Z * c)
end

function DogBrain.kind(kind: string)
	return AI.Kinds[kind] or AI.Kinds.DogCorgi
end

-- options.patrol: points it walks back and forth along (market dogs, leashed
-- to them). options.hunt: alarm dogs, which head for the nearest Santa.
function DogBrain.new(kind: string, options: { patrol: { Vector3 }?, startIndex: number?, hunt: boolean? }?)
	local o = options or {}
	return {
		kind = kind,
		cfg = DogBrain.kind(kind),
		mode = if o.hunt then "Hunt" else "Patrol",
		awareness = 0,
		target = nil :: any,
		lastSeen = nil :: Vector3?,
		investigate = nil :: Vector3?,
		chaseStarted = 0,
		tiredUntil = 0,
		stunnedUntil = 0,
		searchUntil = 0,
		lookUntil = 0,
		heardAt = -math.huge,
		patrol = o.patrol,
		patrolIndex = o.startIndex or 1,
		patrolStep = 1,
		hunt = o.hunt == true,
		returning = false,
	}
end

-- How far this dog sees: further with the lights on, less for a still Santa.
function DogBrain.sightRange(dog, lit: boolean, still: boolean): number
	local base = if lit then AI.SightRange.Lit else AI.SightRange.Sneak
	return base * dog.cfg.SightScale * (if still then AI.StillSight else 1)
end

-- How far it hears a Santa's footsteps (0 when standing still).
function DogBrain.hearRange(dog, santa: Santa, noise: number): number
	if santa.speed < 0.5 then
		return 0
	end
	local steps = if santa.tiptoe then AI.Footsteps.Tiptoe else AI.Footsteps.Walk
	return steps * dog.cfg.HearScale * (1 + math.clamp(noise, 0, 1))
end

-- Where its eyes point: its body facing, swung by the tin dog's sweeping
-- lamp, or by any dog looking round while it searches or rests on patrol.
function DogBrain.look(dog, facing: Vector3, now: number): Vector3
	local f = flat(facing)
	if f.Magnitude < 1e-3 then
		f = Vector3.new(0, 0, -1)
	end
	f = f.Unit
	if dog.mode == "Chase" or dog.mode == "Stunned" or dog.mode == "Tired" then
		return f
	end
	local amplitude = dog.cfg.Sweep or 0
	local period = dog.cfg.SweepSeconds or 2.5
	if dog.mode == "Search" or dog.lookUntil > now then
		amplitude = math.max(amplitude, LOOK_SWEEP)
	end
	if amplitude <= 0 then
		return f
	end
	return yaw(f, amplitude * math.sin(2 * math.pi * now / period))
end

-- Can the dog at `from` (eyes along `look`) see this Santa? Returns the
-- awareness it gains per second (0 = not seen).
function DogBrain.spotRate(dog, from: Vector3, look: Vector3, santa: Santa, world: World): number
	local offset = flat(santa.position - from)
	local distance = offset.Magnitude
	local still = santa.speed < 0.5
	local range = DogBrain.sightRange(dog, world.lit, still)
	if distance > range then
		return 0
	end
	local inCone = distance < 1e-3
	if not inCone then
		local cos = look:Dot(offset.Unit)
		inCone = cos >= math.cos(math.rad(dog.cfg.Fov / 2)) or (distance <= AI.CloseSense and not still)
	end
	if not inCone then
		return 0
	end
	if world.clear and not world.clear(from, santa.position) then
		return 0
	end
	return (1 / AI.SpotSeconds) * (1 + (1 - distance / range))
end

-- The next crumb along the freshest trail it is standing on, or nil.
function DogBrain.sniff(dog, from: Vector3, trails: { [any]: { Crumb } }, now: number): Vector3?
	local best, bestAt = nil, -math.huge
	for _, crumbs in trails do
		for i = #crumbs, 1, -1 do
			local c = crumbs[i]
			if now - c.at > dog.cfg.ScentSeconds then
				break -- older crumbs are staler still
			end
			if c.at > bestAt and flatDistance(c.position, from) <= AI.ScentRadius then
				local nextCrumb = crumbs[i + 1] or c
				best, bestAt = nextCrumb.position, c.at
				break
			end
		end
	end
	return best
end

-- Flat distance from `p` to the patrol path (math.huge with no path).
function DogBrain.leashDistance(points: { Vector3 }?, p: Vector3): number
	if not points or #points == 0 then
		return math.huge
	end
	local best = flatDistance(points[1], p)
	for i = 1, #points - 1 do
		local a, b = flat(points[i]), flat(points[i + 1])
		local ab = b - a
		local len2 = ab:Dot(ab)
		local t = if len2 > 1e-6 then math.clamp((flat(p) - a):Dot(ab) / len2, 0, 1) else 0
		best = math.min(best, (flat(p) - (a + ab * t)).Magnitude)
	end
	return best
end

-- Where a chase runs: a little ahead of where the Santa is going.
function DogBrain.chaseGoal(santa: Santa): Vector3
	local v = santa.velocity
	if not v then
		return santa.position
	end
	return santa.position + flat(v) * AI.Lead
end

-- Chase speed, with a pounce for the last few studs.
function DogBrain.chaseSpeed(dog, from: Vector3, goal: Vector3?): number
	if goal and flatDistance(goal, from) <= AI.PounceRange then
		return math.max(dog.cfg.ChaseSpeed, AI.PounceSpeed)
	end
	return dog.cfg.ChaseSpeed
end

-- Another dog barked at `position`: come and look (unless already chasing).
function DogBrain.alert(dog, position: Vector3, _now: number)
	if dog.mode == "Chase" or dog.mode == "Stunned" or dog.returning then
		return
	end
	dog.investigate = position
	dog.awareness = math.max(dog.awareness, AI.AlertAt + 0.1)
end

-- A tin dog winds down after a bonk.
function DogBrain.stun(dog, seconds: number, now: number)
	dog.mode = "Stunned"
	dog.stunnedUntil = now + seconds
	dog.awareness = math.min(dog.awareness, 0.7)
end

-- A corgi pants for a moment after a bump (or a long chase).
function DogBrain.tire(dog, now: number)
	dog.mode = "Tired"
	dog.tiredUntil = now + dog.cfg.TiredSeconds
end

local function startSearch(dog, at: Vector3?, now: number)
	dog.mode = "Search"
	dog.investigate = nil
	dog.lastSeen = at or dog.lastSeen
	dog.searchUntil = now + AI.SearchSeconds
	dog.awareness = math.min(dog.awareness, 0.9)
end

local function idleMode(dog): string
	return if dog.hunt then "Hunt" else "Patrol"
end

local function patrolGoal(dog, from: Vector3, now: number): Vector3?
	local points = dog.patrol
	if not points or #points == 0 then
		return nil
	end
	if dog.lookUntil > now then
		return nil
	end
	local goal = points[dog.patrolIndex] or points[1]
	if flatDistance(goal, from) < 2.5 then
		if #points > 1 then
			if
				(dog.patrolIndex == #points and dog.patrolStep > 0)
				or (dog.patrolIndex == 1 and dog.patrolStep < 0)
			then
				dog.patrolStep = -dog.patrolStep
				dog.lookUntil = now + AI.LookAroundSeconds -- an end of the beat: look round
			end
			dog.patrolIndex = math.clamp(dog.patrolIndex + dog.patrolStep, 1, #points)
		end
		return nil
	end
	return goal
end

local function nearestPatrolPoint(points: { Vector3 }, from: Vector3): Vector3
	local best, bestDistance = points[1], math.huge
	for _, p in points do
		local d = flatDistance(p, from)
		if d < bestDistance then
			best, bestDistance = p, d
		end
	end
	return best
end

-- One think: perceive, then pick what to do. `from` is the dog's position,
-- `facing` its body's look direction.
function DogBrain.step(dog, from: Vector3, facing: Vector3, world: World): Intent
	local now, dt = world.now, world.dt
	local cfg = dog.cfg
	local spotted = nil

	if dog.mode == "Stunned" then
		if now < dog.stunnedUntil then
			return { mode = "Stunned", speed = 0, look = flat(facing), awareness = dog.awareness }
		end
		startSearch(dog, dog.lastSeen, now)
	end

	-- Back to its beat after straying too far: it ignores everything on the way.
	if dog.patrol and not dog.returning and DogBrain.leashDistance(dog.patrol, from) > AI.LeashRange then
		dog.returning = true
		dog.mode = "Patrol"
		dog.awareness, dog.target, dog.investigate = 0, nil, nil
	end
	if dog.returning then
		if DogBrain.leashDistance(dog.patrol, from) <= AI.LeashRange / 2 then
			dog.returning = false
		else
			local home = nearestPatrolPoint(dog.patrol, from)
			return {
				mode = "Patrol",
				goal = home,
				speed = Config.Canal.Dogs.Speed,
				look = flat(facing),
				awareness = 0,
			}
		end
	end

	local look = DogBrain.look(dog, facing, now)

	-- Sight: the Santa it sees best this tick.
	local seen, seenRate = nil, 0
	local targetEntry = nil
	for _, santa in world.santas do
		if santa.player == dog.target then
			targetEntry = santa
		end
		if not santa.safe then
			local rate = DogBrain.spotRate(dog, from, look, santa, world)
			-- Keep eyes on the one it's chasing if it can still see them.
			if rate > 0 and santa.player == dog.target and dog.mode == "Chase" then
				rate += 100
			end
			if rate > seenRate then
				seen, seenRate = santa, rate
			end
		end
	end

	if seen then
		dog.awareness = math.min(1, dog.awareness + seenRate * dt)
		dog.target = seen.player
		dog.lastSeen = seen.position
		if dog.mode ~= "Chase" then
			dog.investigate = seen.position
		end
	else
		-- Hearing: footsteps it can't see.
		local heard = nil
		for _, santa in world.santas do
			if
				not santa.safe
				and flatDistance(santa.position, from) <= DogBrain.hearRange(dog, santa, world.noise)
			then
				heard = santa
				break
			end
		end
		if heard and dog.mode ~= "Chase" then
			if dog.awareness < AI.HearCap then
				dog.awareness = math.min(AI.HearCap, dog.awareness + AI.HearRate * dt)
			end
			dog.investigate = heard.position
		elseif dog.mode ~= "Chase" then
			dog.awareness = math.max(0, dog.awareness - AI.Forget * dt)
		end
	end

	-- Loud noises (grabs, gasps, barks) since it last listened.
	local loudRange = AI.LoudRange * (1 + math.clamp(world.noise, 0, 1))
	for _, loud in world.loud do
		if loud.at > dog.heardAt then
			dog.heardAt = math.max(dog.heardAt, loud.at)
			if dog.mode ~= "Chase" and flatDistance(loud.position, from) <= loudRange then
				dog.investigate = loud.position
				dog.awareness = math.max(dog.awareness, AI.AlertAt + 0.05)
			end
		end
	end

	-- Chasing.
	if dog.mode == "Chase" then
		local gone = targetEntry == nil or targetEntry.safe
		if gone then
			startSearch(dog, dog.lastSeen, now)
		elseif now - dog.chaseStarted > cfg.ChaseBurst then
			DogBrain.tire(dog, now)
		else
			local inSight = seen ~= nil and seen.player == dog.target
			local goal = if inSight then DogBrain.chaseGoal(seen) else dog.lastSeen
			if not inSight and goal and flatDistance(goal, from) < REACHED then
				startSearch(dog, goal, now) -- lost them where it last saw them
			else
				return {
					mode = "Chase",
					goal = goal,
					speed = DogBrain.chaseSpeed(dog, from, goal),
					look = look,
					awareness = 1,
					direct = inSight,
				}
			end
		end
	end

	if dog.mode == "Tired" then
		if now < dog.tiredUntil then
			return { mode = "Tired", speed = 0, look = look, awareness = dog.awareness }
		end
		if seen and dog.awareness >= 1 then
			dog.mode = "Chase"
			dog.chaseStarted = now
			local goal = DogBrain.chaseGoal(seen)
			return {
				mode = "Chase",
				goal = goal,
				speed = DogBrain.chaseSpeed(dog, from, goal),
				look = look,
				awareness = 1,
				direct = true,
			}
		end
		startSearch(dog, dog.lastSeen, now)
	end

	-- Spotted: the chase starts.
	if dog.awareness >= 1 and seen then
		dog.mode = "Chase"
		dog.chaseStarted = now
		dog.investigate = nil
		spotted = seen
		local goal = DogBrain.chaseGoal(seen)
		return {
			mode = "Chase",
			goal = goal,
			speed = DogBrain.chaseSpeed(dog, from, goal),
			look = look,
			awareness = 1,
			spotted = spotted,
			direct = true,
		}
	end

	-- Something to look at: walk over.
	if dog.investigate and dog.awareness >= AI.AlertAt then
		if flatDistance(dog.investigate, from) < REACHED then
			startSearch(dog, dog.investigate, now)
		else
			dog.mode = "Alert"
			return {
				mode = "Alert",
				goal = dog.investigate,
				speed = AI.AlertSpeed,
				look = look,
				awareness = dog.awareness,
			}
		end
	end

	-- Searching: follow a trail if it smells one, else stand and look round.
	if dog.mode == "Search" or (dog.mode ~= "Alert" and not dog.hunt) then
		local trail = DogBrain.sniff(dog, from, world.trails, now)
		if trail and flatDistance(trail, from) >= 1 then
			if dog.mode ~= "Search" then
				startSearch(dog, nil, now)
			else
				dog.searchUntil = math.max(dog.searchUntil, now + 1)
			end
			dog.awareness = math.max(dog.awareness, AI.AlertAt)
			return {
				mode = "Search",
				goal = trail,
				speed = AI.AlertSpeed,
				look = look,
				awareness = dog.awareness,
			}
		end
		if dog.mode == "Search" then
			if now < dog.searchUntil then
				return { mode = "Search", speed = 0, look = look, awareness = dog.awareness }
			end
			dog.awareness = math.min(dog.awareness, AI.AlertAt * 0.5)
		end
	end
	if dog.mode == "Alert" and not (dog.investigate and dog.awareness >= AI.AlertAt) then
		dog.investigate = nil
	end

	-- Nothing going on: hunt (alarm dogs) or patrol.
	dog.mode = idleMode(dog)
	if dog.hunt then
		local santa = NoiseAlarm.target(from, world.santas)
		return {
			mode = "Hunt",
			goal = santa and santa.position,
			speed = Config.Noise.Alarm.ChaseSpeed,
			look = look,
			awareness = dog.awareness,
		}
	end
	return {
		mode = "Patrol",
		goal = patrolGoal(dog, from, now),
		speed = Config.Canal.Dogs.Speed,
		look = look,
		awareness = dog.awareness,
	}
end

return DogBrain
