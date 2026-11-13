--[[
	The two toys, built from parts (Josh, 12-13 Nov 2026: picked C + C, then
	"Do it" on the 3D preview, /mnt/project-files/models/toys/toys-3d.html):

	  Catapult  the Candy Cane Catapult (Snowball Launcher): a green wooden
	            cuff with a red-and-white strap, a gold hinge and spring, and
	            a striped candy-cane arm with a silver spoon and a snowball.
	  Globe     the Shaken Snow Globe (Glitter Bomb): a glass ball on a red
	            drum with a gold band and key, a tiny Lair cuckoo clock on a
	            snowy hill inside, and glitter swirling in it.

	Ports of the preview's buildCatapult / buildGlobe. Toy space is the
	preview's: +X forward (where it fires), +Y up, in preview units.

	  ToyBuilder.gear(id) -> Model   held by Santa (shared/GearAttach contract,
	                                 like server/WearBuilder): the Catapult in
	                                 his right hand, the Globe in his left.
	  ToyBuilder.display(id, parent, at) -> Model   on the toy stand, `at` its
	                                 bottom centre, facing -Z (the street side
	                                 is the front).
	Event-free, so Lune can build them.
]]

local Parts = require(script.Parent.Parts)

local ToyBuilder = {}

ToyBuilder.MODELS = { Catapult = "ToyCatapult", Globe = "ToyGlobe" }

