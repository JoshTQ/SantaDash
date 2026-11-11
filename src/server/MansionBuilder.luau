--[[
	The Gingerbread Mansion (Josh picked option C from the big-house round,
	then "make it multiple floors"; approved 6 Nov 2026). A port of the 3D
	preview (/mnt/project-files/models/mansion/mansion-3d.html), built from
	plain parts at Roblox scale and trimmed for phones (~290 parts).

	80 studs along the street, 40 deep. A 3-storey great hall with an attic
	under its roof, and a 2-storey wing either side:
	  ground   hall (tree + 6 boxes, 2 cupboards), dining (west), library (east)
	  1st      a U-shaped gallery round the hall, kids' bedroom, big bedroom
	  2nd      the playroom over the whole hall (the noisy piano is a trap)
	  attic    two trunks, reached by a truss ladder from the playroom
	Storeys are 13.5 studs and doors 6 x 11, so Krampus fits everywhere.

	Follows the HouseKit contract (Floor, TypeSign, Chimney, ChimneyTop,
	Fireplace, Wardrobe, FrontDoor > Door, Ladder) plus:
	  SearchSpots   a Model per spot: attributes Level (0-3) and Room; a
	                SpotTrigger part (the Search prompt) with a GiftAt
	                Attachment where its gift appears; parts with an Open
	                CFrame attribute (part space) swing or slide when searched.
	  TreeBoxes     the boxes under the hall tree (each with a Ribbon child).
	  Piano         looks like a search spot; searching it is very loud.
	HouseKit hides the planned gifts in these; Run opens them.

	Built at the origin, front door facing -Z, ground at Y = 0. Event-free and
	PivotTo-free so the Lune tests can build it.
]]

local Parts = require(script.Parent.Parts)

local MansionBuilder = {}

-- Floor tops: ground, 1st, 2nd, attic.
MansionBuilder.Levels = { [0] = 1, [1] = 14.5, [2] = 28, [3] = 41.5 }
MansionBuilder.Size = Vector3.new(80, 60, 40)

local L = MansionBuilder.Levels
local HALL_TOP = 41.5 -- hall walls: up to the attic floor, then the roof
local WING_TOP = 28
local HALL_RISE, WING_RISE = 18, 9

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

local function rgb(n: number): Color3
	return Color3.fromRGB(bit32.rshift(n, 16) % 256, bit32.rshift(n, 8) % 256, n % 256)
end

local GINGER = rgb(0xC98A55)
local GINGER_D = rgb(0xA8693A)
local ICING = rgb(0xFFFFFF)
local PINK = rgb(0xFF8FC8)
local MINT = rgb(0x7FE3C0)
local RED = rgb(0xE2343E)
local GREEN = rgb(0x3FB874)
local BLUE = rgb(0x3A6FE0)
local GOLD = rgb(0xFFC83D)
local PURPLE = rgb(0xB07CFF)
local WOOD = rgb(0x8A5A3A)
local WOOD_D = rgb(0x6A3A1E)
local SLAB = rgb(0xE6D2BC)
local CARPET = rgb(0xA8283A)
local BULBS = { 0xFF4646, 0xFFCD50, 0x5AE678, 0x5AA0FF, 0xFF78D2 }
-- Window moods the client animates (client/WindowMoods): no extra parts.
local MOODS = { "Lamp", "Lamp", "TV", "Dark" }

