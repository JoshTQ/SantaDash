--[[
	Builds houses from the approved models (contracts from the models thread,
	1 Nov 2026) instead of greybox blocks. MapBuilder calls this with a
	ServerStorage.Assets model when there is one; street and vault houses
	otherwise come from HouseBuilder (the approved kit built from parts).
	A locked house's front Door becomes its vault door.

	House        Floor (PrimaryPart), TypeSign, Chimney, ChimneyTop, Fireplace,
	             Wardrobe, FrontDoor > Door, PresentSpawn1-8 (parts or
	             Attachments); attributes Style ("candy"/"alpine"), Layout,
	             Seed, HouseType ("Snowflake"/"Bell"/"Horns").
	             Several variants may sit in Assets (named House) or in an
	             Assets.Houses folder.
	KrampusLair  Floor (PrimaryPart), ListPedestal, KrampusSpawn, HideSpot1-2,
	             Fireplace, Entrance, Bell1-7, ...
	VaultDoor    Frame (PrimaryPart), Door (hinged on its left edge), Dial, PricePlate

	Present      Box (PrimaryPart), Ribbon, Bow, Tag?; attributes Shape, Pattern,
	             BowStyle. Variants: Assets.Present models and/or Assets.Presents.
	NaughtyList  any PrimaryPart (Book), Chain, Lock

	Event-free (no :Connect) and no PivotTo, so the Lune tests can build it:
	models are moved part by part relative to their PrimaryPart.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local HouseKit = {}

-- House Card -> the kit's HouseType sign (assumed mapping; confirm with the models thread).
HouseKit.HouseTypeSign = { Cosy = "Snowflake", Normal = "Bell", Risky = "Horns" }

local function parts(model: Instance): { BasePart }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- Moves every part so the model's PrimaryPart ends up at `target`, keeping
-- the rest where they sit relative to it (optionally scaled). Anchors everything.
function HouseKit.place(model: Model, target: CFrame, scale: number?)
	local primary = model.PrimaryPart
		or model:FindFirstChild("Floor", true)
		or model:FindFirstChild("Frame", true)
		or model:FindFirstChild("Box", true)
	assert(primary and primary:IsA("BasePart"), model.Name .. " needs a PrimaryPart")
	model.PrimaryPart = primary
	local k = scale or 1
	local from = primary.CFrame
	for _, part in parts(model) do
		local rel = from:ToObjectSpace(part.CFrame)
		part.CFrame = target * (rel - rel.Position + rel.Position * k)
		part.Size *= k
		part.Anchored = true
	end
	if k ~= 1 then
		for _, d in model:GetDescendants() do
			if d:IsA("Attachment") then
				local a = d.CFrame
				d.CFrame = a - a.Position + a.Position * k
			end
		end
	end
end

function HouseKit.find(model: Instance, name: string): Instance?
	return model:FindFirstChild(name, true)
end

-- World position on top of a marker part, or an Attachment's position.
local function topOf(marker: Instance): Vector3
	if marker:IsA("BasePart") then
		return marker.CFrame.Position + Vector3.new(0, marker.Size.Y / 2, 0)
	end
	local attachment = marker :: Attachment
	local parent = attachment.Parent :: BasePart
	return (parent.CFrame * attachment.CFrame).Position
end

-- `dist` studs from `from` toward `centre`, on the level plane at height y.
local function toward(from: Vector3, centre: Vector3, dist: number, y: number): CFrame
	local flat = Vector3.new(centre.X - from.X, 0, centre.Z - from.Z)
	local step = if flat.Magnitude > 0.01 then flat.Unit * math.min(dist, flat.Magnitude) else Vector3.zero
	local p = from + step
	return CFrame.new(p.X, y, p.Z)
end

-- Every approved house variant: Assets.House models plus an Assets.Houses folder.
function HouseKit.variants(assets: Instance?): { Model }
	local list = {}
	if not assets then
		return list
	end
	local function add(m: Instance)
		if m:IsA("Model") and HouseKit.find(m, "Floor") then
			table.insert(list, m)
		end
	end
	for _, child in assets:GetChildren() do
		if child.Name == "House" then
			add(child)
		end
	end
	local folder = assets:FindFirstChild("Houses")
	if folder then
		for _, child in folder:GetChildren() do
			add(child)
		end
	end
	return list
end

-- Any style anywhere; the Far ring prefers Alpine when there is one (run map thread).
function HouseKit.pick(variants: { Model }, rng: Random, plan): Model?
	if #variants == 0 then
		return nil
	end
	local pool = variants
	if plan.ring == "Far" then
		local alpine = {}
		for _, v in variants do
			if v:GetAttribute("Style") == "alpine" then
				table.insert(alpine, v)
			end
		end
		if #alpine > 0 then
			pool = alpine
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

export type Helpers = {
	newPart: (...any) -> BasePart,
	addPrompt: (parent: Instance, action: string, object: string, hold: number?) -> ProximityPrompt,
	addLabel: (part: BasePart, text: string, color: Color3, offsetY: number) -> (),
	buildPresent: (parent: Instance, rng: Random, position: Vector3, plan: any) -> any,
}

export type Context = {
	parent: Instance,
	stop: any, -- MapBuilder.Stop
	rng: Random,
	plan: any, -- Loot.HousePlan
	cframe: CFrame, -- house centre on the ground, LookVector out of the front door
	label: string,
	template: Model,
	owned: boolean?, -- template is a fresh model (HouseBuilder) to use as is, not clone
	vaultDoor: Model?, -- approved VaultDoor for a locked house (plan.locked)
	helpers: Helpers,
}

-- Builds one house from a template. Returns the Lair's Krampus spawn, if any.
function HouseKit.build(ctx: Context): CFrame?
	local plan, stop, rng, h = ctx.plan, ctx.stop, ctx.rng, ctx.helpers
	local houseType = Config.Houses.Types[plan.typeName]
	local model = if ctx.owned then ctx.template else ctx.template:Clone()
	model.Name = plan.typeName .. "House"
	local floor = (model.PrimaryPart or HouseKit.find(model, "Floor")) :: BasePart
	HouseKit.place(model, ctx.cframe * CFrame.new(0, floor.Size.Y / 2, 0))
	model:SetAttribute("HouseType", HouseKit.HouseTypeSign[plan.typeName] or plan.typeName)
	if not ctx.owned then
		model:SetAttribute("Seed", rng:NextInteger(1, 2 ^ 30))
	end

	local centre = floor.CFrame.Position
	local floorTop = centre.Y + floor.Size.Y / 2
	local top = floorTop
	for _, part in parts(model) do
		top = math.max(top, part.CFrame.Position.Y + part.Size.Y / 2)
	end

	local sign = HouseKit.find(model, "TypeSign")
	if sign and sign:IsA("BasePart") then
		h.addLabel(sign, ctx.label, houseType.RoofColor, 3)
	end

	-- Lights on at 0:45, like the greybox houses.
	local lamp = h.newPart(
		model,
		"Lamp",
		Vector3.one,
		CFrame.new(centre.X, floorTop + 8, centre.Z),
		Color3.new(1, 1, 1)
	)
	lamp.Transparency = 1
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = math.max(floor.Size.X, floor.Size.Z)
	light.Brightness = 2
	light.Color = Color3.fromRGB(255, 220, 160)
	light.Enabled = false
	light.Parent = lamp
	table.insert(stop.lights, light)

	-- Front door: Run swings it open and shut from this prompt.
	local frontDoor = HouseKit.find(model, "FrontDoor")
	local door = frontDoor and frontDoor:FindFirstChild("Door", true)
	if door and door:IsA("BasePart") and plan.locked then
		-- The vault house: its front door is the vault door, opened for the crew
		-- by a Jingle buy (Run._buyVault), never by hand.
		local vault = ctx.vaultDoor
			and HouseKit.placeVaultDoor(
				model,
				ctx.vaultDoor,
				door.CFrame * CFrame.new(0, -door.Size.Y / 2, 0)
			)
		if vault then
			door:Destroy()
		else
			vault = door
			door.Name = "VaultDoor"
			door.Color = Color3.fromRGB(255, 200, 60)
			door.Material = Enum.Material.Neon
		end
		stop.vaultDoor = vault
		stop.vaultPrompt =
			h.addPrompt(vault :: BasePart, "Open vault", Config.Buys.VaultDoor.Cost .. " Jingle", 0.5)
	elseif door and door:IsA("BasePart") then
		local prompt = door:FindFirstChildOfClass("ProximityPrompt") or h.addPrompt(door, "Open", "Door")
		table.insert(stop.doors, { door = door, prompt = prompt, closed = door.CFrame, open = false })
	end

	-- Chimney: down from ChimneyTop, out at the Fireplace.
	local chimneyTop = HouseKit.find(model, "ChimneyTop")
	local fireplace = HouseKit.find(model, "Fireplace")
	if
		plan.chimney
		and chimneyTop
		and chimneyTop:IsA("BasePart")
		and fireplace
		and fireplace:IsA("BasePart")
	then
		table.insert(stop.chimneys, {
			down = h.addPrompt(chimneyTop, "Slide down", "Chimney"),
			up = h.addPrompt(fireplace, "Climb up", "Chimney"),
			inside = toward(fireplace.CFrame.Position, centre, 5, floorTop + 3),
			roof = chimneyTop.CFrame + Vector3.new(0, chimneyTop.Size.Y / 2 + 3, 0),
		})
		-- Ladder up the side so the chimney can be reached from the street
		-- (unless the model brings its own, like the Lair's up to its eaves).
		if not HouseKit.find(model, "Ladder") then
			local height = top - ctx.cframe.Position.Y
			h.newPart(
				model,
				"Ladder",
				Vector3.new(2, height, 2),
				ctx.cframe * CFrame.new(floor.Size.X / 2 + 1, height / 2, -floor.Size.Z / 4),
				Color3.fromRGB(110, 80, 60),
				nil,
				"TrussPart"
			)
		end
	end

	-- Hide spots: the house Wardrobe, or the Lair's HideSpot1/HideSpot2.
	local spots = {}
	for _, name in { "Wardrobe", "HideSpot1", "HideSpot2" } do
		local spot = HouseKit.find(model, name)
		if spot and spot:IsA("BasePart") then
			table.insert(spots, spot)
		end
	end
	for i = 1, math.min(plan.hideSpots, #spots) do
		local spot = spots[i]
		table.insert(stop.hideSpots, {
			prompt = h.addPrompt(spot, "Hide", if spot.Name == "Wardrobe" then "Wardrobe" else "Hiding spot"),
			inside = CFrame.new(spot.CFrame.Position.X, floorTop + 3, spot.CFrame.Position.Z),
			exit = toward(spot.CFrame.Position, centre, 4, floorTop + 3),
		})
	end

	-- Presents: on the spawn points first, then scattered across the floor.
	local spawns = {}
	for i = 1, 8 do
		local marker = HouseKit.find(model, "PresentSpawn" .. i)
		if marker then
			table.insert(spawns, topOf(marker))
		end
	end
	local pedestal = HouseKit.find(model, "ListPedestal")
	local halfX, halfZ = math.max(floor.Size.X / 2 - 4, 1), math.max(floor.Size.Z / 2 - 4, 1)
	local nextSpawn = 1
	for _, presentPlan in plan.presents do
		local at: Vector3
		if presentPlan.naughtyList and pedestal then
			at = topOf(pedestal)
		elseif spawns[nextSpawn] then
			at = spawns[nextSpawn]
			nextSpawn += 1
		else
			at = (floor.CFrame * CFrame.new(
				rng:NextNumber(-halfX, halfX),
				floor.Size.Y / 2,
				rng:NextNumber(-halfZ, halfZ)
			)).Position
		end
		local present = h.buildPresent(model, rng, at, presentPlan)
		present.inVault = plan.locked or nil
		table.insert(stop.presents, present)
	end

	model.Parent = ctx.parent

	local spawnMarker = HouseKit.find(model, "KrampusSpawn")
	if spawnMarker and spawnMarker:IsA("BasePart") then
		return CFrame.new(spawnMarker.CFrame.Position.X, floorTop + 6, spawnMarker.CFrame.Position.Z)
	end
	return nil
end

-- Every approved present variant: Assets.Present models plus an Assets.Presents folder.
function HouseKit.presentVariants(assets: Instance?): { Model }
	local list = {}
	if not assets then
		return list
	end
	local function add(m: Instance)
		if m:IsA("Model") and m:FindFirstChild("Box", true) then
			table.insert(list, m)
		end
	end
	for _, child in assets:GetChildren() do
		if child.Name == "Present" then
			add(child)
		end
	end
	local folder = assets:FindFirstChild("Presents")
	if folder then
		for _, child in folder:GetChildren() do
			add(child)
		end
	end
	return list
end

-- A present model standing at `position`, its Box's largest side = `edge` studs.
function HouseKit.placePresent(
	template: Model,
	position: Vector3,
	edge: number,
	yaw: number,
	colour: Color3
): Model
	local model = template:Clone()
	local box = (model.PrimaryPart or model:FindFirstChild("Box", true)) :: BasePart
	local size = box.Size
	local k = edge / math.max(size.X, size.Y, size.Z)
	HouseKit.place(
		model,
		CFrame.new(position + Vector3.new(0, size.Y * k / 2, 0)) * CFrame.Angles(0, yaw, 0),
		k
	)
	box.Color = colour
	return model
end

-- An approved NaughtyList standing at `position`, unscaled.
function HouseKit.placeList(template: Model, position: Vector3): Model
	local model = template:Clone()
	local primary = (model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)) :: BasePart
	model.PrimaryPart = primary
	HouseKit.place(model, CFrame.new(position + Vector3.new(0, primary.Size.Y / 2, 0)))
	return model
end

-- Places an approved VaultDoor in a doorway. bottom: the doorway's floor centre,
-- LookVector out of the house. Returns the swinging Door part.
function HouseKit.placeVaultDoor(parent: Instance, template: Model, bottom: CFrame): BasePart?
	local vault = template:Clone()
	local frame = (vault.PrimaryPart or vault:FindFirstChild("Frame", true)) :: BasePart
	HouseKit.place(vault, bottom * CFrame.new(0, frame.Size.Y / 2, 0))
	vault.Parent = parent
	local door = vault:FindFirstChild("Door", true)
	return if door and door:IsA("BasePart") then door else nil
end

-- Swings a door about its left edge (its local -X side). Pure CFrame maths.
function HouseKit.doorCFrame(closed: CFrame, size: Vector3, open: boolean): CFrame
	if not open then
		return closed
	end
	local hinge = CFrame.new(-size.X / 2, 0, 0)
	return closed * hinge * CFrame.Angles(0, math.rad(100), 0) * hinge:Inverse()
end

return HouseKit
