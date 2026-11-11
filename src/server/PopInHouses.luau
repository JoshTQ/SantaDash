--[[
	Pop-in houses (Config.PopIn; Josh, 11 Nov 2026: "most houses on the map are
	closed with no entry, feels wrong").

	A Frozen Canal route has ~44 filler townhouses between its 9 robbable
	houses. A full kit house costs 95-150 parts and the route is already near
	the 9,000-part phone budget, so each filler is built as one solid block
	with a real front door (CanalTown, stop.popIns). When a Santa walks up to
	the door, it swings open, the block steps aside and a cosy one-room
	interior is built in its place: fireplace, tree, sofa, a warm lamp, and
	usually one small gift (Loot.planPopIn). When nobody's been near for a few
	seconds the room is packed away and the block comes back, so only a handful
	of rooms (MaxOpen) ever exist at once. Which rooms open and close is in
	PopInRules; this module builds them and runs them during a stop.

	buildRoom / open / close only touch Instances (no events), so the Lune
	tests build them; start() is the runtime loop.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local Loot = require(script.Parent.Loot)
local Parts = require(script.Parent.Parts)
local PopInRules = require(script.Parent.PopInRules)

local P = Config.PopIn
local T = 1 -- wall thickness (studs)
local DOOR_SWING = math.rad(100)

local FLOOR = Color3.fromRGB(165, 115, 75)
local BRICK = Color3.fromRGB(160, 70, 55)
local FIRE = Color3.fromRGB(255, 140, 40)
local PINE = Color3.fromRGB(40, 140, 75)
local TRUNK = Color3.fromRGB(110, 70, 45)
local GOLD = Color3.fromRGB(255, 200, 60)
local SOFA = Color3.fromRGB(200, 50, 60)
local RUG = Color3.fromRGB(240, 225, 190)
local WARM = Color3.fromRGB(255, 215, 150)
local WHITE = Color3.fromRGB(250, 250, 250)

local PopInHouses = {}

-- What CanalTown records for each filler townhouse.
export type Entry = {
	block: BasePart,
	door: BasePart,
	wreath: { BasePart },
	frame: CFrame, -- centre of the floor, LookVector out of the front door
	size: Vector3, -- the block's world size: X across (depth), Y height, Z along the street
	color: Color3,
	seed: number,
	-- Runtime state (PopInHouses):
	room: Model?,
	gift: any?, -- false: cookies, no gift; nil: not rolled yet; else its PresentPlan
	present: any?, -- the BuiltPresent while the room is open
	doorClosed: CFrame?,
	dressing: { { part: BasePart, rel: CFrame } }?,
}

-- Width (along the street) and depth (street to back wall) of a filler's room.
function PopInHouses.roomSize(entry: Entry): (number, number, number)
	return entry.size.Z, entry.size.X, entry.size.Y
end

-- Where the front door is (world), for PopInRules.
function PopInHouses.doorAt(entry: Entry): Vector3
	local _, depth = PopInHouses.roomSize(entry)
	return (entry.frame * CFrame.new(0, 0, -depth / 2)).Position
end

-- The gift (or none) in this house's room, rolled once per stop.
function PopInHouses.giftFor(entry: Entry): any?
	if entry.gift == nil then
		local rng = Random.new(entry.seed)
		entry.gift = if rng:NextNumber() < P.GiftChance then Loot.planPopIn() else false
	end
	return if entry.gift then entry.gift else nil
end

--[[
	Builds the room inside a filler's block (the caller hides the block):
	shell walls matching the block outside, a doorway of DoorWidth x
	DoorHeight, a ceiling at RoomHeight, and the furniture. buildPresent is
	MapBuilder's (stop.buildPresent). Returns the room and its BuiltPresent.
]]
function PopInHouses.buildRoom(entry: Entry, parent: Instance, buildPresent: any?): (Model, any?)
	local W, D, H = PopInHouses.roomSize(entry)
	local f = entry.frame
	local room = Instance.new("Model")
	room.Name = "PopInRoom"
	room:SetAttribute("KeepDetail", true) -- it comes and goes: never culled
	local function part(name, size, at: CFrame, color, material, className)
		return Parts.new(room, name, size, f * at, color, material, className)
	end
	local wall = entry.color
	local frontZ = -D / 2 + T / 2

	-- Shell. Same outside as the block, so the street doesn't change.
	part("Floor", Vector3.new(W - 2 * T, 0.4, D - 2 * T), CFrame.new(0, 0.2, 0), FLOOR, Enum.Material.WoodPlanks)
	part("WallBack", Vector3.new(W, H, T), CFrame.new(0, H / 2, D / 2 - T / 2), wall)
	for _, sx in { -1, 1 } do
		part("WallSide", Vector3.new(T, H, D - 2 * T), CFrame.new(sx * (W / 2 - T / 2), H / 2, 0), wall)
	end
	local seg = (W - P.DoorWidth) / 2
	for _, sx in { -1, 1 } do
		part("Front", Vector3.new(seg, H, T), CFrame.new(sx * (P.DoorWidth + seg) / 2, H / 2, frontZ), wall)
	end
	part(
		"Lintel",
		Vector3.new(P.DoorWidth, H - P.DoorHeight, T),
		CFrame.new(0, P.DoorHeight + (H - P.DoorHeight) / 2, frontZ),
		wall
	)
	local ceilingY = math.min(P.RoomHeight, H - 1)
	part("Ceiling", Vector3.new(W - 2 * T, 1, D - 2 * T), CFrame.new(0, ceilingY + 0.5, 0), WHITE)

	-- Furniture against the back wall, the middle left open to walk about.
	local backZ = D / 2 - T
	local fx = -W / 4
	part("Fireplace", Vector3.new(8, 6, 2), CFrame.new(fx, 3, backZ - 1), BRICK, Enum.Material.Brick)
	part("Fire", Vector3.new(4, 2.4, 0.6), CFrame.new(fx, 1.6, backZ - 2.1), FIRE, Enum.Material.Neon).CanCollide =
		false
	-- Sofa against the left wall, facing the room (the middle stays clear).
	local sx = -W / 2 + T
	part("Sofa", Vector3.new(3, 2, 8), CFrame.new(sx + 1.5, 1.4, backZ - 8), SOFA, Enum.Material.Fabric)
	part("SofaBack", Vector3.new(1, 3, 8), CFrame.new(sx + 0.5, 2.9, backZ - 8), SOFA, Enum.Material.Fabric)
	part("Rug", Vector3.new(10, 0.1, 6), CFrame.new(fx, 0.45, backZ - 5), RUG, Enum.Material.Fabric).CanCollide =
		false

	local tx, tz = W / 2 - T - 4, backZ - 4
	part("TreeTrunk", Vector3.new(1.2, 1.5, 1.2), CFrame.new(tx, 1.15, tz), TRUNK, Enum.Material.Wood)
	for i, tier in { { 6, 3 }, { 4.4, 2.8 }, { 2.8, 2.6 } } do
		local y = 1.9 + (i - 1) * 2.5 + tier[2] / 2
		part("Tree", Vector3.new(tier[1], tier[2], tier[1]), CFrame.new(tx, y, tz), PINE, Enum.Material.Grass)
	end
	local star = part("TreeStar", Vector3.one * 1.2, CFrame.new(tx, 9.6, tz), GOLD, Enum.Material.Neon)
	star.Shape = Enum.PartType.Ball
	star.CanCollide = false

	local lamp = part("Lamp", Vector3.one * 1.6, CFrame.new(0, ceilingY - 0.8, 0), WARM, Enum.Material.Neon)
	lamp.Shape = Enum.PartType.Ball
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = math.max(W, D)
	light.Brightness = 1.4
	light.Color = WARM
	light.Shadows = false
	light.Parent = lamp

	local present
	local gift = PopInHouses.giftFor(entry)
	if gift and buildPresent then
		local at = (f * CFrame.new(tx - 4.5, 0.4, tz)).Position
		present = buildPresent(room, Random.new(entry.seed), at, gift)
	else
		-- Somebody ate the gift money: a plate of cookies on a little table.
		local table_ = part("Table", Vector3.new(3, 2.6, 3), CFrame.new(tx - 4.5, 1.7, tz), TRUNK, Enum.Material.Wood)
		local plate = Parts.new(
			room,
			"Cookies",
			Vector3.new(0.3, 2.2, 2.2),
			table_.CFrame * CFrame.new(0, 1.45, 0) * CFrame.Angles(0, 0, math.pi / 2),
			WHITE
		)
		plate.Shape = Enum.PartType.Cylinder
		plate.CanCollide = false
	end

	Parts.settle(room)
	room.Parent = parent
	return room, present
end

-- The door's swung-open frame: hinged on its street-left edge, out onto the path.
local function swung(closed: CFrame, width: number, outward: Vector3): CFrame
	local hinge = closed * CFrame.new(0, 0, -width / 2)
	for _, angle in { DOOR_SWING, -DOOR_SWING } do
		local cf = hinge * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, width / 2)
		if (cf.Position - closed.Position):Dot(outward) > 0 then
			return cf
		end
	end
	return closed
end

--[[
	Opens a filler: hides its block, swings its door out and builds the room.
	Returns the room's BuiltPresent (nil when it has cookies instead).
]]
function PopInHouses.open(entry: Entry, buildPresent: any?): any?
	if entry.room then
		return entry.present
	end
	local block = entry.block
	block.Transparency = 1
	block.CanCollide = false
	block.CanQuery = false
	block.CanTouch = false

	local door = entry.door
	entry.doorClosed = entry.doorClosed or door.CFrame
	local closed = entry.doorClosed :: CFrame
	if not entry.dressing then
		local list = {}
		for _, p in entry.wreath do
			table.insert(list, { part = p, rel = closed:ToObjectSpace(p.CFrame) })
		end
		entry.dressing = list
	end
	local open = swung(closed, door.Size.Z, entry.frame.LookVector)
	door.CFrame = open
	door.CanCollide = false
	for _, d in entry.dressing :: any do
		d.part.CFrame = open * d.rel
	end

	local room, present = PopInHouses.buildRoom(entry, block.Parent :: Instance, buildPresent)
	entry.room = room
	entry.present = present
	return present
end

-- Packs a room away: the block and door come back. A gift nobody took stays
-- for the next visit (its old BuiltPresent is marked taken so nothing grabs it).
function PopInHouses.close(entry: Entry)
	local room = entry.room
	if not room then
		return
	end
	local present = entry.present
	if present and present.taken then
		entry.gift = false -- taken: no gift next time
	elseif present then
		present.taken = true
	end
	entry.present = nil
	room:Destroy()
	entry.room = nil

	local block = entry.block
	block.Transparency = 0
	block.CanCollide = true
	block.CanQuery = true
	block.CanTouch = true
	local closed = entry.doorClosed
	if closed then
		entry.door.CFrame = closed
		entry.door.CanCollide = true
		for _, d in entry.dressing or {} do
			d.part.CFrame = closed * d.rel
		end
	end
end

-- Anything with a Humanoid (a Santa, an elf, a dog, Krampus) inside the room?
-- (The stop's own model is ignored: walls and furniture aren't visitors.)
local function occupied(entry: Entry): boolean
	if OverlapParams == nil then
		return false -- headless test engine: Santas inside are always within CloseRadius anyway
	end
	local W, D, H = PopInHouses.roomSize(entry)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { entry.block.Parent :: Instance }
	local box = entry.frame * CFrame.new(0, H / 2, 0)
	for _, hit in Workspace:GetPartBoundsInBox(box, Vector3.new(W, H, D), params) do
		local model = hit:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return true
		end
	end
	return false
end

-- Runs a stop's pop-in houses until the returned cleanup (the sleigh leaves).
function PopInHouses.start(run, stop): (() -> ())?
	local entries: { Entry } = stop.popIns or {}
	if #entries == 0 then
		return nil
	end
	local states: { PopInRules.House } = {}
	for i, entry in entries do
		entry.gift = nil -- a fresh roll each time the stop is played
		states[i] = { doorAt = PopInHouses.doorAt(entry), open = false, lastNear = 0 }
	end
	local alive = true

	local function removePresent(present)
		local list = stop.presents
		for i = #list, 1, -1 do
			if list[i] == present then
				table.remove(list, i)
			end
		end
	end

	local function openOne(entry: Entry)
		local present = PopInHouses.open(entry, stop.buildPresent)
		SoundPlayer.at("DoorOpen", entry.door)
		if present then
			table.insert(stop.presents, present) -- elves can fetch it too
			present.prompt.Triggered:Connect(function(player)
				run:_grab(player, present)
			end)
		end
	end

	local function closeOne(entry: Entry)
		local present = entry.present
		PopInHouses.close(entry)
		if present then
			removePresent(present)
		end
	end

	task.spawn(function()
		while alive do
			task.wait(P.TickSeconds)
			if not alive or run.ended then
				break
			end
			local santas = {}
			for player in run.players do
				local root = Util.rootOf(player)
				if root then
					table.insert(santas, root.Position)
				end
			end
			for i, entry in entries do
				if states[i].open then
					states[i].occupied = occupied(entry)
				end
			end
			local opens, closes = PopInRules.step(states, santas, Util.now())
			for _, i in closes do
				closeOne(entries[i])
			end
			for _, i in opens do
				local ok, err = pcall(openOne, entries[i])
				if not ok then
					warn("[PopInHouses] couldn't open a house: " .. tostring(err))
				end
			end
		end
	end)

	return function()
		alive = false
		for _, entry in entries do
			closeOne(entry)
		end
	end
end

return PopInHouses
