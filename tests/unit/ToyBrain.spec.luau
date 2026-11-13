-- Toys to fight back (Josh, 11 Nov 2026: "Can we use the toys against them,
-- like snow guns etc" ... "Build them"). Pure rules, server/ToyBrain.
local Config = load("ReplicatedStorage.Shared.Config")
local Brain = load("ServerScriptService.Server.ToyBrain")
local T = Config.Toys
local L, G = T.Launcher, T.Glitter

local function target(kind: string, x: number, z: number)
	return { kind = kind, position = Vector3.new(x, 0, z) }
end

describe("Snowball Launcher aim", function()
	local forward = Vector3.new(0, 0, -1)

	test("picks the nearest target in front", function()
		local near, far = target("Dog", 0, -10), target("Krampus", 0, -30)
		expect(Brain.aim(Vector3.zero, forward, { far, near })).toBe(near)
	end)

	test("ignores anything behind or off to the side", function()
		local behind = target("Dog", 0, 10)
		local side = target("Dog", 20, -1)
		expect(Brain.aim(Vector3.zero, forward, { behind, side })).toBeNil()
	end)

	test("allows a soft cone either side", function()
		local angle = math.rad(L.AimCone - 5)
		local inside = target("Dog", math.sin(angle) * 20, -math.cos(angle) * 20)
		expect(Brain.aim(Vector3.zero, forward, { inside })).toBe(inside)
		local wide = math.rad(L.AimCone + 5)
		local outside = target("Dog", math.sin(wide) * 20, -math.cos(wide) * 20)
		expect(Brain.aim(Vector3.zero, forward, { outside })).toBeNil()
	end)

	test("has a range", function()
		expect(Brain.aim(Vector3.zero, forward, { target("Dog", 0, -(L.Range + 1)) })).toBeNil()
		expect(Brain.aim(Vector3.zero, forward, { target("Dog", 0, -(L.Range - 1)) })).never.toBeNil()
	end)

	test("height doesn't matter (stairs, the Lair floor)", function()
		local up = { kind = "Krampus", position = Vector3.new(0, 12, -15) }
		expect(Brain.aim(Vector3.zero, forward, { up })).toBe(up)
	end)

	test("looking straight up or down aims at nothing", function()
		expect(Brain.aim(Vector3.zero, Vector3.yAxis, { target("Dog", 0, -10) })).toBeNil()
	end)

	test("flight time follows the snowball's speed", function()
		expect(math.abs(Brain.flightSeconds(Vector3.zero, Vector3.new(0, 0, L.Speed)) - 1) < 1e-6).toBe(true)
	end)
end)

describe("Krampus only flinches", function()
	test("once per cooldown for the whole crew", function()
		expect(Brain.canFlinch(nil, 0)).toBe(true)
		expect(Brain.canFlinch(10, 10 + L.KrampusCooldown - 0.1)).toBe(false)
		expect(Brain.canFlinch(10, 10 + L.KrampusCooldown)).toBe(true)
	end)

	test("red-team: a flinch is short, a knocked-over guard is long", function()
		expect(L.KrampusFlinch).toBeLessThanOrEqual(1)
		expect(L.KrampusCooldown).toBeGreaterThan(L.KrampusFlinch * 4)
		expect(L.GuardDown).toBeGreaterThan(L.KrampusFlinch)
	end)

	test("toys cost Jingle, a refill less than the launcher", function()
		expect(L.Refill).toBeLessThan(L.Cost)
		expect(G.Cost).toBeGreaterThan(0)
	end)
end)

describe("Glitter Bomb clouds", function()
	test("hide you inside the radius while they last", function()
		local clouds = { { position = Vector3.zero, untilT = 10 } }
		expect(Brain.inCloud(clouds, Vector3.new(G.Radius - 1, 0, 0), 5)).toBe(true)
		expect(Brain.inCloud(clouds, Vector3.new(G.Radius + 1, 0, 0), 5)).toBe(false)
		expect(Brain.inCloud(clouds, Vector3.new(0, G.Radius + 1, 0), 5)).toBe(false)
		expect(Brain.inCloud(clouds, Vector3.zero, 10)).toBe(false)
	end)

	test("any live cloud counts", function()
		local clouds = {
			{ position = Vector3.new(100, 0, 0), untilT = 1 },
			{ position = Vector3.new(100, 0, 0), untilT = 10 },
		}
		expect(Brain.inCloud(clouds, Vector3.new(100, 0, 0), 5)).toBe(true)
		expect(Brain.inCloud({}, Vector3.zero, 0)).toBe(false)
	end)

	test("prune drops faded clouds", function()
		local clouds = {
			{ position = Vector3.zero, untilT = 1 },
			{ position = Vector3.zero, untilT = 10 },
			{ position = Vector3.zero, untilT = 2 },
		}
		Brain.prune(clouds, 5)
		expect(#clouds).toBe(1)
		expect(clouds[1].untilT).toBe(10)
	end)
end)
