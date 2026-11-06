--[[
	The four warm-gear pieces for Krampus's Lair, built from parts (Josh,
	6 Nov 2026: approved sets A + D, "build from parts", no Meshy credits).
	Ports of the approved 3D preview (/mnt/project-files/models/warmgear/
	warmgear-3d.html, addGear) at Santa's scale.

	Each model follows shared/GearAttach's contract: modelled around the
	classic Santa in his bind pose, with the PrimaryPart "Root" where his
	HumanoidRootPart is (facing -Z), and each piece (or child model) carries
	a FollowBone attribute, so one model fits every suit.

	  WearBuilder.build(id) -> Model?   ids: Scarf, Mittens, DuckieRing, HotWaterBottle
	  WearBuilder.MODELS                id -> model name (Config.Wardrobe item .model)

	A model of the same name in ServerStorage.Assets (e.g. a later Meshy
	scarf) wins over these: see server/Wardrobe.
]]

local Parts = require(script.Parent.Parts)

local WearBuilder = {}

-- Preview units -> studs: the preview Santa is ~6.25 units to his hat tip,
-- the game Santa 5.5 studs; his root sits 3 studs over his feet.
local S = 0.88
local ROOT_Y = 3 / S

-- A preview position (Santa facing +Z, feet at y 0) in root space (facing -Z).
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(-x * S, (y - ROOT_Y) * S, -z * S)
end

local RED = Color3.fromRGB(232, 51, 59)
local CREAM = Color3.fromRGB(247, 243, 234)
local KNIT = Color3.fromRGB(46, 155, 87)
local DUCK = Color3.fromRGB(255, 217, 46)
local BEAK = Color3.fromRGB(255, 138, 31)
local INK = Color3.fromRGB(30, 35, 64)
local RUBBER = Color3.fromRGB(255, 127, 158)
local CAP = Color3.fromRGB(176, 42, 70)
local COVER = Color3.fromRGB(201, 40, 58)

local function model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	local root = Parts.new(m, "Root", Vector3.new(1, 1, 1), CFrame.new(), Color3.new(1, 1, 1))
	root.Transparency = 1
	root.CanCollide = false
	m.PrimaryPart = root
	return m
end

local function holder(parent: Instance, name: string, bone: string): Model
	local h = Instance.new("Model")
	h.Name = name
	h:SetAttribute("FollowBone", bone)
	h.Parent = parent
	return h
end

local function ball(
	parent: Instance,
	name: string,
	r: number,
	cframe: CFrame,
	color: Color3,
	stretch: Vector3?
)
	local size = (stretch or Vector3.one) * r * 2 * S
	local p = Parts.new(parent, name, size, cframe, color)
	p.Shape = Enum.PartType.Ball
	p.CanCollide = false
	return p
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
)
	local p = Parts.new(parent, name, size * S, cframe, color, material)
	p.CanCollide = false
	return p
end

