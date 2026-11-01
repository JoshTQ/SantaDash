-- Builds real Instances (Lune's Roblox library) from real plans and checks the
-- greybox layout: counts, prompts, sleigh placement, no overlapping houses.
local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")

local function buildRoute(seed)
	local rng = Random.new(seed)
	local plans, onFoot = {}, {}
	for i = 1, #Config.Run.StopKinds do
		plans[i] = Loot.planStop(rng, i)
		if i < #Config.Run.StopKinds then
			onFoot[i] = Loot.planOnFoot(rng)
		end
	end
	local parent = newFolder()
	return MapBuilder.buildRoute(parent, 1, rng, plans, onFoot), plans, parent
end

local function countClass(root, className)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.ClassName == className then
			n += 1
		end
	end
	return n
end

test("hub has a spawn, a Quick Join pad and returns the spawn point", function()
	local hub = MapBuilder.buildHub(newFolder())
	expect(countClass(hub.model, "SpawnLocation")).toBe(1)
	expect(hub.quickJoinPad.Name).toBe("QuickJoinPad")
	expect(hub.spawn).toBe(Config.Map.HubSpawn)
end)

test("lobby has three bays with a gate, stats board and board zone each", function()
	local hub = MapBuilder.buildHub(newFolder())
	expect(#hub.bays).toBe(#Config.LobbyMap.Bays)
	local kinds = {}
	for i, bay in hub.bays do
		local cfg = Config.LobbyMap.Bays[i]
		kinds[bay.kind] = true
		expect(bay.kind).toBe(cfg.Kind)
		expect(bay.zone.Parent ~= nil).toBeTruthy()
		expect(bay.gate.CanCollide).toBeTruthy()
		expect(#bay.arms > 0).toBeTruthy()
		expect(bay.stats.status ~= nil).toBeTruthy()
	end
	expect(kinds.Public and kinds.Party and kinds.Private).toBeTruthy()
	expect(hub.quickJoinPad).toBe(hub.bays[1].zone)
end)

test("lobby spawn sits inside the workshop", function()
	local w = Config.LobbyMap.Workshop
	local p = Config.Map.HubSpawn.Position
	expect(p.X > w.X0 and p.X < w.X1).toBeTruthy()
	expect(p.Z > w.Z0 and p.Z < w.Z1).toBeTruthy()
end)

test("route has one built stop per planned stop and a sleigh", function()
	local route, plans, parent = buildRoute(1)
	expect(#route.stops).toBe(#plans)
	expect(route.model.Parent).toBe(parent)
	expect(route.sleigh.PrimaryPart ~= nil).toBeTruthy()
end)

test("every planned present is built with a prompt", function()
	for seed = 1, 5 do
		local route, plans = buildRoute(seed)
		for i, stop in route.stops do
			local planned = 0
			for _, house in plans[i].houses do
				planned += #house.presents
			end
			expect(#stop.presents).toBe(planned)
			for _, present in stop.presents do
				expect(present.prompt.ClassName).toBe("ProximityPrompt")
				expect(present.prompt.Parent ~= nil).toBeTruthy()
			end
		end
		expect(#route.onFootPresents).toBe(Config.Presents.OnFootPresents * (#plans - 1))
	end
end)

test("street stops have a paid vault door; the finale has the Naughty List instead", function()
	local route = buildRoute(2)
	for _, stop in route.stops do
		if stop.plan.kindName == "Finale" then
			expect(stop.vaultPrompt).toBe(nil)
			expect(stop.presents[#stop.presents].model.Name).toBe("NaughtyList")
		else
			expect(stop.vaultPrompt.Enabled).toBeTruthy()
			expect(stop.vaultDoor.CanCollide).toBeTruthy()
		end
	end
end)

test("hiding spots and chimneys match the plan", function()
	local route = buildRoute(3)
	for _, stop in route.stops do
		local spots, chimneys = 0, 0
		for _, house in stop.plan.houses do
			spots += house.hideSpots
			chimneys += if house.chimney then 1 else 0
		end
		expect(#stop.hideSpots).toBe(spots)
		expect(#stop.chimneys).toBe(chimneys)
	end
end)

test("the sleigh lands on top of the landing roof and a rider on the deck counts as aboard", function()
	local route = buildRoute(4)
	for _, stop in route.stops do
		local deck = stop.deckCFrame
		local roofTop = 1 + Config.Map.HouseSize.Y + 1
		expect(deck.Position.Y - roofTop).toBeGreaterThan(1.29) -- runners clear the roof
		expect(MapBuilder.isAboard(deck, (deck * MapBuilder.SeatOffsets[1]).Position)).toBeTruthy()
		expect(MapBuilder.isAboard(deck, deck.Position + Vector3.new(0, 0, 30))).toBeFalsy()
	end
end)

test("houses on a street never overlap", function()
	for seed = 1, 5 do
		local route = buildRoute(seed)
		for _, stopModel in route.model:GetChildren() do
			local floors = {}
			for _, house in stopModel:GetChildren() do
				local floor = house:IsA("Model") and house:FindFirstChild("Floor")
				if floor then
					table.insert(floors, floor)
				end
			end
			for i = 1, #floors do
				for j = i + 1, #floors do
					local a, b = floors[i], floors[j]
					local gap = (a.CFrame.Position - b.CFrame.Position)
					local overlapX = math.abs(gap.X) < (a.Size.X + b.Size.X) / 2
					local overlapZ = math.abs(gap.Z) < (a.Size.Z + b.Size.Z) / 2
					expect(overlapX and overlapZ).toBeFalsy()
				end
			end
		end
	end
end)

test("everything in a route is anchored (nothing falls over)", function()
	local route = buildRoute(5)
	for _, d in route.model:GetDescendants() do
		if d:IsA("BasePart") then
			expect(d.Anchored).toBeTruthy()
		end
	end
end)

test("Krampus stand-in: humanoid rig, basket with bell prompt, about Config height", function()
	local body = MapBuilder.buildKrampus(newFolder(), CFrame.new(0, 5.5, 0))
	expect(body.humanoid.RequiresNeck).toBeFalsy()
	expect(body.root.Name).toBe("HumanoidRootPart")
	expect(body.bellPrompt.Parent).toBe(body.basket)
	local top, bottom = -math.huge, math.huge
	for _, part in body.model:GetChildren() do
		if part:IsA("BasePart") and part ~= body.root then
			top = math.max(top, part.CFrame.Position.Y + part.Size.Y / 2)
			bottom = math.min(bottom, part.CFrame.Position.Y - part.Size.Y / 2)
		end
	end
	expect(bottom).toBeNear(0, 0.01) -- feet on the floor
	expect(top - bottom).toBeNear(Config.Krampus.Height, 1)
	-- The basket is on his back, where the bells must be rung from.
	expect(body.root.CFrame:PointToObjectSpace(body.basket.CFrame.Position).Z).toBeGreaterThan(0)
end)

test("Krampus spawns in the open on streets and inside his Lair in the finale", function()
	for seed = 1, 5 do
		local route = buildRoute(seed)
		for i, stop in route.stops do
			local spawn = stop.krampusSpawn.Position
			local insideAny = nil
			for _, house in route.model:FindFirstChild("Stop" .. i .. "_" .. stop.plan.kindName):GetChildren() do
				local floor = house:IsA("Model") and house:FindFirstChild("Floor")
				if floor then
					local rel = floor.CFrame:PointToObjectSpace(spawn)
					if math.abs(rel.X) < floor.Size.X / 2 and math.abs(rel.Z) < floor.Size.Z / 2 then
						insideAny = house.Name
					end
				end
			end
			if stop.plan.kindName == "Finale" then
				expect(insideAny).toBe("LairHouse")
			else
				expect(insideAny).toBe(nil)
			end
		end
	end
end)

test("greybox routes use the six default sleigh seats", function()
	local route = buildRoute(4)
	expect(#route.seatOffsets).toBe(6)
	expect(route.seatOffsets).toBe(MapBuilder.SeatOffsets)
end)

test("elf stand-ins have a Humanoid, a root and their design's colours", function()
	for _, variant in Config.ElfBots.Variants do
		local elf = MapBuilder.buildElf(newFolder(), CFrame.new(0, 5, 0), variant)
		expect(elf.humanoid.ClassName).toBe("Humanoid")
		expect(elf.root.Name).toBe("HumanoidRootPart")
		expect(elf.humanoid.WalkSpeed).toBe(Config.ElfBots.WalkSpeed)
		expect(elf.model.Name).toBe(variant .. "StandIn")
	end
end)

test("only vault presents are marked as behind the vault door", function()
	local route = buildRoute(5)
	for _, stop in route.stops do
		local inVault = 0
		for _, present in stop.presents do
			if present.inVault then
				inVault += 1
			end
		end
		expect(inVault).toBe(if stop.vaultDoor then Config.Houses.Types.Vault.Presents else 0)
	end
end)
