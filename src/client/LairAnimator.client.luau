--[[
	Brings Krampus's Lair (LairBuilder's Cuckoo Clock Den) to life on this
	player's machine: the clock ticks, the gears turn, the bells sway, the eyes
	in the corners blink, the cuckoo pops out on the sleigh horn and the bells
	light up one by one when Krampus wakes. The motion itself is LairMotion;
	the server only stamps CuckooAt / BellsAt on the Lair model.

	Purely visual and local (anchored parts moved with BulkMoveTo), and only
	while the camera is within LairMotion.Range of the Lair.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LairMotion = require(ReplicatedStorage.Shared.LairMotion)
local Util = require(ReplicatedStorage.Shared.Util)

type Piece = { part: BasePart, base: CFrame }
type Swinger = { pieces: { Piece }, pivot: Vector3, axis: Vector3, index: number, bell: BasePart? }
type Lair = {
	model: Model,
	centre: Vector3,
	hands: { { pieces: { Piece }, pivot: Vector3, axis: Vector3, minute: boolean } },
	gears: { { pieces: { Piece }, pivot: Vector3, axis: Vector3, radius: number, index: number } },
	bells: { Swinger },
	doors: { { piece: Piece, hinge: CFrame, sign: number } },
	figure: { Piece },
	figureOut: Vector3,
	eyes: { BasePart },
	shown: boolean?,
}

local lairs: { [Model]: Lair } = {}

local function pieces(root: Instance): { Piece }
	local list = {}
	if root:IsA("BasePart") then
		table.insert(list, { part = root, base = root.CFrame })
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, { part = d, base = d.CFrame })
		end
	end
	return list
end

local function find(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function setup(model: Model): Lair?
	local face, hub = find(model, "ClockFace"), find(model, "ClockHub")
	local floor = find(model, "Floor")
	if not (face and hub and floor) then
		return nil
	end
	local lair: Lair = {
		model = model,
		centre = floor.Position,
		hands = {},
		gears = {},
		bells = {},
		doors = {},
		figure = {},
		figureOut = Vector3.zero,
		eyes = {},
	}
	-- Clock hands turn about the face's outward normal (towards the hub).
	local outward = (hub.Position - face.Position).Unit
	for _, name in { "HourHand", "MinuteHand" } do
		local hand = find(model, name)
		if hand then
			table.insert(lair.hands, {
				pieces = pieces(hand),
				pivot = hub.Position,
				axis = outward,
				minute = name == "MinuteHand",
			})
		end
	end
	for i = 1, 3 do
		local gear = model:FindFirstChild("Gear" .. i, true)
		local gearHub = gear and gear:FindFirstChild("Hub")
		if gear and gearHub and gearHub:IsA("BasePart") then
			table.insert(lair.gears, {
				pieces = pieces(gear),
				pivot = gearHub.Position,
				axis = gearHub.CFrame.XVector, -- a Cylinder's axis
				radius = gear:GetAttribute("Radius") or 1,
				index = i,
			})
		end
	end
	for i = 1, 7 do
		local bell = find(model, "Bell" .. i)
		if bell then
			table.insert(lair.bells, {
				pieces = pieces(bell),
				pivot = bell.Position + bell.CFrame.YVector * LairMotion.BellDrop,
				axis = bell.CFrame.ZVector,
				index = i,
				bell = bell,
			})
		end
	end
	-- Cuckoo doors hinge on their outer edges.
	for _, d in { { "CuckooDoor", -1 }, { "CuckooDoorR", 1 } } do
		local door = find(model, d[1] :: string)
		if door then
			local sign = d[2] :: number
			table.insert(lair.doors, {
				piece = { part = door, base = door.CFrame },
				hinge = door.CFrame * CFrame.new(sign * door.Size.X / 2, 0, 0),
				sign = sign,
			})
		end
	end
	local figure = find(model, "CuckooKrampus")
	if figure then
		lair.figure = pieces(figure)
		lair.figureOut = figure.CFrame.ZVector * (figure.Size.X * 1.5)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "GlowEye" then
			table.insert(lair.eyes, d)
		end
	end
	return lair
end

local function turn(list: { Piece }, pivot: Vector3, axis: Vector3, angle: number, parts, cframes)
	local spin = CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * CFrame.new(-pivot)
	for _, p in list do
		table.insert(parts, p.part)
		table.insert(cframes, spin * p.base)
	end
end

local function since(model: Model, attribute: string, now: number): number?
	local at = model:GetAttribute(attribute)
	return if type(at) == "number" then now - at else nil
end

local function animate(lair: Lair, t: number, now: number)
	local parts, cframes = {}, {}
	local hour, minute = LairMotion.hands(now)
	for _, hand in lair.hands do
		-- Clockwise seen from the front = negative about the outward normal.
		turn(hand.pieces, hand.pivot, hand.axis, -(if hand.minute then minute else hour), parts, cframes)
	end
	for _, gear in lair.gears do
		turn(gear.pieces, gear.pivot, gear.axis, LairMotion.gear(t, gear.index, gear.radius), parts, cframes)
	end
	local sinceCuckoo = since(lair.model, "CuckooAt", now)
	local sinceBells = since(lair.model, "BellsAt", now)
	for _, bell in lair.bells do
		local swing, lit = LairMotion.bell(t, bell.index, sinceCuckoo, sinceBells)
		turn(bell.pieces, bell.pivot, bell.axis, swing, parts, cframes)
		local part = bell.bell :: BasePart
		part.Material = if lit then Enum.Material.Neon else Enum.Material.Metal
	end
	local open = LairMotion.cuckoo(sinceCuckoo)
	for _, door in lair.doors do
		local swing = door.hinge * CFrame.Angles(0, door.sign * open * 1.8, 0) * door.hinge:Inverse()
		table.insert(parts, door.piece.part)
		table.insert(cframes, swing * door.piece.base)
	end
	local pop = LairMotion.pop(open)
	local bounce = lair.figureOut * (pop * (1 + math.sin(t * 9) * 0.15))
	for _, p in lair.figure do
		p.part.Transparency = if pop > 0 then 0 else 1
		table.insert(parts, p.part)
		table.insert(cframes, p.base + bounce)
	end
	for i, eye in lair.eyes do
		eye.Transparency = if LairMotion.eyesOpen(t, (i + 1) // 2) then 0 else 1
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function track(model: Instance)
	if model:IsA("Model") and model.Name == "LairHouse" and not lairs[model] then
		-- Wait a frame so the whole model has replicated.
		task.defer(function()
			if model.Parent and model:GetAttribute("Style") == "CuckooClockDen" then
				lairs[model] = setup(model)
			end
		end)
	end
end

for _, d in workspace:GetDescendants() do
	track(d)
end
workspace.DescendantAdded:Connect(track)
workspace.DescendantRemoving:Connect(function(d)
	lairs[d :: any] = nil
end)

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera or next(lairs) == nil then
		return
	end
	local t = os.clock()
	local now = Util.now()
	for _, lair in lairs do
		if (camera.CFrame.Position - lair.centre).Magnitude <= LairMotion.Range then
			animate(lair, t, now)
		end
	end
end)
