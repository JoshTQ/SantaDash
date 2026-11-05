--[[
	Krampus's Lair, the approved "Cuckoo Clock Den" (Josh, 1 Nov 2026), built
	from parts. A port of buildLair in models/lair/lair-3d.html (the models
	gallery's buildLairSet): ground floor only, scarier interior, fireplace with
	roasting marshmallows. It is a walk-in building, so it stays hand-built
	rather than a Meshy mesh.

	LairBuilder.template() is the KrampusLair model Run hands to HouseKit when
	ServerStorage.Assets has no KrampusLair. It meets HouseKit's contract:

	  Floor (PrimaryPart, stone plinth), ListPedestal, KrampusSpawn,
	  HideSpot1 (basket), HideSpot2 (wardrobe), Fireplace (+ FireLight),
	  Chimney, ChimneyTop, Ladder, TypeSign, Entrance (Model, the arched
	  doorway), Bell1-Bell7 (1-4 under the front eaves, 5-7 inside),
	  CuckooDoor, CuckooDoorR, ClockFace, HourHand, MinuteHand, Gear1-3,
	  PresentSpawn1-8

	The preview is 12 x 9 units; SCALE makes it 48 studs wide like
	Config.Houses.Types.Lair. The preview's front is +Z; here it is -Z (the
	model's LookVector), which is how HouseKit places houses.

	Additions the game needs that the preview doesn't show: a chimney stack and
	ChimneyTop over the fireplace plus a ladder up to the eaves (the chimney
	route into the Lair), steps up the plinth to the door, a TypeSign signpost.
	The preview's pine trees are left to the map (the Lair grounds have their own).

	Event-free and no PivotTo, so the Lune tests can build it.
]]

local LairBuilder = {}

LairBuilder.Scale = 4

local S = LairBuilder.Scale
local W, D, H1 = 12, 9, 6.5 -- preview footprint and wall height (units)
local FZ = D / 2 - 0.25 -- front wall centre
local WALL_TOP = 0.8 + H1
local PI = math.pi

local function hex(n: number): Color3
	return Color3.fromRGB(bit32.rshift(n, 16) % 256, bit32.rshift(n, 8) % 256, n % 256)
end

local WOOD, WOODD, STONE, TRIM, SNOW =
	hex(0x8A5A30), hex(0x5A2E1E), hex(0x9AA3BE), hex(0x3A2A1E), hex(0xFFFFFF)
local FLOORWOOD, DARKW, STEEL, GOLD, RED =
	hex(0x6A4A2E), hex(0x3A2430), hex(0x5A6380), hex(0xF2B91E), hex(0xC42A33)
local IRON, COAL, CREAM = hex(0x2B2030), hex(0x22222A), hex(0xF4E4C8)

type Opts = { solid: boolean?, material: Enum.Material?, transparency: number?, className: string? }

-- Model space: `ROOT` turns the preview round so its front faces -Z.
local ROOT = CFrame.Angles(0, PI, 0)

-- A frame `x, y, z` preview units from `frame`, turned by Euler XYZ like three.js.
local function at(
	frame: CFrame,
	x: number,
	y: number,
	z: number,
	rx: number?,
	ry: number?,
	rz: number?
): CFrame
	return frame * CFrame.new(x * S, y * S, z * S) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end

local function pt(frame: CFrame, p: { number }): Vector3
	return frame * Vector3.new(p[1] * S, p[2] * S, p[3] * S)
end

local function make(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	colour: Color3,
	o: Opts?
): BasePart
	local opts: Opts = o or {}
	local part = Instance.new(opts.className or "Part") :: BasePart
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = colour
	part.Material = opts.material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = opts.solid == true
	part.Transparency = opts.transparency or 0
	part.Parent = parent
	return part
end

-- Box w x h x d preview units centred on `cf`.
local function block(parent, name, cf: CFrame, w, h, d, colour, o: Opts?): BasePart
	return make(parent, name, Vector3.new(w * S, h * S, d * S), cf, colour, o)
end

-- Cylinder of radius r and height h along `cf`'s Y axis (three.js CylinderGeometry).
local function cyl(parent, name, cf: CFrame, r, h, colour, o: Opts?): BasePart
	local part = make(
		parent,
		name,
		Vector3.new(h * S, 2 * r * S, 2 * r * S),
		cf * CFrame.Angles(0, 0, PI / 2),
		colour,
		o
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function ball(parent, name, cf: CFrame, r, colour, o: Opts?): BasePart
	local part = make(parent, name, Vector3.one * (2 * r * S), cf, colour, o)
	part.Shape = Enum.PartType.Ball
	return part
end

-- A frame at `p` whose X axis points along `dir` (CFrame.lookAt is NaN straight up or down).
local function along(p: Vector3, dir: Vector3): CFrame
	local x = dir.Unit
	local other = if math.abs(x.Y) < 0.99 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(other).Unit
	return CFrame.fromMatrix(p, x, z:Cross(x).Unit, z)
end

-- A round rod between two model-space points (studs).
local function rod(parent, name, a: Vector3, b: Vector3, r, colour, o: Opts?): BasePart
	local length = math.max((b - a).Magnitude, 0.05)
	local part =
		make(parent, name, Vector3.new(length, 2 * r * S, 2 * r * S), along((a + b) / 2, b - a), colour, o)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A bent rod through preview-unit points in `frame` (the preview's tubes).
local function path(parent, name, frame: CFrame, points: { { number } }, r, colour, o: Opts?)
	for i = 1, #points - 1 do
		rod(parent, name, pt(frame, points[i]), pt(frame, points[i + 1]), r, colour, o)
	end
end

-- A ring (three.js TorusGeometry: in `cf`'s XY plane) of `segments` blocks over `arc` radians.
local function ring(parent, name, cf: CFrame, radius, tube, segments, arc, colour, o: Opts?)
	local length = arc * radius / segments * 1.15
	for i = 0, segments - 1 do
		local a = (i + 0.5) / segments * arc
		block(
			parent,
			name,
			at(cf, math.cos(a) * radius, math.sin(a) * radius, 0, 0, 0, a),
			tube * 2,
			length,
			tube * 2,
			colour,
			o
		)
	end
end

local function folder(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function light(parent: BasePart, colour: Color3, brightness: number, range: number, name: string?)
	local l = Instance.new("PointLight")
	l.Name = name or "Glow"
	l.Color = colour
	l.Brightness = brightness
	l.Range = math.min(range, 60)
	l.Shadows = false
	l.Parent = parent
	return l
end

-- Painted card on a part's face (posters, the mallow bag).
local function paint(part: BasePart, face: Enum.NormalId, bg: Color3, lines: { { string | Color3 } })
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.CanvasSize = Vector2.new(128, 170)
	gui.LightInfluence = 1
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg
	frame.BorderSizePixel = 0
	frame.Parent = gui
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1 / #lines)
		label.Position = UDim2.fromScale(0, (i - 1) / #lines)
		label.Text = line[1] :: string
		label.TextColor3 = line[2] :: Color3
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.Parent = frame
	end
	gui.Parent = part
end

----------------------------------------------------------------------------
-- Outside: plinth, timber walls, clock, cuckoo, roof, bells
----------------------------------------------------------------------------

local bellCount = 0
local function addBell(parent: Instance, frame: CFrame, s: number)
	bellCount += 1
	-- The strap and lip ride on the bell part, so LairAnimator swings all three.
	local bell = ball(
		parent,
		"Bell" .. bellCount,
		at(frame, 0, -0.65, 0),
		0.22 * s,
		GOLD,
		{ material = Enum.Material.Metal }
	)
	rod(bell, "BellStrap", pt(frame, { 0, 0, 0 }), pt(frame, { 0, -0.5, 0 }), 0.02, TRIM)
	cyl(bell, "BellLip", at(frame, 0, -0.75, 0), 0.24 * s, 0.06, GOLD, { material = Enum.Material.Metal })
end

local function outside(model: Model)
	local root = ROOT
	-- Stone plinth (the Floor) and the plank floor on it.
	local floor = block(model, "Floor", at(root, 0, 0.4, 0), W + 1.2, 0.8, D + 1.2, STONE, { solid = true })
	model.PrimaryPart = floor
	block(model, "Planks", at(root, 0, 0.85, 0), W - 0.4, 0.1, D - 0.4, FLOORWOOD, { solid = true })
	-- Steps up the plinth to the door, and the Keep Out style signpost.
	block(
		model,
		"Steps",
		at(root, 0, 0.4, (D + 1.2) / 2 + 0.7, 0, PI, 0),
		3.8,
		0.8,
		1.4,
		STONE,
		{ solid = true, className = "WedgePart" }
	)
	block(model, "SignPost", at(root, -3.2, 0.9, D / 2 + 1.5), 0.15, 1.8, 0.15, TRIM, { solid = true })
	block(model, "TypeSign", at(root, -3.2, 1.7, D / 2 + 1.5), 1.8, 0.55, 0.12, WOODD, { solid = true })

	-- Back and side walls with dark timber beams.
	local y = 0.8 + H1 / 2
	block(model, "WallBack", at(root, 0, y, -D / 2 + 0.25), W, H1, 0.5, WOOD, { solid = true })
	for _, s in { -1, 1 } do
		block(model, "WallSide", at(root, s * (W / 2 - 0.25), y, 0), 0.5, H1, D, WOOD, { solid = true })
		for _, z in { -3, 0, 3 } do
			block(model, "Beam", at(root, s * (W / 2 + 0.02), y, z), 0.2, H1, 0.4, TRIM)
		end
		block(model, "Beam", at(root, s * (W / 2 + 0.02), 0.8 + H1 * 0.55, 0), 0.2, 0.35, D, TRIM)
	end

	-- Front wall round the arched doorway (3.8 x 5.5 units: 15 x 22 studs, Krampus fits).
	local side = (W - 3.8) / 2
	for _, s in { -1, 1 } do
		block(
			model,
			"WallFront",
			at(root, s * (W / 2 - side / 2), y, FZ),
			side,
			H1,
			0.5,
			WOOD,
			{ solid = true }
		)
	end
	block(
		model,
		"Lintel",
		at(root, 0, 0.8 + 5.5 + (H1 - 5.5) / 2, FZ),
		4.0,
		H1 - 5.5,
		0.5,
		WOOD,
		{ solid = true }
	)
	local entrance = folder(model, "Entrance")
	ring(entrance, "Arch", at(root, 0, 4.4, FZ + 0.28), 1.9, 0.18, 10, PI, TRIM)
	for _, x in { -1.9, 1.9 } do
		block(entrance, "Post", at(root, x, 2.6, FZ + 0.28), 0.36, 3.6, 0.36, TRIM)
	end

	-- Glowing windows with sills and red shutters.
	for _, x in { -4, 4 } do
		block(
			model,
			"Window",
			at(root, x, 3.3, FZ + 0.27),
			1.2,
			1.4,
			0.1,
			hex(0xFFD86A),
			{ material = Enum.Material.Neon }
		)
		block(model, "Sill", at(root, x, 2.5, FZ + 0.35), 1.5, 0.2, 0.3, TRIM)
		for _, k in { -1, 1 } do
			block(model, "Shutter", at(root, x + k * 0.9, 3.3, FZ + 0.3), 0.5, 1.5, 0.12, RED)
		end
	end

	-- Big clock face over the door, hands at five to midnight.
	local clock = at(root, 0, WALL_TOP + 1.7, FZ + 0.5)
	local face = CFrame.Angles(PI / 2, 0, 0)
	cyl(model, "ClockRim", clock * face, 2.1, 0.35, TRIM, { solid = true })
	cyl(model, "ClockFace", at(clock, 0, 0, 0.02) * face, 1.85, 0.4, hex(0xF4E4C8), { solid = true })
	for i = 0, 11 do
		local a = i / 12 * PI * 2
		ball(model, "HourDot", at(clock, math.sin(a) * 1.55, math.cos(a) * 1.55, 0.25), 0.11, TRIM)
	end
	block(
		model,
		"HourHand",
		at(clock, 0, 0, 0, 0, 0, math.rad(2.5)) * CFrame.new(0, 0.45 * S, 0.27 * S),
		0.18,
		1.0,
		0.06,
		TRIM
	)
	block(
		model,
		"MinuteHand",
		at(clock, 0, 0, 0, 0, 0, math.rad(30)) * CFrame.new(0, 0.65 * S, 0.32 * S),
		0.12,
		1.4,
		0.06,
		TRIM
	)
	ball(model, "ClockHub", at(clock, 0, 0, 0.36), 0.16, GOLD)

	-- Gables (front and back) and the steep snowy roof.
	for _, z in { FZ, -D / 2 + 0.25 } do
		for _, s in { -1, 1 } do
			block(
				model,
				"Gable",
				at(root, s * W / 4, WALL_TOP + 2.6, z, 0, -s * PI / 2, 0),
				0.5,
				5.2,
				W / 2,
				WOOD,
				{ solid = true, className = "WedgePart" }
			)
		end
	end
	local slope = math.atan2(5.2, W / 2)
	local len = math.sqrt((W / 2) ^ 2 + 5.2 ^ 2) + 1.2
	for _, s in { -1, 1 } do
		local g = at(root, s * W / 4, WALL_TOP + 2.6, 0, 0, 0, -s * slope)
		block(model, "Roof", g, len, 0.45, D + 2, WOODD, { solid = true })
		block(model, "RoofSnow", at(g, 0, 0.32, 0), len, 0.35, D + 2.2, SNOW, { solid = true })
		for i = 0, 5 do
			ball(
				model,
				"SnowPuff",
				at(g, -len / 2 + 0.6 + i * (len - 1.2) / 5, 0.25, D / 2 + 1.05),
				0.3,
				SNOW
			)
		end
	end

	-- Cuckoo house under the peak; its doors fly open on the 30-second horn.
	local cuckoo = at(root, 0, WALL_TOP + 3.9, FZ + 0.6)
	block(model, "CuckooBox", cuckoo, 1.4, 1.2, 0.5, IRON, { solid = true })
	block(model, "CuckooDoor", at(cuckoo, -0.34, 0, 0.28), 0.68, 1.1, 0.08, WOODD)
	block(model, "CuckooDoorR", at(cuckoo, 0.34, 0, 0.28), 0.68, 1.1, 0.08, WOODD)
	-- The little Krampus on a spring, hidden inside until the horn (LairAnimator).
	local fig = ball(model, "CuckooKrampus", at(cuckoo, 0, 0, -0.1), 0.3, hex(0x7A4A2C), { transparency = 1 })
	for _, k in { -1, 1 } do
		path(fig, "CuckooHorn", cuckoo, {
			{ k * 0.17, 0.2, -0.1 },
			{ k * 0.38, 0.38, -0.15 },
			{ k * 0.34, 0.53, -0.05 },
		}, 0.06, hex(0xF1DDB8), { transparency = 1 })
		ball(fig, "CuckooEye", at(cuckoo, k * 0.11, 0.07, 0.16), 0.06, hex(0xFFB43D), {
			material = Enum.Material.Neon,
			transparency = 1,
		})
	end
	ball(fig, "CuckooMuzzle", at(cuckoo, 0, -0.09, 0.13), 0.14, hex(0xECC8A0), { transparency = 1 })

	-- Pinecone clock weights on chains.
	for i, x in { -2.4, 2.4 } do
		local drop = 1.6 + (i - 1) * 0.6
		rod(
			model,
			"WeightChain",
			pt(root, { x, WALL_TOP, FZ + 0.45 }),
			pt(root, { x, WALL_TOP - drop, FZ + 0.45 }),
			0.03,
			hex(0xC98A10)
		)
		cyl(model, "ClockWeight", at(root, x, WALL_TOP - drop - 0.4, FZ + 0.45), 0.22, 0.8, hex(0x7A4A2C))
	end

	-- Chimney stack over the fireplace (right wall in the preview), and a ladder up to the eaves.
	block(
		model,
		"Chimney",
		at(root, 4.9, WALL_TOP + 2.1, 0.7),
		1.5,
		4.2,
		1.5,
		hex(0x6E6680),
		{ solid = true }
	)
	block(
		model,
		"ChimneyTop",
		at(root, 4.9, WALL_TOP + 4.38, 0.7),
		1.8,
		0.35,
		1.8,
		hex(0x5C556C),
		{ solid = true }
	)
	block(model, "ChimneySnow", at(root, 4.9, WALL_TOP + 4.6, 0.7), 1.7, 0.12, 1.7, SNOW)
	local ladder = make(
		model,
		"Ladder",
		Vector3.new(2, 28, 2),
		root * CFrame.new((W / 2 + 0.85) * S, 14, 3 * S),
		hex(0x6E4E3C),
		{ solid = true, className = "TrussPart" }
	)
	ladder.Material = Enum.Material.Wood

	for _, x in { -4.8, -3.2, 3.2, 4.8 } do
		addBell(model, at(root, x, WALL_TOP - 0.05, FZ + 0.9), 1)
	end
end

----------------------------------------------------------------------------
-- Inside: the Naughty List's cage, hide spots, throne, gears, fireplace
----------------------------------------------------------------------------

-- Spots on the planks clear of the furniture, for the Lair's 8 presents.
LairBuilder.PresentSpots = {
	{ -2.2, 0.2 },
	{ 2.0, 0.4 },
	{ -1.0, 1.8 },
	{ 1.0, 1.6 },
	{ -2.9, 1.0 },
	{ 2.6, -1.3 },
	{ -2.3, 3.2 },
	{ 1.8, 3.2 },
}

local function fireplace(model: Model, root: CFrame)
	local fp = at(root, W / 2 - 0.6, 0.9, 0.7, 0, -PI / 2, 0) -- local +Z faces into the room
	local dressing = folder(model, "FireplaceDressing")
	local stones = { hex(0x6E6680), hex(0x80788F), hex(0x5C556C), hex(0x746C84) }
	local back =
		block(model, "Fireplace", at(fp, 0, 0.8, 0.12), 1.6, 1.5, 0.1, hex(0x14101A), { solid = true })
	block(dressing, "FireboxRoof", at(fp, 0, 1.5, 0.45), 1.6, 0.1, 0.8, hex(0x1E1820))
	for _, sd in { -1, 1 } do
		for i = 0, 3 do
			block(
				dressing,
				"Stone",
				at(fp, sd * 1.08 + (i % 2) * sd * 0.03, 0.21 + i * 0.41, 0.48),
				0.62 + (i % 2) * 0.08,
				0.4,
				0.95,
				stones[(i + (if sd > 0 then 1 else 0)) % 4 + 1],
				{ solid = true }
			)
		end
	end
	for i, x in { -0.85, 0, 0.85 } do
		block(
			dressing,
			"Lintel",
			at(fp, x, 1.86, 0.48),
			0.86,
			0.48,
			0.95,
			stones[(i + 1) % 4 + 1],
			{ solid = true }
		)
	end
	block(dressing, "Mantel", at(fp, 0, 2.18, 0.55), 3.0, 0.16, 1.15, hex(0x4A2E1E), { solid = true })
	block(
		dressing,
		"ChimneyBreast",
		at(fp, 0, 2.26 + (H1 - 2.4) / 2, 0.28),
		2.1,
		H1 - 2.4,
		0.55,
		hex(0x5C556C),
		{ solid = true }
	)
	block(dressing, "Hearth", at(fp, 0, 0.05, 0.85), 3.0, 0.1, 1.5, hex(0x4E4860), { solid = true })

	-- Logs, embers and a real crackling fire.
	cyl(dressing, "Log", at(fp, 0, 0.2, 0.5, 0, 0.5, PI / 2), 0.12, 1.2, hex(0x5A3A22))
	cyl(dressing, "Log", at(fp, 0, 0.3, 0.55, 0, -0.5, PI / 2), 0.11, 1.1, hex(0x6A4428))
	for i = 0, 5 do
		block(
			dressing,
			"Ember",
			at(fp, -0.45 + i * 0.18, 0.13, 0.42 + (i % 3) * 0.12, i, i * 0.7, 0),
			0.1,
			0.1,
			0.1,
			if i % 2 == 1 then hex(0xFF4A1A) else hex(0xFF8A2A),
			{ material = Enum.Material.Neon }
		)
	end
	local core = block(
		dressing,
		"FireCore",
		at(fp, 0, 0.55, 0.55),
		0.6,
		0.3,
		0.3,
		hex(0xFF7A1E),
		{ material = Enum.Material.Neon }
	)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 6
	fire.Color = hex(0xFF7A1E)
	fire.SecondaryColor = hex(0xFFD23A)
	fire.Parent = core
	local fireLight = light(back, hex(0xFF7A2A), 1.6, 11 * S, "FireLight")
	fireLight.Shadows = true

	-- Marshmallows toasting on forked sticks from a sand bucket.
	local bucket = at(fp, -1.25, 0.1, 1.9)
	cyl(dressing, "Bucket", at(bucket, 0, 0.25, 0), 0.25, 0.5, hex(0x7A3A2A), { solid = true })
	cyl(dressing, "Sand", at(bucket, 0, 0.48, 0), 0.26, 0.04, hex(0xD9C08A))
	local mallow = { hex(0xFFF8EE), hex(0xF0C47A), hex(0xFFF8EE), hex(0x5A3420) }
	for i, tip in { { -0.35, 1.0, 0.8 }, { 0.0, 1.15, 0.75 }, { 0.35, 0.95, 0.85 }, { 0.15, 0.85, 0.95 } } do
		local a = { -1.25 + (i - 2.5) * 0.06, 0.6, 1.9 }
		local mid = { (a[1] + tip[1]) / 2, (a[2] + tip[2]) / 2 + 0.25, (a[3] + tip[3]) / 2 }
		path(dressing, "Stick", fp, { { a[1], a[2] - 0.1, a[3] }, mid, tip }, 0.02, hex(0x8A6038))
		local from, to = pt(fp, a), pt(fp, tip)
		local dir = (to - from).Unit
		for k, off in { 0.1, 0.32 } do
			if k == 2 and i % 2 == 0 then
				continue
			end
			local p = to - dir * off * S
			cyl(
				dressing,
				"Marshmallow",
				along(p, dir) * CFrame.Angles(0, 0, -PI / 2),
				0.1,
				0.17,
				mallow[(i + k - 2) % 4 + 1]
			)
		end
		if i == 4 then
			ball(
				dressing,
				"MallowFlame",
				CFrame.new(to - dir * 0.1 * S + Vector3.new(0, 0.18 * S, 0)),
				0.07,
				hex(0xFF8A2A),
				{
					material = Enum.Material.Neon,
				}
			)
		end
	end

	-- On the mantel: a bag of mallows, a mug of cocoa; stockings full of coal below it.
	local bag =
		block(dressing, "MallowBag", at(fp, -0.9, 2.57, 0.6, 0, 0, 0.08), 0.5, 0.6, 0.3, hex(0xF6D8E8))
	paint(bag, Enum.NormalId.Back, hex(0xF6D8E8), { { "MALLOWS", hex(0xC42A6A) } })
	for i = 0, 2 do
		cyl(
			dressing,
			"Marshmallow",
			at(fp, -0.6 + i * 0.12, 2.31, 0.85, PI / 2, 0, 0),
			0.07,
			0.1,
			hex(0xFFF8EE)
		)
	end
	local mug = at(fp, 0.85, 2.26, 0.65)
	cyl(dressing, "Mug", at(mug, 0, 0.15, 0), 0.15, 0.3, RED)
	cyl(dressing, "Cocoa", at(mug, 0, 0.29, 0), 0.14, 0.02, hex(0x6A3A22))
	block(dressing, "MugHandle", at(mug, 0.18, 0.15, 0), 0.05, 0.18, 0.05, RED)
	for _, s in { { -1.1, hex(0x2A2A34) }, { 1.1, hex(0x8A1A22) } } do
		local sock = at(fp, s[1] :: number, 2.08, 1.1)
		block(dressing, "Stocking", at(sock, 0, -0.28, 0), 0.32, 0.55, 0.16, s[2] :: Color3)
		block(dressing, "StockingToe", at(sock, 0.07, -0.58, 0), 0.42, 0.18, 0.16, s[2] :: Color3)
		block(dressing, "StockingCuff", sock, 0.36, 0.12, 0.18, hex(0xF2EEE6))
		for k = 0, 2 do
			block(
				dressing,
				"Coal",
				at(sock, -0.08 + k * 0.08, 0.06 + (k % 2) * 0.05, 0, k, k, 0),
				0.12,
				0.12,
				0.12,
				COAL
			)
		end
	end
	-- Poker stand.
	local tools = at(fp, 1.4, 0.1, 1.15)
	cyl(dressing, "ToolStand", at(tools, 0, 0.03, 0), 0.16, 0.05, IRON)
	path(dressing, "ToolStand", tools, { { 0, 0, 0 }, { 0, 1.1, 0 } }, 0.025, IRON)
	path(dressing, "Poker", tools, { { 0.05, 0.05, 0 }, { 0.12, 1.0, 0.05 } }, 0.02, STEEL)
	ball(dressing, "ToolKnob", at(tools, 0, 1.13, 0), 0.05, GOLD)
end

local function inside(model: Model)
	local root = ROOT
	local decor = folder(model, "Interior")

	-- Rug.
	cyl(decor, "Rug", at(root, 0, 0.92, 0.3), 2.2, 0.04, RED)
	ring(decor, "RugTrim", at(root, 0, 0.95, 0.3, PI / 2, 0, 0), 2.0, 0.08, 16, PI * 2, hex(0xFFC83D))

	-- The Naughty List's pedestal (HouseKit puts the List on top) in a cage, glowing red.
	local pedestal =
		block(model, "ListPedestal", at(root, 0, 1.5, -1.5), 1.2, 1.2, 1.2, STONE, { solid = true })
	light(pedestal, hex(0xFF5A5A), 1.2, 6 * S, "ListGlow")
	for i = 0, 9 do
		local a = i / 10 * PI * 2
		local x, z = math.cos(a) * 1.1, -1.5 + math.sin(a) * 1.1
		path(decor, "CageBar", root, { { x, 0.9, z }, { x, 3.4, z } }, 0.04, STEEL)
	end
	ring(decor, "CageRing", at(root, 0, 3.4, -1.5, PI / 2, 0, 0), 1.1, 0.06, 12, PI * 2, STEEL)

	-- Hide spots: Krampus's big basket and a wardrobe.
	local basket = cyl(model, "HideSpot1", at(root, -4, 1.5, -2.8), 0.8, 1.2, hex(0xD49A50), { solid = true })
	basket.Material = Enum.Material.Fabric
	cyl(decor, "BasketRim", at(root, -4, 2.1, -2.8), 0.95, 0.15, hex(0xB07A3A))
	block(model, "HideSpot2", at(root, 4.3, 2.4, -2.9), 1.6, 3, 1, FLOORWOOD, { solid = true })
	for _, x in { -0.4, 0.4 } do
		ball(decor, "Knob", at(root, 4.3 + x * 0.3, 2.4, -2.38), 0.07, GOLD)
	end
	for i = 0, 2 do
		block(decor, "Vent", at(root, 4.0, 3.2 - i * 0.15, -2.38), 0.6, 0.05, 0.05, IRON)
	end
	-- Coal sacks.
	for _, s in { { -4.6, 1.4, 2.6, 0.9 }, { -3.8, 1.3, 3.0, 0.75 } } do
		ball(decor, "CoalSack", at(root, s[1], s[2] - 0.1, s[3]), 0.5 * s[4], hex(0x3A3A44), { solid = true })
		ball(decor, "SackTie", at(root, s[1], s[2] + 0.4 * s[4], s[3]), 0.15 * s[4], hex(0x3A3A44))
	end

	-- Inside bells (Bell5-7) and Krampus's spawn, marked with hoof prints.
	for _, x in { -2.2, 0, 2.2 } do
		addBell(model, at(root, x, WALL_TOP - 0.3, 0.8), 1.2)
	end
	-- Back left, guarding the List: about 30 studs from both the door and the
	-- chimney's way out (Josh, 5 Nov: not right on top of the chimney landing).
	block(model, "KrampusSpawn", at(root, -2.4, 0.92, -2.65), 0.8, 0.02, 1.6, TRIM, { transparency = 1 })
	for _, p in { { 0, 0 }, { 0.4, 0.5 }, { 0, 1.0 }, { 0.4, 1.5 } } do
		cyl(decor, "HoofPrint", at(root, -2.6 + p[1], 0.91, -1.9 - p[2]), 0.15, 0.02, TRIM)
	end

	-- Dark inner panelling.
	local y = 0.8 + H1 / 2
	block(decor, "Panel", at(root, 0, y, -D / 2 + 0.55), W - 1.1, H1 - 0.2, 0.08, DARKW)
	for _, s in { -1, 1 } do
		block(decor, "Panel", at(root, s * (W / 2 - 0.55), y, 0), 0.08, H1 - 0.2, D - 1.1, DARKW)
	end

	-- Big clock gears on the back wall.
	for i, g in
		{
			{ -2.6, 4.4, 1.3, hex(0xA8782A) },
			{ -0.6, 5.6, 0.8, hex(0x8A6A3A) },
			{ 3.4, 5.0, 1.0, hex(0xA8782A) },
		}
	do
		local gear = folder(decor, "Gear" .. i)
		gear:SetAttribute("Radius", g[3])
		local centre = at(root, g[1] :: number, g[2] :: number, -D / 2 + 0.7)
		local rad, col = g[3] :: number, g[4] :: Color3
		cyl(gear, "Disc", centre * CFrame.Angles(PI / 2, 0, 0), rad, 0.18, col)
		cyl(gear, "Hub", centre * CFrame.Angles(PI / 2, 0, 0), rad * 0.3, 0.24, IRON)
		local teeth = math.round(rad * 10)
		for k = 0, teeth - 1 do
			local a = k / teeth * PI * 2
			block(
				gear,
				"Tooth",
				at(centre, math.cos(a) * (rad + 0.1), math.sin(a) * (rad + 0.1), 0, 0, 0, a),
				0.28,
				0.3,
				0.18,
				col
			)
		end
		for k = 0, 3 do
			block(gear, "Spoke", at(centre, 0, 0, 0.08, 0, 0, k * PI / 4), rad * 1.6, 0.14, 0.12, IRON)
		end
	end

	-- Krampus's horned throne.
	local th = at(root, 2.4, 0.9, -3.0)
	local throne, plum = hex(0x4A2A1E), hex(0x8A1A22)
	block(decor, "ThroneSeat", at(th, 0, 0.8, 0), 2.0, 0.5, 1.4, throne, { solid = true })
	block(decor, "ThroneCushion", at(th, 0, 1.12, 0.05), 1.7, 0.25, 1.1, plum)
	block(decor, "ThroneBack", at(th, 0, 2.1, -0.55), 2.0, 2.6, 0.4, throne, { solid = true })
	block(decor, "ThroneBackCushion", at(th, 0, 2.1, -0.32), 1.6, 2.0, 0.1, plum)
	for _, x in { -0.9, 0.9 } do
		block(decor, "ThroneArm", at(th, x, 1.0, 0), 0.3, 1.4, 1.4, throne, { solid = true })
		block(decor, "ThroneFoot", at(th, x, 0.25, 0.4), 0.3, 0.5, 0.5, throne)
	end
	for _, k in { -1, 1 } do
		path(decor, "ThroneHorn", th, {
			{ k * 0.7, 3.3, -0.55 },
			{ k * 1.2, 3.8, -0.6 },
			{ k * 1.35, 3.4, -0.5 },
			{ k * 1.15, 3.2, -0.45 },
		}, 0.13, hex(0xE6DCC8))
	end
	for i = 0, 2 do
		block(
			decor,
			"Scratch",
			at(th, -0.4 + i * 0.15, 2.3, -0.26, 0, 0, 0.3),
			0.05,
			0.9,
			0.04,
			hex(0xD8C8B8)
		)
	end

	-- Coal heap.
	for i = 0, 13 do
		local a, rr = i * 2.4, 0.15 + (i % 5) * 0.12
		local r = 0.18 + (i % 3) * 0.06
		block(
			decor,
			"Coal",
			at(
				root,
				-4.0 + math.cos(a) * rr * 2,
				0.95 + (1 - rr) * 0.35,
				1.6 + math.sin(a) * rr * 1.6,
				a,
				a * 0.7,
				0
			),
			r * 1.5,
			r * 1.5,
			r * 1.5,
			COAL
		)
	end

	-- Flickering candles; two of them light the room.
	for i, c in { { -1.4, -3.4 }, { 1.4, -3.4 }, { -4.6, -0.6 }, { 4.4, -1.6 }, { -1.2, 2.8 } } do
		local h = 0.5 + ((i - 1) % 3) * 0.3
		cyl(decor, "Candle", at(root, c[1], 0.92 + h / 2, c[2]), 0.11, h, CREAM)
		cyl(decor, "CandleDish", at(root, c[1], 0.92, c[2]), 0.19, 0.08, CREAM)
		local flame = ball(decor, "CandleFlame", at(root, c[1], 0.92 + h + 0.1, c[2]), 0.08, hex(0xFFB43D), {
			material = Enum.Material.Neon,
		})
		if i == 1 then
			light(flame, hex(0xFF8A3A), 1.0, 9 * S, "CandleLight")
		elseif i == 4 then
			light(flame, hex(0xFF5A2A), 0.8, 8 * S, "CandleLight")
		end
	end

	-- Hanging cages with stolen presents.
	for ci, c in { { -2.4, 1.2, hex(0xB07CFF) }, { 2.0, 1.8, hex(0x3A6FE0) } } do
		local cage = at(root, c[1] :: number, WALL_TOP - 0.3, c[2] :: number)
		path(decor, "CageChain", cage, { { 0, 0, 0 }, { 0, -1.2, 0 } }, 0.03, STEEL)
		for i = 0, 5 do
			local a = i / 6 * PI * 2
			local x, z = math.cos(a) * 0.5, math.sin(a) * 0.5
			path(decor, "CageBar", cage, { { 0, -1.2, 0 }, { x, -1.6, z }, { x, -2.5, z } }, 0.025, STEEL)
		end
		cyl(decor, "CageFloor", at(cage, 0, -2.5, 0), 0.52, 0.06, STEEL)
		block(decor, "CagedPresent", at(cage, 0, -2.27, 0, 0, ci * 0.6, 0), 0.45, 0.4, 0.45, c[3] :: Color3)
		block(decor, "CagedRibbon", at(cage, 0, -2.27, 0, 0, ci * 0.6, 0), 0.47, 0.42, 0.1, hex(0xFFC83D))
	end

	-- Hanging chains.
	for i, x in { -4.2, -0.9, 4.0 } do
		for k = 0, 5 do
			block(
				decor,
				"ChainLink",
				at(
					root,
					x,
					WALL_TOP - 0.3 - k * 0.15,
					-2.2 + (i - 1) * 0.6,
					0,
					if k % 2 == 1 then PI / 2 else 0,
					0
				),
				0.16,
				0.2,
				0.04,
				STEEL
			)
		end
	end

	-- Cobwebs in the top corners.
	for _, w in
		{
			{ -W / 2 + 0.6, -D / 2 + 0.6, 1, 0 },
			{ W / 2 - 0.6, -D / 2 + 0.6, -1, 0 },
			{ -W / 2 + 0.6, D / 2 - 0.6, 1, PI / 2 },
		}
	do
		local web = at(root, w[1], WALL_TOP - 0.2, w[2], 0, w[4], 0)
		local sx = w[3]
		local o = { transparency = 0.3 }
		for i = 0, 4 do
			local a = i / 4 * PI / 2
			path(
				decor,
				"Cobweb",
				web,
				{ { 0, 0, 0 }, { sx * math.cos(a) * 1.2, -math.sin(a) * 1.2, 0 } },
				0.012,
				hex(0xEDEDF5),
				o
			)
		end
		for _, rad in { 0.5, 1.0 } do
			local points = {}
			for i = 0, 4 do
				local a = i / 4 * PI / 2
				table.insert(points, { sx * math.cos(a) * rad, -math.sin(a) * rad, 0.02 })
			end
			path(decor, "Cobweb", web, points, 0.01, hex(0xEDEDF5), o)
		end
	end

	-- WANTED posters of naughty Santas, and claw marks on the floor.
	for i, p in
		{
			{ -W / 2 + 0.62, 3.6, -1.6, PI / 2 },
			{ -W / 2 + 0.62, 3.3, 0.6, PI / 2 },
			{ W / 2 - 0.62, 3.6, -1.75, -PI / 2 },
			{ 0.8, 3.6, -D / 2 + 0.62, 0 },
		}
	do
		local poster = block(
			decor,
			"Poster",
			at(root, p[1], p[2], p[3], 0, p[4], if i % 2 == 0 then 0.08 else -0.06),
			0.9,
			1.2,
			0.02,
			hex(0xF2E2B8)
		)
		paint(poster, Enum.NormalId.Back, hex(0xF2E2B8), {
			{ "WANTED", hex(0x8A1A22) },
			{ "", hex(0x8A1A22) },
			{ "NAUGHTY", hex(0x5A3A22) },
			{ "SANTA", hex(0x5A3A22) },
		})
	end
	for _, c in { { -2.0, 2.0 }, { 2.6, -0.6 } } do
		for i = 0, 2 do
			block(
				decor,
				"ClawMark",
				at(root, c[1] + i * 0.18, 0.91, c[2], 0, 0.4, 0),
				0.05,
				0.02,
				1.0,
				hex(0x2A1A14)
			)
		end
	end

	-- Glowing eyes blinking in the dark corners.
	for _, e in { { -5.2, 4.8, -3.5 }, { 5.2, 4.2, 3.2 }, { -5.2, 2.2, 3.4 } } do
		local g = at(root, e[1], e[2], e[3], 0, if e[1] < 0 then PI / 2 else -PI / 2, 0)
		for _, dx in { -0.12, 0.12 } do
			ball(decor, "GlowEye", at(g, dx, 0, 0), 0.07, hex(0xFFD23A), { material = Enum.Material.Neon })
		end
	end

	-- Shelf of confiscated toys.
	local sh = at(root, -4.75, 0.9, -1.0, 0, PI / 2, 0)
	for _, y2 in { 1.6, 2.6 } do
		block(decor, "Shelf", at(sh, 0, y2, 0), 2.6, 0.12, 0.7, throne, { solid = true })
	end
	local bear = hex(0xC98A54)
	ball(decor, "Teddy", at(sh, -0.8, 1.94, 0), 0.28, bear)
	ball(decor, "Teddy", at(sh, -0.8, 2.36, 0), 0.2, bear)
	for _, k in { -1, 1 } do
		ball(decor, "Teddy", at(sh, -0.8 + k * 0.14, 2.54, 0), 0.08, bear)
	end
	ball(decor, "ToyBall", at(sh, 0.1, 1.96, 0), 0.3, hex(0xE2343E))
	block(decor, "ToyBlock", at(sh, 0.8, 2.86, 0, 0, 0.3, 0), 0.4, 0.4, 0.4, hex(0x3A6FE0))
	block(decor, "ToyBlock", at(sh, -0.6, 2.86, 0, 0, 0.3, 0), 0.4, 0.4, 0.4, hex(0xFFC83D))

	-- Birch broom by the door.
	for i = 0, 6 do
		path(decor, "Broom", root, {
			{ 4.5 + math.cos(i) * 0.05, 0.95, 3.4 + math.sin(i) * 0.05 },
			{ 4.4 + math.cos(i * 1.7) * 0.25, 3.0, 3.3 + math.sin(i * 1.7) * 0.25 },
		}, 0.025, if i % 2 == 1 then hex(0xE8E2D2) else hex(0x5A4A3A))
	end
	path(decor, "BroomBand", root, { { 4.35, 1.6, 3.2 }, { 4.7, 1.6, 3.6 } }, 0.06, RED)

	-- Present spawn points (HouseKit fills these first).
	for i, p in LairBuilder.PresentSpots do
		block(
			model,
			"PresentSpawn" .. i,
			at(root, p[1], 0.89, p[2]),
			0.4,
			0.02,
			0.4,
			FLOORWOOD,
			{ transparency = 1 }
		)
	end

	fireplace(model, root)
end

-- Builds a fresh KrampusLair model at the origin: Floor's bottom on y = 0, front facing -Z.
function LairBuilder.build(): Model
	local model = Instance.new("Model")
	model.Name = "KrampusLair"
	model:SetAttribute("Style", "CuckooClockDen")
	bellCount = 0
	outside(model)
	inside(model)
	return model
end

local cached: Model? = nil

-- The shared template (built once per server; HouseKit clones it per run).
function LairBuilder.template(): Model
	if not cached then
		cached = LairBuilder.build()
	end
	return cached :: Model
end

return LairBuilder
