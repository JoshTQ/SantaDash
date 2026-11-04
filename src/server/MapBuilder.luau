--[[
	Builds the greybox world from plain Parts: the Sleigh Station hub, one route
	(4 stops) per running crew, and the Krampus stand-in. No models or meshes:
	art only goes in after Josh approves it.

	MapBuilder only turns plans (from Loot.planStop) into Instances and returns
	the prompts. It connects no events, so it runs in tests outside Roblox. Run
	owns every rule and wires the prompts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Maps = require(ReplicatedStorage.Shared.Maps)
local HouseKit = require(script.Parent.HouseKit)
local MapFeatures = require(script.Parent.MapFeatures)
local Parts = require(script.Parent.Parts)

local MapBuilder = {}

local WALL = Color3.fromRGB(190, 185, 175)
local SLEIGH_RED = Color3.fromRGB(200, 30, 40)
local GOLD = Color3.fromRGB(255, 200, 60)
local KRAMPUS_FUR = Color3.fromRGB(125, 85, 55) -- approved Shaggy Goat Grump palette
local PRESENT_COLOURS = {
	Color3.fromRGB(230, 50, 60),
	Color3.fromRGB(40, 170, 90),
	Color3.fromRGB(60, 120, 230),
	Color3.fromRGB(170, 80, 220),
	Color3.fromRGB(255, 150, 40),
}

local WALL_THICKNESS = 1
local FLOOR_TOP = 1 -- house floors sit 1 stud above the street

-- Six rider spots on the sleigh deck, relative to the deck centre.
MapBuilder.SeatOffsets = {}
for _, z in { -4, 0, 4 } do
	for _, x in { -2.5, 2.5 } do
		table.insert(MapBuilder.SeatOffsets, CFrame.new(x, 3.5, z))
	end
end

local newPart = Parts.new

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

----------------------------------------------------------------------------
-- Sleigh
----------------------------------------------------------------------------

-- The sleigh's deck centre is the model's pivot.
function MapBuilder.buildSleigh(parent: Instance, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Sleigh"
	local deckSize = Config.Map.DeckSize
	local deck = newPart(model, "Deck", deckSize, cframe, SLEIGH_RED)
	for _, sx in { -1, 1 } do
		newPart(model, "Side", Vector3.new(1, 3, deckSize.Z), cframe * CFrame.new(sx * 5.5, 1, 0), SLEIGH_RED)
		newPart(
			model,
			"Runner",
			Vector3.new(1, 0.6, deckSize.Z + 2),
			cframe * CFrame.new(sx * 4, -1, 0),
			GOLD,
			Enum.Material.Metal
		)
	end
	newPart(
		model,
		"Front",
		Vector3.new(12, 5, 1),
		cframe * CFrame.new(0, 2, -deckSize.Z / 2 - 0.5),
		SLEIGH_RED
	)
	newPart(model, "Back", Vector3.new(12, 2, 1), cframe * CFrame.new(0, 1, deckSize.Z / 2 + 0.5), SLEIGH_RED)
	addLabel(deck, "SLEIGH", Color3.new(1, 1, 1), 9)
	model.PrimaryPart = deck
	model.Parent = parent
	return model
end

-- Places an approved sleigh model (contract in Assets.luau) with its Body at
-- cframe, anchors it, hitches two reindeer and returns rider offsets from
-- Seat1-Seat6. Seats are turned off (Run carries riders, not welds) unless
-- seatable, as at the lobby station where riders really sit down.
function MapBuilder.placeSleighTemplate(
	parent: Instance,
	sleigh: Model,
	cframe: CFrame,
	reindeer: Model?,
	seatable: boolean?
): (Model, { CFrame })
	local body = sleigh:FindFirstChild("Body", true) :: BasePart
	sleigh.PrimaryPart = body
	sleigh.Name = "Sleigh"
	if reindeer then
		local hitch = sleigh:FindFirstChild("Hitch", true) :: BasePart
		for i, side in { -1.6, 1.6 } do
			local deer = reindeer:Clone()
			deer.Name = "Reindeer" .. i
			-- Pivot first so the reindeer stand in front of the hitch, facing forward.
			deer:PivotTo(hitch.CFrame * CFrame.new(side, 0, -4))
			deer.Parent = sleigh
		end
	end
	sleigh:PivotTo(cframe)
	for _, part in sleigh:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
		if (part:IsA("Seat") or part:IsA("VehicleSeat")) and not seatable then
			part.Disabled = true
		end
	end
	local offsets = {}
	local pivot = sleigh:GetPivot()
	for i = 1, 6 do
		local seat = sleigh:FindFirstChild("Seat" .. i, true) :: BasePart?
		if seat then
			-- Stand the rider's root a little above the seat.
			table.insert(offsets, pivot:ToObjectSpace(seat.CFrame) * CFrame.new(0, seat.Size.Y / 2 + 2.5, 0))
		end
	end
	if #offsets == 0 then
		offsets = MapBuilder.SeatOffsets
	end
	sleigh.Parent = parent
	return sleigh, offsets
end

-- Real Seats for a stand-in sleigh at the rider spots (lobby station).
function MapBuilder.addSeats(sleigh: Model): { Seat }
	local seats = {}
	local pivot = (sleigh.PrimaryPart :: BasePart).CFrame -- the deck centre
	for i, offset in MapBuilder.SeatOffsets do
		local seat = newPart(
			sleigh,
			"Seat" .. i,
			Vector3.new(2, 1, 2),
			pivot * offset * CFrame.new(0, -1.5, 0),
			GOLD,
			nil,
			"Seat"
		) :: Seat
		table.insert(seats, seat)
	end
	return seats
end

-- True if a position is inside the Sleigh Stop clearing around the sleigh
-- (deckCFrame), or riding on it.
function MapBuilder.isAboard(deckCFrame: CFrame, position: Vector3): boolean
	local rel = deckCFrame:PointToObjectSpace(position)
	local flat = Vector3.new(rel.X, 0, rel.Z).Magnitude
	return flat <= Config.Map.SleighStopRadius and rel.Y >= -4 and rel.Y <= 12
end

----------------------------------------------------------------------------
-- Houses
----------------------------------------------------------------------------

export type Chimney = { down: ProximityPrompt, up: ProximityPrompt, inside: CFrame, roof: CFrame }
export type HideSpot = { prompt: ProximityPrompt, inside: CFrame, exit: CFrame }
export type BuiltPresent = {
	model: Model,
	prompt: ProximityPrompt,
	plan: any,
	taken: boolean?,
	inVault: boolean?, -- behind a locked vault door until someone buys it open
}

export type Stop = {
	plan: any, -- Loot.StopPlan
	deckCFrame: CFrame, -- where the sleigh deck sits when landed
	lights: { PointLight },
	presents: { BuiltPresent },
	chimneys: { Chimney },
	hideSpots: { HideSpot },
	cocoaPrompt: ProximityPrompt,
	vaultPrompt: ProximityPrompt?,
	vaultDoor: BasePart?,
	krampusSpawn: CFrame,
	doors: { Door }, -- approved houses' front doors (Run swings them)
	origin: CFrame, -- stop space: +Z runs down the street from the landing house
}

export type Door = { door: BasePart, prompt: ProximityPrompt, closed: CFrame, open: boolean }

-- Approved house models (see HouseKit); empty/nil = greybox blocks.
export type Kit = { houses: { Model }, lair: Model?, vaultDoor: Model? }

-- Approved present models for the route being built (buildRoute sets these).
local presentKit: { variants: { Model }, naughtyList: Model? } = { variants = {} }

local function buildPresent(parent: Instance, rng: Random, position: Vector3, plan): BuiltPresent
	local model: Model
	local prompt
	if plan.naughtyList then
		if presentKit.naughtyList then
			model = HouseKit.placeList(presentKit.naughtyList, position)
			model.Name = "NaughtyList"
			prompt = addPrompt(model.PrimaryPart :: BasePart, "Steal", "The Naughty List", 1)
		else
			model = Instance.new("Model")
			model.Name = "NaughtyList"
			local scroll = newPart(
				model,
				"Scroll",
				Vector3.new(3, 0.6, 4),
				CFrame.new(position + Vector3.new(0, 2, 0)),
				GOLD,
				Enum.Material.Neon
			)
			addLabel(scroll, "THE NAUGHTY LIST", GOLD, 3)
			model.PrimaryPart = scroll
			prompt = addPrompt(scroll, "Steal", "The Naughty List", 1)
		end
	else
		local edge = 1.6 * plan.size
		local yaw = rng:NextNumber(0, math.pi)
		local colour = PRESENT_COLOURS[rng:NextInteger(1, #PRESENT_COLOURS)]
		local variants = presentKit.variants
		if #variants > 0 then
			model =
				HouseKit.placePresent(variants[rng:NextInteger(1, #variants)], position, edge, yaw, colour)
		else
			model = Instance.new("Model")
			local cf = CFrame.new(position + Vector3.new(0, edge / 2, 0)) * CFrame.Angles(0, yaw, 0)
			local box = newPart(model, "Box", Vector3.one * edge, cf, colour)
			for _, size in { Vector3.new(1.03, 1.03, 0.18), Vector3.new(0.18, 1.03, 1.03) } do
				newPart(model, "Ribbon", size * edge, cf, GOLD).CanCollide = false
			end
			model.PrimaryPart = box
		end
		model.Name = "Present"
		prompt = addPrompt(model.PrimaryPart :: BasePart, "Grab", "Present", Config.Presents.GrabHoldSeconds)
	end
	model.Parent = parent
	return { model = model, prompt = prompt, plan = plan }
end

-- cframe: centre of the house on the street, LookVector pointing out of the front door.
-- Returns the Lair's Krampus spawn when an approved Lair model sets one.
local function buildHouse(
	parent: Instance,
	stop: Stop,
	rng: Random,
	plan,
	cframe: CFrame,
	labelText: string,
	kit: Kit?
): CFrame?
	local template = if not kit
		then nil
		elseif plan.typeName == "Lair" then kit.lair
		elseif plan.locked then nil
		else HouseKit.pick(kit.houses, rng, plan)
	if template then
		return HouseKit.build({
			parent = parent,
			stop = stop,
			rng = rng,
			plan = plan,
			cframe = cframe,
			label = labelText,
			template = template,
			helpers = {
				newPart = newPart,
				addPrompt = addPrompt,
				addLabel = addLabel,
				buildPresent = buildPresent,
			},
		})
	end
	local houseType = Config.Houses.Types[plan.typeName]
	local model = Instance.new("Model")
	model.Name = plan.typeName .. "House"
	local w, h, d = plan.size.X, plan.size.Y, plan.size.Z
	local t = WALL_THICKNESS
	local wallY = FLOOR_TOP + h / 2
	local door = Config.Map.DoorSize

	newPart(
		model,
		"Floor",
		Vector3.new(w, 1, d),
		cframe * CFrame.new(0, FLOOR_TOP - 0.5, 0),
		Color3.fromRGB(150, 110, 80)
	)
	newPart(model, "WallBack", Vector3.new(w, h, t), cframe * CFrame.new(0, wallY, d / 2 - t / 2), WALL)
	for _, sx in { -1, 1 } do
		newPart(
			model,
			"WallSide",
			Vector3.new(t, h, d),
			cframe * CFrame.new(sx * (w / 2 - t / 2), wallY, 0),
			WALL
		)
	end

	-- Front wall with a doorway (front = local -Z = LookVector), and a ramp up to it.
	local segW = (w - door.X) / 2
	local frontZ = -d / 2 + t / 2
	for _, sx in { -1, 1 } do
		newPart(
			model,
			"Front",
			Vector3.new(segW, h, t),
			cframe * CFrame.new(sx * (door.X + segW) / 2, wallY, frontZ),
			WALL
		)
	end
	newPart(
		model,
		"Lintel",
		Vector3.new(door.X, h - door.Y, t),
		cframe * CFrame.new(0, FLOOR_TOP + door.Y + (h - door.Y) / 2, frontZ),
		WALL
	)
	newPart(
		model,
		"Ramp",
		Vector3.new(door.X, FLOOR_TOP, 3),
		cframe * CFrame.new(0, FLOOR_TOP / 2, -d / 2 - 1.5),
		Color3.fromRGB(150, 110, 80),
		nil,
		"WedgePart"
	)

	local roofTop = FLOOR_TOP + h + 1
	local roof = newPart(
		model,
		"Roof",
		Vector3.new(w + 2, 1, d + 2),
		cframe * CFrame.new(0, roofTop - 0.5, 0),
		houseType.RoofColor
	)
	addLabel(roof, labelText, houseType.RoofColor, 10)

	local lamp = newPart(model, "Lamp", Vector3.one, cframe * CFrame.new(0, h - 1, 0), Color3.new(1, 1, 1))
	lamp.Transparency = 1
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = math.max(w, d)
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Enabled = false
	light.Parent = lamp
	table.insert(stop.lights, light)

	if plan.locked then
		local vaultDoor = kit
			and kit.vaultDoor
			and HouseKit.placeVaultDoor(model, kit.vaultDoor, cframe * CFrame.new(0, FLOOR_TOP, frontZ))
		if not vaultDoor then
			vaultDoor = newPart(
				model,
				"VaultDoor",
				Vector3.new(door.X, door.Y, t + 0.4),
				cframe * CFrame.new(0, FLOOR_TOP + door.Y / 2, frontZ),
				GOLD,
				Enum.Material.Neon
			)
		end
		stop.vaultDoor = vaultDoor
		stop.vaultPrompt = addPrompt(vaultDoor, "Open vault", Config.Buys.VaultDoor.Cost .. " Jingle", 0.5)
	end

	if plan.chimney then
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
			cframe * CFrame.new(0, FLOOR_TOP + 2, d / 2 - 2),
			Color3.fromRGB(120, 50, 40),
			Enum.Material.Brick
		)
		table.insert(stop.chimneys, {
			down = addPrompt(chimney, "Slide down", "Chimney"),
			up = addPrompt(fireplace, "Climb up", "Chimney"),
			inside = cframe * CFrame.new(0, FLOOR_TOP + 3, d / 2 - 6),
			roof = cframe * CFrame.new(-w / 4, roofTop + 3, 0),
		})

		-- Ladder up the side so the roof (and the sleigh) can be reached from the street.
		newPart(
			model,
			"Ladder",
			Vector3.new(2, roofTop, 2),
			cframe * CFrame.new(w / 2 + 1, roofTop / 2, -d / 4),
			Color3.fromRGB(110, 80, 60),
			nil,
			"TrussPart"
		)
	end

	-- Wardrobes to hide in from Krampus, along the side walls.
	for i = 1, plan.hideSpots do
		local sx = if i % 2 == 1 then -1 else 1
		local x = sx * (w / 2 - t - 1.5)
		local wardrobe = newPart(
			model,
			"Wardrobe",
			Vector3.new(3, 9, 5),
			cframe * CFrame.new(x, FLOOR_TOP + 4.5, d / 4),
			Color3.fromRGB(110, 70, 45),
			Enum.Material.Wood
		)
		table.insert(stop.hideSpots, {
			prompt = addPrompt(wardrobe, "Hide", "Wardrobe"),
			inside = cframe * CFrame.new(x, FLOOR_TOP + 3, d / 4),
			exit = cframe * CFrame.new(x - sx * 4, FLOOR_TOP + 3, d / 4),
		})
	end

	-- Presents on the floor, clear of the walls and the fireplace.
	for _, presentPlan in plan.presents do
		local offset = if presentPlan.naughtyList
			then CFrame.new(0, FLOOR_TOP, 0)
			else CFrame.new(
				rng:NextNumber(-w / 2 + 5, w / 2 - 5),
				FLOOR_TOP,
				rng:NextNumber(-d / 2 + 4, d / 2 - 8)
			)
		local present = buildPresent(model, rng, (cframe * offset).Position, presentPlan)
		present.inVault = plan.locked or nil
		table.insert(stop.presents, present)
	end

	model.Parent = parent
	return nil
end

----------------------------------------------------------------------------
-- Streets and routes
----------------------------------------------------------------------------

export type Route = {
	model: Model,
	sleigh: Model,
	startDeck: CFrame,
	stops: { Stop },
	onFootPresents: { BuiltPresent },
	seatOffsets: { CFrame }, -- rider spots relative to the deck pivot
	map: Maps.Map,
}

-- buildRoute options. Pivots of StopDressing/RouteDressing go to the stop/route origin.
-- sleigh: an approved "Sleigh" clone (Assets.clone) to use
-- instead of the greybox blocks; reindeer: the "Reindeer" template for it.
export type RouteOptions = {
	yieldEach: (() -> ())?, -- called between stops to spread the build over frames
	map: Maps.Map?, -- defaults to Maps.Default
	dressing: Model?, -- approved set dressing: children StopDressing (per stop) and RouteDressing
	cocoa: Model?, -- approved "CocoaMachine" (Assets contract) instead of the block
	houseKit: Kit?, -- approved House variants, KrampusLair and VaultDoor (HouseKit)
	presents: { Model }?, -- approved Present variants (HouseKit.presentVariants)
	naughtyList: Model?, -- approved NaughtyList
	sleigh: Model?,
	reindeer: Model?,
}

local function buildStop(
	parent: Instance,
	rng: Random,
	plan,
	origin: CFrame,
	mapDef: Maps.Map,
	cocoaTemplate: Model?,
	kit: Kit?
): Stop
	local model = Instance.new("Model")
	model.Name = "Stop" .. plan.index .. "_" .. plan.kindName
	local map = mapDef.layout
	local far = Config.Rings.Far.Distance
	local streetLength = far + map.StreetOverrun - map.StreetStart

	newPart(
		model,
		"Road",
		Vector3.new(map.RoadWidth, 0.2, streetLength),
		origin * CFrame.new(0, 0.1, map.StreetStart + streetLength / 2),
		mapDef.palette.Road[1],
		mapDef.palette.Road[2]
	)

	local stop: Stop = {
		plan = plan,
		deckCFrame = CFrame.new(),
		lights = {},
		presents = {},
		chimneys = {},
		hideSpots = {},
		cocoaPrompt = nil :: any,
		doors = {},
		krampusSpawn = origin * CFrame.new(0, 6, far + map.StreetOverrun - 20), -- past the vault
		origin = origin,
	}

	for _, house in plan.houses do
		local cf
		local endAt = map.EndHouseAt and map.EndHouseAt[plan.kindName]
		if house.side == 0 and endAt then
			cf = origin * endAt -- placed by the map (e.g. the Lair on its island)
		elseif house.side == 0 then
			-- End-of-street house, facing back up the street.
			cf = origin * CFrame.lookAt(Vector3.new(0, 0, house.distance), Vector3.zero)
		else
			local pos = Vector3.new(house.side * map.SideOffset, 0, house.distance)
			cf = origin * CFrame.lookAt(pos, pos - Vector3.xAxis * house.side)
		end
		local label = Config.Houses.Types[house.typeName].Label .. " · " .. string.upper(house.ring)
		local kitSpawn = buildHouse(model, stop, rng, house, cf, label, kit)
		if house.typeName == "Lair" then
			stop.krampusSpawn = kitSpawn or cf * CFrame.new(0, 6, house.size.Z / 4)
		end
	end

	-- Sleigh Stop: the sleigh lands on the ground in this clearing.
	local landingLocal = map.LandingAt and map.LandingAt[plan.index] or Config.Map.LandingAt
	local landing = origin * landingLocal
	stop.deckCFrame = landing * CFrame.new(0, Config.Map.DeckHeight, 0)
	local radius = Config.Map.SleighStopRadius
	local clearing = newPart(
		model,
		"SleighStop",
		Vector3.new(0.3, radius * 2, radius * 2),
		landing * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(255, 220, 120),
		Enum.Material.Neon
	)
	clearing.Shape = Enum.PartType.Cylinder
	clearing.Transparency = 0.6
	clearing.CanCollide = false
	local sign = newPart(
		model,
		"SleighStopSign",
		Vector3.new(1, 8, 1),
		landing * CFrame.new(radius - 1, 4, 0),
		Color3.fromRGB(200, 30, 40)
	)
	addLabel(sign, "SLEIGH STOP", Color3.new(1, 1, 1), 5)

	-- Cocoa machine (Peppermint Rush) by the landing house, Near ring.
	local machineAt = origin * CFrame.new(map.CocoaMachine)
	if cocoaTemplate then
		-- Approved booth at the same spot, standing on the street; prompt at BuyPrompt.
		local booth = cocoaTemplate:Clone()
		booth.Name = "CocoaMachine"
		booth:PivotTo(machineAt)
		local box, size = booth:GetBoundingBox()
		local street = (origin * CFrame.new(map.CocoaMachine.X, 0, map.CocoaMachine.Z)).Position.Y
		booth:PivotTo(machineAt + Vector3.new(0, street - (box.Position.Y - size.Y / 2), 0))
		booth.Parent = model
		local at = booth:FindFirstChild("BuyPrompt", true)
		stop.cocoaPrompt = addPrompt(at :: Instance, "Buy perk", "Peppermint Rush", 0.5)
	else
		local machine =
			newPart(model, "CocoaMachine", Vector3.new(4, 7, 3), machineAt, Color3.fromRGB(120, 70, 40))
		addLabel(
			machine,
			"PEPPERMINT RUSH\n" .. Config.Buys.PeppermintRush.Cost .. " Jingle",
			Color3.new(1, 1, 1),
			6
		)
		stop.cocoaPrompt = addPrompt(machine, "Buy perk", "Peppermint Rush", 0.5)
	end

	for _, feature in mapDef.features do
		local entry = MapFeatures[feature.kind]
		assert(entry, "unknown map feature " .. tostring(feature.kind))
		if entry.build and Maps.featureOnStop(feature, plan.index) then
			entry.build({
				model = model,
				origin = origin,
				feature = feature,
				rng = rng,
				stop = stop,
				newPart = newPart,
				map = mapDef,
				landing = landingLocal,
			})
		end
	end

	model.Parent = parent
	return stop
end

-- The path from one stop to the next (stop origins `from` -> `to`), with
-- hidden presents behind snow mounds on alternate sides.
local function buildFootPath(
	parent: Instance,
	rng: Random,
	from: CFrame,
	to: CFrame,
	presents,
	out: { BuiltPresent },
	mapDef: Maps.Map
)
	local z = mapDef.layout.FootPathZ
	local a = (from * CFrame.new(0, 0, z)).Position
	local b = (to * CFrame.new(0, 0, z)).Position
	local length = (b - a).Magnitude
	local frame = CFrame.lookAt(a, b) -- -Z runs along the path, +X is its right side
	newPart(
		parent,
		"FootPath",
		Vector3.new(10, 0.2, length),
		frame * CFrame.new(0, 0.1, -length / 2),
		mapDef.palette.Path[1],
		mapDef.palette.Path[2]
	)
	for n, plan in presents do
		local along = length * n / (#presents + 1)
		local side = if n % 2 == 0 then -20 else 18
		local mound = newPart(
			parent,
			"SnowMound",
			Vector3.new(10, 5, 10),
			frame * CFrame.new(side - 8, 2.5, -along),
			mapDef.palette.Ground[1],
			mapDef.palette.Ground[2]
		)
		mound.Shape = Enum.PartType.Ball
		table.insert(out, buildPresent(parent, rng, (frame * CFrame.new(side, 0, -along)).Position, plan))
	end
end

local stopOrigin = Maps.stopOrigin

-- plans: one Loot.StopPlan per stop; onFoot: one present list per gap between stops.
function MapBuilder.buildRoute(
	parent: Instance,
	slot: number,
	rng: Random,
	plans: { any },
	onFoot: { any },
	opts: RouteOptions?
): Route
	local options: RouteOptions = opts or {}
	local mapDef = options.map or Maps.get()
	presentKit = { variants = options.presents or {}, naughtyList = options.naughtyList }
	local model = Instance.new("Model")
	model.Name = "Route" .. slot
	local map = Config.Map
	local base = CFrame.new(0, 0, map.RouteOriginZ + (slot - 1) * map.RouteSpacing)
	local far = Config.Rings.Far.Distance

	-- Snow under every street: the bounds of each stop's street area.
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for i = 1, #plans do
		local o = stopOrigin(mapDef.layout, i)
		for _, corner in { Vector3.new(-200, 0, -120), Vector3.new(200, 0, far + 200) } do
			for _, x in { corner.X, -corner.X } do
				local p = (o * CFrame.new(x, 0, corner.Z)).Position
				lo, hi = lo:Min(p), hi:Max(p)
			end
		end
	end
	local size = hi - lo
	newPart(
		model,
		"Ground",
		Vector3.new(size.X, 2, size.Z),
		base * CFrame.new((lo.X + hi.X) / 2, -1, (lo.Z + hi.Z) / 2),
		mapDef.palette.Ground[1],
		mapDef.palette.Ground[2]
	)

	local route: Route = {
		model = model,
		sleigh = nil :: any,
		startDeck = base * stopOrigin(mapDef.layout, 1) * CFrame.new(map.TakeoffOffset),
		stops = {},
		onFootPresents = {},
		seatOffsets = MapBuilder.SeatOffsets,
		map = mapDef,
	}
	for i, plan in plans do
		local origin = base * stopOrigin(mapDef.layout, i)
		route.stops[i] = buildStop(model, rng, plan, origin, mapDef, options.cocoa, options.houseKit)
		if onFoot[i] then
			local nextOrigin = base * stopOrigin(mapDef.layout, i + 1)
			buildFootPath(model, rng, origin, nextOrigin, onFoot[i], route.onFootPresents, mapDef)
		end
		local stopDressing = options.dressing and options.dressing:FindFirstChild("StopDressing")
		if stopDressing then
			local copy = stopDressing:Clone() :: Model
			copy:PivotTo(origin)
			copy.Parent = model
		end
		if options.yieldEach then
			options.yieldEach()
		end
	end

	local routeDressing = options.dressing and options.dressing:FindFirstChild("RouteDressing")
	if routeDressing then
		local copy = routeDressing:Clone() :: Model
		copy:PivotTo(base)
		copy.Parent = model
	end

	if options.sleigh then
		route.sleigh, route.seatOffsets =
			MapBuilder.placeSleighTemplate(model, options.sleigh, route.startDeck, options.reindeer)
	else
		route.sleigh = MapBuilder.buildSleigh(model, route.startDeck)
	end
	presentKit = { variants = {} }
	Parts.settle(model)
	model.Parent = parent
	return route
end

----------------------------------------------------------------------------
-- Krampus stand-in (GREYBOX blocks until the Meshy mesh exists)
----------------------------------------------------------------------------

export type KrampusBody = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	basket: BasePart,
	bellPrompt: ProximityPrompt,
}

-- cframe: where his root part starts. Only the root collides; the rest is welded on.
function MapBuilder.buildKrampus(parent: Instance, cframe: CFrame): KrampusBody
	local model = Instance.new("Model")
	model.Name = "KrampusStandIn"
	local height = Config.Krampus.Height
	local hip = 3

	local root = newPart(model, "HumanoidRootPart", Vector3.new(4, 5, 3), cframe, KRAMPUS_FUR)
	root.Transparency = 1
	local function limb(name: string, size: Vector3, offset: CFrame, color: Color3?): BasePart
		local part = newPart(model, name, size, cframe * offset, color or KRAMPUS_FUR)
		part.CanCollide = false
		part.Massless = true
		part.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		return part
	end
	-- Root centre is hip + 2.5 above the floor; build up from the feet.
	local feet = -(hip + 2.5)
	for _, sx in { -1, 1 } do
		limb("Leg", Vector3.new(1.6, hip, 1.6), CFrame.new(sx * 1.2, feet + hip / 2, 0))
		limb(
			"Horn",
			Vector3.new(0.8, 2.5, 0.8),
			CFrame.new(sx * 1.6, feet + height - 0.5, 0) * CFrame.Angles(0, 0, sx * -0.4),
			Color3.fromRGB(240, 230, 200)
		)
		limb(
			"Eye",
			Vector3.new(0.6, 0.6, 0.2),
			CFrame.new(sx * 0.8, feet + hip + 7, -1.85),
			Color3.fromRGB(255, 220, 60)
		).Material =
			Enum.Material.Neon
	end
	limb("Body", Vector3.new(6, 5.5, 4), CFrame.new(0, feet + hip + 2.75, 0))
	limb("Head", Vector3.new(3.5, 2.5, 3), CFrame.new(0, feet + hip + 6.75, -0.3))
	-- The basket on his back (+Z), where snatched Santas ride. Ring the bells here.
	local basket =
		limb("Basket", Vector3.new(5, 4, 3), CFrame.new(0, feet + hip + 3, 3.6), Color3.fromRGB(170, 120, 60))
	basket.Material = Enum.Material.WoodPlanks
	addLabel(root, "KRAMPUS (stand-in)", Color3.fromRGB(255, 120, 120), 9)

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hip
	humanoid.WalkSpeed = Config.Krampus.WalkSpeed
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	root.Anchored = false
	model.PrimaryPart = root
	model.Parent = parent
	return {
		model = model,
		humanoid = humanoid,
		root = root,
		basket = basket,
		bellPrompt = addPrompt(basket, "Ring bells", "Krampus", 0.3),
	}
end

----------------------------------------------------------------------------
-- Elf bot stand-ins (GREYBOX until designs A and D are approved)
----------------------------------------------------------------------------

export type ElfBody = { model: Model, humanoid: Humanoid, root: BasePart }

-- variant: a Config.ElfBots.Variants name; picks the stand-in colours.
function MapBuilder.buildElf(parent: Instance, cframe: CFrame, variant: string): ElfBody
	local colours = Config.ElfBots.StandIn[variant]
	local model = Instance.new("Model")
	model.Name = variant .. "StandIn"
	local hip = 1.2
	local root = newPart(model, "HumanoidRootPart", Vector3.new(2, 1.6, 1), cframe, colours.Body)
	root.Transparency = 1
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3): BasePart
		local part = newPart(model, name, size, cframe * offset, color)
		part.CanCollide = false
		part.Massless = true
		part.Anchored = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
		return part
	end
	local feet = -(hip + 0.8)
	for _, sx in { -1, 1 } do
		piece("Leg", Vector3.new(0.6, hip, 0.6), CFrame.new(sx * 0.45, feet + hip / 2, 0), colours.Body)
	end
	piece("Body", Vector3.new(1.6, 1.4, 1), CFrame.new(0, feet + hip + 0.7, 0), colours.Body)
	piece("Head", Vector3.new(1.2, 1, 1), CFrame.new(0, feet + hip + 1.9, 0), Color3.fromRGB(255, 210, 180))
	piece("Hat", Vector3.new(1, 1.4, 1), CFrame.new(0, feet + hip + 3.1, 0), colours.Hat)
	addLabel(root, variant .. " (stand-in)", colours.Body, 4)

	local humanoid = Instance.new("Humanoid")
	humanoid.HipHeight = hip
	humanoid.WalkSpeed = Config.ElfBots.WalkSpeed
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	root.Anchored = false
	model.PrimaryPart = root
	model.Parent = parent
	return { model = model, humanoid = humanoid, root = root }
end

return MapBuilder
