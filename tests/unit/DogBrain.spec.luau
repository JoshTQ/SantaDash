--[[
	Guard dog senses and modes (Josh's first playtest, 6 Nov 2026: "I can
	walk by them and they don't find me").
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Brain = load("ServerScriptService.Server.DogBrain")
local AI = Config.DogAI

local EAST = Vector3.new(1, 0, 0)
local origin = Vector3.new(0, 0, 0)

local function santa(name: string, x: number, z: number?, extra: { [string]: any }?)
	local s =
		{ player = name, position = Vector3.new(x, 0, z or 0), speed = 16, safe = false, tiptoe = false }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

local function world(santas, extra: { [string]: any }?)
	local w = { now = 0, dt = 0.2, lit = true, noise = 0, santas = santas, trails = {}, loud = {} }
	for k, v in extra or {} do
		w[k] = v
	end
	return w
end

-- Thinks every 0.2 s for `seconds`, the dog standing still at `from`.
local function think(dog, from, w, seconds: number)
	local intent
	local t = w.now
	while t < w.now + seconds - 1e-6 do
		t += 0.2
		local step = table.clone(w)
		step.now = t
		intent = Brain.step(dog, from, EAST, step)
	end
	w.now = t
	return intent
end

describe("sight", function()
	it("spots a Santa walking in front of it, faster up close", function()
		local far = Brain.new("DogCorgi")
		local near = Brain.new("DogCorgi")
		local range = Brain.sightRange(far, true, false)
		local w = world({})
		local farRate = Brain.spotRate(far, origin, EAST, santa("A", range - 1), w)
		local nearRate = Brain.spotRate(near, origin, EAST, santa("A", 5), w)
		expect(farRate).toBeGreaterThan(0)
		expect(nearRate).toBeGreaterThan(farRate * 1.5)
	end)

	it("walking right past its nose is a chase within a second", function()
		local dog = Brain.new("DogCorgi")
		local w = world({ santa("A", 6, 2) })
		local intent = think(dog, origin, w, 1)
		expect(intent.mode).toBe("Chase")
		expect(intent.speed).toBeGreaterThan(Config.Player.WalkSpeed)
	end)

	it("can't see behind it, but feels a Santa brushing past", function()
		local dog = Brain.new("DogCorgi")
		local w = world({})
		expect(Brain.spotRate(dog, origin, EAST, santa("A", -15), w)).toBe(0)
		expect(Brain.spotRate(dog, origin, EAST, santa("A", -AI.CloseSense + 1), w)).toBeGreaterThan(0)
		-- ... unless they freeze
		expect(Brain.spotRate(dog, origin, EAST, santa("A", -AI.CloseSense + 1, 0, { speed = 0 }), w)).toBe(0)
	end)

	it("walls block its view", function()
		local dog = Brain.new("DogCorgi")
		local w = world({}, {
			clear = function()
				return false
			end,
		})
		expect(Brain.spotRate(dog, origin, EAST, santa("A", 5), w)).toBe(0)
	end)

	it("sees much further once the lights are on", function()
		local dog = Brain.new("DogTin")
		expect(Brain.sightRange(dog, true, false)).toBeGreaterThan(Brain.sightRange(dog, false, false) * 1.5)
		local x = Brain.sightRange(dog, false, false) + 5
		expect(Brain.spotRate(dog, origin, EAST, santa("A", x), world({}, { lit = false }))).toBe(0)
		expect(Brain.spotRate(dog, origin, EAST, santa("A", x), world({}, { lit = true }))).toBeGreaterThan(0)
	end)

	it("a still Santa is harder to see", function()
		local dog = Brain.new("DogCorgi")
		expect(Brain.sightRange(dog, true, true)).toBeLessThan(Brain.sightRange(dog, true, false))
	end)

	it("the tin dog's head lamp sweeps; a corgi on the move looks straight ahead", function()
		local tin = Brain.new("DogTin")
		local a = Brain.look(tin, EAST, 0.75)
		local b = Brain.look(tin, EAST, 2.25)
		expect(a.Z * b.Z).toBeLessThan(0) -- one side, then the other
		local corgi = Brain.new("DogCorgi")
		expect(Brain.look(corgi, EAST, 0.75).X).toBeNear(1, 1e-6)
	end)

	it("never chases a Santa safe at the Sleigh Stop", function()
		local dog = Brain.new("DogCorgi")
		local w = world({ santa("A", 5, 0, { safe = true }) })
		local intent = think(dog, origin, w, 3)
		expect(intent.mode).toBe("Patrol")
		expect(intent.awareness).toBe(0)
	end)
end)

describe("hearing", function()
	it("footsteps behind it make it suspicious, and it comes to look", function()
		local dog = Brain.new("DogCorgi")
		local w = world({ santa("A", -12) })
		local intent = think(dog, origin, w, 1)
		expect(intent.mode).toBe("Alert")
		expect(intent.goal.X).toBe(-12)
		expect(intent.awareness).toBeLessThan(1) -- hearing alone is never a chase
		think(dog, origin, w, 5)
		expect(dog.awareness).toBeLessThan(AI.HearCap + 1e-6)
	end)

	it("tiptoeing is quiet, a noisy street makes footsteps carry", function()
		local dog = Brain.new("DogCorgi")
		local walk = Brain.hearRange(dog, santa("A", 0), 0)
		local tiptoe = Brain.hearRange(dog, santa("A", 0, 0, { tiptoe = true }), 0)
		local noisy = Brain.hearRange(dog, santa("A", 0), 1)
		expect(tiptoe).toBeLessThan(walk / 2)
		expect(noisy).toBe(walk * 2)
		expect(Brain.hearRange(dog, santa("A", 0, 0, { speed = 0 }), 1)).toBe(0)
	end)

	it("a grab down the street brings it over", function()
		local dog = Brain.new("DogTin")
		local w = world({}, { loud = { { position = Vector3.new(-30, 0, 0), at = 0.1 } } })
		local intent = think(dog, origin, w, 0.2)
		expect(intent.mode).toBe("Alert")
		expect(intent.goal.X).toBe(-30)
	end)

	it("a bark from the pack brings it over", function()
		local dog = Brain.new("DogTin")
		Brain.alert(dog, Vector3.new(0, 0, 40), 0)
		local intent = think(dog, origin, world({}), 0.2)
		expect(intent.mode).toBe("Alert")
		expect(intent.goal.Z).toBe(40)
	end)
end)

describe("scent", function()
	it("follows a fresh trail toward the Santa who left it", function()
		local dog = Brain.new("DogCorgi")
		local trails = {
			A = {
				{ position = Vector3.new(2, 0, 0), at = 1 },
				{ position = Vector3.new(8, 0, 6), at = 2 },
				{ position = Vector3.new(14, 0, 12), at = 3 },
			},
		}
		local next = Brain.sniff(dog, origin, trails, 4)
		expect(next).toEqual(Vector3.new(8, 0, 6))
		local intent = think(dog, origin, world({}, { trails = trails, now = 3.8 }), 0.2)
		expect(intent.mode).toBe("Search")
		expect(intent.goal).toEqual(Vector3.new(8, 0, 6))
	end)

	it("a stale trail is gone, sooner for a tin dog", function()
		local trails = { A = { { position = origin, at = 0 }, { position = Vector3.new(5, 0, 0), at = 1 } } }
		local corgi, tin = Brain.new("DogCorgi"), Brain.new("DogTin")
		local t = AI.Kinds.DogTin.ScentSeconds + 1.5
		expect(Brain.sniff(corgi, origin, trails, t)).never.toBeNil()
		expect(Brain.sniff(tin, origin, trails, t)).toBeNil()
		expect(Brain.sniff(corgi, origin, trails, AI.Kinds.DogCorgi.ScentSeconds + 2)).toBeNil()
	end)
end)

describe("chasing", function()
	local function chasing(kind: string)
		local dog = Brain.new(kind)
		local w = world({ santa("A", 6) })
		local intent = think(dog, origin, w, 1)
		assert(intent.mode == "Chase", "should be chasing")
		return dog, w
	end

	it("runs out of puff after its burst: the window to escape", function()
		for kind, cfg in AI.Kinds do
			local dog, w = chasing(kind)
			local intent = think(dog, origin, w, cfg.ChaseBurst + 0.4)
			expect(intent.mode).toBe("Tired")
			expect(intent.speed).toBe(0)
		end
	end)

	it("loses you behind a wall and searches where it last saw you", function()
		local dog, w = chasing("DogCorgi")
		w.clear = function()
			return false
		end
		w.santas = { santa("A", 40) }
		local intent = think(dog, origin, w, 0.2)
		expect(intent.mode).toBe("Chase")
		expect(intent.goal.X).toBe(6) -- heads for the last place it saw you
		intent = think(dog, Vector3.new(6, 0, 0), w, 0.2)
		expect(intent.mode).toBe("Search")
		intent = think(dog, Vector3.new(6, 0, 0), w, AI.SearchSeconds + 0.4)
		expect(intent.mode).toBe("Patrol")
	end)

	it("gives up when you hide or reach the sleigh", function()
		local dog, w = chasing("DogCorgi")
		w.santas = {} -- hidden in a wardrobe: not a candidate
		expect(think(dog, origin, w, 0.2).mode).toBe("Search")
		local dog2, w2 = chasing("DogTin")
		w2.santas = { santa("A", 6, 0, { safe = true }) }
		expect(think(dog2, origin, w2, 0.2).mode).toBe("Search")
	end)

	it("a stunned tin dog stands still, then searches", function()
		local dog = Brain.new("DogTin")
		Brain.stun(dog, 3, 0)
		local w = world({ santa("A", 6) })
		expect(think(dog, origin, w, 1).mode).toBe("Stunned")
		expect(think(dog, origin, w, 2.4).mode).never.toBe("Stunned")
	end)
end)

describe("patrol", function()
	it("walks its beat back and forth, stopping to look round at each end", function()
		local a, b = Vector3.new(0, 0, 0), Vector3.new(0, 0, 50)
		local dog = Brain.new("DogCorgi", { patrol = { a, b }, startIndex = 2 })
		local w = world({})
		expect(think(dog, Vector3.new(0, 0, 20), w, 0.2).goal).toEqual(b)
		local atEnd = think(dog, b, w, 0.2)
		expect(atEnd.goal).toBeNil() -- looking round
		local back = think(dog, b, w, AI.LookAroundSeconds + 0.2)
		expect(back.goal).toEqual(a)
	end)

	it("market dogs are leashed to their beat", function()
		local a, b = Vector3.new(0, 0, 0), Vector3.new(0, 0, 50)
		local dog = Brain.new("DogCorgi", { patrol = { a, b } })
		dog.mode = "Chase"
		dog.target = "A"
		dog.chaseStarted = 0
		local far = Vector3.new(AI.LeashRange + 5, 0, 25)
		local intent = think(dog, far, world({ santa("A", AI.LeashRange + 15, 25) }), 0.2)
		expect(intent.mode).toBe("Patrol")
		expect(intent.goal).toEqual(a)
		expect(Brain.leashDistance({ a, b }, Vector3.new(10, 0, 25))).toBeNear(10, 1e-6)
	end)

	it("alarm dogs hunt the nearest Santa who isn't safe", function()
		local dog = Brain.new("DogCorgi", { hunt = true })
		local w = world({ santa("A", -60), santa("B", -30, 0, { safe = true }) }, { lit = false })
		local intent = think(dog, origin, w, 0.2)
		expect(intent.mode).toBe("Hunt")
		expect(intent.goal.X).toBe(-60)
		expect(intent.speed).toBe(Config.Noise.Alarm.ChaseSpeed)
	end)
end)

describe("Josh's 11 Nov pass: fiercer chases and a red alert mark", function()
	local GuardDogs = load("ServerScriptService.Server.GuardDogs")

	it("the ? goes red on alert, ! when chasing", function()
		expect(GuardDogs.markFor({ mode = "Patrol", awareness = 0 })).toBe("")
		expect(GuardDogs.markFor({ mode = "Patrol", awareness = AI.NoticeAt + 0.01 })).toBe("?")
		expect(GuardDogs.markFor({ mode = "Alert", awareness = AI.AlertAt })).toBe("alert?")
		expect(GuardDogs.markFor({ mode = "Search", awareness = 0.2 })).toBe("alert?")
		expect(GuardDogs.markFor({ mode = "Chase", awareness = 1 })).toBe("!")
		expect(GuardDogs.markFor({ mode = "Stunned", awareness = 1 })).toBe("")
	end)

	it("runs at where you're going, not where you were", function()
		local s = santa("A", 10, 0, { velocity = Vector3.new(0, 0, 16) })
		local goal = Brain.chaseGoal(s)
		expect(goal.Z).toBeNear(16 * AI.Lead, 1e-6)
		expect(Brain.chaseGoal(santa("A", 10)).Z).toBe(0)
	end)

	it("pounces for the last few studs", function()
		local dog = Brain.new("DogCorgi")
		expect(Brain.chaseSpeed(dog, origin, Vector3.new(AI.PounceRange - 1, 0, 0))).toBe(AI.PounceSpeed)
		expect(Brain.chaseSpeed(dog, origin, Vector3.new(AI.PounceRange + 5, 0, 0))).toBe(dog.cfg.ChaseSpeed)
	end)

	it("a chase it can see steers straight at you", function()
		local dog = Brain.new("DogCorgi")
		local intent = think(dog, origin, world({ santa("A", 6) }), 1)
		expect(intent.mode).toBe("Chase")
		expect(intent.direct).toBe(true)
	end)
end)

describe("Josh's 11 Nov follow-ups: Fetch, bones, flaps, yard dogs", function()
	it("a corgi with your present keeps away from Santas, then drops it", function()
		local dog = Brain.new("DogCorgi")
		Brain.fetch(dog, 0)
		local w = world({ santa("A", 10) })
		local intent = think(dog, origin, w, 0.2)
		expect(intent.mode).toBe("Fetch")
		expect(intent.goal.X).toBeLessThan(0) -- away from the Santa at +X
		expect(intent.speed).toBeLessThan(Config.Player.WalkSpeed) -- catchable
		intent = think(dog, origin, w, AI.Fetch.Seconds)
		expect(intent.drop).toBe(true)
	end)

	it("a bone: trots over, chews, ignores Santas, then goes back to work", function()
		local dog = Brain.new("DogCorgi")
		local bone = Vector3.new(20, 0, 0)
		Brain.distract(dog, bone, 0)
		local w = world({ santa("A", 6) }) -- right in front of it
		local intent = think(dog, origin, w, 0.2)
		expect(intent.mode).toBe("Chew")
		expect(intent.goal).toEqual(bone)
		intent = think(dog, bone, w, 0.2)
		expect(intent.chewing).toBe(true)
		intent = think(dog, bone, w, AI.Bone.ChewSeconds - 0.6)
		expect(intent.mode).toBe("Chew")
		expect(dog.awareness).toBe(0)
		Brain.alert(dog, origin, w.now) -- the pack can't call it off the bone
		expect(dog.mode).toBe("Chew")
		intent = think(dog, bone, w, 1)
		expect(intent.mode).never.toBe("Chew")
	end)

	it("a bone never makes a corgi drop your present", function()
		local dog = Brain.new("DogCorgi")
		Brain.fetch(dog, 0)
		Brain.distract(dog, Vector3.new(5, 0, 0), 0)
		expect(dog.mode).toBe("Fetch")
	end)

	it("dog flaps: a dog goes in through a closed front door", function()
		local flap = {
			box = CFrame.new(0, 0, 0),
			size = Vector3.new(20, 10, 20),
			outside = Vector3.new(0, 0, 13),
			inside = Vector3.new(0, 0, 7),
			open = false,
		}
		local street = Vector3.new(0, 0, 40)
		local indoors = Vector3.new(2, 0, -3)
		local wp, straight = Brain.flapWaypoint(street, indoors, { flap })
		expect(wp).toEqual(flap.outside) -- first, to the door
		expect(straight).toBe(false)
		wp, straight = Brain.flapWaypoint(Vector3.new(0, 0, 14), indoors, { flap })
		expect(wp).toEqual(flap.inside) -- then through the flap
		expect(straight).toBe(true)
		-- and back out the same way
		wp = Brain.flapWaypoint(indoors, street, { flap })
		expect(wp).toEqual(flap.inside)
		-- an open door needs no flap, nor does a walk outside
		flap.open = true
		expect(Brain.flapWaypoint(street, indoors, { flap })).toBeNil()
		flap.open = false
		expect(Brain.flapWaypoint(street, Vector3.new(30, 0, 40), { flap })).toBeNil()
	end)

	it("yard dogs leash close to home", function()
		local dog = Brain.new("DogTin", { patrol = { origin, Vector3.new(0, 0, 10) }, leash = AI.Yard.Leash })
		expect(dog.leash).toBe(AI.Yard.Leash)
		expect(Brain.new("DogTin").leash).toBe(AI.LeashRange)
	end)
end)

describe("yard dogs", function()
	local YardDogs = load("ServerScriptService.Server.YardDogs")

	it("come out on Yard.Stops, never in the Lair", function()
		expect(YardDogs.applies(2, "Street")).toBeTruthy()
		expect(YardDogs.applies(1, "Street")).toBeFalsy()
		expect(YardDogs.applies(2, "Finale")).toBeFalsy()
	end)

	it("guard the richer houses: secret rooms first, then the Far ring", function()
		local function h(name, ring, secret, distance, side)
			return {
				plan = { name = name, ring = ring, secret = secret, distance = distance, side = side or 1 },
			}
		end
		local picked = YardDogs.pick({
			h("near", "Near", false, 50),
			h("far1", "Far", false, 450),
			h("secret", "Mid", true, 250),
			h("far2", "Far", false, 480),
			h("end", "Far", false, 560, 0),
			h("far3", "Far", false, 470),
		})
		expect(#picked).toBe(AI.Yard.Count)
		expect(picked[1].name).toBe("secret")
		expect(picked[2].name).toBe("far2")
		for _, p in picked do
			expect(p.name ~= "near" and p.name ~= "end").toBeTruthy()
		end
	end)

	it("pace the front garden, between the house and the street", function()
		local stop = {
			origin = CFrame.new(),
			houses = {
				{
					plan = {
						ring = "Far",
						secret = false,
						distance = 400,
						side = 1,
						size = Vector3.new(24, 14, 20),
					},
				},
			},
		}
		local specs = YardDogs.specs(stop, 46)
		expect(#specs).toBe(1)
		local a, b = specs[1].patrol[1], specs[1].patrol[2]
		expect(a.X).toBe(46 - 10 - AI.Yard.Garden)
		expect(a.X).toBeGreaterThan(0)
		expect(math.abs(b.Z - a.Z)).toBeGreaterThan(8)
		expect(specs[1].leash).toBe(AI.Yard.Leash)
	end)
end)
