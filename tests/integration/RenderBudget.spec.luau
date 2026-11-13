--[[
	Render and physics budgets for the built maps (phones feel every part):
	Frozen Canal Town is ~8,650 parts. These fail loudly if a change blows
	the budget or undoes Parts.settle. What a phone actually draws at each
	stop (level of detail, Shared.Detail) is checked in Detail.spec.
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local LobbyMap = load("ServerScriptService.Server.LobbyMap")
local Maps = load("ReplicatedStorage.Shared.Maps")
local Parts = load("ServerScriptService.Server.Parts")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

-- Per route (one crew's three stops and the paths between).
-- Prompts counts the ones live when the route is built (what a phone checks
-- each frame). Hidden ones (mansion gifts, secret-room gifts) wake up later,
-- so they only count towards AllPrompts.
local BUDGET = { Parts = 9000, Lights = 200, Prompts = 150, AllPrompts = 200, Billboards = 120 }

local function build(seed)
	local map = Maps.get("FrozenCanal")
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i, map.layout.Slots, map.layout.StopSlots)
		onFoot[i] = if i < #Config.Run.StopKinds then Loot.planOnFoot(rng) else nil
	end
	return MapBuilder.buildRoute(newFolder(), 1, rng, plans, onFoot, { map = map })
end

local function census(root)
	local c = { parts = 0, lights = 0, prompts = 0, allPrompts = 0, billboards = 0, list = {} }
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			c.parts += 1
			table.insert(c.list, d)
		elseif d:IsA("Light") then
			c.lights += 1
		elseif d:IsA("ProximityPrompt") then
			c.allPrompts += 1
			if d.Enabled then
				c.prompts += 1
			end
		elseif d:IsA("BillboardGui") then
			c.billboards += 1
		end
	end
	return c
end

local route = build(11)
local c = census(route.model)

test("a route stays inside the phone budget", function()
	expect(c.parts).toBeLessThan(BUDGET.Parts)
	expect(c.lights).toBeLessThan(BUDGET.Lights)
	expect(c.prompts).toBeLessThan(BUDGET.Prompts)
	expect(c.allPrompts).toBeLessThan(BUDGET.AllPrompts)
	expect(c.billboards).toBeLessThan(BUDGET.Billboards)
end)

test("the map is fully anchored: nothing falls, nothing simulates", function()
	for _, p in c.list do
		if not p.Anchored then
			error(p:GetFullName() .. " is unanchored")
		end
	end
end)

test("no light casts shadows (each one re-renders the scene on phones)", function()
	for _, d in route.model:GetDescendants() do
		if d:IsA("Light") then
			expect(d.Shadows).toBe(false)
		end
	end
end)

test("dressing that can't be walked on can't be touched or ray-hit either", function()
	for _, p in c.list do
		if not p.CanCollide and not p:GetAttribute("Trigger") then
			if p.CanTouch or p.CanQuery then
				error(p:GetFullName() .. " is non-colliding but still touchable")
			end
		end
	end
end)

test("boost hoops keep Touched", function()
	local hoops = 0
	for _, p in c.list do
		if p.Name == "BoostHoop" then
			hoops += 1
			expect(p.CanTouch).toBe(true)
		end
	end
	expect(hoops).toBeGreaterThan(0)
end)

test("neon and tiny parts never cast shadows", function()
	for _, p in c.list do
		local tiny = math.max(p.Size.X, p.Size.Y, p.Size.Z) <= Parts.TinyShadow
		if p.Material == Enum.Material.Neon or tiny then
			if p.CastShadow then
				error(p:GetFullName() .. " casts a shadow")
			end
		end
	end
end)

test("ice, water and the ground still collide and are touchable", function()
	for _, stop in route.stops do
		for _, zone in stop.canal.iceZones do
			expect(zone.CanCollide).toBe(true)
			expect(zone.CanQuery).toBe(true)
		end
	end
	local ground = route.model:FindFirstChild("Ground")
	expect(ground.CanCollide and ground.CanTouch and ground.CanQuery).toBe(true)
end)

test("nothing is buried out of sight or floating absurdly high", function()
	for _, p in c.list do
		-- Sunk snow hills reach deep, so check the top of each part.
		local top = p.CFrame.Position.Y + p.Size.Y / 2
		if top < -20 or top > 400 then
			error(p:GetFullName() .. " tops out at " .. top)
		end
	end
end)

test("settle reports what it changed and is safe to run twice", function()
	local again = Parts.settle(route.model)
	expect(again).toBe(0)
end)

test("the lobby is settled too", function()
	local hub = LobbyMap.build(newFolder())
	local lobby = census(hub.model)
	print(string.format("  [budget] lobby parts %d, lights %d", lobby.parts, lobby.lights))
	expect(lobby.parts).toBeLessThan(Config.LobbyMap.PartBudget)
	expect(lobby.lights).toBeLessThan(40)
	for _, p in lobby.list do
		if not p.CanCollide and (p.CanTouch or p.CanQuery) then
			error(p:GetFullName() .. " is non-colliding but still touchable")
		end
		expect(p.Anchored).toBe(true)
	end
end)

test("streaming is pinned off in every place build (server-sent model refs need it)", function()
	for _, file in { "default.project.json", "deploy.project.json" } do
		local project = serde.decode("json", fs.readFile(file))
		local ws = project.tree.Workspace
		expect(ws ~= nil and ws["$properties"] ~= nil).toBe(true)
		expect(ws["$properties"].StreamingEnabled).toBe(false)
	end
end)

test(
	"Future lighting in every place build (Josh, 4 Nov 2026; Roblox scales it down on low-end phones)",
	function()
		for _, file in { "default.project.json", "deploy.project.json" } do
			local project = serde.decode("json", fs.readFile(file))
			expect(project.tree.Lighting["$properties"].Technology).toBe("Future")
		end
	end
)
