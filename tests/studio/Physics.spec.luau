--[[
	Real Roblox physics for the rules the Lune tests can only fake: knockback
	that moves a body, FloorMaterial for skating, how high a Humanoid's root
	really rides (the splash and hazard-reach maths depend on it), and the
	floe hop with real collisions.

	STUDIO ONLY. Open Cloud test servers don't simulate physics (checked
	4 Nov 2026: RunService:IsRunning() is false, Stepped never fires, an
	unanchored part never falls, and StepPhysics/Run need Plugin capability),
	so these run in Studio Play mode. See docs/PLAYTEST.md.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect, afterEach =
	JestGlobals.describe, JestGlobals.it, JestGlobals.expect, JestGlobals.afterEach

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local CanalRules = require(ServerStorage.Server.CanalRules)
local CanalTown = require(ServerStorage.Server.CanalTown)
local Knockback = require(ServerStorage.Server.Knockback)
local Rig = require(ReplicatedStorage.EngineTests.Rig)

local made: { Instance } = {}
local function pad(size: Vector3?, material: Enum.Material?): (Folder, Vector3)
	local folder, top = Rig.pad(size, material)
	table.insert(made, folder)
	return folder, top
end

afterEach(function()
	for _, f in made do
		f:Destroy()
	end
	table.clear(made)
end)

describe("a Humanoid on real ground", function()
	it("rides its root at Util.standHeight above the floor", function()
		local folder, top = pad()
		local santa = Rig.santa(folder, top)
		Rig.settle(santa)
		local rise = santa.root.Position.Y - top.Y
		expect(math.abs(rise - Util.standHeight(santa.humanoid, santa.root))).toBeLessThan(0.35)
	end, 20000)

	it("reports Ice as its floor on canal ice, which is what skating keys off", function()
		local folder, top = pad(nil, Enum.Material.Ice)
		local santa = Rig.santa(folder, top)
		Rig.settle(santa)
		expect(santa.humanoid.FloorMaterial).toBe(Enum.Material.Ice)
	end, 20000)

	it("skates at SkateSpeed on ice", function()
		local folder, top = pad(Vector3.new(400, 2, 60), Enum.Material.Ice)
		local santa = Rig.santa(folder, top - Vector3.new(150, 0, 0))
		Rig.settle(santa)
		santa.humanoid.WalkSpeed = CanalRules.walkSpeed(
			Config.Player.WalkSpeed,
			santa.humanoid.FloorMaterial == Enum.Material.Ice,
			false
		)
		local from = santa.root.Position
		santa.humanoid:MoveTo(from + Vector3.new(300, 0, 0))
		task.wait(1) -- get up to speed
		local a, t0 = santa.root.Position, os.clock()
		task.wait(1)
		local speed = Rig.flat(santa.root.Position - a).Magnitude / (os.clock() - t0)
		expect(speed).toBeGreaterThan(Config.Canal.SkateSpeed * 0.8)
		expect(speed).toBeLessThan(Config.Canal.SkateSpeed * 1.2)
	end, 20000)
end)

describe("knockback", function()
	it("actually moves a standing body away from the dog and drops it back down", function()
		local folder, top = pad()
		local santa = Rig.santa(folder, top)
		Rig.settle(santa)
		local start = santa.root.Position
		local push = Knockback.velocity(Vector3.new(1, 0, 0), Vector3.zAxis, Config.Canal.Dogs.Knockback)
		Knockback.apply(santa.root, push)
		local peak = start.Y
		Rig.waitFor(function()
			peak = math.max(peak, santa.root.Position.Y)
			return false
		end, 1.2)
		local moved = Rig.flat(santa.root.Position - start)
		expect(moved.X).toBeGreaterThan(4) -- a real shove, not a twitch
		expect(math.abs(moved.Z)).toBeLessThan(2)
		expect(peak - start.Y).toBeGreaterThan(0.5) -- a little hop
		expect(santa.root:FindFirstChild("SleighHeistKnockback")).toBeNil() -- cleaned up
		Rig.settle(santa)
		expect(santa.humanoid.FloorMaterial).never.toBe(Enum.Material.Air) -- landed
		expect(santa.root.CFrame.UpVector.Y).toBeGreaterThan(0.7) -- still on its feet
	end, 20000)

	it("a second bump replaces the first instead of stacking", function()
		local folder, top = pad()
		local santa = Rig.santa(folder, top)
		Rig.settle(santa)
		Knockback.apply(santa.root, Vector3.new(30, 10, 0))
		Knockback.apply(santa.root, Vector3.new(-30, 10, 0))
		local count = 0
		for _, c in santa.root:GetChildren() do
			if c.Name == "SleighHeistKnockback" then
				count += 1
			end
		end
		expect(count).toBe(1)
	end, 20000)
end)

describe("hazard reach with a real body", function()
	it("a dog on the ground reaches a Santa beside it, not one on a roof above", function()
		local folder, top = pad()
		local roof = Instance.new("Part")
		roof.Anchored = true
		roof.Size = Vector3.new(20, 1, 20)
		roof.CFrame = CFrame.new(top + Vector3.new(30, 14, 0))
		roof.Parent = folder
		local onGround = Rig.santa(folder, top)
		local onRoof = Rig.santa(folder, roof.Position + Vector3.new(0, 0.5, 0))
		Rig.settle(onGround)
		Rig.settle(onRoof)
		local r = Config.Canal.Dogs.HitRadius
		expect(CanalRules.inReach(onGround.root.Position, top + Vector3.new(1, 0, 0), r)).toBe(true)
		expect(CanalRules.inReach(onRoof.root.Position, top + Vector3.new(31, 0, 0), r)).toBe(false)
	end, 20000)
end)

describe("floe hop with real collisions", function()
	local function lake(folder: Instance, centre: Vector3): BasePart
		local zone = Instance.new("Part")
		zone.Name = "LakeIce"
		zone.Anchored = true
		zone.Size = Vector3.new(80, Config.Canal.IceTop, 80)
		zone.CFrame = CFrame.new(centre + Vector3.new(0, Config.Canal.IceTop / 2, 0))
		zone.Material = Enum.Material.Ice
		zone:SetAttribute("IceZone", true)
		zone.Parent = folder
		return zone
	end

	it("a Santa standing in the water is in the water; on a floe is dry", function()
		local folder, top = pad(Vector3.new(120, 2, 120))
		local zone = lake(folder, top)
		local floes = CanalTown.breakZone(zone, Random.new(3))
		expect(#floes).toBeGreaterThan(10)

		-- Somewhere between floes.
		local boxes = {}
		for _, f in floes do
			table.insert(boxes, { cframe = f.CFrame, size = f.Size })
		end
		local water: Vector3? = nil
		for x = -38, 38, 1 do
			for z = -38, 38, 1 do
				local p = zone.CFrame.Position + Vector3.new(x, 0, z)
				local clear = true
				for _, b in boxes do
					local q = b.cframe:PointToObjectSpace(p)
					if math.abs(q.X) < b.size.X / 2 + 1.5 and math.abs(q.Z) < b.size.Z / 2 + 1.5 then
						clear = false
						break
					end
				end
				if clear then
					water = p
					break
				end
			end
			if water then
				break
			end
		end
		expect(water).never.toBeNil()

		local wet = Rig.santa(folder, (water :: Vector3) + Vector3.new(0, zone.Size.Y / 2, 0))
		Rig.settle(wet)
		local stand = Util.standHeight(wet.humanoid, wet.root)
		expect(CanalTown.waterUnder({ zone }, wet.root, stand)).toBe(zone)

		local floe = floes[1]
		local dry = Rig.santa(folder, floe.Position + Vector3.new(0, floe.Size.Y / 2, 0))
		Rig.settle(dry)
		expect(CanalTown.waterUnder({ zone }, dry.root, Util.standHeight(dry.humanoid, dry.root))).toBeNil()

		-- Mid-jump over the water: not a splash.
		wet.humanoid.Jump = true
		local sawAirborneDry = Rig.waitFor(function()
			return wet.humanoid.FloorMaterial == Enum.Material.Air
				and wet.root.Position.Y > top.Y + stand + 1.5
				and CanalTown.waterUnder({ zone }, wet.root, stand) == nil
		end, 1.5)
		expect(sawAirborneDry).toBe(true)
	end, 30000)
end)
