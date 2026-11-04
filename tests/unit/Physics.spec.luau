--[[
	Physics and controls rules (4 Nov 2026 hardening pass): hazard reach,
	water under a Santa, knockback direction, stand height, sleigh flight edge
	cases, HUD layout on phones. Pure maths, no engine.
]]

local Config = load("ReplicatedStorage.Shared.Config")
local CanalRules = load("ServerScriptService.Server.CanalRules")
local Knockback = load("ServerScriptService.Server.Knockback")
local SleighFlight = load("ReplicatedStorage.Shared.SleighFlight")
local HudLayout = load("ReplicatedStorage.Shared.HudLayout")
local Util = load("ReplicatedStorage.Shared.Util")
local C = Config.Canal

local function isNumber(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

local function finiteCFrame(cf: CFrame): boolean
	local parts = { cf:GetComponents() }
	for _, v in parts do
		if not isNumber(v) then
			return false
		end
	end
	return true
end

describe("hazard reach", function()
	it("bumps a Santa on the pavement next to it", function()
		expect(CanalRules.inReach(Vector3.new(2, 3, 1), Vector3.new(0, 0, 0), 4)).toBe(true)
	end)
	it("misses one out of range", function()
		expect(CanalRules.inReach(Vector3.new(5, 3, 0), Vector3.new(0, 0, 0), 4)).toBe(false)
	end)
	it("never bumps a Santa on a roof or bridge above it", function()
		expect(CanalRules.inReach(Vector3.new(0, 20, 0), Vector3.zero, 4)).toBe(false)
		expect(CanalRules.inReach(Vector3.new(0, C.Hazards.Above + 0.1, 0), Vector3.zero, 4)).toBe(false)
		expect(CanalRules.inReach(Vector3.new(0, C.Hazards.Above - 0.1, 0), Vector3.zero, 4)).toBe(true)
	end)
	it("never bumps a Santa down a chimney or below the ground", function()
		expect(CanalRules.inReach(Vector3.new(0, -C.Hazards.Below - 0.1, 0), Vector3.zero, 4)).toBe(false)
	end)
	it("reaches a Santa standing on the ground at normal hip height", function()
		-- An R15 root rides 3 studs up; a tall Rthro body about 4.5.
		expect(CanalRules.inReach(Vector3.new(1, 3, 0), Vector3.zero, 4)).toBe(true)
		expect(CanalRules.inReach(Vector3.new(1, 4.5, 0), Vector3.zero, 4)).toBe(true)
	end)
end)

describe("water under a Santa (broken ice)", function()
	-- A 100 x 0.25 x 40 zone at the origin with one 8 x 0.9 x 8 floe in it,
	-- laid out exactly as CanalTown.breakZone does.
	local zone = { cframe = CFrame.new(0, C.IceTop / 2, 0), size = Vector3.new(100, C.IceTop, 40) }
	local floe = {
		cframe = zone.cframe * CFrame.new(10, C.FloeTop / 2 - C.IceTop / 2, 0),
		size = Vector3.new(8, C.FloeTop, 8),
	}
	local stand = 3 -- R15: HipHeight 2 + half the 2-stud root
	local waterTop = C.IceTop
	local floeTop = C.FloeTop

	it("standing in the water splashes", function()
		expect(CanalRules.inWater(zone, { floe }, Vector3.new(-20, waterTop + stand, 0), stand)).toBe(true)
	end)
	it("standing on a floe never splashes", function()
		expect(CanalRules.inWater(zone, { floe }, Vector3.new(10, floeTop + stand, 0), stand)).toBe(false)
		-- even with the root a little past the edge (a foot still on it)
		local edge = 10 + 4 + C.FloeEdgeGrace - 0.1
		expect(CanalRules.inWater(zone, { floe }, Vector3.new(edge, floeTop + stand, 0), stand)).toBe(false)
	end)
	it("a Santa on a floe is high enough even without the floe list", function()
		-- Floes stand FloeTop - IceTop proud: more than the splash slack.
		expect(C.FloeTop - C.IceTop).toBeGreaterThan(C.SplashSlack)
		expect(CanalRules.inWater(zone, {}, Vector3.new(10, floeTop + stand, 0), stand)).toBe(false)
	end)
	it("mid-hop over the water is not a splash", function()
		expect(CanalRules.inWater(zone, { floe }, Vector3.new(-20, waterTop + stand + 3, 0), stand)).toBe(
			false
		)
	end)
	it("off the zone is not a splash", function()
		expect(CanalRules.inWater(zone, { floe }, Vector3.new(60, waterTop + stand, 0), stand)).toBe(false)
		expect(CanalRules.inWater(zone, { floe }, Vector3.new(0, waterTop + stand, 25), stand)).toBe(false)
	end)
	it("works for a zone turned along the canal", function()
		local turned = {
			cframe = CFrame.new(500, C.IceTop / 2, 0) * CFrame.Angles(0, math.rad(60), 0),
			size = zone.size,
		}
		local inside = turned.cframe * Vector3.new(30, 0, 0) + Vector3.new(0, stand + C.IceTop / 2, 0)
		local outside = turned.cframe * Vector3.new(0, 0, 30) + Vector3.new(0, stand + C.IceTop / 2, 0)
		expect(CanalRules.inWater(turned, {}, inside, stand)).toBe(true)
		expect(CanalRules.inWater(turned, {}, outside, stand)).toBe(false)
	end)
	it("a tall avatar (higher hips) standing in water still splashes", function()
		local tall = 4.4
		expect(CanalRules.inWater(zone, {}, Vector3.new(-20, waterTop + tall, 0), tall)).toBe(true)
	end)
end)

describe("stand height", function()
	it("R15 rides HipHeight plus half the root", function()
		local humanoid = { RigType = Enum.HumanoidRigType.R15, HipHeight = 2 }
		expect(Util.standHeight(humanoid :: any, { Size = Vector3.new(2, 2, 1) } :: any)).toBe(3)
	end)
	it("R6 legs are always 2 studs", function()
		local humanoid = { RigType = Enum.HumanoidRigType.R6, HipHeight = 0 }
		expect(Util.standHeight(humanoid :: any, { Size = Vector3.new(2, 2, 1) } :: any)).toBe(3)
	end)
end)

describe("knockback", function()
	it("pushes straight away from the dog with a hop", function()
		local v = Knockback.velocity(Vector3.new(3, 0, 4), Vector3.zAxis, 40)
		expect(v.X).toBeNear(24, 1e-6)
		expect(v.Z).toBeNear(32, 1e-6)
		expect(v.Y).toBe(Config.Knockback.Lift)
	end)
	it("ignores height difference in the push direction", function()
		local v = Knockback.velocity(Vector3.new(0, 30, 2), Vector3.zAxis, 40)
		expect(v.Z).toBeNear(40, 1e-6)
		expect(v.Y).toBe(Config.Knockback.Lift)
	end)
	it("right on top of the dog: along its facing, never NaN", function()
		local v = Knockback.velocity(Vector3.zero, Vector3.new(1, 0, 0), 40)
		expect(v.X).toBeNear(40, 1e-6)
		local w = Knockback.velocity(Vector3.zero, Vector3.zero, 40)
		expect(isNumber(w.X) and isNumber(w.Z)).toBe(true)
		expect(Vector3.new(w.X, 0, w.Z).Magnitude).toBeNear(40, 1e-6)
	end)
	it("is short and strong enough to beat ground friction", function()
		expect(Config.Knockback.Seconds).toBeGreaterThan(0.05)
		expect(Config.Knockback.Seconds).toBeLessThan(0.6) -- a bump, not a launch
		expect(Config.Knockback.MaxForce).toBeGreaterThan(20000)
	end)
end)

describe("dog patrols, degenerate paths", function()
	it("a patrol with both ends in one place stands still (no NaN)", function()
		local p, facing = CanalRules.patrolAt({ Vector3.new(5, 0, 5), Vector3.new(5, 0, 5) }, 9, 3)
		expect(p).toEqual(Vector3.new(5, 0, 5))
		expect(isNumber(facing.Z)).toBe(true)
	end)
	it("a repeated middle point doesn't produce NaN facing", function()
		local pts = { Vector3.zero, Vector3.new(0, 0, 10), Vector3.new(0, 0, 10), Vector3.new(0, 0, 20) }
		for t = 0, 6, 0.1 do
			local p, facing = CanalRules.patrolAt(pts, 9, t)
			expect(isNumber(p.Z) and isNumber(facing.Z)).toBe(true)
		end
	end)
end)

describe("sleigh flight edge cases", function()
	local S, PEAK = Config.Run.FlightSeconds, Config.Run.FlightArcHeight

	it("a hop to the same spot stays finite and lands", function()
		local deck = CFrame.new(10, 0, 10)
		for t = 0, S, 0.05 do
			expect(finiteCFrame(SleighFlight.deckAt(deck, deck, t, S, PEAK))).toBe(true)
		end
		expect(SleighFlight.deckAt(deck, deck, S, S, PEAK)).toEqual(deck)
	end)
	it("a deck pointing straight up never makes NaN", function()
		local up = CFrame.new(0, 0, 0) * CFrame.Angles(math.pi / 2, 0, 0)
		local to = CFrame.new(0, 0, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		for t = 0, S, 0.05 do
			expect(finiteCFrame(SleighFlight.deckAt(up, to, t, S, PEAK))).toBe(true)
		end
	end)
	it("a U-turn flight banks within limits and never flips", function()
		local from = CFrame.new(0, 0, 0)
		local to = CFrame.new(40, 0, 0) * CFrame.Angles(0, math.pi, 0)
		for t = 0, S, 1 / 60 do
			local cf = SleighFlight.deckAt(from, to, t, S, PEAK)
			expect(finiteCFrame(cf)).toBe(true)
			expect(cf.UpVector.Y).toBeGreaterThan(
				math.cos(SleighFlight.MaxBank + SleighFlight.MaxPitch) - 0.05
			)
		end
	end)
	it("never dips below the lower deck", function()
		local from = CFrame.new(0, 20, 0)
		local to = CFrame.new(700, 0, 300)
		for t = 0, S, 0.05 do
			expect(SleighFlight.deckAt(from, to, t, S, PEAK).Position.Y).toBeGreaterThan(-1e-6)
		end
	end)
	it("a zero-length flight is just the destination", function()
		local to = CFrame.new(1, 2, 3)
		expect(SleighFlight.deckAt(CFrame.new(), to, 0, 0, PEAK)).toEqual(CFrame.new())
		expect(SleighFlight.deckAt(CFrame.new(), to, 1, 0, PEAK)).toEqual(to)
	end)
end)

describe("HUD layout on phones", function()
	it("full size on a laptop", function()
		expect(HudLayout.scale(Vector2.new(1366, 768))).toBe(1)
	end)
	it("shrinks on a landscape phone so the top row fits", function()
		local s = HudLayout.scale(Vector2.new(667, 375))
		expect(s).toBeLessThan(1)
		expect(HudLayout.DesignWidth * s).toBeLessThanOrEqual(667)
	end)
	it("never shrinks below the tappable minimum", function()
		expect(HudLayout.scale(Vector2.new(300, 200))).toBe(HudLayout.MinScale)
	end)
	it("no viewport yet: full size", function()
		expect(HudLayout.scale(nil)).toBe(1)
		expect(HudLayout.scale(Vector2.new(0, 0))).toBe(1)
	end)
	it("keeps Back to hub out of the thumbstick corner on every device", function()
		for _, touch in { true, false } do
			local quit = HudLayout.spots(touch).quit
			expect(quit.Y.Scale).toBe(0) -- measured from the top
		end
	end)
	it("lifts the throw button above the jump button on touch screens", function()
		local touch, mouse = HudLayout.spots(true).snow, HudLayout.spots(false).snow
		expect(touch.Y.Offset).toBeLessThan(mouse.Y.Offset - 120)
	end)
end)