type Opts = { deco: boolean?, mat: Enum.Material?, class: string?, shape: Enum.PartType? }

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	opts: Opts?
): BasePart
	local o = opts or {}
	local p = Parts.new(parent, name, size, cf, color, o.mat or SMOOTH, o.class)
	if o.shape then
		(p :: Part).Shape = o.shape
	end
	if o.deco then
		p.CanCollide = false
	end
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- A vertical cylinder (Roblox cylinders run along X).
local function upright(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
end

-- A cylinder facing out of the front (-Z), like a wreath or a clock.
local function facing(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0)
end

local function light(parent: Instance, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = Color3.fromRGB(255, 214, 160)
	l.Shadows = false
	l.Parent = parent
end

----------------------------------------------------------------------------
-- Shell
----------------------------------------------------------------------------

local function shell(m: Model)
	local floor = part(m, "Floor", Vector3.new(80, 1, 40), at(0, 0.5, 0), SLAB)
	m.PrimaryPart = floor
	part(m, "FrontStep", Vector3.new(10, 0.5, 3), at(0, 0.25, -21.5), ICING)

	-- Hall front with the doorway (6 x 11), back, and sides with a door into
	-- each wing on the ground and 1st floors.
	local h = HALL_TOP
	part(m, "Wall", Vector3.new(15, h, 1), at(-10.5, h / 2, -19.5), GINGER)
	part(m, "Wall", Vector3.new(15, h, 1), at(10.5, h / 2, -19.5), GINGER)
	part(m, "Wall", Vector3.new(6, h - 12, 1), at(0, 12 + (h - 12) / 2, -19.5), GINGER)
	part(m, "Wall", Vector3.new(36, h, 1), at(0, h / 2, 19.5), GINGER)
	for _, s in { -1, 1 } do
		local x = s * 17.5
		part(m, "Wall", Vector3.new(1, h, 20), at(x, h / 2, -10), GINGER)
		part(m, "Wall", Vector3.new(1, h, 14), at(x, h / 2, 13), GINGER)
		part(m, "Wall", Vector3.new(1, 2.5, 6), at(x, 13.25, 3), GINGER)
		part(m, "Wall", Vector3.new(1, h - 25.5, 6), at(x, 25.5 + (h - 25.5) / 2, 3), GINGER)
		-- Wing: front, back and outer side (its inner side is the hall wall).
		local cx = s * 29
		part(m, "Wall", Vector3.new(22, WING_TOP, 1), at(cx, WING_TOP / 2, -9.5), GINGER)
		part(m, "Wall", Vector3.new(22, WING_TOP, 1), at(cx, WING_TOP / 2, 19.5), GINGER)
		part(m, "Wall", Vector3.new(1, WING_TOP, 30), at(s * 39.5, WING_TOP / 2, 5), GINGER)
	end

	-- Front door (HouseKit swings it about its left edge) and the type sign.
	local frontDoor = Instance.new("Model")
	frontDoor.Name = "FrontDoor"
	frontDoor.Parent = m
	part(frontDoor, "Door", Vector3.new(6, 11, 0.5), at(0, 6.5, -19.5), BLUE)
	part(m, "TypeSign", Vector3.new(8, 1.6, 0.4), at(0, 12.9, -20.3), ICING, { deco = true })
end

----------------------------------------------------------------------------
-- Floors, stairs and the attic ladder
----------------------------------------------------------------------------

local function floors(m: Model)
	local y1, y2, y3 = L[1] - 0.5, L[2] - 0.5, L[3] - 0.5
	-- 1st floor: both wings, and a U-shaped gallery round the great hall.
	for _, s in { -1, 1 } do
		part(m, "Slab", Vector3.new(21, 1, 28), at(s * 28.5, y1, 5), SLAB)
		part(m, "Gallery", Vector3.new(6, 1, 38), at(s * 14, y1, 0), SLAB)
		part(m, "Balustrade", Vector3.new(0.4, 3, 28.5), at(s * 11.2, L[1] + 1.5, 0.25), ICING)
	end
	part(m, "Gallery", Vector3.new(22, 1, 5), at(0, y1, -16.5), SLAB)
	part(m, "Balustrade", Vector3.new(22.4, 3, 0.4), at(0, L[1] + 1.5, -13.8), ICING)
	-- 2nd floor over the whole hall, with the stairwell open at the back.
	part(m, "Slab", Vector3.new(34, 1, 33), at(0, y2, -2.5), SLAB)
	part(m, "Slab", Vector3.new(12, 1, 5), at(-11, y2, 16.5), SLAB)
	part(m, "Slab", Vector3.new(6, 1, 5), at(14, y2, 16.5), SLAB)
	part(m, "Balustrade", Vector3.new(16, 3, 0.4), at(3, L[2] + 1.5, 13.8), ICING)
	-- Attic floor, with a hatch for the ladder.
	part(m, "Slab", Vector3.new(19, 1, 38), at(-7.5, y3, 0), WOOD)
	part(m, "Slab", Vector3.new(12, 1, 38), at(11, y3, 0), WOOD)
	part(m, "Slab", Vector3.new(3, 1, 16), at(3.5, y3, -11), WOOD)
	part(m, "Slab", Vector3.new(3, 1, 19), at(3.5, y3, 9.5), WOOD)
	part(m, "AtticLadder", Vector3.new(2, 16, 2), at(3.5, 36, -1.5), WOOD, { class = "TrussPart" })

	-- Grand staircase along the back wall: ground -> left gallery (solid
	-- steps), then right gallery -> 2nd floor (treads over the first flight).
	local n = 14
	local rise = (L[1] - L[0]) / n
	local run1 = 15 / n
	for i = 1, n do
		local top = L[0] + i * rise
		local x = 4 - (i - 0.5) * run1
		part(
			m,
			"Stairs",
			Vector3.new(run1 + 0.05, top, 4),
			at(x, top / 2, 17),
			if i % 2 == 0 then CARPET else RED
		)
	end
	local run2 = 16 / n
	for i = 1, n do
		local top = L[1] + i * rise
		local x = 11 - (i - 0.5) * run2
		part(
			m,
			"Stairs",
			Vector3.new(run2 + 0.05, 0.6, 4),
			at(x, top - 0.3, 17),
			if i % 2 == 0 then CARPET else RED
		)
	end
end

----------------------------------------------------------------------------
-- Roofs, chimney and the outside
----------------------------------------------------------------------------

-- A gabled roof over x0..x1 (ridge along X) from the eave height up `rise`.
local function roof(
	m: Model,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	eave: number,
	rise: number,
	gables
)
	local w = x1 - x0 + 2
	local cx = (x0 + x1) / 2
	local half = (z1 - z0) / 2 + 1
	local cz = (z0 + z1) / 2
	local slope = math.sqrt(half * half + rise * rise)
	local angle = math.atan2(rise, half)
	for _, s in { -1, 1 } do
		part(
			m,
			"Roof",
			Vector3.new(w, 1, slope),
			at(cx, eave + rise / 2, cz + s * half / 2) * CFrame.Angles(s * angle, 0, 0),
			PINK
		)
		part(m, "Icing", Vector3.new(w, 0.8, 0.8), at(cx, eave - 0.2, cz + s * half), ICING, { deco = true })
	end
	-- Gable ends: two wedges each (a wedge's slope faces -Z).
	for _, gx in gables do
		local inner = (z1 - z0) / 2
		part(
			m,
			"Gable",
			Vector3.new(1, rise, inner),
			at(gx, eave + rise / 2, cz - inner / 2),
			GINGER_D,
			{ class = "WedgePart" }
		)
		part(
			m,
			"Gable",
			Vector3.new(1, rise, inner),
			at(gx, eave + rise / 2, cz + inner / 2) * CFrame.Angles(0, math.pi, 0),
			GINGER_D,
			{ class = "WedgePart" }
		)
	end
end

local function window(m: Model, rng: Random, x: number, y: number, z: number, w: number, h: number)
	part(m, "WindowFrame", Vector3.new(w + 0.8, h + 0.8, 0.2), at(x, y, z - 0.1), ICING, { deco = true })
	local pane = part(
		m,
		"Window",
		Vector3.new(w, h, 0.2),
		at(x, y, z - 0.25),
		Color3.fromRGB(255, 224, 122),
		{ deco = true, mat = NEON }
	)
	pane:SetAttribute("Mood", MOODS[rng:NextInteger(1, #MOODS)])
end

local function outside(m: Model, rng: Random)
	roof(m, -18, 18, -20, 20, HALL_TOP, HALL_RISE, { -17.5, 17.5 })
	roof(m, -40, -18, -10, 20, WING_TOP, WING_RISE, { -39.5 })
	roof(m, 18, 40, -10, 20, WING_TOP, WING_RISE, { 39.5 })
	-- The attic's dormer on the front of the hall roof.
	part(m, "Dormer", Vector3.new(6, 5, 4), at(0, 50, -12), GINGER)
	part(m, "DormerCap", Vector3.new(7, 0.8, 5), at(0, 52.9, -12), ICING)
	window(m, rng, 0, 50, -14, 3, 2.5)

	-- Chimney on the west wing (down to the dining-room fireplace), and a
	-- ladder up the wing's gable end so it can be reached from the garden.
	part(m, "Chimney", Vector3.new(3, 11, 3), at(-33, 35.5, 12), rgb(0xB04A3A))
	part(m, "ChimneyTop", Vector3.new(3.6, 0.8, 3.6), at(-33, 41.4, 12), ICING)
	part(m, "Ladder", Vector3.new(2, 38, 2), at(-42.5, 19, 5), WOOD, { class = "TrussPart" })

	-- Front: windows on every floor, icing bands, candy-cane corners, a big
	-- wreath, a clock and fairy lights along the eaves.
	local fz = -20
	for _, x in { -10, 10 } do
		window(m, rng, x, 6.5, fz, 4, 5)
	end
	for _, x in { -9, 9 } do
		window(m, rng, x, 20, fz, 4, 5.5)
	end
	for _, x in { -9, 0, 9 } do
		window(m, rng, x, 33.5, fz, 4, 5.5)
	end
	for _, s in { -1, 1 } do
		for _, y in { 6.5, 20 } do
			for _, dx in { -5, 5 } do
				window(m, rng, s * 29 + dx, y, -10, 3.4, 4.6)
			end
		end
		part(m, "IcingBand", Vector3.new(22, 0.6, 0.6), at(s * 29, L[1], -10.3), ICING, { deco = true })
	end
	for _, y in { L[1], L[2] } do
		part(m, "IcingBand", Vector3.new(36, 0.6, 0.6), at(0, y, -20.3), ICING, { deco = true })
	end
	for _, corner in
		{ { -18, -20, HALL_TOP }, { 18, -20, HALL_TOP }, { -40, -10, WING_TOP }, { 40, -10, WING_TOP } }
	do
		local x, z, h = corner[1], corner[2], corner[3]
		part(
			m,
			"CandyCane",
			Vector3.new(h, 1.4, 1.4),
			upright(x, h / 2, z),
			ICING,
			{ shape = Enum.PartType.Cylinder }
		)
		local bands = if h > 30 then 3 else 2
		for k = 1, bands do
			part(
				m,
				"CandyStripe",
				Vector3.new(1.4, 1.6, 1.6),
				upright(x, h * k / (bands + 1), z),
				RED,
				{ deco = true, shape = Enum.PartType.Cylinder }
			)
		end
	end
	part(
		m,
		"Wreath",
		Vector3.new(0.5, 5, 5),
		facing(0, 20, -20.4),
		GREEN,
		{ deco = true, shape = Enum.PartType.Cylinder }
	)
	part(
		m,
		"WreathBow",
		Vector3.new(1.2, 1.2, 1.2),
		at(0, 17.8, -20.8),
		RED,
		{ deco = true, shape = Enum.PartType.Ball }
	)
	part(
		m,
		"Clock",
		Vector3.new(0.4, 4, 4),
		facing(0, 39, -20.3),
		ICING,
		{ deco = true, shape = Enum.PartType.Cylinder }
	)
	part(m, "ClockHand", Vector3.new(0.2, 1.6, 0.2), at(0, 39.6, -20.6), RED, { deco = true })
	part(m, "ClockHand", Vector3.new(1.2, 0.2, 0.2), at(0.4, 39, -20.6), RED, { deco = true })
	local k = 0
	local function bulbs(x0: number, x1: number, y: number, z: number, step: number)
		local x = x0
		while x <= x1 + 0.01 do
			k += 1
			part(
				m,
				"Bulb",
				Vector3.new(0.6, 0.6, 0.6),
				at(x, y - math.abs(math.sin(x * 1.3)) * 0.4, z),
				rgb(BULBS[k % #BULBS + 1]),
				{ deco = true, mat = NEON, shape = Enum.PartType.Ball }
			)
			x += step
		end
	end
	bulbs(-18, 18, HALL_TOP - 0.8, -21.4, 3)
	bulbs(-40, -19, WING_TOP - 0.8, -11.4, 3.5)
	bulbs(19, 40, WING_TOP - 0.8, -11.4, 3.5)
end

----------------------------------------------------------------------------
-- Search spots
----------------------------------------------------------------------------

-- A search spot: a Model with a SpotTrigger part (the furniture you search),
-- where its gift appears (GiftAt), and any parts that open (see opens()).
local function spot(parent: Instance, name: string, room: string, level: number): Model
	local s = Instance.new("Model")
	s.Name = name
	s:SetAttribute("Level", level)
	s:SetAttribute("Room", room)
	s.Parent = parent
	return s
end

local function giftAt(trigger: BasePart, x: number, y: number, z: number)
	local a = Instance.new("Attachment")
	a.Name = "GiftAt"
	a.CFrame = trigger.CFrame:ToObjectSpace(CFrame.new(x, y, z))
	a.Parent = trigger
end

-- Marks a part to move by `open` (in its own space) when the spot is searched.
local function opens(p: BasePart, open: CFrame): BasePart
	p:SetAttribute("Open", open)
	return p
end

-- Swings about the part's back (+Z) edge, like a lid.
local function lid(depth: number, angle: number): CFrame
	return CFrame.new(0, 0, depth / 2) * CFrame.Angles(angle, 0, 0) * CFrame.new(0, 0, -depth / 2)
end

local function interior(m: Model)
	local spots = Instance.new("Folder")
	spots.Name = "SearchSpots"
	spots.Parent = m
	local y0, y1, y2, y3 = L[0], L[1], L[2], L[3]

	-- Ground, great hall: the tree with its boxes, two cupboards, a rug.
	part(
		m,
		"TreeTrunk",
		Vector3.new(3, 1.6, 1.6),
		upright(0, y0 + 1.5, 2),
		WOOD,
		{ shape = Enum.PartType.Cylinder }
	)
	for i, d in { 12, 9, 6 } do
		part(
			m,
			"TreeTier",
			Vector3.new(4, d, d),
			upright(0, y0 + 3 + (i - 0.5) * 4, 2),
			rgb(0x2E8A55),
			{ shape = Enum.PartType.Cylinder }
		)
	end
	local star = part(m, "TreeStar", Vector3.new(1.6, 1.6, 1.6), at(0, y0 + 15.8, 2), GOLD, {
		deco = true,
		mat = NEON,
		shape = Enum.PartType.Ball,
	})
	light(star, 26, 1)
	for i = 1, 8 do
		local a = i * 2.4
		local y = y0 + 4.5 + (i % 3) * 3.6
		local r = 6.2 - (i % 3) * 1.6
		part(
			m,
			"TreeBulb",
			Vector3.new(0.7, 0.7, 0.7),
			at(math.cos(a) * r, y, 2 + math.sin(a) * r),
			rgb(BULBS[i % #BULBS + 1]),
			{ deco = true, mat = NEON, shape = Enum.PartType.Ball }
		)
	end
	local boxes = Instance.new("Folder")
	boxes.Name = "TreeBoxes"
	boxes.Parent = m
	local layout = {
		{ -8.4, -3.6, 2.8, BLUE, ICING },
		{ -4.4, -7.6, 2.2, GOLD, RED },
		{ 1.2, -8.8, 3.2, GREEN, RED },
		{ 6, -6.8, 2.2, PURPLE, GOLD },
		{ 9.2, -2.8, 2.6, RED, GREEN },
		{ -1.6, -4.8, 2, PINK, GREEN },
	}
	for _, b in layout do
		local x, dz, s = b[1], b[2], b[3]
		local box = part(boxes, "TreeBox", Vector3.new(s, s, s), at(x, y0 + s / 2, 2 + dz), b[4])
		part(
			box,
			"Ribbon",
			Vector3.new(s * 0.2, s + 0.04, s + 0.04),
			at(x, y0 + s / 2, 2 + dz),
			b[5],
			{ deco = true }
		)
	end
	part(m, "Rug", Vector3.new(14, 0.1, 8), at(0, y0 + 0.05, -12), CARPET, { deco = true })
	for _, s in { -1, 1 } do
		local cup = spot(spots, if s < 0 then "Left cupboard" else "Right cupboard", "Great hall", 0)
		local body = part(cup, "SpotTrigger", Vector3.new(2, 8, 5), at(s * 16, y0 + 4, -6), MINT)
		local door =
			part(cup, "CupboardDoor", Vector3.new(0.3, 7.6, 4.6), at(s * 14.85, y0 + 4, -6), rgb(0xA8EBCF))
		-- Hinged on its front edge: swings out into the hall.
		opens(door, CFrame.new(0, 0, -2.3) * CFrame.Angles(0, -s * 1.6, 0) * CFrame.new(0, 0, 2.3))
		giftAt(body, s * 13.2, y0, -6)
	end

	-- Ground, west wing: dining room (table and cake, sideboard, fireplace).
	part(m, "Table", Vector3.new(10, 0.6, 5), at(-28, y0 + 3.8, 6), WOOD)
	part(m, "TableLeg", Vector3.new(2, 3.5, 2), at(-28, y0 + 1.75, 6), WOOD_D)
	part(
		m,
		"Cake",
		Vector3.new(1.2, 2, 2),
		upright(-25, y0 + 4.7, 6),
		PINK,
		{ shape = Enum.PartType.Cylinder }
	)
	local cake = spot(spots, "Cake dome", "Dining room", 0)
	local dome = part(cake, "SpotTrigger", Vector3.new(3, 3, 3), at(-25, y0 + 5.6, 6), rgb(0xE7F6FF), {
		deco = true,
		shape = Enum.PartType.Ball,
	})
	dome.Transparency = 0.5
	opens(dome, CFrame.new(0, 2.5, 0))
	giftAt(dome, -30.5, y0 + 4.1, 6)
	local side = spot(spots, "Sideboard", "Dining room", 0)
	local sb = part(side, "SpotTrigger", Vector3.new(9, 4, 2.4), at(-29, y0 + 2, -7.8), rgb(0xFFB3C9))
	opens(part(side, "Drawer", Vector3.new(8, 1.2, 2.2), at(-29, y0 + 3, -7.6), PINK), CFrame.new(0, 0, 1.8))
	giftAt(sb, -29, y0, -4.5)
	part(m, "Fireplace", Vector3.new(2.4, 7, 9), at(-37.8, y0 + 3.5, 6), rgb(0xB04A3A))
	part(m, "Mantel", Vector3.new(3, 0.6, 10), at(-37.6, y0 + 7.3, 6), ICING)
	part(m, "Hearth", Vector3.new(0.3, 3.5, 4), at(-36.5, y0 + 1.75, 6), rgb(0x2A1414), { deco = true })
	part(m, "Fire", Vector3.new(1.6, 1.6, 1.6), at(-36.6, y0 + 1, 6), rgb(0xFF8A2A), {
		deco = true,
		mat = NEON,
		shape = Enum.PartType.Ball,
	})
	local stock = spot(spots, "Stockings", "Dining room", 0)
	for i, z in { 3.5, 6, 8.5 } do
		local sock = part(
			stock,
			if i == 2 then "SpotTrigger" else "Stocking",
			Vector3.new(0.4, 2.2, 1.1),
			at(-36.3, y0 + 5.9, z),
			({ RED, GREEN, BLUE })[i],
			{ deco = true }
		)
		opens(sock, CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, 0.5) * CFrame.new(0, -1.1, 0))
		if i == 2 then
			giftAt(sock, -35, y0, 2.5)
		end
	end

	-- Ground, east wing: library (bookshelf, desk, armchair, the wardrobe to hide in).
	local shelf = spot(spots, "Bookshelf", "Library", 0)
	local body = part(shelf, "SpotTrigger", Vector3.new(12, 10, 2.4), at(29, y0 + 5, 17.8), WOOD)
	for r, colour in { RED, BLUE, GREEN } do
		local row =
			part(shelf, "Books", Vector3.new(11, 2.2, 0.4), at(29, y0 + 2.2 + (r - 1) * 3, 16.5), colour, {
				deco = true,
			})
		if r == 2 then
			opens(row, CFrame.Angles(0, 0, 0.12))
		end
	end
	giftAt(body, 29, y0, 15.2)
	local desk = spot(spots, "Desk drawers", "Library", 0)
	local top = part(desk, "SpotTrigger", Vector3.new(7, 3.8, 3.5), at(27, y0 + 1.9, -5), rgb(0xC98A55))
	opens(
		part(desk, "Drawer", Vector3.new(3, 1.2, 3.3), at(29, y0 + 2.8, -5.1), GINGER_D),
		CFrame.new(0, 0, 2.4)
	)
	giftAt(top, 25, y0 + 3.8, -5)
	part(m, "Armchair", Vector3.new(5, 2.5, 4.5), at(34, y0 + 1.25, 8), GREEN)
	part(m, "ArmchairBack", Vector3.new(5, 3.5, 1.2), at(34, y0 + 3.5, 10.5), rgb(0x2F9A60))
	part(m, "Wardrobe", Vector3.new(3, 10, 6), at(37.5, y0 + 5, -4), rgb(0x9FD3FF))

	-- 1st floor, west wing: kids' bedroom (bunk bed, toy box, rug).
	local bunk = spot(spots, "Under the bunk bed", "Kids' bedroom", 1)
	local lower = part(bunk, "SpotTrigger", Vector3.new(5, 2, 10), at(-35.5, y1 + 1, 12), WOOD)
	opens(
		part(bunk, "Drawer", Vector3.new(4.4, 1.2, 4), at(-35.5, y1 + 0.6, 9.2), GOLD),
		CFrame.new(0, 0, -3.5)
	)
	giftAt(lower, -35.5, y1, 4.2)
	local upper = part(m, "TopBunk", Vector3.new(5, 1.2, 10), at(-35.5, y1 + 5.6, 12), rgb(0x5AA0FF))
	light(upper, 18, 0.6)
	for _, z in { 7.2, 16.8 } do
		part(m, "BunkPost", Vector3.new(0.6, 7, 0.6), at(-33.2, y1 + 3.5, z), WOOD_D)
	end
	local toys = spot(spots, "Toy box", "Kids' bedroom", 1)
	local tb = part(toys, "SpotTrigger", Vector3.new(5, 3, 3), at(-22, y1 + 1.5, 14), RED)
	opens(part(toys, "Lid", Vector3.new(5.2, 0.8, 3.2), at(-22, y1 + 3.4, 14), GOLD), lid(3.2, 1.3))
	giftAt(tb, -22, y1, 11)
	part(m, "Rug", Vector3.new(8, 0.1, 6), at(-27, y1 + 0.05, 0), MINT, { deco = true })

	-- 1st floor, east wing: big bedroom (bed, dresser, jewellery box).
	part(m, "Bed", Vector3.new(8, 2, 10), at(32, y1 + 1, 12), WOOD)
	part(m, "Duvet", Vector3.new(7.6, 1, 8), at(32, y1 + 2.5, 11), PURPLE)
	local head = part(m, "Headboard", Vector3.new(8, 5, 0.8), at(32, y1 + 2.5, 17.6), WOOD_D)
	light(head, 18, 0.6)
	local dresser = spot(spots, "Dresser", "Big bedroom", 1)
	local db = part(dresser, "SpotTrigger", Vector3.new(8, 5, 3), at(24, y1 + 2.5, -7.5), rgb(0xFFE58A))
	opens(
		part(dresser, "Drawer", Vector3.new(7, 1.6, 2.8), at(24, y1 + 2.5, -7.3), GOLD),
		CFrame.new(0, 0, 2.4)
	)
	giftAt(db, 24, y1, -4.2)
	local jewels = spot(spots, "Jewellery box", "Big bedroom", 1)
	local jb = part(jewels, "SpotTrigger", Vector3.new(2, 1.2, 1.5), at(27, y1 + 5.6, -7.5), PINK)
	opens(part(jewels, "Lid", Vector3.new(2.1, 0.4, 1.6), at(27, y1 + 6.4, -7.5), GOLD), lid(1.6, 1.1))
	giftAt(jb, 23.8, y1 + 5, -7.5)

	-- 2nd floor: the playroom (rocking horse, toy shelf, the noisy piano).
	local horse = spot(spots, "Rocking horse saddlebag", "Playroom", 2)
	local hb = part(horse, "SpotTrigger", Vector3.new(2, 2.4, 6), at(-8, y2 + 2.6, -2), ICING)
	part(horse, "HorseHead", Vector3.new(1.8, 2.8, 2), at(-8, y2 + 4.4, -5.5), ICING)
	part(horse, "Rocker", Vector3.new(1.2, 0.6, 8), at(-8, y2 + 0.6, -2), RED)
	opens(
		part(horse, "Saddlebag", Vector3.new(1.4, 1.6, 1.6), at(-6.6, y2 + 2.3, -0.5), WOOD),
		CFrame.new(1.2, 0, 0)
	)
	giftAt(hb, -4.5, y2, 0)
	local tshelf = spot(spots, "Toy shelf", "Playroom", 2)
	local ts = part(tshelf, "SpotTrigger", Vector3.new(10, 6, 2.4), at(6, y2 + 3, -17.8), rgb(0xFFB3C9))
	light(ts, 22, 0.7)
	for i, colour in { RED, BLUE, GREEN } do
		local toy = part(tshelf, "Toy", Vector3.new(1.6, 1.6, 1.6), at(3 * i, y2 + 6.8, -17.6), colour, {
			deco = true,
			shape = Enum.PartType.Ball,
		})
		if i == 2 then
			opens(toy, CFrame.new(0, 0, 1.6))
		end
	end
	giftAt(ts, 6, y2, -14.8)
	local piano = part(m, "Piano", Vector3.new(8, 5, 3), at(-11, y2 + 2.5, 8), rgb(0x2A2140))
	part(piano, "PianoKeys", Vector3.new(7, 0.5, 1.2), at(-11, y2 + 3.2, 6.1), ICING, { deco = true })

	-- Attic: two trunks, dust sheets and a lantern.
	for i, def in { { -8, "Old trunk" }, { 9, "Steamer trunk" } } do
		local x = def[1]
		local trunk = spot(spots, def[2], "Attic", 3)
		local tr = part(trunk, "SpotTrigger", Vector3.new(5, 3, 3), at(x, y3 + 1.5, 3), WOOD_D)
		part(trunk, "TrunkBand", Vector3.new(5.2, 0.5, 3.2), at(x, y3 + 1.2, 3), GOLD, { deco = true })
		opens(part(trunk, "Lid", Vector3.new(5.2, 1, 3.2), at(x, y3 + 3.5, 3), rgb(0x8A4A26)), lid(3.2, 1.3))
		giftAt(tr, x + (if i == 1 then 1 else -1) * 0.5, y3, -0.2)
	end
	for _, p in { { -12, -6 }, { 0, 9 }, { 12, -6 } } do
		part(m, "DustSheet", Vector3.new(4, 1.6, 4), at(p[1], y3 + 0.8, p[2]), rgb(0xD8D2C4))
	end
	local lantern =
		part(m, "Lantern", Vector3.new(0.8, 1.2, 0.8), at(0, y3 + 4, -6), GOLD, { deco = true, mat = NEON })
	light(lantern, 24, 0.8)
end

function MansionBuilder.build(rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "MansionHouse"
	m:SetAttribute("Layout", "Mansion")
	m:SetAttribute("Style", "candy")
	shell(m)
	floors(m)
	outside(m, rng)
	interior(m)
	return m
end

return MansionBuilder
