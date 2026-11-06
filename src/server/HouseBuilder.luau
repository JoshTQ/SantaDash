--[[
	The approved house kit (Josh, 1 Nov 2026: a mix of Candy Suburban and
	Alpine, three layouts, randomised per house), built from plain parts.
	A port of buildHouse(seed, style, layout) in the models thread's 3D
	preview (/mnt/project-files/models/house/house-3d.html), trimmed for
	phones: no fence or snowman (the map's gardens add those), one part per
	trim, and Fire/Smoke instances instead of flame and smoke meshes.

	HouseBuilder.build returns a House model that follows the HouseKit
	contract: Floor (PrimaryPart), TypeSign, Chimney, ChimneyTop, Fireplace,
	LooseBrick, Wardrobe, FrontDoor > Door (one part, hinged on its left edge),
	Stairs (Two-storey), InnerDoorway (L-shape), Tree and PresentSpawn1-8
	Attachments; attributes Style, Layout, Seed, HouseType.

	The model is built at the origin, front door facing -Z, ground at Y = 0.
	The same seed gives the same colours and choices as the 3D preview (the
	preview's mulberry32 random numbers, called in the same order).

	Event-free and PivotTo-free so the Lune tests can build it.
]]

local Parts = require(script.Parent.Parts)

local HouseBuilder = {}

-- Studs per preview unit. Wider than tall so a 28-stud plot fits a cottage,
-- tall enough that doors clear a Santa and Krampus.
HouseBuilder.ScaleH = 3.4
HouseBuilder.ScaleV = 4

HouseBuilder.Styles = { "candy", "alpine" }
-- "Room Mix" (Josh, 6 Nov 2026): 5-7 rooms over 1-2 floors, see HouseBuilder.roomPlan.
HouseBuilder.Layouts = { "Cottage", "Two-storey", "L-shape", "Room Mix" }
HouseBuilder.Types = { "Snowflake", "Bell", "Horns" }

local SX, SY = HouseBuilder.ScaleH, HouseBuilder.ScaleV
local ROOT = CFrame.Angles(0, math.pi, 0) -- the preview's front is +Z; Roblox's is -Z

local FH, T = 3.2, 0.3 -- floor height and wall thickness (preview units)
local DOOR_GAP = { w = 1.7, h = 2.7 } -- wider than the preview's 1.3 x 2.4: Krampus fits
local BASE = 0.3 -- top of the Floor slab

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

local PALETTE = {
	candy = {
		walls = { 0xFFB3C9, 0xA8EBCF, 0xFFE58A, 0x9FD3FF, 0xD3B8FF, 0xFFC79A },
		roofs = { 0xE2386A, 0x2FA89A, 0x5A7BE0, 0x7A4A2C, 0xB04AD8 },
		trims = { 0xFFFFFF },
		doors = { 0xE2343E, 0x3FB874, 0x3A6FE0, 0xFFC83D, 0xB07CFF },
		shutters = { 0xFFFFFF },
	},
	alpine = {
		walls = { 0xF4E8D4, 0xC98A54, 0xE8D2B0, 0xA86A3A, 0xF6F0E6 },
		roofs = { 0x5A2E1E, 0x4A5068, 0x8A2A22, 0x3A2A22 },
		trims = { 0x4A2C1C, 0x5A3A22 },
		doors = { 0x6A3A1E, 0x2F6B4A, 0x8A1A22, 0x2B4A80 },
		shutters = { 0xC42A33, 0x2F7A4A, 0x2B5AA8, 0xE8A23A },
	},
}
HouseBuilder.Palette = PALETTE

local BULBS = { 0xFF4A4A, 0x4AD07A, 0x4A8AFF, 0xFFD23A, 0xFF7AD0 }
local BAUBLES = { 0xE2343E, 0xFFC83D, 0x3A6FE0 }

----------------------------------------------------------------------------
-- Random numbers: mulberry32, bit-for-bit the preview's.
----------------------------------------------------------------------------

local TWO32 = 4294967296

local function imul(a: number, b: number): number
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	return (al * b + ((ah * b) % 65536) * 65536) % TWO32
end

function HouseBuilder.mulberry(seed: number): () -> number
	local a = seed % TWO32
	return function()
		a = (a + 0x6D2B79F5) % TWO32
		local t = imul(bit32.bxor(a, bit32.rshift(a, 15)), bit32.bor(a, 1))
		t = bit32.bxor((t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61))) % TWO32, t)
		return bit32.bxor(t, bit32.rshift(t, 14)) / TWO32
	end
end

