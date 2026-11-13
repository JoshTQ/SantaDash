--[[
	Frozen Canal Town built in a real server and probed with real raycasts
	and pathfinding: nowhere a Santa needs to stand has a hole under it, the
	routes between them are walkable, and the build fits the phone budget.
]]

local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect, beforeAll, afterAll =
	JestGlobals.describe, JestGlobals.it, JestGlobals.expect, JestGlobals.beforeAll, JestGlobals.afterAll

local Config = require(ReplicatedStorage.Shared.Config)
local Maps = require(ReplicatedStorage.Shared.Maps)
local Loot = require(ServerStorage.Server.Loot)
local MapBuilder = require(ServerStorage.Server.MapBuilder)

local route
local folder: Folder

-- The first collidable thing straight below `from` (within `depth`).
local function floorUnder(from: Vector3, depth: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	params.RespectCanCollide = true
	return workspace:Raycast(from, Vector3.new(0, -depth, 0), params)
end

beforeAll(function()
	folder = Instance.new("Folder")
	folder.Name = "EngineTestMap"
	folder.Parent = workspace
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(42)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots, map.layout.StopSlots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	route = MapBuilder.buildRoute(folder, 9, rng, plans, onFoot, { map = map, yieldEach = task.wait })
end)

afterAll(function()
	folder:Destroy()
end)

describe("Frozen Canal Town in the engine", function()
	it("every Sleigh Stop has solid ground under the sleigh", function()
		for _, stop in route.stops do
			local hit = floorUnder(stop.deckCFrame.Position + Vector3.new(0, 8, 0), 20)
			expect(hit).never.toBeNil()
		end
	end)

	it("every present sits on something solid (no loot over the void)", function()
		local missing = {}
		local function check(present)
			local p = present.model:GetPivot().Position
			if not floorUnder(p + Vector3.new(0, 2, 0), 30) then
				table.insert(missing, present.model:GetFullName())
			end
		end
		for _, stop in route.stops do
			for _, present in stop.presents do
				check(present)
			end
		end
		for _, present in route.onFootPresents do
			check(present)
		end
		expect(#missing).toBe(0)
	end)

	it("the on-foot canal between stops has no holes", function()
		local layout = route.map.layout
		for i = 1, #route.stops - 1 do
			local a = (route.stops[i].origin * CFrame.new(0, 0, layout.FootPathZ)).Position
			local b = (route.stops[i + 1].origin * CFrame.new(0, 0, layout.FootPathZ)).Position
			local steps = math.floor((b - a).Magnitude / 10)
			for k = 0, steps do
				local p = a:Lerp(b, k / steps)
				local hit = floorUnder(p + Vector3.new(0, 10, 0), 30)
				if not hit then
					error(string.format("hole on the path from stop %d at %s", i, tostring(p)))
				end
			end
		end
	end)

	it("Krampus can path from his Lair to the Sleigh Stop (bridge or ice)", function()
		local finale = route.stops[#route.stops]
		local path = PathfindingService:CreatePath({
			AgentRadius = 3,
			AgentHeight = Config.Krampus.Height,
			AgentCanJump = false,
		})
		path:ComputeAsync(finale.krampusSpawn.Position, finale.deckCFrame.Position)
		expect(path.Status).toBe(Enum.PathStatus.Success)
	end, 30000)

	it("a Santa who misses the sleigh can walk to the hidden presents and the next stop", function()
		local from = route.stops[1].deckCFrame.Position + Vector3.new(0, 3, 0)
		local targets = {}
		for _, present in route.onFootPresents do
			table.insert(targets, present.model:GetPivot().Position)
		end
		table.insert(targets, route.stops[2].deckCFrame.Position + Vector3.new(0, 3, 0))
		local failed = {}
		for _, target in targets do
			local path =
				PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
			path:ComputeAsync(from, target)
			if path.Status ~= Enum.PathStatus.Success then
				table.insert(failed, tostring(target))
			end
		end
		expect(table.concat(failed, ", ")).toBe("")
	end, 90000)

	it("fits the phone budget, fully anchored, no shadow-casting lights", function()
		local parts, lights = 0, 0
		for _, d in route.model:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				expect(d.Anchored).toBe(true)
			elseif d:IsA("Light") then
				lights += 1
				expect(d.Shadows).toBe(false)
			end
		end
		expect(parts).toBeLessThan(9000)
		expect(lights).toBeLessThan(200)
	end)

	it("streaming is off, so clients always have the models the server points at", function()
		expect(workspace.StreamingEnabled).toBe(false)
	end)
end)
