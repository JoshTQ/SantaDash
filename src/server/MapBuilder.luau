--[[
	Builds the greybox world from plain Parts: the Sleigh Station hub and one
	route (4 streets) per running crew. No models or meshes: art only goes in
	after Josh approves it.

	MapBuilder owns geometry and simple movement (chimneys). Run owns the rules
	(grabs, buys, noise), wired through the prompts returned here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Loot = require(script.Parent.Loot)

local MapBuilder = {}

local SNOW = Color3.fromRGB(235, 240, 250)
local ROAD = Color3.fromRGB(70, 74, 86)
local WALL = Color3.fromRGB(190, 185, 175)
local SLEIGH_RED = Color3.fromRGB(200, 30, 40)
local GOLD = Color3.fromRGB(255, 200, 60)
local PRESENT_COLOURS = {
	Color3.fromRGB(230, 50, 60),
	Color3.fromRGB(40, 170, 90),
	Color3.fromRGB(60, 120, 230),
	Color3.fromRGB(170, 80, 220),
	Color3.fromRGB(255, 150, 40),
}

local DOOR_WIDTH = 8
local DOOR_HEIGHT = 9
local WALL_THICKNESS = 1

-- Six rider spots on the sleigh deck, relative to the deck centre.
MapBuilder.SeatOffsets = {
	CFrame.new(-2.5, 3.5, -4),
	CFrame.new(2.5, 3.5, -4),
	CFrame.new(-2.5, 3.5, 0),
	CFrame.new(2.5, 3.5, 0),
	CFrame.new(-2.5, 3.5, 4),
	CFrame.new(2.5, 3.5, 4),
}

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function addPrompt(
	parent: Instance,
	actionText: string,
	objectText: string,
	hold: number?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function addLabel(part: BasePart, text: string, color: Color3, offsetY: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 300
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Parent = gui
	gui.Parent = part
end

local function teleportCharacter(player: Player, target: CFrame)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		(root :: BasePart).AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(target)
	end
end

----------------------------------------------------------------------------
-- Sleigh
----------------------------------------------------------------------------

-- The sleigh's deck centre is the model's pivot.
function MapBuilder.buildSleigh(parent: Instance, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Sleigh"
	local deck = newPart(model, "Deck", Vector3.new(10, 1, 14), cframe, SLEIGH_RED)
	newPart(model, "SideL", Vector3.new(1, 3, 14), cframe * CFrame.new(-5.5, 1, 0), SLEIGH_RED)
	newPart(model, "SideR", Vector3.new(1, 3, 14), cframe * CFrame.new(5.5, 1, 0), SLEIGH_RED)
	newPart(model, "Front", Vector3.new(12, 5, 1), cframe * CFrame.new(0, 2, -7.5), SLEIGH_RED)
	newPart(model, "Back", Vector3.new(12, 2, 1), cframe * CFrame.new(0, 1, 7.5), SLEIGH_RED)
	newPart(
		model,
		"RunnerL",
		Vector3.new(1, 0.6, 16),
		cframe * CFrame.new(-4, -1, 0),
		GOLD,
		Enum.Material.Metal
	)
	newPart(
		model,
		"RunnerR",
		Vector3.new(1, 0.6, 16),
		cframe * CFrame.new(4, -1, 0),
		GOLD,
		Enum.Material.Metal
	)
	addLabel(deck, "SLEIGH", Color3.new(1, 1, 1), 9)
	model.PrimaryPart = deck
	model.Parent = parent
	return model
end

-- True if a position is standing on (or in) the sleigh at deckCFrame.
function MapBuilder.isAboard(deckCFrame: CFrame, position: Vector3): boolean
	local rel = deckCFrame:PointToObjectSpace(position)
	return math.abs(rel.X) <= 6.5 and math.abs(rel.Z) <= 8.5 and rel.Y >= -1 and rel.Y <= 10
end

----------------------------------------------------------------------------
-- Hub
----------------------------------------------------------------------------

function MapBuilder.buildHub(): { model: Model, quickJoinPad: BasePart }
	local model = Instance.new("Model")
	model.Name = "SleighStation"

	newPart(model, "Floor", Vector3.new(220, 2, 220), CFrame.new(0, -1, 0), SNOW, Enum.Material.Snow)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, -50)
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Parent = model

	local pad = newPart(
		model,
		"QuickJoinPad",
		Vector3.new(18, 1, 18),
		CFrame.new(0, 0.5, 20),
		Color3.fromRGB(60, 220, 110),
		Enum.Material.Neon
	)
	addLabel(pad, "QUICK JOIN\nstep on to board", Color3.new(1, 1, 1), 6)

	-- Decorative departure sleigh so the hub reads as a station.
	MapBuilder.buildSleigh(model, CFrame.new(0, 2, 50) * CFrame.Angles(0, math.pi, 0))

	local sign =
		newPart(model, "Sign", Vector3.new(40, 10, 1), CFrame.new(0, 12, 75), Color3.fromRGB(40, 50, 80))
	addLabel(sign, "SLEIGH STATION", GOLD, 0)

	model.Parent = workspace
	return { model = model, quickJoinPad = pad }
end

----------------------------------------------------------------------------
-- Houses
----------------------------------------------------------------------------

export type House = {
	model: Model,
	cframe: CFrame,
	size: Vector3,
	typeName: string,
	ring: string,
	light: PointLight,
	door: BasePart?,
}

-- cframe: centre of the house on the ground, LookVector pointing out of the front door.
local function buildHouse(
	parent: Instance,
	name: string,
	cframe: CFrame,
	size: Vector3,
	roofColor: Color3,
	labelText: string,
	opts: { locked: boolean?, chimney: boolean? }
): House
	local model = Instance.new("Model")
	model.Name = name
	local w, h, d = size.X, size.Y, size.Z
	local t = WALL_THICKNESS
	local wallY = 1 + h / 2

	newPart(
		model,
		"Floor",
		Vector3.new(w, 1, d),
		cframe * CFrame.new(0, 0.5, 0),
		Color3.fromRGB(150, 110, 80)
	)
	newPart(model, "WallBack", Vector3.new(w, h, t), cframe * CFrame.new(0, wallY, d / 2 - t / 2), WALL)
	newPart(model, "WallL", Vector3.new(t, h, d), cframe * CFrame.new(-w / 2 + t / 2, wallY, 0), WALL)
	newPart(model, "WallR", Vector3.new(t, h, d), cframe * CFrame.new(w / 2 - t / 2, wallY, 0), WALL)

	-- Front wall with a doorway (front = local -Z = LookVector).
	local segW = (w - DOOR_WIDTH) / 2
	local frontZ = -d / 2 + t / 2
	newPart(
		model,
		"FrontL",
		Vector3.new(segW, h, t),
		cframe * CFrame.new(-(DOOR_WIDTH + segW) / 2, wallY, frontZ),
		WALL
	)
	newPart(
		model,
		"FrontR",
		Vector3.new(segW, h, t),
		cframe * CFrame.new((DOOR_WIDTH + segW) / 2, wallY, frontZ),
		WALL
	)
	newPart(
		model,
		"Lintel",
		Vector3.new(DOOR_WIDTH, h - DOOR_HEIGHT, t),
		cframe * CFrame.new(0, 1 + DOOR_HEIGHT + (h - DOOR_HEIGHT) / 2, frontZ),
		WALL
	)

	local roof =
		newPart(model, "Roof", Vector3.new(w + 2, 1, d + 2), cframe * CFrame.new(0, 1.5 + h, 0), roofColor)
	addLabel(roof, labelText, roofColor, 10)

	local lamp =
		newPart(model, "Lamp", Vector3.new(1, 1, 1), cframe * CFrame.new(0, h - 1, 0), Color3.new(1, 1, 1))
	lamp.Transparency = 1
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = math.max(w, d)
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Enabled = false
	light.Parent = lamp

	local door: BasePart? = nil
	if opts.locked then
		local vaultDoor = newPart(
			model,
			"VaultDoor",
			Vector3.new(DOOR_WIDTH, DOOR_HEIGHT, t + 0.4),
			cframe * CFrame.new(0, 1 + DOOR_HEIGHT / 2, frontZ),
			GOLD,
			Enum.Material.Neon
		)
		door = vaultDoor
	end

	if opts.chimney ~= false then
		local roofTop = 2 + h
		local chimney = newPart(
			model,
			"Chimney",
			Vector3.new(4, 6, 4),
			cframe * CFrame.new(w / 4, roofTop + 3, d / 4),
			Color3.fromRGB(150, 60, 50),
			Enum.Material.Brick
		)
		local fireplace = newPart(
			model,
			"Fireplace",
			Vector3.new(6, 4, 2),
			cframe * CFrame.new(0, 3, d / 2 - 2),
			Color3.fromRGB(120, 50, 40),
			Enum.Material.Brick
		)
		local inside = cframe * CFrame.new(0, 4, d / 2 - 6)
		local onRoof = cframe * CFrame.new(-w / 4, roofTop + 3, 0)
		addPrompt(chimney, "Slide down", "Chimney").Triggered:Connect(function(player)
			teleportCharacter(player, inside)
		end)
		addPrompt(fireplace, "Climb up", "Chimney").Triggered:Connect(function(player)
			teleportCharacter(player, onRoof)
		end)

		-- Ladder up the side so the roof (and the sleigh) can be reached from the street.
		local ladder = Instance.new("TrussPart")
		ladder.Name = "Ladder"
		ladder.Anchored = true
		ladder.Size = Vector3.new(2, roofTop, 2)
		ladder.CFrame = cframe * CFrame.new(w / 2 + 1, roofTop / 2, -d / 4)
		ladder.Color = Color3.fromRGB(110, 80, 60)
		ladder.Parent = model
	end

	model.Parent = parent
	return {
		model = model,
		cframe = cframe,
		size = size,
		typeName = "",
		ring = "",
		light = light,
		door = door,
	}
end

----------------------------------------------------------------------------
-- Presents
----------------------------------------------------------------------------

export type Present = {
	model: Model,
	prompt: ProximityPrompt,
	value: number,
	ringMultiplier: number,
	threats: number,
	kind: string, -- "Present" | "Vault" | "OnFoot" | "NaughtyList"
}

local function buildPresent(
	parent: Instance,
	rng: Random,
	position: Vector3,
	size: number,
	value: number
): Model
	local model = Instance.new("Model")
	model.Name = "Present"
	local edge = 1.6 * size
	local cf = CFrame.new(position + Vector3.new(0, edge / 2, 0))
		* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local colour = PRESENT_COLOURS[rng:NextInteger(1, #PRESENT_COLOURS)]
	local box = newPart(model, "Box", Vector3.one * edge, cf, colour)
	newPart(model, "RibbonA", Vector3.new(edge + 0.05, edge + 0.05, edge * 0.18), cf, GOLD).CanCollide = false
	newPart(model, "RibbonB", Vector3.new(edge * 0.18, edge + 0.05, edge + 0.05), cf, GOLD).CanCollide = false
	model.PrimaryPart = box
	model:SetAttribute("Value", value)
	model.Parent = parent
	return model
end

local function makePresent(
	parent: Instance,
	rng: Random,
	position: Vector3,
	size: number,
	ringMultiplier: number,
	threats: number,
	kind: string
): Present
	local value = Loot.presentValue(size, ringMultiplier, threats)
	local model = buildPresent(parent, rng, position, size, value)
	local prompt =
		addPrompt(model.PrimaryPart :: BasePart, "Grab", "Present", Config.Presents.GrabHoldSeconds)
	return {
		model = model,
		prompt = prompt,
		value = value,
		ringMultiplier = ringMultiplier,
		threats = threats,
		kind = kind,
	}
end

local function randomFloorPoint(rng: Random, house: House): Vector3
	local w, d = house.size.X, house.size.Z
	local x = rng:NextNumber(-w / 2 + 4, w / 2 - 4)
	local z = rng:NextNumber(-d / 2 + 4, d / 2 - 8) -- keep clear of the fireplace
	return (house.cframe * CFrame.new(x, 1, z)).Position
end

----------------------------------------------------------------------------
-- Streets and routes
----------------------------------------------------------------------------

export type Stop = {
	index: number,
	isFinale: boolean,
	origin: CFrame,
	deckCFrame: CFrame, -- where the sleigh deck sits when landed
	houses: { House },
	presents: { Present },
	cocoaPrompt: ProximityPrompt,
	vaultPrompt: ProximityPrompt?,
	vaultDoor: BasePart?,
}

export type Route = {
	model: Model,
	sleigh: Model,
	startDeck: CFrame,
	stops: { Stop },
	onFootPresents: { Present },
}

local function facingRoad(pos: Vector3): CFrame
	local dir = if pos.X < 0 then Vector3.xAxis else -Vector3.xAxis
	return CFrame.lookAt(pos, pos + dir)
end

-- House slots on a normal street, in stop-local studs. Slot 1 is the landing house.
local function streetSlots(): { { ring: string, pos: Vector3 } }
	local s = Config.Map.SideOffset
	local mid = Config.Rings.Mid.Distance
	local far = Config.Rings.Far.Distance
	return {
		{ ring = "Near", pos = Vector3.new(-s, 0, 0) },
		{ ring = "Mid", pos = Vector3.new(s, 0, mid) },
		{ ring = "Mid", pos = Vector3.new(-s, 0, mid) },
		{ ring = "Mid", pos = Vector3.new(s, 0, mid + 50) },
		{ ring = "Far", pos = Vector3.new(-s, 0, far) },
		{ ring = "Far", pos = Vector3.new(s, 0, far) },
	}
end

local function buildStop(parent: Instance, rng: Random, index: number, origin: CFrame): Stop
	local isFinale = index == Config.Run.Stops
	local model = Instance.new("Model")
	model.Name = if isFinale then "Stop" .. index .. "_KrampusLair" else "Stop" .. index
	local far = Config.Rings.Far.Distance
	local streetLength = far + 120

	newPart(
		model,
		"Road",
		Vector3.new(Config.Map.RoadWidth, 0.2, streetLength),
		origin * CFrame.new(0, 0.1, streetLength / 2 - 40),
		ROAD
	)

	local slots = streetSlots()
	if isFinale then
		-- Finale street: landing house plus two Mid houses, then the Lair at the far end.
		slots = { slots[1], slots[2], slots[3] }
	end
	local types = Loot.rollStreet(rng, index, #slots)
	if isFinale then
		for i = 2, #types do
			types[i] = "Risky"
		end
	end

	local stop: Stop = {
		index = index,
		isFinale = isFinale,
		origin = origin,
		deckCFrame = CFrame.new(),
		houses = {},
		presents = {},
		cocoaPrompt = nil :: any,
	}

	for i, slot in slots do
		local typeName = types[i]
		local houseType = Config.Houses.Types[typeName]
		local ringInfo = Config.Rings[slot.ring]
		local cf = origin * facingRoad(slot.pos)
		local label = houseType.Label .. " · " .. string.upper(slot.ring)
		local house =
			buildHouse(model, "House" .. i, cf, Config.Map.HouseSize, houseType.RoofColor, label, {})
		house.typeName = typeName
		house.ring = slot.ring
		table.insert(stop.houses, house)

		local count = Config.Houses.PresentsPerHouse[slot.ring]
		if typeName == "Risky" then
			count += Config.Houses.RiskyExtraPresents
		end
		for _ = 1, count do
			local p = makePresent(
				model,
				rng,
				randomFloorPoint(rng, house),
				Loot.rollSize(rng),
				ringInfo.LootMultiplier,
				houseType.Threats,
				"Present"
			)
			table.insert(stop.presents, p)
		end

		if i == 1 then
			-- Sleigh lands on this roof, clear of the chimney.
			local h = Config.Map.HouseSize.Y
			stop.deckCFrame = cf * CFrame.new(-4, 2 + h + 1.6, -2)
		end
	end

	local farMult = Config.Rings.Far.LootMultiplier
	if isFinale then
		local lairCF = origin * CFrame.lookAt(Vector3.new(0, 0, far + 30), Vector3.new(0, 0, 0))
		local lair = buildHouse(
			model,
			"KrampusLair",
			lairCF,
			Config.Map.LairSize,
			Color3.fromRGB(90, 40, 120),
			"KRAMPUS'S LAIR · FAR",
			{}
		)
		lair.typeName = "Risky"
		lair.ring = "Far"
		table.insert(stop.houses, lair)
		for _ = 1, Config.Houses.PresentsPerHouse.Far * 2 do
			local p = makePresent(
				model,
				rng,
				randomFloorPoint(rng, lair),
				Loot.rollSize(rng),
				farMult,
				2,
				"Present"
			)
			table.insert(stop.presents, p)
		end
		-- The Naughty List: a flat golden "present" in the middle of the Lair.
		local listModel = Instance.new("Model")
		listModel.Name = "NaughtyList"
		local listPart = newPart(
			listModel,
			"Scroll",
			Vector3.new(3, 0.6, 4),
			lairCF * CFrame.new(0, 3, 0),
			GOLD,
			Enum.Material.Neon
		)
		addLabel(listPart, "THE NAUGHTY LIST", GOLD, 3)
		listModel.PrimaryPart = listPart
		listModel.Parent = model
		table.insert(stop.presents, {
			model = listModel,
			prompt = addPrompt(listPart, "Steal", "The Naughty List", 1),
			value = Config.Presents.NaughtyListValue,
			ringMultiplier = farMult,
			threats = 2,
			kind = "NaughtyList",
		})
	else
		-- Far ring vault: locked room with big presents, 1,000 Jingle to open.
		local vaultCF = origin * CFrame.lookAt(Vector3.new(0, 0, far + 60), Vector3.new(0, 0, 0))
		local vault = buildHouse(
			model,
			"Vault",
			vaultCF,
			Config.Map.HouseSize,
			GOLD,
			"VAULT · FAR",
			{ locked = true, chimney = false }
		)
		vault.typeName = "Normal"
		vault.ring = "Far"
		table.insert(stop.houses, vault)
		for _ = 1, Config.Presents.VaultPresents do
			local p = makePresent(
				model,
				rng,
				randomFloorPoint(rng, vault),
				Config.Presents.VaultPresentSize,
				farMult,
				0,
				"Vault"
			)
			table.insert(stop.presents, p)
		end
		stop.vaultDoor = vault.door
		stop.vaultPrompt =
			addPrompt(vault.door :: BasePart, "Open vault", Config.Buys.VaultDoor.Cost .. " Jingle", 0.5)
	end

	-- Cocoa machine (Peppermint Rush) by the landing house, Near ring.
	local machine = newPart(
		model,
		"CocoaMachine",
		Vector3.new(4, 7, 3),
		origin * CFrame.new(-14, 3.5, 22),
		Color3.fromRGB(120, 70, 40)
	)
	addLabel(
		machine,
		"PEPPERMINT RUSH\n" .. Config.Buys.PeppermintRush.Cost .. " Jingle",
		Color3.new(1, 1, 1),
		6
	)
	stop.cocoaPrompt = addPrompt(machine, "Buy perk", "Peppermint Rush", 0.5)

	model.Parent = parent
	return stop
end

function MapBuilder.buildRoute(slot: number, rng: Random): Route
	local model = Instance.new("Model")
	model.Name = "Route" .. slot
	local spacing = Config.Map.StopSpacing
	local stopsCount = Config.Run.Stops
	local base = CFrame.new(0, 0, Config.Map.RouteOriginZ + (slot - 1) * Config.Map.RouteSpacing)

	local widthX = (stopsCount - 1) * spacing + 400
	newPart(
		model,
		"Ground",
		Vector3.new(widthX, 2, 760),
		base * CFrame.new((stopsCount - 1) * spacing / 2, -1, 260),
		SNOW,
		Enum.Material.Snow
	)

	local route: Route = {
		model = model,
		sleigh = nil :: any,
		startDeck = base * CFrame.new(-150, 60, 0),
		stops = {},
		onFootPresents = {},
	}

	for i = 1, stopsCount do
		local origin = base * CFrame.new((i - 1) * spacing, 0, 0)
		route.stops[i] = buildStop(model, rng, i, origin)

		if i < stopsCount then
			-- The snowy path you run along if you miss the sleigh, with hidden loot.
			newPart(
				model,
				"FootPath" .. i,
				Vector3.new(spacing, 0.2, 10),
				origin * CFrame.new(spacing / 2, 0.1, -40),
				Color3.fromRGB(200, 210, 230)
			)
			for n = 1, Config.Presents.OnFootPresents do
				local along = spacing * n / (Config.Presents.OnFootPresents + 1)
				local side = if n % 2 == 0 then -60 else -22
				local mound = newPart(
					model,
					"SnowMound",
					Vector3.new(10, 5, 10),
					origin * CFrame.new(along, 2.5, side - 8),
					SNOW,
					Enum.Material.Snow
				)
				mound.Shape = Enum.PartType.Ball
				local pos = (origin * CFrame.new(along, 0, side)).Position
				local p = makePresent(
					model,
					rng,
					pos,
					Loot.rollSize(rng),
					Config.Presents.OnFootMultiplier,
					0,
					"OnFoot"
				)
				table.insert(route.onFootPresents, p)
			end
		end
	end

	route.sleigh = MapBuilder.buildSleigh(model, route.startDeck)
	model.Parent = workspace
	return route
end

-- Teleport helper reused by Run (respawns, take-off, results).
MapBuilder.teleportCharacter = teleportCharacter

return MapBuilder