-- Balls round a ring (there is no torus part): radius R, tube r, at `centre`.
local function ring(
	parent: Instance,
	name: string,
	centre: Vector3,
	R: number,
	r: number,
	n: number,
	colors: { Color3 },
	squash: Vector3?
)
	local sq = squash or Vector3.one
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local x, z = centre.X + math.cos(a) * R * sq.X, centre.Z + math.sin(a) * R * sq.Z
		ball(parent, name, r, at(x, centre.Y, z), colors[i % #colors + 1], Vector3.new(1, 0.9, 1))
	end
end

local BUILD = {}

function BUILD.Scarf(): Model
	local m = model("WearScarf")
	local h = holder(m, "Scarf", "Spine")
	ring(h, "ScarfLoop", Vector3.new(0, 3.12, 0), 0.88, 0.32, 12, { RED, CREAM }, Vector3.new(1.05, 1, 1.1))
	for k = 0, 3 do
		block(
			h,
			"ScarfTail",
			Vector3.new(0.5, 0.32, 0.2),
			at(-0.55, 2.86 - k * 0.32, 0.92),
			if k % 2 == 0 then RED else CREAM,
			Enum.Material.Fabric
		)
	end
	for i = 0, 4 do
		block(
			h,
			"ScarfTassel",
			Vector3.new(0.07, 0.22, 0.07),
			at(-0.75 + i * 0.1, 1.6, 0.98),
			CREAM,
			Enum.Material.Fabric
		)
	end
	return m
end

function BUILD.Mittens(): Model
	local m = model("WearMittens")
	-- Preview x < 0 is Santa's right hand (he faces +Z there).
	for _, side in { { "RightHand", -1 }, { "LeftHand", 1 } } do
		local bone, sx = side[1], side[2]
		local h = holder(m, bone == "RightHand" and "RightMitten" or "LeftMitten", bone)
		local x = sx * 1.47
		local mitt = ball(h, "Mitten", 0.44, at(x, 1.29, 0), KNIT, Vector3.new(1, 1.1, 0.95))
		mitt.Material = Enum.Material.Fabric
		ball(h, "Thumb", 0.17, at(x - sx * 0.38, 1.39, 0.12), KNIT, Vector3.new(1, 1.4, 1)).Material =
			Enum.Material.Fabric
		local cuff = block(
			h,
			"Cuff",
			Vector3.new(0.24, 0.84, 0.84),
			at(x, 1.71, 0) * CFrame.Angles(0, 0, math.pi / 2),
			CREAM,
			Enum.Material.Fabric
		)
		cuff.Shape = Enum.PartType.Cylinder
		ball(h, "Bobble", 0.16, at(x, 1.75, 0.42), RED)
	end
	return m
end

function BUILD.DuckieRing(): Model
	local m = model("WearDuckieRing")
	local h = holder(m, "DuckieRing", "Hips")
	ring(h, "Ring", Vector3.new(0, 1.62, 0.12), 1.45, 0.42, 14, { DUCK })
	for _, p in h:GetChildren() do
		if p:IsA("BasePart") then
			p.Material = Enum.Material.SmoothPlastic
			p.Reflectance = 0.05
		end
	end
	local hx, hy, hz = -0.75, 2.17, 1.37
	ball(h, "DuckNeck", 0.32, at(hx, hy - 0.25, hz), DUCK, Vector3.new(1, 1.3, 1))
	ball(h, "DuckHead", 0.42, at(hx, hy + 0.32, hz), DUCK)
	ball(h, "DuckBeak", 0.16, at(hx, hy + 0.26, hz + 0.45), BEAK, Vector3.new(1.4, 0.6, 1.3))
	for _, sd in { -1, 1 } do
		ball(h, "DuckEye", 0.07, at(hx + sd * 0.18, hy + 0.45, hz + 0.34), INK)
	end
	ball(h, "DuckTail", 0.18, at(0.6, 1.97, -1.18), DUCK, Vector3.new(1, 0.8, 1.4))
	return m
end

function BUILD.HotWaterBottle(): Model
	local m = model("WearHotWaterBottle")
	local h = holder(m, "HotWaterBottle", "Spine")
	local x, y, z = 0.05, 2.4, 1.08
	block(h, "Bottle", Vector3.new(0.82, 0.86, 0.26), at(x, y, z), RUBBER)
	ball(h, "BottleTop", 0.41, at(x, y + 0.42, z), RUBBER, Vector3.new(1, 0.35, 0.33))
	ball(h, "BottleBottom", 0.41, at(x, y - 0.42, z), RUBBER, Vector3.new(1, 0.35, 0.33))
	block(h, "BottleNeck", Vector3.new(0.3, 0.2, 0.22), at(x, y + 0.62, z), RUBBER)
	block(h, "BottleCap", Vector3.new(0.28, 0.16, 0.28), at(x, y + 0.78, z), CAP)
	for i = 0, 3 do
		block(h, "BottleRib", Vector3.new(0.6, 0.05, 0.05), at(x, y + 0.3 - i * 0.14, z + 0.14), CAP)
	end
	block(
		h,
		"BottleCover",
		Vector3.new(0.86, 0.42, 0.3),
		at(x, y - 0.3, z + 0.01),
		COVER,
		Enum.Material.Fabric
	)
	for _, sd in { -1, 1 } do
		block(
			h,
			"BottleStrap",
			Vector3.new(0.08, 0.95, 0.06),
			at(x + sd * 0.32, y + 0.95, z - 0.12) * CFrame.Angles(0.35, 0, sd * 0.35),
			COVER,
			Enum.Material.Fabric
		)
	end
	-- glows warm: the client may pulse this (it's a cosy light, not a fire)
	local glow = Instance.new("PointLight")
	glow.Name = "Warm"
	glow.Color = Color3.fromRGB(255, 154, 90)
	glow.Brightness = 0.6
	glow.Range = 6
	glow.Parent = h:FindFirstChild("Bottle")
	return m
end

WearBuilder.MODELS = {
	Scarf = "WearScarf",
	Mittens = "WearMittens",
	DuckieRing = "WearDuckieRing",
	HotWaterBottle = "WearHotWaterBottle",
}

-- A fresh copy of a piece, or nil for an unknown id.
function WearBuilder.build(id: string): Model?
	local fn = BUILD[id]
	return if fn then fn() else nil
end

return WearBuilder
