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
