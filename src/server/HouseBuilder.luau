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
HouseBuilder.Layouts = { "Cottage", "Two-storey", "L-shape" }
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

local function window(ctx: Ctx, f: CFrame)
	local m, alp, C = ctx.model, ctx.alp, ctx.C
	local frame = if alp then C.trim else C.white
	if alp then
		box(m, "Shutters", 2.0, 1.35, 0.08, C.shut, f, 0, 0, 0.02, { deco = true })
	end
	box(m, "WindowFrame", 1.15, 1.35, 0.14, frame, f, 0, 0, 0, { deco = true })
	box(m, "Window", 0.85, 1.05, 0.05, C.pane, f, 0, 0, 0.07, { deco = true, mat = NEON })
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
	opt: { leftRange: { number }?, rightGaps: { Gap }?, noSideWin: number? }
): Block
	local m, rng, alp, C = ctx.model, ctx.rng, ctx.alp, ctx.C
	local f = CFrame.new(cx * SX, 0, cz * SX)
	local nW = math.max(1, round(w / 2.6))
	local doorX = if main then pick(rng, { 0, -w / 4, w / 4 }) else 0
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
	box(m, "Wall", w, H, T, C.wall, f, 0, BASE + H / 2, -d / 2 + T / 2)
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
			window(ctx, at(f, x, y, -d / 2 - 0.05) * CFrame.Angles(0, math.pi, 0))
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

		if not alp and rng() < 0.6 then
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

export type Options = { houseType: string? }

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

	local model = Instance.new("Model")
	model.Name = "House"
	model:SetAttribute("Style", style)
	model:SetAttribute("Layout", layout)
	model:SetAttribute("Seed", seed)
	model:SetAttribute("HouseType", houseType)

	-- Footprint (preview units) for the Floor slab under everything.
	local isL = layout == "L-shape"
	local halfW, halfD
	if layout == "Cottage" then
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

	local ctx: Ctx = { model = model, rng = rng, alp = alp, C = C, floorFront = halfD + 0.2 }

	local main: Block
	if layout == "Cottage" then
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
	local rug = hex(pick(rng, { 0xC42A33, 0x3A6FE0, 0x2F7A4A }))
	post(model, "Rug", 0.1, 2.6 * SX, at(M, 0, 0.4, 0.3), rug, { deco = true })

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
	post(treeModel, "Trunk", 0.5 * SY, 1, tr * CFrame.new(0, 0.25 * SY, 0), hex(0x5A3A22), { deco = true })
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

-- A fresh house for one of Loot's house plans: any style and layout, the
-- Far ring Alpine (the run map thread's call), the vault a plain Cottage.
-- signs: House Card -> roof sign (HouseKit.HouseTypeSign).
function HouseBuilder.forPlan(rng: Random, plan, signs: { [string]: string }?): Model
	local style = if plan.ring == "Far" then "alpine" else HouseBuilder.Styles[rng:NextInteger(1, 2)]
	local layout = if plan.locked then "Cottage" else HouseBuilder.Layouts[rng:NextInteger(1, 3)]
	local sign = signs and signs[plan.typeName]
	return HouseBuilder.build(rng:NextInteger(1, 2 ^ 30), style, layout, { houseType = sign })
end

return HouseBuilder
