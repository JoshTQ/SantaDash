--[[
	A whole run with every approved model in ServerStorage.Assets (plain-part
	stand-ins that follow each model's contract), in a headless world, so the
	PivotTo / bounding-box paths that place them run too.
]]

local function kit(world)
	local engine = world.engine
	local New = engine.Instance.new

	local function part(parent, name, size, cf, className)
		local p = New(className or "Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Parent = parent
		return p
	end
	local function model(name)
		local m = New("Model")
		m.Name = name
		return m
	end
	local function rig(name)
		local m = model(name)
		m.PrimaryPart = part(m, "HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
		New("Humanoid").Parent = m
		return m
	end

	local assets = New("Folder")
	assets.Name = "Assets"

	local krampus = rig("Krampus")
	part(krampus, "Basket", Vector3.new(3, 2, 3), CFrame.new(0, 4, 1.5))
	krampus.Parent = assets
	rig("ElfA").Parent = assets
	rig("ElfD").Parent = assets

	local sleigh = model("Sleigh")
	sleigh.PrimaryPart = part(sleigh, "Body", Vector3.new(8, 3, 14), CFrame.new())
	part(sleigh, "Hitch", Vector3.new(1, 1, 1), CFrame.new(0, 0, -8))
	for i = 1, 6 do
		part(sleigh, "Seat" .. i, Vector3.new(2, 1, 2), CFrame.new((i % 2) * 3 - 1.5, 2, i * 2 - 7), "Seat")
	end
	sleigh.Parent = assets
	local deer = model("Reindeer")
	deer.PrimaryPart = part(deer, "Body", Vector3.new(2, 3, 5), CFrame.new())
	deer.Parent = assets

	local cocoa = model("CocoaMachine")
	cocoa.PrimaryPart = part(cocoa, "Body", Vector3.new(4, 7, 3), CFrame.new(0, 3.5, 0))
	local prompt = New("Attachment")
	prompt.Name = "BuyPrompt"
	prompt.Parent = cocoa.PrimaryPart
	cocoa.Parent = assets

	local house = model("House")
	local at = CFrame.new(500, 50, -300)
	house.PrimaryPart = part(house, "Floor", Vector3.new(24, 1, 24), at)
	house:SetAttribute("Style", "alpine")
	part(house, "TypeSign", Vector3.new(4, 2, 0.5), at * CFrame.new(0, 16, 0))
	part(house, "ChimneyTop", Vector3.new(3, 1, 3), at * CFrame.new(6, 18, 6))
	part(house, "Fireplace", Vector3.new(5, 4, 2), at * CFrame.new(0, 2.5, 10))
	part(house, "Wardrobe", Vector3.new(3, 8, 4), at * CFrame.new(-9, 4.5, 4))
	local front = model("FrontDoor")
	front.Parent = house
	part(front, "Door", Vector3.new(4, 8, 0.5), at * CFrame.new(0, 4.5, -12))
	for i = 1, 3 do
		-- Spawn points as Attachments on the floor.
		local spawn = New("Attachment")
		spawn.Name = "PresentSpawn" .. i
		spawn.CFrame = CFrame.new(i * 3 - 6, 0.6, 0)
		spawn.Parent = house.PrimaryPart
	end
	house.Parent = assets

	local lair = model("KrampusLair")
	local la = CFrame.new(-50, 20, 80)
	lair.PrimaryPart = part(lair, "Floor", Vector3.new(44, 1, 44), la)
	part(lair, "ListPedestal", Vector3.new(3, 3, 3), la * CFrame.new(0, 2, 10))
	part(lair, "KrampusSpawn", Vector3.new(2, 0.2, 2), la * CFrame.new(0, 0.6, 15))
	part(lair, "HideSpot1", Vector3.new(4, 4, 4), la * CFrame.new(-15, 2.5, 0))
	lair.Parent = assets

	local vault = model("VaultDoor")
	vault.PrimaryPart = part(vault, "Frame", Vector3.new(10, 13, 1), CFrame.new(0, 100, 0))
	part(vault, "Door", Vector3.new(8, 12, 0.6), CFrame.new(0, 99.5, 0))
	vault.Parent = assets

	local present = model("Present")
	present.PrimaryPart = part(present, "Box", Vector3.new(2, 2, 2), CFrame.new())
	part(present, "Ribbon", Vector3.new(2.1, 0.3, 2.1), CFrame.new())
	part(present, "Bow", Vector3.new(1, 1, 1), CFrame.new(0, 1.2, 0))
	present.Parent = assets
	local list = model("NaughtyList")
	list.PrimaryPart = part(list, "Book", Vector3.new(3, 1, 4), CFrame.new())
	list.Parent = assets

	assets.Parent = engine:service("ServerStorage")

	-- Map set dressing for the default map and every map in the rotation.
	local maps = New("Folder")
	maps.Name = "Maps"
	local dressing = model("TestDressing")
	local stopDressing = model("StopDressing")
	stopDressing.PrimaryPart = part(stopDressing, "Lamp", Vector3.new(1, 8, 1), CFrame.new())
	stopDressing.Parent = dressing
	local routeDressing = model("RouteDressing")
	routeDressing.PrimaryPart = part(routeDressing, "Arch", Vector3.new(20, 10, 1), CFrame.new())
	routeDressing.Parent = dressing
	dressing.Parent = maps
	maps.Parent = engine:service("ServerStorage")
	local Maps = world.load("ReplicatedStorage.Shared.Maps")
	Maps.get().dressing = "TestDressing"
	for _, id in Maps.Rotation do -- the run picks from the rotation
		Maps.get(id).dressing = "TestDressing"
	end
end

local function countNamed(root, name)
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == name then
			n += 1
		end
	end
	return n
end

describe("a run with every approved model", function()
	it("builds from the approved models and plays through Krampus's Lair", function()
		local world = headless()
		local engine = world.engine
		kit(world)
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local Run = world.load("ServerScriptService.Server.Run")
		local santa = engine:addPlayer("Solo")
		world.run(function()
			local finished = false
			local run = Run.new(1, { santa }, function()
				finished = true
			end)
			local model = run.route.model
			local stops = #run.route.stops

			expect(run.route.sleigh.Name).toBe("Sleigh")
			expect(run.route.sleigh:FindFirstChild("Reindeer1")).never.toBeNil()
			expect(#run.route.seatOffsets).toBe(6)
			expect(countNamed(model, "CocoaMachine")).toBe(stops)
			expect(countNamed(model, "StopDressing")).toBe(stops)
			expect(countNamed(model, "RouteDressing")).toBe(1)
			expect(#run.route.stops[1].doors).toBeGreaterThan(0)

			run:start()
			while run.stopIndex < 1 do
				world.wait(0.5)
			end
			world.wait(1)
			for _, elf in run.elves do
				expect(elf.body.model.Name).toBe(elf.variant) -- the approved elf, not the stand-in
			end
			local door = run.route.stops[1].doors[1]
			expect(door.open).toBe(true) -- doors start open
			expect(door.door.CanCollide).toBe(false)
			engine.trigger(door.prompt, santa)
			expect(door.open).toBe(false)
			expect(door.door.CanCollide).toBe(true)

			while not run.krampus do
				world.wait(0.5)
			end
			expect(run.krampus.body.model.Name).toBe("Krampus")
			if run.stopIndex == stops then
				-- He wakes in his Lair: the bells light up (LairAnimator.client).
				local lair = model:FindFirstChild("LairHouse", true)
				expect(lair:GetAttribute("BellsAt")).never.toBeNil()
			end
			while not finished do
				world.wait(1)
			end
		end)
	end)

	it("falls back to the stand-in Krampus when the approved one is missing its Basket", function()
		local world = headless()
		local engine = world.engine
		kit(world)
		engine:service("ServerStorage").Assets.Krampus.Basket:Destroy()
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local Run = world.load("ServerScriptService.Server.Run")
		local santa = engine:addPlayer("Solo")
		world.run(function()
			local run = Run.new(1, { santa }, function() end)
			run:start()
			while not run.krampus do
				world.wait(0.5)
			end
			expect(run.krampus.body.model.Name).toBe("KrampusStandIn")
			run.ended = true
		end)
		local warned = false
		for _, w in engine.warnings do
			warned = warned or string.find(w, "Basket", 1, true) ~= nil
		end
		expect(warned).toBe(true)
	end)
end)
