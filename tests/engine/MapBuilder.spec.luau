-- Approved-model paths that need the live engine (PivotTo, GetBoundingBox),
-- built with plain-part stand-ins that follow the Assets contract.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect, afterEach =
	JestGlobals.describe, JestGlobals.it, JestGlobals.expect, JestGlobals.afterEach

local Config = require(ReplicatedStorage.Shared.Config)
local Loot = require(ServerStorage.Server.Loot)
local MapBuilder = require(ServerStorage.Server.MapBuilder)

local function part(parent: Instance, className: string, name: string, size: Vector3, cf: CFrame): BasePart
	local p = Instance.new(className) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.Parent = parent
	return p
end

local function model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

local function fakeSleigh(): Model
	local m = model("Sleigh")
	m.PrimaryPart = part(m, "Part", "Body", Vector3.new(8, 3, 14), CFrame.new())
	part(m, "Part", "Hitch", Vector3.new(1, 1, 1), CFrame.new(0, 0, -8))
	for i = 1, 6 do
		part(m, "Seat", "Seat" .. i, Vector3.new(2, 1, 2), CFrame.new((i % 2) * 3 - 1.5, 2, i * 2 - 7))
	end
	return m
end

local function fakeReindeer(): Model
	local m = model("Reindeer")
	m.PrimaryPart = part(m, "Part", "Body", Vector3.new(2, 3, 5), CFrame.new())
	return m
end

local function fakeCocoa(): Model
	local m = model("CocoaMachine")
	local body = part(m, "Part", "Body", Vector3.new(4, 7, 3), CFrame.new())
	m.PrimaryPart = body
	local prompt = Instance.new("Attachment")
	prompt.Name = "BuyPrompt"
	prompt.Parent = body
	return m
end

local function fakeDressing(): Model
	local m = model("Dressing")
	for _, name in { "StopDressing", "RouteDressing" } do
		local child = model(name)
		child.PrimaryPart = part(child, "Part", "Lamp", Vector3.new(1, 8, 1), CFrame.new())
		child.Parent = m
	end
	return m
end

local function plans(rng: Random)
	local stops, onFoot = {}, {}
	local count = #Config.Run.StopKinds
	for i = 1, count do
		stops[i] = Loot.planStop(rng, i)
		if i < count then
			onFoot[i] = Loot.planOnFoot(rng)
		end
	end
	return stops, onFoot
end

local function countNamed(root: Instance, name: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == name then
			n += 1
		end
	end
	return n
end

describe("buildRoute with approved models", function()
	local route

	afterEach(function()
		if route then
			route.model:Destroy()
			route = nil
		end
	end)

	it("places the approved sleigh, hitches two reindeer and seats riders at Seat1-6", function()
		local rng = Random.new(1)
		local stops, onFoot = plans(rng)
		local sleigh = fakeSleigh()
		route = MapBuilder.buildRoute(
			workspace,
			91,
			rng,
			stops,
			onFoot,
			{ sleigh = sleigh, reindeer = fakeReindeer() }
		)

		expect(route.sleigh).toBe(sleigh)
		expect(sleigh.Parent).toBe(route.model)
		expect(sleigh:FindFirstChild("Reindeer1")).never.toBeNil()
		expect(sleigh:FindFirstChild("Reindeer2")).never.toBeNil()
		expect(#route.seatOffsets).toBe(6)
		expect((sleigh:GetPivot().Position - route.startDeck.Position).Magnitude).toBeLessThan(0.01)
		for _, d in sleigh:GetDescendants() do
			if d:IsA("BasePart") then
				expect(d.Anchored).toBe(true)
			end
			if d:IsA("Seat") then
				expect(d.Disabled).toBe(true)
			end
		end
	end)

	it("puts an approved cocoa machine at every stop, standing on the street, with a buy prompt", function()
		local rng = Random.new(2)
		local stops, onFoot = plans(rng)
		route = MapBuilder.buildRoute(workspace, 92, rng, stops, onFoot, { cocoa = fakeCocoa() })
		expect(countNamed(route.model, "CocoaMachine")).toBe(#stops)
		for _, stop in route.stops do
			if stop.cocoaPrompt then
				expect(stop.cocoaPrompt:IsA("ProximityPrompt")).toBe(true)
			end
		end
	end)

	it("copies StopDressing to every stop and RouteDressing once", function()
		local rng = Random.new(3)
		local stops, onFoot = plans(rng)
		route = MapBuilder.buildRoute(workspace, 93, rng, stops, onFoot, { dressing = fakeDressing() })
		expect(countNamed(route.model, "StopDressing")).toBe(#stops)
		expect(countNamed(route.model, "RouteDressing")).toBe(1)
	end)
end)
