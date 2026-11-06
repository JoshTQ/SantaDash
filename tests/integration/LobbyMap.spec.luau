-- Builds the Sleigh Station lobby as real Instances and checks its layout.
local Config = load("ReplicatedStorage.Shared.Config")
local LobbyMap = load("ServerScriptService.Server.LobbyMap")

local function countClass(root, className)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.ClassName == className then
			n += 1
		end
	end
	return n
end

test("lobby has one spawn and returns the spawn point", function()
	local hub = LobbyMap.build(newFolder())
	expect(countClass(hub.model, "SpawnLocation")).toBe(1)
	expect(hub.spawn).toBe(Config.Map.HubSpawn)
end)

test("lobby has three bays with a gate, stats board and board zone each", function()
	local hub = LobbyMap.build(newFolder())
	expect(#hub.bays).toBe(#Config.LobbyMap.Bays)
	local kinds = {}
	for i, bay in hub.bays do
		local cfg = Config.LobbyMap.Bays[i]
		kinds[bay.kind] = true
		expect(bay.kind).toBe(cfg.Kind)
		expect(bay.zone.Name).toBe(cfg.Kind .. "Zone")
		expect(bay.gate.CanCollide).toBeTruthy()
		expect(#bay.arms > 0).toBeTruthy()
		expect(bay.stats.status ~= nil).toBeTruthy()
		expect(bay.stats.mode.Text ~= "").toBeTruthy()
	end
	expect(kinds.Public and kinds.Party and kinds.Private).toBeTruthy()
end)

test("lobby spawn sits inside the workshop", function()
	local w = Config.LobbyMap.Workshop
	local p = Config.Map.HubSpawn.Position
	expect(p.X > w.X0 and p.X < w.X1).toBeTruthy()
	expect(p.Z > w.Z0 and p.Z < w.Z1).toBeTruthy()
end)

-- Josh's playtest (6 Nov 2026): the bay boards and Top Crews board showed
-- their blank backs to players walking up from the workshop.
test("boards and podium face the yard (-Z), where players walk up", function()
	local hub = LobbyMap.build(newFolder())
	for _, bay in hub.bays do
		local gui = bay.stats.title.Parent.Parent
		expect(gui.ClassName).toBe("SurfaceGui")
		expect(gui.Face).toBe(Enum.NormalId.Front)
		expect(gui.Parent.CFrame.LookVector.Z < -0.99).toBeTruthy()
	end
	local found = { TopCrewsBoard = 0, PodiumBadge = 0 }
	for _, d in hub.model:GetDescendants() do
		if found[d.Name] then
			found[d.Name] += 1
			expect(d.CFrame.LookVector.Z < -0.99).toBeTruthy()
			expect(d:FindFirstChildOfClass("SurfaceGui").Face).toBe(Enum.NormalId.Front)
		end
	end
	expect(found.TopCrewsBoard).toBe(1)
	expect(found.PodiumBadge).toBe(3)
end)

-- Josh's playtest (6 Nov 2026): Santas couldn't walk under the boards over
-- the gates. A Roblox character is about 5 studs tall and jumps ~7.
test("players walk and jump under the boards over the gates", function()
	local hub = LobbyMap.build(newFolder())
	local floorH = Config.LobbyMap.FloorHeight
	local canopy
	for _, d in hub.model:GetDescendants() do
		if d.Name == "Canopy" then
			canopy = d
		end
	end
	local canopyBottom = canopy.CFrame.Position.Y - canopy.Size.Y / 2
	local boards = 0
	for _, d in hub.model:GetDescendants() do
		if d.Name == "StatsBoard" then
			boards += 1
			local bottom = d.CFrame.Position.Y - d.Size.Y / 2
			expect(bottom - floorH >= 6.5).toBeTruthy()
			expect(d.CFrame.Position.Y + d.Size.Y / 2 <= canopyBottom).toBeTruthy()
		end
	end
	expect(boards).toBe(#Config.LobbyMap.Bays)
end)

test("scenery closes the yard in: forest, lights and falling snow", function()
	local hub = LobbyMap.build(newFolder())
	local scenery = hub.model:FindFirstChild("Scenery")
	expect(scenery ~= nil).toBeTruthy()
	expect(scenery:GetAttribute("Trees") > 40).toBeTruthy()
	expect(scenery:FindFirstChild("Snowfall"):FindFirstChildOfClass("ParticleEmitter") ~= nil).toBeTruthy()
	local S, y = Config.LobbyMap.Scenery, Config.LobbyMap.Yard
	for _, d in scenery:GetChildren() do
		if d.Name == "PineTrunk" and not d.CanCollide then
			local p = d.CFrame.Position
			local inYard = p.X > y.X0 and p.X < y.X1 and p.Z > y.Z0 and p.Z < y.Z1
			expect(inYard).toBe(false)
			-- the sleighs' flight lane stays clear
			expect(math.abs(p.Z - Config.LobbyMap.SleighZ) >= S.FlightGap).toBeTruthy()
		end
	end
end)