local function pick<T>(rng: () -> number, list: { T }): T
	return list[math.floor(rng() * #list) + 1]
end

-- JavaScript's Math.round (halves round up).
local function round(x: number): number
	return math.floor(x + 0.5)
end

local function hex(n: number): Color3
	return Color3.fromRGB(bit32.rshift(n, 16) % 256, bit32.rshift(n, 8) % 256, n % 256)
end

local function shade(c: Color3, f: number): Color3
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

----------------------------------------------------------------------------
-- Part helpers. Frames are CFrames in studs, in the preview's orientation;
-- ROOT turns everything round at the end so the front faces -Z.
----------------------------------------------------------------------------

type Opts = { deco: boolean?, mat: Enum.Material?, class: string?, shape: Enum.PartType? }

local function raw(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	opts: Opts?
): BasePart
	local o = opts or {}
	local part = Parts.new(parent, name, size, ROOT * cf, color, o.mat or SMOOTH, o.class)
	if o.shape then
		(part :: Part).Shape = o.shape
	end
	if o.deco then
		part.CanCollide = false
	end
	return part
end

-- A box sized and placed in preview units inside frame f.
local function box(
	parent: Instance,
	name: string,
	w: number,
	h: number,
	d: number,
	color: Color3,
	f: CFrame,
	x: number,
	y: number,
	z: number,
	opts: Opts?
): BasePart
	return raw(
		parent,
		name,
		Vector3.new(w * SX, h * SY, d * SX),
		f * CFrame.new(x * SX, y * SY, z * SX),
		color,
		opts
	)
end

local function at(f: CFrame, x: number, y: number, z: number): CFrame
	return f * CFrame.new(x * SX, y * SY, z * SX)
end

-- A ball of the given diameter (studs).
local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	cf: CFrame,
	color: Color3,
	mat: Enum.Material?
)
	return raw(
		parent,
		name,
		Vector3.one * diameter,
		cf,
		color,
		{ deco = true, shape = Enum.PartType.Ball, mat = mat }
	)
end

-- An upright cylinder (studs).
local function post(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	cf: CFrame,
	color: Color3,
	opts: Opts?
)
	local o = table.clone(opts or {})
	o.shape = Enum.PartType.Cylinder
	return raw(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		cf * CFrame.Angles(0, 0, math.pi / 2),
		color,
		o
	)
end

-- A bar from a to b (studs, frame space).
local function bar(parent: Instance, name: string, a: Vector3, b: Vector3, thick: number, color: Color3)
	return raw(
		parent,
		name,
		Vector3.new(thick, thick, (b - a).Magnitude),
		CFrame.lookAt(
			(a + b) / 2,
			b,
			if math.abs((b - a).Unit.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
		),
		color,
		{ deco = true }
	)
end

type Gap = { c: number, w: number, h: number }

-- A wall along X with openings (preview units).
local function segX(parent, f, x0, x1, z, y0, h, th, col, gaps: { Gap }, name)
	local xs = x0
	local sorted = table.clone(gaps)
	table.sort(sorted, function(a, b)
		return a.c < b.c
	end)
	for _, gp in sorted do
		local a = gp.c - gp.w / 2
		if a > xs + 0.01 then
			box(parent, name, a - xs, h, th, col, f, (xs + a) / 2, y0 + h / 2, z)
		end
		if h > gp.h then
			box(parent, name, gp.w, h - gp.h, th, col, f, gp.c, y0 + gp.h + (h - gp.h) / 2, z)
		end
		xs = gp.c + gp.w / 2
	end
	if x1 > xs + 0.01 then
		box(parent, name, x1 - xs, h, th, col, f, (xs + x1) / 2, y0 + h / 2, z)
	end
end

-- A wall along Z with openings (preview units).
local function segZ(parent, f, z0, z1, x, y0, h, th, col, gaps: { Gap }, name)
	local zs = z0
	for _, gp in gaps do
		local a = gp.c - gp.w / 2
		if a > zs + 0.01 then
			box(parent, name, th, h, a - zs, col, f, x, y0 + h / 2, (zs + a) / 2)
		end
		if h > gp.h then
			box(parent, name, th, h - gp.h, gp.w, col, f, x, y0 + gp.h + (h - gp.h) / 2, gp.c)
		end
		zs = gp.c + gp.w / 2
	end
	if z1 > zs + 0.01 then
		box(parent, name, th, h, z1 - zs, col, f, x, y0 + h / 2, (zs + z1) / 2)
	end
end

----------------------------------------------------------------------------
-- The house
----------------------------------------------------------------------------

type Ctx = {
	model: Model,
	rng: () -> number,
	alp: boolean,
	C: { [string]: Color3 },
	floorFront: number, -- front edge of the Floor slab (preview units)
	deco: (() -> number)?, -- window dressing rolls (kept apart so seeds still match the preview)
}

type Block = {
	f: CFrame,
	cx: number,
	cz: number,
	w: number,
	d: number,
	H: number,
	wallTop: number, -- preview units
	topS: number, -- roof ridge height, studs
	ddS: number,
	doorX: number?, -- block-local, when the block has the front door
}

-- What's going on behind each window (Josh, 6 Nov 2026: "outside should be
-- more dynamic, not just blank windows"). The pane's Mood attribute drives
-- client/WindowMoods: TV glow flickers, dark rooms light up now and then.
HouseBuilder.WindowMoods = {
	{ "Lamp", 3 },
	{ "Curtains", 3 },
	{ "TV", 2 },
	{ "Dark", 2 },
	{ "Candle", 2 },
	{ "Cat", 1 },
	{ "Tree", 1 },
	{ "Star", 1 },
}
local MOOD_TOTAL = 0
for _, mood in HouseBuilder.WindowMoods do
	MOOD_TOTAL += mood[2]
end
local function rollMood(rng: () -> number): string
	local r = rng() * MOOD_TOTAL
	for _, mood in HouseBuilder.WindowMoods do
		r -= mood[2]
		if r < 0 then
			return mood[1]
		end
	end
	return "Lamp"
end
local CURTAINS = { 0xE2343E, 0x3FB874, 0xB07CFF, 0xFFC83D, 0xFF8FC8, 0x3A6FE0 }

local function window(ctx: Ctx, f: CFrame)
	local m, alp, C = ctx.model, ctx.alp, ctx.C
	local frame = if alp then C.trim else C.white
	if alp then
		box(m, "Shutters", 2.0, 1.35, 0.08, C.shut, f, 0, 0, 0.02, { deco = true })
	end
	box(m, "WindowFrame", 1.15, 1.35, 0.14, frame, f, 0, 0, 0, { deco = true })
	local pane = box(m, "Window", 0.85, 1.05, 0.05, C.pane, f, 0, 0, 0.07, { deco = true, mat = NEON })
	if ctx.deco then
		local mood = rollMood(ctx.deco)
		pane:SetAttribute("Mood", mood)
		if mood == "Curtains" then
			local cloth = hex(pick(ctx.deco, CURTAINS))
			for _, k in { -1, 1 } do
				box(m, "Curtain", 0.24, 1.0, 0.04, cloth, f, k * 0.29, 0.02, 0.11, { deco = true })
			end
		elseif mood == "TV" then
			pane.Color = hex(0x8FD0FF)
		elseif mood == "Dark" then
			pane.Color = hex(0x2B3550)
			pane.Material = SMOOTH
		elseif mood == "Candle" then
			box(
				m,
				"Candle",
				0.12,
				0.3,
				0.12,
				hex(0xFFF4D6),
				f,
				0.25,
				-0.38,
				0.14,
				{ deco = true, mat = NEON }
			)
		elseif mood == "Cat" then
			-- A cat curled on the sill, peering out.
			ball(m, "Cat", 0.38 * SX, at(f, -0.15, -0.36, 0.16), hex(0x2A2140))
		elseif mood == "Tree" then
			post(
				m,
				"WindowTree",
				0.7 * SY,
				0.5 * SX,
				at(f, 0.18, -0.12, 0.12),
				hex(0x2F7A4A),
				{ deco = true }
			)
		elseif mood == "Star" then
			raw(
				m,
				"WindowStar",
				Vector3.new(0.6, 0.6, 0.15),
				at(f, 0, 0.18, 0.12) * CFrame.Angles(0, 0, math.pi / 4),
				hex(0xFFD23A),
				{ deco = true, mat = NEON }
			)
		end
	end
	if alp then
		box(m, "FlowerBox", 1.3, 0.25, 0.3, hex(0x2F6B4A), f, 0, -0.8, 0.12, { deco = true })
	else
		box(m, "Sill", 1.35, 0.14, 0.3, C.white, f, 0, -0.72, 0.1, { deco = true })
	end
end

local function block(
	ctx: Ctx,
	cx: number,
	cz: number,
	w: number,
	d: number,
	floors: number,
	main: boolean,
	opt: {
		leftRange: { number }?,
		rightGaps: { Gap }?,
		noSideWin: number?,
		doorX: number?,
		porch: boolean?,
		backGap: Gap?, -- a ground-floor opening in the back wall (Room Mix secret bookcase)
	}
): Block
	local m, rng, alp, C = ctx.model, ctx.rng, ctx.alp, ctx.C
	local f = CFrame.new(cx * SX, 0, cz * SX)
	local nW = math.max(1, round(w / 2.6))
	local doorX = if not main then 0 elseif opt.doorX then opt.doorX else pick(rng, { 0, -w / 4, w / 4 })
	local fGaps: { Gap } = if main then { { c = doorX, w = DOOR_GAP.w, h = DOOR_GAP.h } } else {}
	local function sideRange(s)
		if s < 0 and opt.leftRange then
			return opt.leftRange[1], opt.leftRange[2]
		end
		return -d / 2, d / 2
	end
	local function sideGaps(s): { Gap }
		return if s > 0 and opt.rightGaps then opt.rightGaps else {}
	end
	local H = floors * FH
	local wallTop = BASE + H

	-- Walls (the front one has a real door opening) and the floorboards.
	segX(
		m,
		f,
		-w / 2,
		w / 2,
		-d / 2 + T / 2,
		BASE,
		H,
		T,
		C.wall,
		if opt.backGap then { opt.backGap } else {},
		"Wall"
	)
	for _, s in { -1, 1 } do
		local z0, z1 = sideRange(s)
		segZ(m, f, z0, z1, s * (w / 2 - T / 2), BASE, H, T, C.wall, sideGaps(s), "Wall")
	end
	segX(m, f, -w / 2, w / 2, d / 2 - T / 2, BASE, H, T, C.wall, fGaps, "Wall")
	box(m, "FloorBoards", w - 0.6, 0.08, d - 0.6, C.boards, f, 0, 0.34, 0)

	if alp then
		-- Stone base band and a dark timber frame.
		local stone = hex(0x8C8FA6)
		box(m, "StoneBand", w + 0.08, 1.0, T + 0.06, stone, f, 0, 0.8, -d / 2 + T / 2)
		for _, s in { -1, 1 } do
			local z0, z1 = sideRange(s)
			segZ(
				m,
				f,
				z0 - 0.04,
				z1 + 0.04,
				s * (w / 2 - T / 2),
				BASE,
				1.0,
				T + 0.06,
				stone,
				sideGaps(s),
				"StoneBand"
			)
		end
		segX(m, f, -w / 2 - 0.04, w / 2 + 0.04, d / 2 - T / 2, BASE, 1.0, T + 0.06, stone, fGaps, "StoneBand")
		for fl = 1, floors do
			box(
				m,
				"Timber",
				w + 0.1,
				0.22,
				0.12,
				C.trim,
				f,
				0,
				BASE + fl * FH - 0.1,
				d / 2 + 0.02,
				{ deco = true }
			)
		end
		for _, s in { -1, 1 } do
			box(
				m,
				"Timber",
				0.24,
				H - 1,
				0.12,
				C.trim,
				f,
				s * (w / 2 - 0.12),
				1.3 + (H - 1) / 2,
				d / 2 + 0.02,
				{ deco = true }
			)
		end
	else
		for _, s in { -1, 1 } do
			for _, z in { d / 2 + 0.02, -d / 2 - 0.02 } do
				box(
					m,
					"CornerTrim",
					0.26,
					H,
					0.14,
					C.white,
					f,
					s * (w / 2 - 0.1),
					BASE + H / 2,
					z,
					{ deco = true }
				)
			end
		end
	end

	-- Windows on every side (surface-mounted, like the preview's).
	for fl = 0, floors - 1 do
		local y = BASE + fl * FH + 1.75
		for i = 0, nW - 1 do
			local x = -w / 2 + (i + 0.5) * w / nW
			if not (fl == 0 and main and math.abs(x - doorX) < 1.5) then
				window(ctx, at(f, x, y, d / 2 + 0.05))
			end
			if not (fl == 0 and opt.backGap and math.abs(x - opt.backGap.c) < 1.5) then
				window(ctx, at(f, x, y, -d / 2 - 0.05) * CFrame.Angles(0, math.pi, 0))
			end
		end
		for _, s in { -1, 1 } do
			if opt.noSideWin ~= s then
				window(ctx, at(f, s * (w / 2 + 0.05), y, 0) * CFrame.Angles(0, s * math.pi / 2, 0))
			end
		end
	end

	-- Front door: a frame, a wreath and one hinged Door part.
	if main then
		local dg = at(f, doorX, BASE, d / 2 + 0.05)
		local fd = Instance.new("Model")
		fd.Name = "FrontDoor"
		fd.Parent = m
		local fc = if alp then C.trim else C.white
		local half = DOOR_GAP.w / 2 + 0.09
		for _, k in { -1, 1 } do
			box(fd, "DoorFrame", 0.18, DOOR_GAP.h + 0.05, 0.22, fc, dg, k * half, (DOOR_GAP.h + 0.05) / 2, 0)
		end
		box(fd, "DoorFrame", DOOR_GAP.w + 0.36, 0.18, 0.22, fc, dg, 0, DOOR_GAP.h + 0.05, 0)
		local wreath = at(dg, 0, DOOR_GAP.h + 0.42, 0.12)
		raw(
			fd,
			"Wreath",
			Vector3.new(0.4, 2.2, 2.2),
			wreath * CFrame.Angles(0, math.pi / 2, 0),
			hex(0x2F7A4A),
			{
				deco = true,
				shape = Enum.PartType.Cylinder,
			}
		)
		ball(fd, "WreathBow", 0.7, wreath * CFrame.new(0, -0.9, 0.3), hex(0xE2343E))
		local door = box(
			fd,
			"Door",
			DOOR_GAP.w - 0.1,
			DOOR_GAP.h - 0.1,
			0.15,
			C.door,
			dg,
			0,
			(DOOR_GAP.h - 0.1) / 2,
			-0.2
		)
		-- Face it out of the house like the model (HouseKit hinges doors on their
		-- local left edge and seats a VaultDoor by the Door's LookVector).
		door.CFrame *= CFrame.Angles(0, math.pi, 0)

		-- A ramp from the street up to the floor, at the Floor slab's front edge.
		local edge = ctx.floorFront - (cz + d / 2 + 0.05)
		raw(
			fd,
			"DoorRamp",
			Vector3.new(2.0 * SX, BASE * SY, 0.8 * SX),
			at(dg, 0, BASE / 2 - BASE, edge + 0.4) * CFrame.Angles(0, math.pi, 0),
			hex(0x9AA3BE),
			{ class = "WedgePart" }
		)

		local porch = if opt.porch ~= nil then opt.porch else (not alp and rng() < 0.6)
		if porch then
			-- Porch canopy on two posts, wide enough for the door to swing out.
			local hw, rh = 1.6 * SX, 0.4 * SY
			local slope = math.atan2(rh, hw)
			local ridge = at(dg, 0, DOOR_GAP.h + 0.15, 0.6)
			for _, s in { -1, 1 } do
				raw(
					fd,
					"PorchRoof",
					Vector3.new(math.sqrt(hw * hw + rh * rh), 0.12 * SY, 1.3 * SX),
					ridge * CFrame.new(s * hw / 2, rh / 2, 0) * CFrame.Angles(0, 0, -s * slope),
					C.roof,
					{ deco = true }
				)
				local hgt = (DOOR_GAP.h + 0.15 + BASE) * SY
				post(
					fd,
					"PorchPost",
					hgt,
					0.4,
					at(dg, s * 1.45, 0, 1.1) * CFrame.new(0, hgt / 2 - BASE * SY, 0),
					C.white,
					{
						deco = true,
					}
				)
			end
		end
	end

	-- Roof: two snowy slopes, a ridge, gables and a snow roll on each eave.
	local pitch = if alp then 0.85 else 0.55
	local tanP, cosP = math.tan(pitch), math.cos(pitch)
	local wS, dS, wallTopS = w * SX, d * SX, wallTop * SY
	local ddS, ovS = 0.3 * SX, 0.5 * SX
	local run = dS / 2 + ovS - ddS
	local rise = run * tanP
	local eaveY = wallTopS - ovS * tanP
	local topS = eaveY + rise
	local L = run / cosP
	for _, s in { -1, 1 } do
		raw(
			m,
			"Roof",
			Vector3.new(wS + SX, 0.32 * SX, L),
			f * CFrame.new(0, eaveY + rise / 2, s * (ddS + run / 2)) * CFrame.Angles(s * pitch, 0, 0),
			C.roof
		)
		raw(
			m,
			"RoofSnow",
			Vector3.new(wS + 1.1 * SX, 0.22 * SX, L * 0.62),
			f
				* CFrame.new(0, eaveY + rise * 0.69 + 0.27 * SX / cosP, s * (ddS + run * 0.31))
				* CFrame.Angles(s * pitch, 0, 0),
			C.white
		)
		raw(
			m,
			"EaveSnow",
			Vector3.new(wS + 0.4 * SX, 0.5 * SX, 0.5 * SX),
			f * CFrame.new(0, eaveY + 0.1 * SX, s * (dS / 2 + ovS - 0.1 * SX)),
			C.white,
			{
				deco = true,
				shape = Enum.PartType.Cylinder,
			}
		)
		-- Gable: two wedges under the slopes, on each side wall.
		local gh = topS - wallTopS
		for _, side in { -1, 1 } do
			raw(
				m,
				"Gable",
				Vector3.new(T * SX, gh, dS / 2),
				f
					* CFrame.new(s * (wS / 2 - T * SX / 2), wallTopS + gh / 2, side * dS / 4)
					* CFrame.Angles(0, if side > 0 then math.pi else 0, 0),
				C.wall,
				{ class = "WedgePart" }
			)
		end
	end
	raw(
		m,
		"RoofRidge",
		Vector3.new(wS + SX, 0.36 * SX, 2 * ddS + 0.3 * SX),
		f * CFrame.new(0, topS + 0.02 * SX, 0),
		C.roof
	)
	raw(
		m,
		"RoofRidgeSnow",
		Vector3.new(wS + 1.05 * SX, 0.2 * SX, 2 * ddS + 0.25 * SX),
		f * CFrame.new(0, topS + 0.24 * SX, 0),
		C.white
	)

	-- Fairy lights along the front eave (every Candy house, some Alpine ones).
	if not alp or rng() < 0.4 then
		local n = round(w)
		for i = 0, n do
			local x = (-w / 2 - 0.3 + i * (w + 0.6) / n) * SX
			local y = eaveY - 0.12 * SX - (i % 2) * 0.05 * SX
			ball(
				m,
				"FairyLight",
				0.8,
				f * CFrame.new(x, y, dS / 2 + ovS - 0.05 * SX),
				hex(BULBS[i % 5 + 1]),
				NEON
			)
		end
	end

	return {
		f = f,
		cx = cx,
		cz = cz,
		w = w,
		d = d,
		H = H,
		wallTop = wallTop,
		topS = topS,
		ddS = ddS,
		doorX = if main then doorX else nil,
	}
end

-- The sign on the roof ridge: Snowflake (Cosy), Bell (Normal) or Horns (Risky).
local function typeSign(ctx: Ctx, f: CFrame, houseType: string)
	local m = ctx.model
	post(m, "SignPost", 2.5, 0.35, f * CFrame.new(0, 1.25, 0), hex(0x5A6380), { deco = true })
	local disc = f * CFrame.new(0, 2.55 + 1.7, 0)
	local face = disc * CFrame.Angles(0, math.pi / 2, 0)
	raw(m, "SignRim", Vector3.new(0.25, 3.7, 3.7), face * CFrame.new(-0.05, 0, 0), hex(0x2B3A6E), {
		deco = true,
		shape = Enum.PartType.Cylinder,
	})
	local sign = raw(
		m,
		"TypeSign",
		Vector3.new(0.3, 3.3, 3.3),
		face,
		hex(0xFFF8EC),
		{ shape = Enum.PartType.Cylinder }
	)
	sign.CanCollide = false
	local front = disc * CFrame.new(0, 0, 0.2)
	if houseType == "Snowflake" then
		for i = 0, 2 do
			raw(
				m,
				"SignSymbol",
				Vector3.new(0.35, 2.6, 0.15),
				front * CFrame.Angles(0, 0, i * math.pi / 3),
				hex(0x3A8FE0),
				{ deco = true }
			)
		end
	elseif houseType == "Bell" then
		ball(m, "SignSymbol", 1.7, front * CFrame.new(0, 0.15, 0), hex(0xF2B91E))
		ball(m, "SignSymbol", 0.6, front * CFrame.new(0, -0.85, 0.1), hex(0xF2B91E))
	else
		for _, s in { -1, 1 } do
			raw(
				m,
				"SignSymbol",
				Vector3.new(0.45, 2.0, 0.15),
				front * CFrame.new(s * 0.55, 0, 0) * CFrame.Angles(0, 0, -s * 0.45),
				hex(0xC42A33),
				{
					deco = true,
				}
			)
		end
	end
end

local function spawnAt(floor: BasePart, name: string, cf: CFrame)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = floor.CFrame:ToObjectSpace(ROOT * cf)
	a.Parent = floor
end

----------------------------------------------------------------------------
-- Room Mix (Josh, 6 Nov 2026: "more interesting inside & out, multiple rooms,
-- more variety"; approved from the 3D preview at
-- /mnt/project-files/models/house-v2/house-v2-3d.html). A grid of cells, two
-- deep, 2 or 3 wide, on 1 or 2 floors: the hall (front door) and 4-6 rooms,
-- doorways on a tree from the hall so every room is reachable, plus a porch,
-- bay window, balcony or garage. About half get a secret room.
----------------------------------------------------------------------------

local CW, CD = 3.0, 3.2 -- cell width and depth (preview units: ~10 x 11 studs)
HouseBuilder.Cell = { W = CW, D = CD }
HouseBuilder.SecretKinds = { "Bookcase", "Cellar", "Attic" }

export type Room = { type: string, level: number, cells: { { number } }, id: number }
export type RoomPlan = {
	floors: number,
	cols: number,
	hallCol: number, -- 0-based column of the hall (front row)
	stairSide: number, -- -1/1: the hall's outer wall, where the stairs run
	W: number,
	D: number,
	grid: { { { Room? } } }, -- grid[level + 1][row + 1][col + 1]; row 0 back, 1 front
	rooms: { Room },
	doors: { [string]: boolean },
	parent: { [string]: { number } },
	porch: boolean,
	bay: number?, -- column with a bay window (ground, front)
	balcony: number?, -- column with a balcony (upstairs, front)
	garage: number?, -- side (-1/1) with a garage, two-column houses only
	secret: { kind: string, level: number, col: number, row: number }?,
}

local function edgeKey(l: number, c1: number, r1: number, c2: number, r2: number): string
	if c1 > c2 or (c1 == c2 and r1 > r2) then
		c1, r1, c2, r2 = c2, r2, c1, r1
	end
	return string.format("%d:%d,%d-%d,%d", l, c1, r1, c2, r2)
end
HouseBuilder.edgeKey = edgeKey

local function cellX(plan, c: number): number
	return -plan.W / 2 + CW * (c + 0.5)
end
local function cellZ(r: number): number
	return if r == 0 then -CD / 2 else CD / 2
end
HouseBuilder.cellX = cellX
HouseBuilder.cellZ = cellZ

local function shuffled<T>(rng: () -> number, list: { T }): { T }
	local a = table.clone(list)
	for i = #a, 2, -1 do
		local j = math.floor(rng() * i) + 1
		a[i], a[j] = a[j], a[i]
	end
	return a
end

-- Where the chimney's fireplace sits: the back wall, on chimney side cs.
local function fireCol(plan, cs: number): number
	return if cs < 0 then 0 else plan.cols - 1
end

-- Rooms, doorways and extras for one Room Mix house. secret: give it a secret room.
function HouseBuilder.roomPlan(rng: () -> number, secret: boolean?, cs: number?, alpine: boolean?): RoomPlan
	local floors = if rng() < 0.55 then 2 else 1
	local cols = if floors == 2 then 2 else 3
	local hallCol = if floors == 2 then (if rng() < 0.5 then 0 else 1) else 1
	local plan = {
		floors = floors,
		cols = cols,
		hallCol = hallCol,
		stairSide = if hallCol == 0 then -1 else 1,
		W = cols * CW,
		D = 2 * CD,
		grid = {},
		rooms = {},
		doors = {},
		parent = {},
		porch = false,
	}
	for l = 1, floors do
		plan.grid[l] = { {}, {} }
	end
	local function addRoom(kind: string, l: number, cells: { { number } })
		local room = { type = kind, level = l, cells = cells, id = #plan.rooms + 1 }
		table.insert(plan.rooms, room)
		for _, cell in cells do
			plan.grid[l + 1][cell[2] + 1][cell[1] + 1] = room
		end
	end
	addRoom("Hall", 0, { { hallCol, 1 } })
	if floors == 2 then
		addRoom("Landing", 1, { { hallCol, 1 } })
	end
	local pools = if floors == 2
		then {
			{ "Living", "Kitchen", pick(rng, { "Dining", "Study", "Playroom" }) },
			{ "Bedroom", table.unpack(shuffled(rng, { "Kids room", "Bathroom", "Playroom" }), 1, 2) },
		}
		else {
			{
				"Living",
				"Kitchen",
				table.unpack(shuffled(rng, { "Bedroom", "Kids room", "Bathroom", "Dining" })),
			},
		}
	local mergeable = { Living = true, Kitchen = true, Bedroom = true, Playroom = true }
	for l = 0, floors - 1 do
		local pool = table.clone(pools[l + 1])
		local g = plan.grid[l + 1]
		for r = 0, 1 do
			for c = 0, cols - 1 do
				if not g[r + 1][c + 1] and #pool > 0 then
					local kind = table.remove(pool, 1)
					if mergeable[kind] and c + 1 < cols and not g[r + 1][c + 2] and rng() < 0.4 then
						addRoom(kind, l, { { c, r }, { c + 1, r } })
					else
						addRoom(kind, l, { { c, r } })
					end
				end
			end
		end
		for r = 0, 1 do
			for c = 0, cols - 1 do
				if not g[r + 1][c + 1] then
					addRoom(if l == 0 then "Study" else "Bedroom", l, { { c, r } })
				end
			end
		end
		-- Doorways: breadth first from the hall (or landing).
		local seen = { [hallCol .. "," .. 1] = true }
		local queue = { { hallCol, 1 } }
		while #queue > 0 do
			local cur = table.remove(queue, 1)
			for _, step in shuffled(rng, { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local nc, nr = cur[1] + step[1], cur[2] + step[2]
				if nc >= 0 and nc < cols and nr >= 0 and nr <= 1 and not seen[nc .. "," .. nr] then
					seen[nc .. "," .. nr] = true
					plan.parent[l .. ":" .. nc .. "," .. nr] = cur
					if g[cur[2] + 1][cur[1] + 1] ~= g[nr + 1][nc + 1] then
						plan.doors[edgeKey(l, cur[1], cur[2], nc, nr)] = true
					end
					table.insert(queue, { nc, nr })
				end
			end
		end
	end
	plan.porch = rng() < 0.6
	if rng() < 0.6 then
		local options = {}
		for c = 0, cols - 1 do
			if c ~= hallCol then
				table.insert(options, c)
			end
		end
		plan.bay = pick(rng, options)
	end
	if floors == 2 and rng() < 0.6 then
		plan.balcony = pick(rng, { 0, 1 })
	end
	if cols == 2 and rng() < 0.5 then
		plan.garage = if hallCol == 0 then 1 else -1
	end
	if secret then
		local top = floors - 1
		local fire = fireCol(plan, cs or 1)
		local options: { any } = {}
		for _, room in plan.rooms do
			local kind = room.type
			if kind ~= "Hall" and kind ~= "Landing" and kind ~= "Bathroom" then
				for _, cell in room.cells do
					-- Bookcase: a ground-floor back room, clear of the fireplace's wall.
					if room.level == 0 and cell[2] == 0 and cell[1] ~= fire then
						table.insert(
							options,
							{ kind = "Bookcase", level = room.level, col = cell[1], row = 0 }
						)
					end
				end
				if room.level == 0 and kind ~= "Kitchen" then
					local cell = room.cells[1]
					table.insert(options, { kind = "Cellar", level = 0, col = cell[1], row = cell[2] })
				end
				-- Attic: only under the steep Alpine roofs (a Candy roof has no headroom).
				if room.level == top and alpine then
					local cell = room.cells[1]
					table.insert(options, { kind = "Attic", level = top, col = cell[1], row = cell[2] })
				end
			end
		end
		local kinds = {}
		for _, kind in HouseBuilder.SecretKinds do
			for _, o in options do
				if o.kind == kind then
					table.insert(kinds, kind)
					break
				end
			end
		end
		if #kinds > 0 then
			local kind = pick(rng, kinds)
			local list = {}
			for _, o in options do
				if o.kind == kind then
					table.insert(list, o)
				end
			end
			plan.secret = pick(rng, list)
		end
	end
	return plan
end

-- Furniture: { name, w, h, d, colour, spot } in preview units; spot = a present spawn on top/beside it.
local FURNITURE = {
	Hall = { { "ShoeBench", 1.0, 0.45, 0.45, 0x8A5A3A, true } },
	Landing = {},
	Living = { { "Sofa", 1.9, 0.75, 0.8, 0x5A7BE0, true }, { "TVCabinet", 1.3, 0.6, 0.5, 0x8A5A3A, true } },
	Kitchen = { { "Counter", 2.0, 0.95, 0.65, 0xFFFFFF, true }, { "Fridge", 0.8, 1.9, 0.7, 0xEAF3FF, true } },
	Dining = { { "Table", 1.6, 0.8, 1.0, 0x8A5A3A, true }, { "Sideboard", 1.3, 0.9, 0.5, 0xFFB3C9, true } },
	Bedroom = { { "Bed", 1.3, 0.6, 2.0, 0xB07CFF, true }, { "Dresser", 1.2, 1.0, 0.55, 0xFFE58A, true } },
	["Kids room"] = {
		{ "BunkBed", 1.1, 1.9, 1.9, 0x5AA0FF, true },
		{ "ToyBox", 0.9, 0.6, 0.6, 0xE2343E, true },
	},
	Bathroom = { { "Bath", 1.6, 0.6, 0.8, 0xFFFFFF, false }, { "Cabinet", 0.8, 1.0, 0.45, 0xDDEFF5, true } },
	Playroom = {
		{ "ToyShelf", 1.4, 1.6, 0.45, 0xFFB3C9, true },
		{ "RockingHorse", 0.4, 1.0, 1.1, 0xFFFFFF, true },
	},
	Study = { { "Desk", 1.4, 0.75, 0.7, 0xC98A55, true }, { "Bookshelf", 1.3, 1.9, 0.45, 0x8A5A3A, true } },
}
HouseBuilder.Furniture = FURNITURE

type MixCtx = {
	ctx: Ctx,
	plan: RoomPlan,
	floor: BasePart,
	M: CFrame,
	cs: number,
	spawns: { CFrame }, -- present spawns, best first
}

-- One Room Mix house's inside: partitions, upper floor, stairs, furniture,
-- wardrobe, tree, present spawns, extras and the secret room.
local function roomMixInside(mx: MixCtx)
	local ctx, plan, M = mx.ctx, mx.plan, mx.M
	local m, C, alp = ctx.model, ctx.C, ctx.alp
	local inner = if alp then hex(0xF4E8D4) else hex(0xFFF4E2)
	local slab = if alp then hex(0x8A5A30) else hex(0xB98A50)
	local W, D, cols, floors = plan.W, plan.D, plan.cols, plan.floors
	local hx = cellX(plan, plan.hallCol)
	local ss = plan.stairSide
	local stairX0 = if ss < 0 then hx - CW / 2 + T / 2 else hx + CW / 2 - T / 2 - 1.0
	local stairX1 = stairX0 + 1.0
	local N, tread = 13, 0.2
	local zTop = D / 2 - T - 0.05 -- the bottom step, just inside the front wall
	local zEnd = zTop - N * tread
	local secret = plan.secret

	-- Upper floor, cell by cell: a stairwell over the hall, a hatch for an attic.
	if floors == 2 then
		local y = BASE + FH
		for r = 0, 1 do
			for c = 0, cols - 1 do
				local x0, z0 = cellX(plan, c) - CW / 2 + T, cellZ(r) - CD / 2
				local x1, z1 = x0 + CW - 2 * T, z0 + CD
				if r == 0 then
					z0 += T
				else
					z1 -= T
				end
				if c == plan.hallCol and r == 1 then
					-- Leave the stairwell open (beside the stairs, the landing).
					local a, b = if ss < 0 then stairX1 + 0.05 else x0, if ss < 0 then x1 else stairX0 - 0.05
					box(m, "UpperFloor", b - a, 0.2, z1 - z0, slab, M, (a + b) / 2, y, (z0 + z1) / 2)
					box(
						m,
						"UpperFloor",
						stairX1 - stairX0,
						0.2,
						zEnd - z0,
						slab,
						M,
						(stairX0 + stairX1) / 2,
						y,
						(z0 + zEnd) / 2
					)
					local railX = if ss < 0 then stairX1 + 0.05 else stairX0 - 0.05
					bar(
						m,
						"Banister",
						Vector3.new(railX * SX, (y + 1.0) * SY, (zEnd + 0.6) * SX),
						Vector3.new(railX * SX, (y + 1.0) * SY, (zTop - 0.1) * SX),
						0.35,
						if alp then hex(0x7A4A2C) else C.white
					)
				else
					box(m, "UpperFloor", x1 - x0, 0.2, z1 - z0, slab, M, (x0 + x1) / 2, y, (z0 + z1) / 2)
				end
			end
		end
		-- Stairs up the hall's outer wall, front to back.
		local stairs = Instance.new("Model")
		stairs.Name = "Stairs"
		stairs.Parent = m
		local riseU = FH / N
		local runner = if alp then hex(0xC42A33) else hex(0xE2343E)
		for i = 0, N - 1 do
			local h = riseU * (i + 1)
			box(
				stairs,
				"Step",
				1.0,
				h,
				tread,
				if i % 2 == 1 then slab else runner,
				M,
				(stairX0 + stairX1) / 2,
				BASE + h / 2,
				zTop - i * tread - tread / 2
			)
		end
	end

	-- Partitions with doorways (a doorway in the hall's back wall steps away from the stairs).
	for l = 0, floors - 1 do
		local g = plan.grid[l + 1]
		local y0 = BASE + l * FH
		local h = FH - (if l < floors - 1 then 0.1 else 0)
		for r = 0, 1 do
			for c = 0, cols - 2 do
				if g[r + 1][c + 1] ~= g[r + 1][c + 2] then
					local x = cellX(plan, c) + CW / 2
					local z0, z1 =
						cellZ(r) - CD / 2 + (if r == 0 then T else 0),
						cellZ(r) + CD / 2 - (if r == 1 then T else 0)
					local gaps = if plan.doors[edgeKey(l, c, r, c + 1, r)]
						then { { c = cellZ(r), w = DOOR_GAP.w, h = DOOR_GAP.h } }
						else {}
					segZ(m, M, z0, z1, x, y0, h, T, inner, gaps, "Partition")
				end
			end
		end
		for c = 0, cols - 1 do
			if g[1][c + 1] ~= g[2][c + 1] then
				local cx = cellX(plan, c)
				local off = if c == plan.hallCol and floors == 2 then -ss * 0.4 else 0
				local gaps = if plan.doors[edgeKey(l, c, 0, c, 1)]
					then { { c = cx + off, w = DOOR_GAP.w, h = DOOR_GAP.h } }
					else {}
				segX(m, M, cx - CW / 2 + T, cx + CW / 2 - T, 0, y0, h, T, inner, gaps, "Partition")
			end
		end
	end

	-- Furniture in the cell corners (never the stairs side of the hall, never
	-- the fireplace's corner, never in front of a secret bookcase).
	local fire = fireCol(plan, mx.cs)
	local spots: { { CFrame } } = {}
	local wardrobeDone = false
	for _, room in plan.rooms do
		local slots = {}
		for _, cell in room.cells do
			local c, r = cell[1], cell[2]
			local cx, cz = cellX(plan, c), cellZ(r)
			for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
				local back = s[2] < 0
				local skip = (room.type == "Hall" or room.type == "Landing") and floors == 2 and s[1] == ss
				skip = skip or (room.level == 0 and r == 0 and c == fire and back) -- the fireplace
				skip = skip
					or (
						back
						and secret ~= nil
						and secret.kind == "Bookcase"
						and secret.level == room.level
						and secret.col == c
						and r == 0
					)
				skip = skip or (room.type == "Hall" and not back) -- the front door swings in here
				if not skip then
					table.insert(slots, {
						x = cx + s[1] * (CW / 2 - T - 0.75),
						z = cz
							+ s[2]
								* (CD / 2 - (if (r == 0) == back or (r == 1) == not back then T else 0) - 0.55),
						face = if back then 0 else math.pi,
					})
				end
			end
		end
		local list = FURNITURE[room.type] or {}
		local y = BASE + room.level * FH + (if room.level > 0 then 0.1 else 0.08)
		local mine = {}
		for i, item in list do
			local slot = slots[i]
			if slot then
				local f = at(M, slot.x, y, slot.z) * CFrame.Angles(0, slot.face, 0)
				box(m, item[1], item[2], item[3], item[4], hex(item[5]), f, 0, item[3] / 2, 0)
				if item[6] then
					table.insert(mine, at(M, slot.x, y + item[3], slot.z))
				end
			end
		end
		-- The middle of every room is a present spot; living rooms and bedrooms get a rug there.
		local cell = room.cells[1]
		local rx = (cellX(plan, cell[1]) + cellX(plan, room.cells[#room.cells][1])) / 2
		local rz = cellZ(cell[2])
		local hasTrap = secret
			and secret.kind == "Cellar"
			and secret.col == cell[1]
			and secret.row == cell[2]
			and room.level == 0
		if (room.type == "Living" or room.type == "Bedroom" or room.type == "Kids room") and not hasTrap then
			box(
				m,
				"Rug",
				1.4 * #room.cells,
				0.04,
				1.2,
				hex(({ 0xE2386A, 0x2FA89A, 0xFFC83D, 0x5A7BE0 })[room.id % 4 + 1]),
				M,
				rx,
				y + 0.02,
				rz + 0.2,
				{ deco = true }
			)
		end
		table.insert(mine, at(M, rx, y, rz + 0.2))
		-- The hide-spot wardrobe and the tree live downstairs (HouseKit hides you at floor height).
		if
			room.level == 0
			and not wardrobeDone
			and (
				room.type == "Bedroom"
				or room.type == "Study"
				or room.type == "Dining"
				or room.type == "Hall"
			)
		then
			local slot = slots[#list + 1]
			if slot then
				local f = at(M, slot.x, y, slot.z) * CFrame.Angles(0, slot.face, 0)
				box(m, "Wardrobe", 1.2, 2.4, 0.65, C.wardrobe, f, 0, 1.2, 0)
				wardrobeDone = true
			end
		end
		if room.type == "Living" then
			local slot = slots[#list + 1]
			if slot then
				local treeModel = Instance.new("Model")
				treeModel.Name = "Tree"
				treeModel.Parent = m
				local tr = at(M, slot.x, y, slot.z)
				post(
					treeModel,
					"Trunk",
					0.4 * SY,
					1,
					tr * CFrame.new(0, 0.2 * SY, 0),
					hex(0x5A3A22),
					{ deco = true }
				)
				for i, tier in { { 1.5, 0.65 }, { 1.0, 1.25 } } do
					post(
						treeModel,
						"TreeTier",
						0.6 * SY - i * 0.3,
						tier[1] * SX,
						tr * CFrame.new(0, tier[2] * SY, 0),
						hex(0x2F7A4A),
						{ deco = true }
					)
				end
				raw(
					treeModel,
					"Star",
					Vector3.one,
					tr * CFrame.new(0, 1.75 * SY, 0) * CFrame.Angles(0, 0, math.pi / 4),
					hex(0xFFD23A),
					{ deco = true, mat = NEON }
				)
				table.insert(mine, 1, tr * CFrame.new(0.9 * SX, 0, 0))
			end
		end
		if #mine > 0 then
			table.insert(spots, mine)
		end
	end
	if not wardrobeDone then
		-- No downstairs bedroom: tuck it in the hall's back corner.
		local f = at(M, hx + ss * (CW / 2 - T - 0.7), BASE + 0.08, -0.3) * CFrame.Angles(0, math.pi, 0)
		box(m, "Wardrobe", 1.2, 2.4, 0.65, C.wardrobe, f, 0, 1.2, 0)
	end
	-- Present spawns: one per room first, then the rest.
	local k = 1
	while #mx.spawns < 8 do
		local added = false
		for _, list in spots do
			if list[k] and #mx.spawns < 8 then
				table.insert(mx.spawns, list[k])
				added = true
			end
		end
		if not added then
			break
		end
		k += 1
	end

	-- Outside: bay window, balcony, garage.
	local trim = if alp then C.trim else C.white
	if plan.bay then
		local bx = cellX(plan, plan.bay)
		box(m, "BayWindow", 2.2, 1.7, 0.8, C.wall, M, bx, BASE + 1.6, D / 2 + 0.4)
		box(
			m,
			"BayGlass",
			1.8,
			1.1,
			0.06,
			C.pane,
			M,
			bx,
			BASE + 1.65,
			D / 2 + 0.82,
			{ deco = true, mat = NEON }
		)
		box(m, "BayRoof", 2.4, 0.2, 1.0, C.roof, M, bx, BASE + 2.55, D / 2 + 0.45)
	end
	if plan.balcony then
		local bx, y = cellX(plan, plan.balcony), BASE + FH
		box(m, "Balcony", 2.4, 0.2, 1.1, slab, M, bx, y - 0.1, D / 2 + 0.55)
		box(m, "BalconyRail", 2.4, 0.8, 0.1, trim, M, bx, y + 0.4, D / 2 + 1.05, { deco = true })
		box(
			m,
			"BalconyDoor",
			1.2,
			2.2,
			0.06,
			hex(0x7FC4EA),
			M,
			bx,
			y + 1.15,
			D / 2 + 0.12,
			{ deco = true, mat = NEON }
		)
	end
	if plan.garage then
		local s = plan.garage
		local gx, gw = s * (W / 2 + 1.0), 2.0
		local gh = 2.6
		box(m, "GarageFloor", gw, BASE, CD, hex(0x9AA3BE), M, gx, BASE / 2, CD / 2)
		box(m, "GarageWall", gw, gh, T, C.wall, M, gx, BASE + gh / 2, T / 2)
		box(m, "GarageWall", T, gh, CD, C.wall, M, gx + s * (gw / 2 - T / 2), BASE + gh / 2, CD / 2)
		box(m, "GarageRoof", gw + 0.3, 0.25, CD + 0.3, C.roof, M, gx, BASE + gh + 0.12, CD / 2)
		box(
			m,
			"GarageDoor",
			gw - 0.2,
			0.8,
			0.1,
			hex(0xDDE3F0),
			M,
			gx,
			BASE + gh - 0.4,
			CD - 0.05,
			{ deco = true }
		)
		box(m, "Sled", 0.8, 0.35, 1.5, hex(0xE2343E), M, gx, BASE + 0.18, CD / 2 + 0.3)
	end
end

-- The secret room (Config.Houses.Secret): a Model "Secret" (attribute Kind)
-- with SecretTrigger (hold Search on it), parts that move by their "Open"
-- attribute (a CFrame in the part's own space), SecretReveal parts that
-- appear, SecretGlow panels that light up gold and a SecretLight; Floor
-- attachments SecretSpawn (the Big present) and, for the cellar and attic,
-- SecretInside / SecretOutside (Run teleports you, like a chimney, because a
-- cellar can't cut the ground and an attic hatch is out of reach).
-- Run:_findSecret does the opening; the room is sealed until then.
local function secretRoom(mx: MixCtx)
	local ctx, plan, M, floor = mx.ctx, mx.plan, mx.M, mx.floor
	local s = plan.secret :: any
	local sec = Instance.new("Model")
	sec.Name = "Secret"
	sec:SetAttribute("Kind", s.kind)
	sec.Parent = ctx.model
	local wood = if ctx.alp then hex(0x6A4A2E) else hex(0x8A5A3A)
	local plain = hex(0xD9CDB4)
	local cx, cz = cellX(plan, s.col), cellZ(s.row)
	local function glow(w, h, d, x, y, z)
		box(sec, "SecretGlow", w, h, d, hex(0xFFD45A), M, x, y, z, { deco = true, mat = NEON }).Transparency =
			1
	end
	local trigger: BasePart, lightAt: CFrame
	if s.kind == "Bookcase" then
		-- A windowless lean-to behind the back wall, through a bookcase-sized gap.
		local z0, d, w = -plan.D / 2, 1.4, 2.4
		box(sec, "SecretFloor", w, BASE, d, plain, M, cx, BASE / 2, z0 - d / 2)
		box(sec, "SecretWall", w, FH, T, ctx.C.wall, M, cx, BASE + FH / 2, z0 - d + T / 2)
		for _, k in { -1, 1 } do
			box(
				sec,
				"SecretWall",
				T,
				FH,
				d,
				ctx.C.wall,
				M,
				cx + k * (w / 2 - T / 2),
				BASE + FH / 2,
				z0 - d / 2
			)
		end
		box(sec, "SecretRoof", w + 0.4, 0.25, d + 0.4, ctx.C.roof, M, cx, BASE + FH + 0.12, z0 - d / 2)
		trigger = box(sec, "SecretTrigger", 1.5, 2.5, 0.35, wood, M, cx, BASE + 1.25, z0 + T + 0.18)
		-- Swings into the room on its left edge (the part's local +Z faces the room).
		local bw = 1.5 * SX
		trigger:SetAttribute(
			"Open",
			CFrame.new(-bw / 2, 0, 0) * CFrame.Angles(0, -1.45, 0) * CFrame.new(bw / 2, 0, 0)
		)
		for r = 0, 2 do
			local books = box(
				sec,
				"Books",
				1.3,
				0.5,
				0.06,
				hex(({ 0xE2343E, 0x3A6FE0, 0x3FB874 })[r + 1]),
				M,
				cx,
				BASE + 0.45 + r * 0.75,
				z0 + T + 0.38,
				{ deco = true }
			)
			-- The books ride on the bookcase: same hinge, measured from their own centre.
			local off = (trigger.CFrame:Inverse() * books.CFrame)
			books:SetAttribute("Open", off:Inverse() * (trigger:GetAttribute("Open") :: CFrame) * off)
		end
		glow(w - 2 * T - 0.05, 0.05, d - T - 0.05, cx, BASE + 0.03, z0 - d / 2 - T / 2)
		glow(w - 2 * T - 0.05, FH - 0.4, 0.05, cx, BASE + FH / 2, z0 - d + T + 0.03)
		spawnAt(floor, "SecretSpawn", at(M, cx + 0.45, BASE, z0 - d / 2 - 0.1))
		lightAt = at(M, cx, BASE + 2, z0 - d / 2)
	elseif s.kind == "Cellar" then
		-- Under the floor and the ground (the street's 2-stud ground slab is its ceiling).
		local dep, w, d = 2.6, CW - 2 * T - 0.1, CD - 2 * T - 0.1
		local yb = -dep
		box(sec, "SecretFloor", w, 0.3, d, hex(0x8A7A6A), M, cx, yb - 0.15, cz)
		for _, k in { -1, 1 } do
			box(sec, "SecretWall", w, dep, T, plain, M, cx, yb + dep / 2, cz + k * (d / 2 - T / 2))
			box(sec, "SecretWall", T, dep, d, plain, M, cx + k * (w / 2 - T / 2), yb + dep / 2, cz)
		end
		box(
			sec,
			"SecretLadder",
			0.9,
			dep - 0.6,
			0.15,
			wood,
			M,
			cx,
			yb + (dep - 0.6) / 2,
			cz - d / 2 + T + 0.1,
			{ class = "TrussPart" }
		)
		-- The trapdoor under a rug: the rug slides off, the trapdoor flips up on its back edge.
		local hole =
			box(sec, "SecretReveal", 1.2, 0.02, 1.2, hex(0x1E1820), M, cx, BASE + 0.1, cz, { deco = true })
		hole.Transparency = 1
		trigger = box(sec, "SecretTrigger", 1.3, 0.1, 1.3, wood, M, cx, BASE + 0.13, cz, { deco = true })
		trigger:SetAttribute(
			"Open",
			CFrame.new(0, 0, -0.65 * SX) * CFrame.Angles(-1.6, 0, 0) * CFrame.new(0, 0, 0.65 * SX)
		)
		local rug =
			box(sec, "SecretRug", 1.7, 0.05, 1.7, hex(0x7A2A6A), M, cx, BASE + 0.2, cz, { deco = true })
		rug:SetAttribute("Open", CFrame.new(1.4 * SX, 0, 0))
		glow(w - 2 * T - 0.05, dep - 0.7, 0.05, cx, yb + (dep - 0.6) / 2, cz + d / 2 - T - 0.03)
		glow(w - 2 * T - 0.05, 0.05, d - 2 * T - 0.05, cx, yb + 0.03, cz)
		spawnAt(floor, "SecretSpawn", at(M, cx + 0.6, yb, cz + 0.5))
		spawnAt(floor, "SecretInside", at(M, cx - 0.4, yb, cz))
		spawnAt(floor, "SecretOutside", at(M, cx + 0.9, BASE, cz + 0.9))
		lightAt = at(M, cx, yb + 1.6, cz)
	else -- Attic, in an Alpine roof
		local top = BASE + plan.floors * FH
		local y0 = BASE + s.level * FH
		local x0, x1, z0, z1 = -plan.W / 2 + T, plan.W / 2 - T, -plan.D / 2 + T, plan.D / 2 - T
		local hx0, hx1, hz0, hz1 = cx - 0.6, cx + 0.6, cz - 0.6, cz + 0.6
		local wood2 = hex(0xC9A27A)
		box(sec, "AtticFloor", hx0 - x0, 0.2, z1 - z0, wood2, M, (x0 + hx0) / 2, top + 0.1, 0)
		box(sec, "AtticFloor", x1 - hx1, 0.2, z1 - z0, wood2, M, (hx1 + x1) / 2, top + 0.1, 0)
		box(sec, "AtticFloor", hx1 - hx0, 0.2, hz0 - z0, wood2, M, cx, top + 0.1, (z0 + hz0) / 2)
		box(sec, "AtticFloor", hx1 - hx0, 0.2, z1 - hz1, wood2, M, cx, top + 0.1, (hz1 + z1) / 2)
		trigger = box(sec, "SecretTrigger", 1.2, 0.1, 1.2, wood, M, cx, top + 0.05, cz, { deco = true })
		trigger:SetAttribute(
			"Open",
			CFrame.new(0, 0, -0.6 * SX) * CFrame.Angles(1.5, 0, 0) * CFrame.new(0, 0, 0.6 * SX)
		)
		local ladder = box(
			sec,
			"SecretReveal",
			0.8,
			FH - 0.3,
			0.15,
			wood,
			M,
			cx,
			y0 + (FH - 0.3) / 2,
			cz + 0.45,
			{ deco = true, class = "TrussPart" }
		)
		ladder.Transparency = 1
		glow(x1 - x0 - 0.1, 0.05, z1 - z0 - 0.1, 0, top + 0.23, 0)
		box(sec, "Trunk", 1.2, 0.7, 0.8, hex(0x6A3A1E), M, cx + (if cx > 0 then -1.6 else 1.6), top + 0.55, 0)
		spawnAt(floor, "SecretSpawn", at(M, cx + (if cx > 0 then -0.5 else 0.5), top + 0.2, 0))
		spawnAt(floor, "SecretInside", at(M, cx, top + 0.2, 0)) -- under the ridge: the most headroom
		spawnAt(floor, "SecretOutside", at(M, cx + 0.6, y0, cz + 0.7))
		lightAt = at(M, cx, top + 1.5, 0)
	end
	local lamp = raw(sec, "SecretLight", Vector3.one, lightAt, hex(0xFFD45A), { deco = true })
	lamp.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 90)
	light.Range = 18
	light.Brightness = 3
	light.Shadows = false
	light.Enabled = false
	light.Parent = lamp
	return trigger
end

export type Options = { houseType: string?, secret: boolean? }

-- One house. style "candy"/"alpine"; layout "Cottage"/"Two-storey"/"L-shape";
-- houseType picks the roof sign (default: the seed's, as in the preview).
function HouseBuilder.build(seed: number, style: string, layout: string, options: Options?): Model
	assert(PALETTE[style], "unknown house style " .. tostring(style))
	assert(table.find(HouseBuilder.Layouts, layout), "unknown house layout " .. tostring(layout))
	local rng = HouseBuilder.mulberry(seed)
	local P = PALETTE[style]
	local alp = style == "alpine"
	local C: { [string]: Color3 } = {
		wall = hex(pick(rng, P.walls)),
		roof = hex(pick(rng, P.roofs)),
		trim = hex(pick(rng, P.trims)),
		door = hex(pick(rng, P.doors)),
		shut = hex(pick(rng, P.shutters)),
	}
	C.wardrobe = if alp then hex(0x6A4A2E) else hex(pick(rng, { 0x9FD3FF, 0xFFB3C9, 0xA8EBCF }))
	C.quilt = hex(pick(rng, { 0xE2343E, 0x3A6FE0, 0x3FB874, 0xB07CFF }))
	C.white = Color3.new(1, 1, 1)
	C.pane = hex(0xFFD98A)
	C.boards = if alp then hex(0xB07A4A) else hex(0xD9A86A)
	local seededType = pick(rng, HouseBuilder.Types)
	local houseType = options and options.houseType or seededType
	local cs = if rng() < 0.5 then -1 else 1 -- chimney side
	local mix = if layout == "Room Mix"
		then HouseBuilder.roomPlan(rng, options ~= nil and options.secret == true, cs, alp)
		else nil

	local model = Instance.new("Model")
	model.Name = "House"
	model:SetAttribute("Style", style)
	model:SetAttribute("Layout", layout)
	model:SetAttribute("Seed", seed)
	model:SetAttribute("HouseType", houseType)

	-- Footprint (preview units) for the Floor slab under everything.
	local isL = layout == "L-shape"
	local halfW, halfD
	if mix then
		halfW, halfD = mix.W / 2, mix.D / 2
	elseif layout == "Cottage" then
		halfW, halfD = 4, 3.1
	elseif layout == "Two-storey" then
		halfW, halfD = 3.5, 3
	else
		halfW, halfD = 4.55, 3.3
	end
	local floor = raw(
		model,
		"Floor",
		Vector3.new((2 * halfW + 0.4) * SX, BASE * SY, (2 * halfD + 0.4) * SX),
		CFrame.new(0, BASE * SY / 2, 0),
		hex(0x9AA3BE)
	)
	-- Unrotated, so the model's front (-Z) is the Floor's LookVector: HouseKit
	-- turns houses by their PrimaryPart.
	floor.CFrame = CFrame.new(0, BASE * SY / 2, 0)
	model.PrimaryPart = floor

	local ctx: Ctx = {
		model = model,
		rng = rng,
		alp = alp,
		C = C,
		floorFront = halfD + 0.2,
		deco = HouseBuilder.mulberry(seed + 7919),
	}

	local main: Block
	if mix then
		local sec = mix.secret
		main = block(ctx, 0, 0, mix.W, mix.D, mix.floors, true, {
			doorX = cellX(mix, mix.hallCol),
			porch = mix.porch,
			backGap = if sec and sec.kind == "Bookcase"
				then { c = cellX(mix, sec.col), w = 1.5, h = 2.5 }
				else nil,
		})
	elseif layout == "Cottage" then
		main = block(ctx, 0, 0, 8, 6.2, 1, true, {})
	elseif layout == "Two-storey" then
		main = block(ctx, 0, 0, 7, 6, 2, true, {})
	else
		-- Main room plus a wing to its right, joined by an inner doorway.
		main = block(ctx, -1.35, -0.6, 6.4, 5.6, 1, true, {
			rightGaps = { { c = 1.2, w = DOOR_GAP.w, h = DOOR_GAP.h } },
			noSideWin = 1,
		})
		local wing = block(ctx, 3.05, 1.3, 3.0, 4.0, 1, false, { leftRange = { 0.9, 2.0 }, noSideWin = -1 })
		local dw = Instance.new("Model")
		dw.Name = "InnerDoorway"
		dw.Parent = model
		local df = at(CFrame.identity, 1.7, BASE, 0.6)
		local trim = if alp then C.trim else C.white
		for _, k in { -1, 1 } do
			box(
				dw,
				"DoorwayTrim",
				0.4,
				DOOR_GAP.h + 0.05,
				0.14,
				trim,
				df,
				0,
				(DOOR_GAP.h + 0.05) / 2,
				k * (DOOR_GAP.w / 2 + 0.07),
				{ deco = true }
			)
		end
		box(
			dw,
			"DoorwayTrim",
			0.4,
			0.16,
			DOOR_GAP.w + 0.28,
			trim,
			df,
			0,
			DOOR_GAP.h + 0.05,
			0,
			{ deco = true }
		)
		-- A comfy armchair in the wing.
		local cc = hex(pick(rng, { 0xE2343E, 0x3A6FE0, 0x2F7A4A, 0xB07CFF }))
		local ch = at(wing.f, 0.5, 0.38, 0.8) * CFrame.Angles(0, -2.4, 0)
		box(model, "Armchair", 1.1, 0.5, 1.0, cc, ch, 0, 0.25, 0)
		box(model, "Armchair", 1.1, 0.9, 0.25, cc, ch, 0, 0.6, -0.4)
	end
	local M, w, d = main.f, main.w, main.d

	-- Roof sign by the ridge, facing the street.
	typeSign(ctx, M * CFrame.new(-cs * (w / 2 - 0.9) * SX, main.topS - 0.5, main.ddS + 0.6), houseType)

	-- Chimney through the back slope; ChimneyTop is where Santas slide in.
	local chx, chz = cs * (w / 2 - 1.1), -(main.ddS / SX) - 0.6
	local brick = if alp then hex(0x8C8FA6) else hex(0xC4524A)
	local bottomS, topChimney = main.wallTop * SY, main.topS + 4
	local chH = topChimney - bottomS
	raw(
		model,
		"Chimney",
		Vector3.new(1.1 * SX, chH, 1.1 * SX),
		M * CFrame.new(chx * SX, bottomS + chH / 2, chz * SX),
		brick
	)
	local top = raw(
		model,
		"ChimneyTop",
		Vector3.new(1.35 * SX, 0.85, 1.35 * SX),
		M * CFrame.new(chx * SX, topChimney + 0.42, chz * SX),
		if alp then hex(0x6E7088) else hex(0x9A3A34)
	)
	raw(
		model,
		"ChimneySnow",
		Vector3.new(1.3 * SX, 0.7, 1.3 * SX),
		M * CFrame.new(chx * SX, topChimney + 1.2, chz * SX),
		C.white,
		{
			deco = true,
		}
	)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(232, 236, 244)
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 3
	smoke.Size = 2
	smoke.Parent = top

	-- Interior: rug, fireplace under the chimney, wardrobe, tree.
	if not mix then
		local rug = hex(pick(rng, { 0xC42A33, 0x3A6FE0, 0x2F7A4A }))
		post(model, "Rug", 0.1, 2.6 * SX, at(M, 0, 0.4, 0.3), rug, { deco = true })
	end

	local fp = at(M, chx, 0.38, -d / 2 + T + 0.35)
	box(model, "Fireplace", 2.0, 1.8, 0.7, brick, fp, 0, 0.9, 0)
	local hearth = box(model, "Hearth", 1.1, 1.0, 0.2, hex(0x1E1820), fp, 0, 0.55, 0.3, { deco = true })
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 2
	fire.Color = Color3.fromRGB(255, 106, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 180, 61)
	fire.Parent = hearth
	box(model, "Mantel", 2.3, 0.16, 0.85, if alp then hex(0x5A3A22) else C.white, fp, 0, 1.85, 0.06)
	box(model, "ChimneyBreast", 1.2, main.H - 2.1, 0.5, brick, fp, 0, 1.9 + (main.H - 2.1) / 2, -0.1)
	for i, x in { -0.6, 0.6 } do
		box(
			model,
			"Stocking",
			0.26,
			0.5,
			0.12,
			if i == 1 then hex(0x3FB874) else hex(0xE2343E),
			fp,
			x,
			1.45,
			0.48,
			{ deco = true }
		)
	end
	box(model, "LooseBrick", 0.34, 0.16, 0.06, shade(brick, 1.25), fp, 0.62, 1.25, 0.36, { deco = true })

	if mix then
		-- Room Mix: partitions, rooms, stairs, spawns, extras and the secret room.
		local mx: MixCtx = { ctx = ctx, plan = mix, floor = floor, M = M, cs = cs, spawns = {} }
		roomMixInside(mx)
		for i, cf in mx.spawns do
			spawnAt(floor, "PresentSpawn" .. i, cf)
		end
		if mix.secret then
			secretRoom(mx)
		end
		model:SetAttribute("Floors", mix.floors)
		model:SetAttribute("Rooms", #mix.rooms - (if mix.floors == 2 then 1 else 0))
		model:SetAttribute("Secret", if mix.secret then mix.secret.kind else nil)
	else
		local wd = at(M, -cs * (w / 2 - T - 0.85), 0.38, -d / 2 + T + 0.45)
		box(model, "Wardrobe", 1.4, 2.5, 0.8, C.wardrobe, wd, 0, 1.25, 0)
		box(
			model,
			"WardrobeTop",
			1.6,
			0.2,
			0.9,
			if alp then hex(0x4A2C1C) else C.white,
			wd,
			0,
			2.5,
			0,
			{ deco = true }
		)
		for _, x in { -0.34, 0.34 } do
			box(
				model,
				"WardrobeDoor",
				0.64,
				2.2,
				0.06,
				shade(C.wardrobe, 0.88),
				wd,
				x,
				1.25,
				0.42,
				{ deco = true }
			)
		end

		local treeModel = Instance.new("Model")
		treeModel.Name = "Tree"
		treeModel.Parent = model
		local tx, tz = (if isL then -1 else cs) * (w / 2 - 1.3), d / 2 - 1.5
		local tr = at(M, tx, 0.38, tz)
		local green = hex(0x2F7A4A)
		post(
			treeModel,
			"Trunk",
			0.5 * SY,
			1,
			tr * CFrame.new(0, 0.25 * SY, 0),
			hex(0x5A3A22),
			{ deco = true }
		)
		for i, tier in { { 1.8, 0.75 }, { 1.4, 1.3 }, { 0.9, 1.8 } } do
			post(
				treeModel,
				"TreeTier",
				0.55 * SY - i * 0.2,
				tier[1] * SX,
				tr * CFrame.new(0, tier[2] * SY, 0),
				green,
				{ deco = true }
			)
		end
		raw(
			treeModel,
			"Star",
			Vector3.one * 1.1,
			tr * CFrame.new(0, 2.25 * SY, 0) * CFrame.Angles(0, 0, math.pi / 4),
			hex(0xFFD23A),
			{
				deco = true,
				mat = NEON,
			}
		)
		for i = 0, 3 do
			local a, tier = i * 2.2, ({ 0.85, 0.65, 0.85, 0.45 })[i + 1]
			ball(
				treeModel,
				"Bauble",
				0.6,
				tr * CFrame.new(math.cos(a) * tier * SX, (0.6 + (i % 3) * 0.55) * SY, math.sin(a) * tier * SX),
				hex(BAUBLES[i % 3 + 1]),
				NEON
			)
		end

		-- Present spawns: three around the tree, then the floor (and upstairs).
		for i, off in { { -1.0, 0.3 }, { 1.0, 0.3 }, { 0, -1.0 } } do
			spawnAt(floor, "PresentSpawn" .. i, at(tr, off[1], 0, off[2]))
		end
		local extra = {
			{ 0, 0.3 },
			{ -cs * (w / 2 - 2.0), 0.6 },
			{ chx * 0.45, -d / 2 + 1.4 },
			{ cs * 0.6, d / 2 - 0.9 },
		}
		if layout ~= "Two-storey" then
			table.insert(extra, { -cs * 0.9, -0.6 })
		end
		local first = if layout == "Two-storey" then 5 else 4
		for i, p in extra do
			spawnAt(floor, "PresentSpawn" .. (first + i - 1), at(M, p[1], 0.38, p[2]))
		end

		if layout == "Two-storey" then
			-- Stairs up the side wall to a bedroom.
			local stairs = Instance.new("Model")
			stairs.Name = "Stairs"
			stairs.Parent = model
			local ss = -cs
			local sx = ss * (w / 2 - T - 0.55)
			local N, tread = 13, 0.3
			local riseU = FH / N
			local z0 = d / 2 - T - 0.35
			local zEnd = z0 - N * tread
			local slab = if alp then hex(0x8A5A30) else hex(0xB98A50)
			local runner = if alp then hex(0xC42A33) else hex(0xE2343E)
			for i = 0, N - 1 do
				local h = riseU * (i + 1)
				box(
					stairs,
					"Step",
					1.0,
					h,
					tread,
					if i % 2 == 1 then slab else runner,
					M,
					sx,
					0.38 + h / 2,
					z0 - i * tread - tread / 2
				)
			end
			local railX = (sx - ss * 0.5) * SX
			bar(
				stairs,
				"Handrail",
				Vector3.new(railX, 1.3 * SY, z0 * SX),
				Vector3.new(railX, (1.3 + FH) * SY, zEnd * SX),
				0.35,
				if alp then hex(0x7A4A2C) else C.white
			)
			bar(
				stairs,
				"Handrail",
				Vector3.new(railX, 0.4 * SY, z0 * SX),
				Vector3.new(railX, 1.3 * SY, z0 * SX),
				0.35,
				if alp then hex(0x7A4A2C) else C.white
			)

			-- Upper floor with a stairwell opening.
			local xin = sx - ss * 0.55
			local xa, xb = -w / 2 + T, w / 2 - T
			local holeA, holeB = if ss > 0 then xin else xa, if ss > 0 then xb else xin
			local solidA, solidB = if ss > 0 then xa else xin, if ss > 0 then xin else xb
			local y = BASE + FH
			box(model, "UpperFloor", solidB - solidA, 0.2, d - 2 * T, slab, M, (solidA + solidB) / 2, y, 0)
			box(
				model,
				"UpperFloor",
				holeB - holeA,
				0.2,
				zEnd - (-d / 2 + T),
				slab,
				M,
				(holeA + holeB) / 2,
				y,
				(zEnd + (-d / 2 + T)) / 2
			)
			box(
				model,
				"UpperFloor",
				holeB - holeA,
				0.2,
				d / 2 - T - z0,
				slab,
				M,
				(holeA + holeB) / 2,
				y,
				(z0 + d / 2 - T) / 2
			)
			bar(
				model,
				"Banister",
				Vector3.new(xin * SX, (y + 1.0) * SY, z0 * SX),
				Vector3.new(xin * SX, (y + 1.0) * SY, (zEnd + 1.0) * SX),
				0.35,
				if alp then hex(0x7A4A2C) else C.white
			)

			local bed = at(M, cs * 1.5, 0.4 + FH, -1.2)
			local wood = if alp then hex(0x6A4A2E) else C.white
			box(model, "Bed", 1.6, 0.5, 2.4, wood, bed, 0, 0.25, 0)
			box(model, "Quilt", 1.5, 0.25, 1.9, C.quilt, bed, 0, 0.55, 0.2, { deco = true })
			box(model, "Pillow", 1.2, 0.2, 0.45, C.white, bed, 0, 0.6, -0.9, { deco = true })
			box(model, "Headboard", 1.6, 1.0, 0.15, wood, bed, 0, 0.6, -1.2)
			spawnAt(floor, "PresentSpawn4", at(M, sx, 0.4 + FH, (zEnd - d / 2 + T) / 2))
		end
	end

	-- Yard (the preview's snowman roll is kept so seeds match; gardens add snowmen).
	if rng() < 0.6 then
		pick(rng, { 0xE2343E, 0x3A6FE0, 0x3FB874 })
	end
	if alp then
		-- Lamp post and a log pile in front, clear of the door ramp.
		local rampX = main.cx + (main.doorX or 0)
		local front = ctx.floorFront + 0.7
		local lampX, logX = -cs * (halfW - 0.6), cs * (halfW - 1.0)
		if math.abs(lampX - rampX) > 1.6 then
			local lamp = at(CFrame.identity, lampX, 0, front)
			post(model, "LampPost", 2.2 * SY, 0.4, lamp * CFrame.new(0, 1.1 * SY, 0), hex(0x2B2030))
			raw(
				model,
				"LampGlow",
				Vector3.new(1, 1.4, 1),
				lamp * CFrame.new(0, 2.2 * SY + 0.7, 0),
				hex(0xFFD86A),
				{ deco = true, mat = NEON }
			)
		end
		if math.abs(logX - rampX) > 1.8 then
			for i, p in { { -0.18, 0.18 }, { 0.18, 0.18 }, { 0, 0.48 } } do
				raw(
					model,
					"Log",
					Vector3.new(1.2 * SX, 0.36 * SX, 0.36 * SX),
					at(CFrame.identity, logX, 0, front) * CFrame.new(0, p[2] * SX, p[1] * SX),
					if i == 2 then hex(0x8A5A30) else hex(0x7A4A2C),
					{ shape = Enum.PartType.Cylinder }
				)
			end
		end
	end

	return model
end

-- A fresh house for one of Loot's house plans: any style, Room Mix rooms, the
-- Far ring Alpine (the run map thread's call), the vault a plain Cottage.
-- signs: House Card -> roof sign (HouseKit.HouseTypeSign).
function HouseBuilder.forPlan(rng: Random, plan, signs: { [string]: string }?): Model
	local style = if plan.ring == "Far" then "alpine" else HouseBuilder.Styles[rng:NextInteger(1, 2)]
	-- Every robbable house is a Room Mix house (Josh, 6 Nov 2026); the vault stays a Cottage.
	local layout = if plan.locked then "Cottage" else "Room Mix"
	local sign = signs and signs[plan.typeName]
	return HouseBuilder.build(
		rng:NextInteger(1, 2 ^ 30),
		style,
		layout,
		{ houseType = sign, secret = plan.secret == true }
	)
end

return HouseBuilder