-- Preview units -> studs: in hand, twice the preview's real-scale toy so it
-- reads on a phone (as the preview's "In Santa's hand" shows); on the stand,
-- bigger again.
ToyBuilder.HAND_SCALE = 1.76
ToyBuilder.STAND_SCALE = 3

local CANE_RED = Color3.fromRGB(215, 38, 61)
local CANE_WHITE = Color3.fromRGB(255, 248, 240)
local WOOD = Color3.fromRGB(47, 122, 79)
local DECK = Color3.fromRGB(35, 96, 61)
local GOLD = Color3.fromRGB(255, 200, 61)
local SILVER = Color3.fromRGB(216, 222, 234)
local SNOW = Color3.fromRGB(244, 249, 255)
local PLUM = Color3.fromRGB(91, 58, 140)
local ROOF = Color3.fromRGB(60, 42, 28)
local GLASS = Color3.fromRGB(231, 246, 255)
local PINK = Color3.fromRGB(255, 120, 220)

-- Toy space (+X forward) -> Roblox (forward is -Z): a quarter turn round Y.
local TOY = CFrame.Angles(0, math.pi / 2, 0)

type Kit = { parent: Instance, frame: CFrame, k: number }

local function part(
	kit: Kit,
	name: string,
	size: Vector3,
	x: number,
	y: number,
	z: number,
	color: Color3,
	rot: CFrame?
)
	local p = Parts.new(
		kit.parent,
		name,
		size * kit.k,
		kit.frame * CFrame.new(x * kit.k, y * kit.k, z * kit.k) * (rot or CFrame.identity),
		color
	)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- Roblox balls are always round, so no stretching (flat things are cylinders).
local function ball(kit: Kit, name: string, r: number, x: number, y: number, z: number, color: Color3)
	local p = part(kit, name, Vector3.one * r * 2, x, y, z, color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- A Cylinder part's axis is its X: `along` turns it from toy X.
local function cylinder(
	kit: Kit,
	name: string,
	r: number,
	length: number,
	x: number,
	y: number,
	z: number,
	color: Color3,
	along: CFrame?
)
	local p = part(kit, name, Vector3.new(length, r * 2, r * 2), x, y, z, color, along)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder standing up

local BUILD = {}

function BUILD.Catapult(kit: Kit)
	-- The wrist cuff (along the arm, forward) and its strap.
	cylinder(kit, "Cuff", 0.21, 0.42, 0, 0, 0, WOOD).Material = Enum.Material.Wood
	cylinder(kit, "StrapRed", 0.235, 0.06, -0.12, 0, 0, CANE_RED)
	cylinder(kit, "StrapWhite", 0.235, 0.06, 0.12, 0, 0, CANE_WHITE)
	part(kit, "Deck", Vector3.new(0.5, 0.08, 0.3), 0, 0.24, 0, DECK).Material = Enum.Material.Wood
	part(kit, "Hinge", Vector3.new(0.1, 0.16, 0.38), -0.18, 0.34, 0, GOLD).Material = Enum.Material.Metal
	cylinder(kit, "Spring", 0.05, 0.1, 0.05, 0.33, 0, SILVER, UPRIGHT).Material = Enum.Material.Metal
	-- The candy-cane arm, striped, tipped back a little (loaded).
	local tilt = 0.15
	for i = 0, 4 do
		local along = -0.14 + (i + 0.5) * 0.16
		cylinder(
			kit,
			"Arm",
			0.045,
			0.165,
			along * math.cos(tilt),
			0.4 + along * math.sin(tilt),
			0,
			if i % 2 == 0 then CANE_RED else CANE_WHITE,
			CFrame.Angles(0, 0, tilt)
		)
	end
	cylinder(kit, "Hook", 0.045, 0.16, -0.2, 0.46, 0, CANE_RED, UPRIGHT)
	local tipX, tipY = 0.68 * math.cos(tilt), 0.4 + 0.68 * math.sin(tilt)
	cylinder(kit, "Spoon", 0.13, 0.06, tipX, tipY, 0, SILVER, UPRIGHT).Material = Enum.Material.Metal
	ball(kit, "Snowball", 0.09, tipX, tipY + 0.08, 0, SNOW).Material = Enum.Material.Snow
end

function BUILD.Globe(kit: Kit)
	cylinder(kit, "Base", 0.26, 0.16, 0, 0.08, 0, CANE_RED, UPRIGHT)
	cylinder(kit, "Band", 0.27, 0.04, 0, 0.15, 0, GOLD, UPRIGHT).Material = Enum.Material.Metal
	part(kit, "Key", Vector3.new(0.04, 0.1, 0.16), -0.3, 0.08, 0, GOLD).Material = Enum.Material.Metal
	cylinder(kit, "Hill", 0.2, 0.07, 0, 0.19, 0, SNOW, UPRIGHT).Material = Enum.Material.Snow
	part(kit, "Clock", Vector3.new(0.12, 0.12, 0.08), 0, 0.27, 0, PLUM)
	part(kit, "Roof", Vector3.new(0.15, 0.05, 0.11), 0, 0.355, 0, ROOF)
	local glass = ball(kit, "Glass", 0.27, 0, 0.4, 0, GLASS)
	glass.Material = Enum.Material.Glass
	glass.Transparency = 0.6
	-- The glitter storm inside.
	local at = Instance.new("Attachment")
	at.Name = "Glitter"
	at.Parent = glass
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(PINK, GOLD)
	sparkles.LightEmission = 0.8
	sparkles.Size = NumberSequence.new(0.04 * kit.k)
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Speed = NumberRange.new(0.1 * kit.k, 0.3 * kit.k)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Rate = 12
	sparkles.LockedToPart = true
	sparkles.Parent = at
end

local function newModel(id: string): Model
	local m = Instance.new("Model")
	m.Name = ToyBuilder.MODELS[id]
	return m
end

-- Where each toy sits on the classic Santa's hand at his bind pose, in root
-- space (the mittens' hands in server/WearBuilder: x ±1.29, y -1.87).
local HANDS = {
	Catapult = { bone = "RightHand", at = CFrame.new(1.29, -1.75, -0.2) },
	Globe = { bone = "LeftHand", at = CFrame.new(-1.29, -2.05, -0.35) },
}

function ToyBuilder.gear(id: string): Model?
	local build, hand = BUILD[id], HANDS[id]
	if not build then
		return nil
	end
	local m = newModel(id)
	local root = Parts.new(m, "Root", Vector3.one, CFrame.new(), Color3.new(1, 1, 1))
	root.Transparency = 1
	root.CanCollide = false
	m.PrimaryPart = root
	local holder = Instance.new("Model")
	holder.Name = "Toy"
	holder:SetAttribute("FollowBone", hand.bone)
	holder.Parent = m
	build({ parent = holder, frame = hand.at * TOY, k = ToyBuilder.HAND_SCALE })
	return m
end

function ToyBuilder.display(id: string, parent: Instance, at: CFrame): Model?
	local build = BUILD[id]
	if not build then
		return nil
	end
	local m = newModel(id)
	-- The cuff's centre sits a cuff-radius up; the globe's base is its bottom.
	local lift = if id == "Catapult" then 0.21 * ToyBuilder.STAND_SCALE else 0
	build({ parent = m, frame = at * CFrame.new(0, lift, 0) * TOY, k = ToyBuilder.STAND_SCALE })
	m.Parent = parent
	return m
end

return ToyBuilder
