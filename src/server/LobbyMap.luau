--[[
	Builds the Sleigh Station lobby: the Naughty Workshop (spawn inside), the
	show-off yard (top crews podium, giant weekly present, Most Wanted wall), a
	present-lined path that forks three ways at a wooden signpost, and the
	Sleigh Station with a gate, stats board, "BOARDING NOW!" sign and board zone
	per bay. Layout numbers live in Config.LobbyMap.

	Like MapBuilder it connects no events, so tests can build it outside
	Roblox. Station.luau drives the bays (gates, boards, sleighs, seating).
	Plain parts only: approved models replace stand-ins through Assets.

	Scenery (Josh's playtest, 6 Nov 2026: "looks rough"): a pine forest and
	snow hills close the yard in, Christmas lights and lanterns warm it up,
	signs get rounded framed panels, and it snows. The lobby is also built in
	the Run place, so dressing is non-colliding (phones drop it far away,
	Shared.Detail) and the whole hub stays under LobbyMap.PartBudget.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Parts = require(script.Parent.Parts)

local LobbyMap = {}

local C = {
	snow = Color3.fromRGB(235, 240, 250),
	yard = Color3.fromRGB(217, 220, 239),
	wall = Color3.fromRGB(123, 140, 196),
	red = Color3.fromRGB(232, 52, 63),
	cream = Color3.fromRGB(255, 243, 220),
	gold = Color3.fromRGB(255, 200, 61),
	wood = Color3.fromRGB(168, 104, 58),
	darkWood = Color3.fromRGB(110, 65, 38),
	floor = Color3.fromRGB(201, 167, 124),
	coal = Color3.fromRGB(43, 43, 56),
	teal = Color3.fromRGB(46, 196, 196),
	green = Color3.fromRGB(47, 191, 91),
	purple = Color3.fromRGB(138, 92, 255),
	navy = Color3.fromRGB(16, 24, 58),
	platform = Color3.fromRGB(232, 220, 200),
	pine = Color3.fromRGB(29, 138, 69),
	darkPine = Color3.fromRGB(18, 102, 58),
	lantern = Color3.fromRGB(255, 214, 140),
	orange = Color3.fromRGB(255, 138, 43),
}
local BULBS = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 205, 80),
	Color3.fromRGB(90, 230, 120),
	Color3.fromRGB(80, 150, 255),
	Color3.fromRGB(255, 120, 200),
}
local PRESENTS = {
	{ Color3.fromRGB(232, 52, 63), C.gold },
	{ Color3.fromRGB(47, 191, 91), C.snow },
	{ Color3.fromRGB(61, 123, 255), C.gold },
	{ Color3.fromRGB(138, 92, 255), C.snow },
	{ Color3.fromRGB(255, 111, 174), C.gold },
	{ Color3.fromRGB(46, 196, 196), C.snow },
}

export type Bay = {
	kind: string, -- "Public" | "Party" | "Private"
	number: number,
	x: number,
	colour: Color3,
	sleighColour: string,
	zone: BasePart, -- step in to board (not collidable)
	gate: BasePart, -- invisible blocker, collidable while the gate is closed
	arms: { { part: BasePart, closed: CFrame, open: CFrame } },
	stats: { title: TextLabel, status: TextLabel, crew: TextLabel, mode: TextLabel },
	boarding: { TextLabel }, -- both faces of the "BOARDING NOW!" sign
	boardingSign: BasePart,
	home: CFrame, -- sleigh pivot when parked (faces +X, along the platform)
}

-- The live parts of the show-off yard (filled by server/Leaderboards).
export type WantedPoster = {
	poster: BasePart,
	title: TextLabel,
	photo: ImageLabel,
	name: TextLabel,
	haul: TextLabel,
}
export type ShowOff = {
	crewRows: { TextLabel }, -- 1st to 3rd on the Top Crews board
	crewEmpty: TextLabel, -- "Rob the most presents..." while nobody has
	crewReset: TextLabel,
	biggestHaul: { TextLabel }, -- both faces of the sign over the giant present
	wanted: { WantedPoster }, -- in rank order
}

export type Hub = {
	model: Model,
	spawn: CFrame,
	bays: { Bay },
	departureBoards: { TextLabel },
	showOff: ShowOff,
}

local part = Parts.new

local function deco(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

local function surfaceGui(p: BasePart, face: Enum.NormalId): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = p
	return gui
end

local BLACK = Color3.new(0, 0, 0)

-- Rounded corners, a border inset and an outline on the text, so a sign
-- reads as a framed panel on its slab instead of text painted on a block.
local function dress(label: TextLabel, bg: Color3, inset: number)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.max(inset * 1.6, 8))
	corner.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = bg:Lerp(BLACK, 0.6)
	stroke.Thickness = 3
	stroke.Parent = label
end

-- Border width in SurfaceGui pixels for a w x h stud sign.
local function insetFor(w: number, h: number): number
	return math.floor(math.clamp(math.min(w, h) * 0.08, 0.15, 0.45) * 40)
end

local function surfaceText(
	p: BasePart,
	face: Enum.NormalId,
	text: string,
	bg: Color3,
	fg: Color3,
	font: Enum.Font?,
	inset: number?
): TextLabel
	local gui = surfaceGui(p, face)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg
	label.BorderSizePixel = 0
	label.Text = text
	label.TextColor3 = fg
	label.TextScaled = true
	label.Font = font or Enum.Font.FredokaOne
	label.Parent = gui
	if inset then
		dress(label, bg, inset)
	end
	return label
end

-- A framed sign board with text on its -Z face (and +Z if twoSided). The
-- slab is the frame (a darker rim of the panel colour unless given).
local function sign(
	parent: Instance,
	name: string,
	text: string,
	w: number,
	h: number,
	cf: CFrame,
	bg: Color3,
	fg: Color3,
	twoSided: boolean?,
	frame: Color3?
): (BasePart, { TextLabel })
	local p = part(parent, name, Vector3.new(w, h, 0.6), cf, frame or bg:Lerp(BLACK, 0.45))
	local inset = insetFor(w, h)
	local labels = { surfaceText(p, Enum.NormalId.Front, text, bg, fg, nil, inset) }
	if twoSided then
		table.insert(labels, surfaceText(p, Enum.NormalId.Back, text, bg, fg, nil, inset))
	end
	return p, labels
end

-- A rounded panel on a face, for boards with several rows of text.
local function panel(p: BasePart, face: Enum.NormalId, bg: Color3): Frame
	local gui = surfaceGui(p, face)
	local inset = insetFor(p.Size.X, p.Size.Y)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
	f.BackgroundColor3 = bg
	f.BorderSizePixel = 0
	f.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.max(inset * 1.6, 8))
	corner.Parent = f
	return f
end

local function row(
	parent: Instance,
	name: string,
	y: number,
	h: number,
	text: string,
	color: Color3,
	back: Color3?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = UDim2.fromScale(0.05, y)
	l.Size = UDim2.fromScale(0.9, h)
	l.BackgroundTransparency = if back then 0 else 1
	l.BackgroundColor3 = back or C.navy
	l.BorderSizePixel = 0
	l.TextColor3 = color
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	if back then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = l
	end
	return l
end

local function ball(
	parent: Instance,
	name: string,
	pos: Vector3,
	d: number,
	color: Color3,
	material: Enum.Material?
)
	local p = part(parent, name, Vector3.one * d, CFrame.new(pos), color, material)
	p.Shape = Enum.PartType.Ball
	return p
end

-- Upright cylinder standing on base (Roblox cylinders run along X).
local function column(
	parent: Instance,
	name: string,
	height: number,
	diameter: number,
	base: Vector3,
	color: Color3,
	material: Enum.Material?
): BasePart
	local p = part(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material
	)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A snow bump: a big ball sunk so only a cap `height` tall and `radius`
-- wide shows above the ground.
local function mound(parent: Instance, x: number, z: number, radius: number, height: number): BasePart
	local r = (radius * radius + height * height) / (2 * height)
	return deco(ball(parent, "SnowMound", Vector3.new(x, height - r, z), r * 2, C.snow, Enum.Material.Snow))
end

local function glow(p: BasePart, range: number, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = C.lantern
	light.Range = range
	light.Brightness = brightness or 1.4
	light.Shadows = false
	light.Parent = p
end

-- An invisible light source (nothing for the culler to hide).
local function lightAt(parent: Instance, pos: Vector3, range: number, brightness: number?): PointLight
	local p = deco(part(parent, "LightSource", Vector3.one, CFrame.new(pos), C.lantern))
	p.Transparency = 1
	p.CastShadow = false
	glow(p, range, brightness)
	return p:FindFirstChildOfClass("PointLight") :: PointLight
end

-- Christmas bulbs on a sagging wire from a to b.
local function stringLights(parent: Instance, a: Vector3, b: Vector3, sag: number, spacing: number)
	local n = math.max(2, math.floor((b - a).Magnitude / spacing))
	local function at(t: number): Vector3
		return a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
	end
	for k = 0, 3 do -- the wire, in four straight runs
		local p0, p1 = at(k / 4), at((k + 1) / 4)
		deco(
			part(
				parent,
				"LightWire",
				Vector3.new(0.12, 0.12, (p1 - p0).Magnitude),
				CFrame.lookAt((p0 + p1) / 2, p1),
				C.coal
			)
		)
	end
	for i = 1, n - 1 do
		deco(
			ball(
				parent,
				"Bulb",
				at(i / n) - Vector3.new(0, 0.35, 0),
				0.6,
				BULBS[i % #BULBS + 1],
				Enum.Material.Neon
			)
		)
	end
end

-- Snowy pine: trunk, three tiers, a snow tip; lit ones get bulbs.
local function pine(parent: Instance, base: Vector3, h: number, lit: boolean, solid: boolean?)
	local trunk =
		column(parent, "PineTrunk", h * 0.22, math.max(h * 0.08, 1), base, C.darkWood, Enum.Material.Wood)
	if not solid then
		deco(trunk)
	end
	for k, frac in { 0.62, 0.46, 0.3 } do
		deco(
			column(
				parent,
				"PineTier",
				h * 0.24,
				h * frac,
				base + Vector3.new(0, h * (0.01 + k * 0.19), 0),
				if k % 2 == 1 then C.darkPine else C.pine,
				Enum.Material.Grass
			)
		)
	end
	deco(ball(parent, "PineSnow", base + Vector3.new(0, h * 0.86, 0), h * 0.15, C.snow, Enum.Material.Snow))
	if lit then
		for k = 0, 7 do
			local a = k * 2.3
			local tier = k % 3
			local r = h * ({ 0.31, 0.23, 0.15 })[tier + 1]
			local y = h * (0.3 + tier * 0.19)
			deco(
				ball(
					parent,
					"Bulb",
					base + Vector3.new(math.cos(a) * r, y, math.sin(a) * r),
					math.max(h * 0.05, 0.6),
					BULBS[k % #BULBS + 1],
					Enum.Material.Neon
				)
			)
		end
	end
end

local function present(parent: Instance, pos: Vector3, size: number, k: number, yaw: number)
	local colours = PRESENTS[(k - 1) % #PRESENTS + 1]
	local cf = CFrame.new(pos + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, yaw, 0)
	local box = part(parent, "Present", Vector3.one * size, cf, colours[1])
	deco(part(parent, "Ribbon", Vector3.new(size + 0.05, size + 0.05, size * 0.2), cf, colours[2]))
	deco(part(parent, "Ribbon", Vector3.new(size * 0.2, size + 0.05, size + 0.05), cf, colours[2]))
	return box
end

-- Centripetal-free uniform Catmull-Rom through points (enough for a path).
local function catmull(points: { Vector3 }, t: number): Vector3
	local n = #points - 1
	local f = math.clamp(t, 0, 1) * n
	local i = math.min(math.floor(f), n - 1)
	local u = f - i
	local p0 = points[math.max(i, 1)]
	local p1 = points[i + 1]
	local p2 = points[i + 2]
	local p3 = points[math.min(i + 3, #points)]
	local u2, u3 = u * u, u * u * u
	return 0.5
		* (
			(2 * p1)
			+ (-p0 + p2) * u
			+ (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2
			+ (-p0 + 3 * p1 - 3 * p2 + p3) * u3
		)
end

-- Candy-striped path along points, lined with presents, with arrow markers.
local function path(
	parent: Instance,
	points: { Vector3 },
	width: number,
	stripe: Color3,
	tiles: number,
	gifts: number,
	skipStart: number?
)
	for i = 0, tiles - 1 do
		local a, b = catmull(points, i / tiles), catmull(points, (i + 1) / tiles)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude + 0.3
		deco(
			part(
				parent,
				"PathTile",
				Vector3.new(width, 0.2, len),
				CFrame.lookAt(mid + Vector3.new(0, 0.1, 0), b + Vector3.new(0, 0.1, 0)),
				if i % 2 == 0 then C.cream else stripe
			)
		)
	end
	for i = skipStart or 1, gifts - 1 do
		local t = i / gifts
		local p = catmull(points, t)
		local ahead = catmull(points, math.min(t + 0.01, 1))
		local dir = (ahead - p).Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		for _, s in { -1, 1 } do
			present(
				parent,
				p + side * s * (width / 2 + 1.7),
				1.3 + (i % 3) * 0.3,
				i + (if s > 0 then 3 else 0),
				i * 0.7
			)
		end
		if i % 3 == 2 then
			deco(
				part(
					parent,
					"PathArrow",
					Vector3.new(0.2, 1.6, 1.6),
					CFrame.lookAt(p + Vector3.new(0, 0.3, 0), p + dir + Vector3.new(0, 0.3, 0))
						* CFrame.Angles(0, 0, math.rad(90))
						* CFrame.Angles(math.rad(45), 0, 0),
					C.gold,
					Enum.Material.Neon,
					"WedgePart"
				)
			)
		end
	end
end

-- Where a path branch meets its bay's gate.
local function branchEnd(bay): Vector3
	return Vector3.new(bay.X, 0, Config.LobbyMap.GateZ - 2.5)
end

local function buildWorkshop(model: Model, floorH: number): { TextLabel }
	local w = Config.LobbyMap.Workshop
	local W, D = w.X1 - w.X0, w.Z1 - w.Z0
	local cz = (w.Z0 + w.Z1) / 2
	local f = Instance.new("Model")
	f.Name = "NaughtyWorkshop"
	f.Parent = model
	part(
		f,
		"Floor",
		Vector3.new(W, floorH, D + 1),
		CFrame.new(0, floorH / 2, cz + 0.5),
		C.floor,
		Enum.Material.WoodPlanks
	)
	for x = w.X0 + 4, w.X1 - 1, 8 do
		deco(
			part(f, "FloorLine", Vector3.new(0.3, 0.05, D - 2), CFrame.new(x, floorH + 0.03, cz), C.darkWood)
		)
	end
	deco(part(f, "Rug", Vector3.new(16, 0.15, 8), CFrame.new(0, floorH + 0.08, -52), C.red))
	part(f, "BackWall", Vector3.new(W + 2, w.Height, 2), CFrame.new(0, w.Height / 2, w.Z0), C.wall)
	for _, x in { w.X0, w.X1 } do
		part(f, "SideWall", Vector3.new(2, w.Height, D), CFrame.new(x, w.Height / 2, cz), C.wall)
	end
	part(f, "FrontHeader", Vector3.new(W + 2, 5, 2), CFrame.new(0, w.Height - 2.5, w.Z1), C.wall)
	for _, x in { -13, 13 } do
		column(f, "Pillar", w.Height - 5, 2.6, Vector3.new(x, 0, w.Z1), C.gold)
	end
	-- gold trim under the header, snow along the wall tops
	deco(part(f, "HeaderTrim", Vector3.new(W + 2.4, 0.6, 2.4), CFrame.new(0, w.Height - 5, w.Z1), C.gold))
	for _, x in { w.X0, w.X1 } do
		deco(
			part(
				f,
				"WallSnow",
				Vector3.new(2.8, 0.8, D + 2),
				CFrame.new(x, w.Height + 0.4, cz),
				C.snow,
				Enum.Material.Snow
			)
		)
		-- warm lit windows on the outside of each side wall
		for _, z in { -55, -43, -31 } do
			local out = if x < 0 then -1 else 1
			local win = deco(
				part(
					f,
					"Window",
					Vector3.new(0.3, 5, 4.4),
					CFrame.new(x + out * 1.05, 9, z),
					C.lantern,
					Enum.Material.Neon
				)
			)
			win.CastShadow = false
			deco(
				part(f, "WindowFrame", Vector3.new(0.4, 5.8, 0.5), CFrame.new(x + out * 1.15, 9, z), C.cream)
			)
			deco(
				part(f, "WindowFrame", Vector3.new(0.4, 0.5, 5.2), CFrame.new(x + out * 1.15, 9, z), C.cream)
			)
			deco(
				part(
					f,
					"WindowSill",
					Vector3.new(1, 0.5, 5.4),
					CFrame.new(x + out * 1.3, 6.3, z),
					C.snow,
					Enum.Material.Snow
				)
			)
		end
	end
	-- candy-striped chimneys
	for _, x in { -30, 30 } do
		for i = 0, 3 do
			deco(
				column(
					f,
					"Chimney",
					2.6,
					4.2,
					Vector3.new(x, w.Height + i * 2.6, w.Z0 + 5),
					if i % 2 == 0 then C.red else C.snow
				)
			)
		end
		deco(
			ball(f, "ChimneySnow", Vector3.new(x, w.Height + 10.6, w.Z0 + 5), 3.6, C.snow, Enum.Material.Snow)
		)
	end
	stringLights(
		f,
		Vector3.new(w.X0, w.Height - 5.4, w.Z1 + 1.4),
		Vector3.new(w.X1, w.Height - 5.4, w.Z1 + 1.4),
		2,
		2.4
	)
	-- sawtooth roof in candy stripes
	for i = 0, 5 do
		local x = w.X0 + 6.7 + i * 13.3
		part(
			f,
			"Roof",
			Vector3.new(D + 2, 7, 13.3),
			CFrame.new(x, w.Height + 3.5, cz) * CFrame.Angles(0, math.rad(90), 0),
			if i % 2 == 0 then C.snow else C.red,
			nil,
			"WedgePart"
		)
	end
	sign(
		f,
		"WorkshopSign",
		"NAUGHTY WORKSHOP",
		30,
		3.8,
		CFrame.new(0, w.Height + 3.2, w.Z1 + 0.5) * CFrame.Angles(0, math.pi, 0),
		C.coal,
		C.gold
	)
	sign(
		f,
		"FollowSign",
		"FOLLOW THE PRESENTS TO THE SLEIGH STATION!",
		22,
		2.6,
		CFrame.new(0, 12.6, w.Z1 - 1.4),
		C.red,
		Color3.new(1, 1, 1)
	)
	-- workbenches, fireplace, armchairs, tree
	for _, b in { { -26, -56 }, { -26, -44 }, { 26, -56 }, { 26, -44 } } do
		part(f, "Workbench", Vector3.new(10, 0.8, 4.4), CFrame.new(b[1], floorH + 3.6, b[2]), C.wood)
		for _, o in { { -4.3, -1.7 }, { 4.3, -1.7 }, { -4.3, 1.7 }, { 4.3, 1.7 } } do
			part(
				f,
				"BenchLeg",
				Vector3.new(0.8, 3.2, 0.8),
				CFrame.new(b[1] + o[1], floorH + 1.6, b[2] + o[2]),
				C.darkWood
			)
		end
		present(f, Vector3.new(b[1] - 2.5, floorH + 4, b[2]), 1.5, b[1] + b[2], 0.3)
		deco(part(f, "Toy", Vector3.new(1.3, 1.3, 1.3), CFrame.new(b[1] + 2.5, floorH + 4.65, b[2]), C.coal))
		deco(column(f, "Toy", 2, 0.6, Vector3.new(b[1] + 0.5, floorH + 4, b[2] + 0.5), C.red))
		deco(column(f, "LampCord", 6, 0.2, Vector3.new(b[1], w.Height - 6.6, b[2]), C.coal))
		local lamp = deco(
			part(
				f,
				"Lamp",
				Vector3.new(1.2, 1.2, 1.2),
				CFrame.new(b[1], w.Height - 7.2, b[2]),
				Color3.fromRGB(255, 210, 122),
				Enum.Material.Neon,
				"Part"
			)
		)
		lamp.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Range = 24
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 214, 160)
		light.Parent = lamp
	end
	part(
		f,
		"Fireplace",
		Vector3.new(14, 11, 3),
		CFrame.new(0, floorH + 5.5, w.Z0 + 2.6),
		Color3.fromRGB(181, 82, 59),
		Enum.Material.Brick
	)
	deco(
		part(
			f,
			"Fire",
			Vector3.new(7, 5, 1),
			CFrame.new(0, floorH + 3, w.Z0 + 3.8),
			Color3.fromRGB(255, 138, 43),
			Enum.Material.Neon
		)
	)
	part(f, "Mantel", Vector3.new(15, 1, 3.6), CFrame.new(0, floorH + 11.2, w.Z0 + 2.6), C.cream)
	lightAt(f, Vector3.new(0, floorH + 3, w.Z0 + 5), 22, 1.6).Color = C.orange
	for i, col in { C.red, C.green, Color3.fromRGB(61, 123, 255), C.purple, C.gold } do
		local sx = -5.6 + (i - 1) * 2.8
		deco(part(f, "Stocking", Vector3.new(1.2, 2.4, 0.6), CFrame.new(sx, floorH + 9, w.Z0 + 4.5), col))
		deco(
			part(
				f,
				"StockingToe",
				Vector3.new(1.8, 0.9, 0.6),
				CFrame.new(sx + 0.4, floorH + 7.6, w.Z0 + 4.5),
				col
			)
		)
		deco(
			part(
				f,
				"StockingCuff",
				Vector3.new(1.4, 0.6, 0.7),
				CFrame.new(sx, floorH + 10.3, w.Z0 + 4.5),
				C.snow
			)
		)
	end
	for _, s in { -1, 1 } do
		local col = if s < 0 then C.purple else C.teal
		local seat = CFrame.new(s * 10, floorH, -53) * CFrame.Angles(0, -s * 0.5, 0)
		part(f, "Armchair", Vector3.new(4, 2, 4), seat * CFrame.new(0, 1.4, 0), col)
		deco(part(f, "ArmchairBack", Vector3.new(4, 4, 1.2), seat * CFrame.new(0, 2.8, -1.6), col))
		for _, a in { -2, 2 } do
			deco(part(f, "ArmchairArm", Vector3.new(1, 2.6, 4), seat * CFrame.new(a, 2.2, 0), col))
		end
	end
	pine(f, Vector3.new(-34, floorH, -28), 13, true, true)
	for k = 1, 5 do
		local a = k * 1.3
		present(
			f,
			Vector3.new(-34 + math.cos(a) * 3.6, floorH, -28 + math.sin(a) * 3.6),
			1.2 + (k % 2) * 0.5,
			k,
			a
		)
	end
	lightAt(f, Vector3.new(0, w.Height - 4, -44), 60, 1.2)
	-- spawn ring
	local spawnCF = Config.Map.HubSpawn
	local spawnPart = part(
		f,
		"Spawn",
		Vector3.new(12, 0.4, 12),
		CFrame.new(spawnCF.Position.X, floorH + 0.2, spawnCF.Position.Z),
		C.teal,
		Enum.Material.Neon,
		"SpawnLocation"
	) :: SpawnLocation
	spawnPart.Neutral = true
	spawnPart.Duration = 0
	-- departure boards on the side walls, facing in
	local boards = {}
	for _, s in { -1, 1 } do
		local _, labels = sign(
			f,
			"DepartureBoard",
			"DEPARTURES",
			17,
			6.6,
			CFrame.new(s * (w.X1 - 1.4), 11, -40) * CFrame.Angles(0, s * math.rad(90), 0),
			C.navy,
			C.gold
		)
		labels[1].Font = Enum.Font.Code
		labels[1].TextXAlignment = Enum.TextXAlignment.Left
		table.insert(boards, labels[1])
	end
	return boards
end

-- Candy-cane fence from a to b: red and white posts, a rail, and an
-- invisible wall tall enough that nobody hops out of the yard.
local function fence(parent: Instance, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	local frame = CFrame.lookAt(a, b)
	local n = math.floor(len / 3)
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		deco(column(parent, "FencePost", 2.4, 0.6, p, if i % 2 == 0 then C.snow else C.red))
	end
	deco(
		part(parent, "FenceRail", Vector3.new(0.35, 0.35, len), frame * CFrame.new(0, 1.7, -len / 2), C.snow)
	)
	deco(part(parent, "FenceRail", Vector3.new(0.35, 0.35, len), frame * CFrame.new(0, 0.8, -len / 2), C.red))
	local wall =
		part(parent, "FenceWall", Vector3.new(1, 7, len), frame * CFrame.new(0, 3.5, -len / 2), C.snow)
	wall.Transparency = 1
end

-- Candy-striped lamp post with a hook and a glowing lantern.
local function lampPost(parent: Instance, base: Vector3, out: Vector3)
	for i = 0, 3 do
		column(
			parent,
			"LampPost",
			2,
			0.6,
			base + Vector3.new(0, i * 2, 0),
			if i % 2 == 0 then C.red else C.snow
		)
	end
	deco(
		part(
			parent,
			"LampHook",
			Vector3.new(0.4, 0.4, 1.6),
			CFrame.lookAt(base + Vector3.new(0, 8.1, 0) + out * 0.7, base + Vector3.new(0, 8.1, 0) + out * 2),
			C.red
		)
	)
	local bulb = deco(
		ball(parent, "Lantern", base + Vector3.new(0, 7.4, 0) + out * 1.4, 1.2, C.lantern, Enum.Material.Neon)
	)
	glow(bulb, 26, 1.6)
end

local function snowman(parent: Instance, base: Vector3, yaw: number)
	local face = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
	for _, b in { { 1.4, 3.2 }, { 3.4, 2.3 }, { 4.9, 1.6 } } do
		ball(parent, "Snowman", (face * CFrame.new(0, b[1], 0)).Position, b[2], C.snow, Enum.Material.Snow)
	end
	deco(part(parent, "SnowmanNose", Vector3.new(0.3, 0.3, 1), face * CFrame.new(0, 4.9, -0.9), C.orange))
	deco(part(parent, "SnowmanScarf", Vector3.new(2.3, 0.4, 2.3), face * CFrame.new(0, 4.2, 0), C.red))
	for _, x in { -0.3, 0.3 } do
		deco(part(parent, "SnowmanEye", Vector3.new(0.2, 0.2, 0.2), face * CFrame.new(x, 5.2, -0.7), C.coal))
	end
	deco(column(parent, "SnowmanHat", 0.2, 1.8, (face * CFrame.new(0, 5.6, 0)).Position, C.coal))
	deco(column(parent, "SnowmanHat", 1, 1.2, (face * CFrame.new(0, 5.8, 0)).Position, C.coal))
end

-- Forest and hills close the yard in, so it reads as a cosy clearing, not a
-- flat field to the horizon. Seeded: the same lobby every server.
local function buildScenery(model: Model)
	local L = Config.LobbyMap
	local y = L.Yard
	local S = L.Scenery
	local m = Instance.new("Model")
	m.Name = "Scenery"
	m.Parent = model
	local rng = Random.new(S.Seed)
	local function clear(x: number, z: number): boolean
		if x > y.X0 - S.YardGap and x < y.X1 + S.YardGap and z > -70 - S.YardGap and z < y.Z1 + S.YardGap then
			return false
		end
		-- the sleighs fly in and out along the back of the station
		return not (z > L.SleighZ - S.FlightGap and z < L.SleighZ + S.FlightGap)
	end
	local c = S.Centre
	local trees = 0
	for x = -S.Radius.X, S.Radius.X, S.TreeSpacing do
		for z = c.Z - S.Radius.Z, c.Z + S.Radius.Z, S.TreeSpacing do
			local px = x + rng:NextNumber(-0.4, 0.4) * S.TreeSpacing
			local pz = z + rng:NextNumber(-0.4, 0.4) * S.TreeSpacing
			local e = (px / S.Radius.X) ^ 2 + ((pz - c.Z) / S.Radius.Z) ^ 2
			local keep = rng:NextNumber() < S.TreeChance
			local h = rng:NextNumber(S.TreeHeight[1], S.TreeHeight[2])
			local lit = rng:NextNumber() < S.LitChance
			if keep and e <= 1 and clear(px, pz) then
				pine(m, Vector3.new(px, 0, pz), h * (1 + e * 0.3), lit)
				trees += 1
			end
		end
	end
	m:SetAttribute("Trees", trees)
	-- a ring of big snow hills on the skyline
	for i = 1, S.Hills do
		local a = (i + rng:NextNumber(-0.3, 0.3)) / S.Hills * math.pi * 2
		local r = rng:NextNumber(1.05, 1.25)
		mound(
			m,
			math.cos(a) * S.Radius.X * r,
			c.Z + math.sin(a) * S.Radius.Z * r,
			rng:NextNumber(40, 70),
			rng:NextNumber(14, 30)
		)
	end
	-- drifts banked against the inside of the fence
	for i = 0, 5 do
		local z = y.Z0 + 10 + i * (y.Z1 - y.Z0 - 20) / 5
		for _, x in { y.X0 + 3, y.X1 - 3 } do
			if not (z > L.Platform.Z0 - 4 and math.abs(x) < 46) then
				mound(m, x, z, rng:NextNumber(5, 8), rng:NextNumber(1.2, 2.2))
			end
		end
	end
	for _, x in { -48, -24, 24, 48 } do
		mound(m, x, y.Z1 - 3, rng:NextNumber(5, 8), rng:NextNumber(1.2, 2))
	end
	-- big lit trees in the back corners, with presents underneath
	for k, corner in { Vector3.new(-60, 0, 84), Vector3.new(60, 0, 84) } do
		pine(m, corner, 18 - k * 2, true, true)
		for i = 1, 6 do
			local a = i * 1.05 + k
			present(
				m,
				corner + Vector3.new(math.cos(a) * 4.5, 0, math.sin(a) * 4.5),
				1 + (i % 3) * 0.5,
				i + k,
				a
			)
		end
	end
	snowman(m, Vector3.new(-60, 0, -14), math.rad(-150))
	-- falling snow over the yard (client-rendered, no parts)
	local sky =
		deco(part(m, "Snowfall", Vector3.new(S.SnowArea, 1, S.SnowArea), CFrame.new(0, 70, c.Z), C.snow))
	sky.Transparency = 1
	sky.CastShadow = false
	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Snow"
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Rate = S.SnowRate
	snow.Lifetime = NumberRange.new(9, 13)
	snow.Speed = NumberRange.new(5, 8)
	snow.SpreadAngle = Vector2.new(12, 12)
	snow.Size = NumberSequence.new(0.4)
	snow.Color = ColorSequence.new(Color3.new(1, 1, 1))
	snow.LightEmission = 0.3
	snow.RotSpeed = NumberRange.new(-60, 60)
	snow.Acceleration = Vector3.new(1, 0, 0.5)
	snow.Parent = sky
end

local function buildYard(model: Model)
	local y = Config.LobbyMap.Yard
	local m = Instance.new("Model")
	m.Name = "Yard"
	m.Parent = model
	part(m, "Snow", Vector3.new(600, 2, 600), CFrame.new(0, -1, 20), C.snow, Enum.Material.Snow)
	deco(
		part(
			m,
			"YardFloor",
			Vector3.new(y.X1 - y.X0, 0.1, y.Z1 - y.Z0),
			CFrame.new((y.X0 + y.X1) / 2, 0.05, (y.Z0 + y.Z1) / 2),
			C.yard
		)
	)
	-- candy-cane fence on three sides (the workshop closes the fourth)
	fence(m, Vector3.new(y.X0, 0, y.Z0), Vector3.new(y.X0, 0, y.Z1))
	fence(m, Vector3.new(y.X0, 0, y.Z1), Vector3.new(y.X1, 0, y.Z1))
	fence(m, Vector3.new(y.X1, 0, y.Z1), Vector3.new(y.X1, 0, y.Z0))
	-- the yard's front corners, either side of the workshop
	fence(m, Vector3.new(y.X0, 0, y.Z0), Vector3.new(-41, 0, y.Z0))
	fence(m, Vector3.new(41, 0, y.Z0), Vector3.new(y.X1, 0, y.Z0))
	for _, l in { { -56, -12 }, { 36, -12 }, { -50, 34 }, { 42, 36 }, { -60, 60 }, { 60, 60 } } do
		lampPost(m, Vector3.new(l[1], 0, l[2]), Vector3.new(if l[1] > 0 then -1 else 1, 0, 0))
	end
end

local function buildShowOff(model: Model): ShowOff
	local L = Config.LobbyMap
	local m = Instance.new("Model")
	m.Name = "ShowOff"
	m.Parent = model
	-- Top crews podium, facing the workshop (-Z) like the board behind it.
	-- Statues are chunky stand-ins until the crews' avatars are cloned in.
	local P = L.Podium
	for _, s in
		{
			{ 0, 6, C.gold, 1 },
			{ -8, 4, Color3.fromRGB(200, 208, 224), 2 },
			{ 8, 2.6, Color3.fromRGB(208, 138, 74), 3 },
		}
	do
		local x = P.X - s[1]
		local step =
			part(m, "PodiumStep" .. s[4], Vector3.new(7.5, s[2], 6), CFrame.new(x, s[2] / 2, P.Z), s[3])
		local badge = deco(
			part(m, "PodiumBadge", Vector3.new(2.6, 2.6, 0.3), CFrame.new(x, s[2] / 2, P.Z - 3.1), C.snow)
		)
		surfaceText(badge, Enum.NormalId.Front, tostring(s[4]), C.snow, C.navy, nil, 4)
		step:SetAttribute("Place", s[4])
		for k = 0, 2 do
			local base = Vector3.new(x - 2.2 + k * 2.2, s[2], P.Z + 0.5)
			local suit = ({ C.red, C.green, Color3.fromRGB(61, 123, 255) })[k + 1]
			ball(m, "Statue", base + Vector3.new(0, 1.1, 0), 2.2, suit)
			deco(ball(m, "StatueFace", base + Vector3.new(0, 2.6, 0), 1.3, Color3.fromRGB(255, 214, 186)))
			deco(ball(m, "StatueBeard", base + Vector3.new(0, 2.2, -0.35), 1.1, C.snow))
			deco(column(m, "StatueHat", 0.9, 1.2, base + Vector3.new(0, 3.05, 0), suit))
			deco(ball(m, "StatuePom", base + Vector3.new(0, 4.1, 0), 0.5, C.snow))
		end
	end
	-- Filled from the weekly OrderedDataStores by server/Leaderboards.
	local board = part(m, "TopCrewsBoard", Vector3.new(17, 9, 0.6), CFrame.new(P.X, 15, P.Z + 5), C.coal)
	local bg = panel(board, Enum.NormalId.Front, C.navy)
	row(bg, "Title", 0.05, 0.2, "TOP CREWS THIS WEEK", C.gold).TextXAlignment = Enum.TextXAlignment.Center
	local empty = row(bg, "Body", 0.4, 0.26, "Rob the most presents to stand up here!", Color3.new(1, 1, 1))
	empty.TextXAlignment = Enum.TextXAlignment.Center
	local crewRows = {}
	for i, colour in { C.gold, Color3.fromRGB(200, 208, 224), Color3.fromRGB(208, 138, 74) } do
		local r = row(bg, "Crew" .. i, 0.27 + (i - 1) * 0.19, 0.16, "", colour)
		r.Visible = false
		table.insert(crewRows, r)
	end
	local reset = row(bg, "Reset", 0.86, 0.1, "", Color3.fromRGB(170, 180, 205))
	reset.TextXAlignment = Enum.TextXAlignment.Center
	for _, x in { -7, 7 } do
		column(m, "BoardPost", 10.5, 0.8, Vector3.new(P.X + x, 0, P.Z + 5.4), C.coal)
	end
	-- Giant weekly present
	local T = L.Trophy
	local base = part(
		m,
		"TrophyBase",
		Vector3.new(3, 20, 20),
		CFrame.new(T.X, 1.5, T.Z) * CFrame.Angles(0, 0, math.rad(90)),
		C.purple,
		nil,
		"Part"
	)
	base.Shape = Enum.PartType.Cylinder
	local giant = part(
		m,
		"GiantPresent",
		Vector3.new(11, 11, 11),
		CFrame.new(T.X, 8.5, T.Z) * CFrame.Angles(0, 0.4, 0),
		C.gold
	)
	giant:SetAttribute("Spin", true)
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		deco(
			ball(
				m,
				"TrophyBead",
				Vector3.new(T.X + math.cos(a) * 9.5, 3.2, T.Z + math.sin(a) * 9.5),
				1,
				BULBS[i % #BULBS + 1],
				Enum.Material.Neon
			)
		)
	end
	lightAt(m, Vector3.new(T.X, 4, T.Z - 12), 30, 1.2)
	deco(part(m, "GiantRibbon", Vector3.new(11.1, 11.1, 2), giant.CFrame, C.red))
	deco(part(m, "GiantRibbon", Vector3.new(2, 11.1, 11.1), giant.CFrame, C.red))
	local _, haulLabels = sign(
		m,
		"BiggestHaul",
		"THIS WEEK'S BIGGEST HAUL",
		18,
		4,
		CFrame.new(T.X, 21, T.Z),
		C.purple,
		Color3.new(1, 1, 1),
		true
	)
	-- Most Wanted wall, facing the path (-X)
	local wanted = {}
	local Wt = L.Wanted
	local wall = part(
		m,
		"WantedWall",
		Vector3.new(36, 15, 2),
		CFrame.new(Wt.X, 8.5, Wt.Z) * CFrame.Angles(0, math.rad(90), 0),
		C.darkWood,
		Enum.Material.Wood
	)
	deco(
		part(
			m,
			"WantedSnow",
			Vector3.new(38, 1.2, 3),
			wall.CFrame * CFrame.new(0, 7.9, 0),
			C.snow,
			Enum.Material.Snow
		)
	)
	for i = 0, 7 do
		local cf = wall.CFrame
			* CFrame.new(-13.5 + (i % 4) * 9, 3.5 - math.floor(i / 4) * 6.6, -1.2)
			* CFrame.Angles(0, 0, (i % 3 - 1) * 0.06)
		local poster = part(m, "WantedPoster", Vector3.new(7, 5.6, 0.6), cf, Color3.fromRGB(201, 164, 106))
		poster:SetAttribute("Rank", i + 1)
		local paper = panel(poster, Enum.NormalId.Front, Color3.fromRGB(241, 223, 180))
		local ink = Color3.fromRGB(122, 42, 26)
		local title = row(paper, "Title", 0.04, 0.24, "WANTED", ink)
		title.TextXAlignment = Enum.TextXAlignment.Center
		local photo = Instance.new("ImageLabel")
		photo.Name = "Photo"
		photo.Position = UDim2.fromScale(0.05, 0.32)
		photo.Size = UDim2.fromScale(0.36, 0.62)
		photo.BackgroundColor3 = Color3.fromRGB(222, 198, 150)
		photo.BorderSizePixel = 0
		photo.Image = ""
		photo.Visible = false
		photo.Parent = paper
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = photo
		local name = row(paper, "Name", 0.34, 0.26, "", ink)
		name.Position = UDim2.fromScale(0.45, 0.34)
		name.Size = UDim2.fromScale(0.5, 0.26)
		local haul = row(paper, "Haul", 0.64, 0.22, "", Color3.fromRGB(70, 50, 30))
		haul.Position = UDim2.fromScale(0.45, 0.64)
		haul.Size = UDim2.fromScale(0.5, 0.22)
		table.insert(wanted, { poster = poster, title = title, photo = photo, name = name, haul = haul })
	end
	sign(
		m,
		"MostWantedTitle",
		"MOST WANTED THIS WEEK",
		22,
		2.8,
		wall.CFrame * CFrame.new(0, 10.5, -0.6),
		C.red,
		C.gold
	)
	return {
		crewRows = crewRows,
		crewEmpty = empty,
		crewReset = reset,
		biggestHaul = haulLabels,
		wanted = wanted,
	}
end

local function buildPath(model: Model)
	local L = Config.LobbyMap
	local m = Instance.new("Model")
	m.Name = "PresentPath"
	m.Parent = model
	path(m, L.Path, 7, C.red, 50, 18)
	local junction = deco(
		part(
			m,
			"Junction",
			Vector3.new(0.22, 14, 14),
			CFrame.new(L.Fork.X, 0.12, L.Fork.Z) * CFrame.Angles(0, 0, math.rad(90)),
			C.cream,
			nil,
			"Part"
		)
	)
	junction.Shape = Enum.PartType.Cylinder
	-- three branches in bay colours
	for _, bay in L.Bays do
		local finish = branchEnd(bay)
		local mid =
			Vector3.new((L.Fork.X + bay.X) / 2, 0, (L.Fork.Z + finish.Z) / 2 - (if bay.X == 0 then 0 else 3))
		path(m, { L.Fork + Vector3.new(0, 0, 4), mid, finish }, 5.5, bay.Colour, 16, 7, 2)
	end
	-- wooden signpost at the fork: arrow planks to Public and Private, a board on top for Party
	local post =
		column(m, "SignpostStake", 10, 1, Vector3.new(L.Fork.X, 0, L.Fork.Z), C.darkWood, Enum.Material.Wood)
	post:SetAttribute("Signpost", true)
	for k, bay in L.Bays do
		local label = string.upper(bay.Kind)
		if bay.X == 0 then
			sign(
				m,
				"SignParty",
				"PARTY AHEAD",
				6.4,
				1.8,
				CFrame.new(L.Fork.X, 10.9, L.Fork.Z),
				C.wood,
				Color3.fromRGB(74, 42, 20),
				true,
				C.darkWood
			)
		else
			local dir = (branchEnd(bay) - Vector3.new(L.Fork.X, 0, L.Fork.Z)).Unit
			local y = if k == 1 then 7.6 else 5.6
			local origin = Vector3.new(L.Fork.X, y, L.Fork.Z)
			-- plank runs along dir, text on both faces
			local cf = CFrame.lookAt(origin + dir * 3.4, origin + dir * 10)
				* CFrame.Angles(0, math.rad(90), 0)
			sign(
				m,
				"Sign" .. bay.Kind,
				label,
				6.4,
				1.6,
				cf,
				C.wood,
				Color3.fromRGB(74, 42, 20),
				true,
				C.darkWood
			)
			part(
				m,
				"SignTip",
				Vector3.new(0.6, 1.6, 1.2),
				CFrame.lookAt(origin + dir * 7.2, origin + dir * 10) * CFrame.Angles(0, math.rad(90), 0),
				C.darkWood,
				nil,
				"WedgePart"
			)
		end
	end
end

local MODE = {
	Public = "Anyone can hop on",
	Party = "Your group + randoms",
	Private = "Just your crew",
}

local function buildStation(model: Model, floorH: number): { Bay }
	local L = Config.LobbyMap
	local pl = L.Platform
	local m = Instance.new("Model")
	m.Name = "SleighStation"
	m.Parent = model
	local cz = (pl.Z0 + pl.Z1) / 2
	part(
		m,
		"Platform",
		Vector3.new(pl.X1 - pl.X0, floorH, pl.Z1 - pl.Z0),
		CFrame.new(0, floorH / 2, cz),
		C.platform
	)
	deco(
		part(
			m,
			"EdgeLine",
			Vector3.new(pl.X1 - pl.X0, 0.1, 1),
			CFrame.new(0, floorH + 0.05, pl.Z1 - 0.5),
			C.gold,
			Enum.Material.Neon
		)
	)
	-- you board through the zone, not by walking off the edge
	local edge =
		part(m, "EdgeBlocker", Vector3.new(pl.X1 - pl.X0, 8, 0.6), CFrame.new(0, floorH + 4, pl.Z1), C.gold)
	edge.Transparency = 1
	for _, x in { -39, -13, 13, 39 } do
		for _, z in { pl.Z0 + 1, pl.Z1 - 1 } do
			column(m, "CanopyPost", 13, 1.1, Vector3.new(x, floorH, z), C.gold)
		end
	end
	-- Christmas lights along both canopy edges, warm light on the platform
	for _, z in { pl.Z0 - 1.6, pl.Z1 + 1.6 } do
		stringLights(
			m,
			Vector3.new(pl.X0 - 2, floorH + 12.7, z),
			Vector3.new(pl.X1 + 2, floorH + 12.7, z),
			1.2,
			2.4
		)
	end
	part(
		m,
		"Canopy",
		Vector3.new(pl.X1 - pl.X0 + 4, 1, pl.Z1 - pl.Z0 + 4),
		CFrame.new(0, floorH + 13.3, cz),
		C.wall
	)
	part(
		m,
		"CanopySnow",
		Vector3.new(pl.X1 - pl.X0 + 4.6, 0.8, pl.Z1 - pl.Z0 + 4.6),
		CFrame.new(0, floorH + 14.1, cz),
		C.snow,
		Enum.Material.Snow
	)
	sign(
		m,
		"StationSign",
		"SLEIGH STATION",
		26,
		3.6,
		CFrame.new(0, floorH + 12.4, pl.Z0 - 2.4),
		C.red,
		C.gold,
		false,
		C.gold
	)

	-- barrier line across the platform with a gap per bay
	local gaps = {}
	for _, bay in L.Bays do
		table.insert(gaps, { bay.X - L.GateGap / 2, bay.X + L.GateGap / 2 })
	end
	table.sort(gaps, function(a, b)
		return a[1] < b[1]
	end)
	local x = pl.X0
	table.insert(gaps, { pl.X1, pl.X1 })
	for _, g in gaps do
		if g[1] > x then
			part(
				m,
				"Barrier",
				Vector3.new(g[1] - x, 3, 0.8),
				CFrame.new((x + g[1]) / 2, floorH + 1.5, L.GateZ),
				Color3.fromRGB(154, 166, 214)
			)
		end
		x = g[2]
	end

	local bays: { Bay } = {}
	for _, cfg in L.Bays do
		local bx = cfg.X
		local half = L.GateGap / 2
		-- gate arms hinge at the barrier ends; closed = across the gap
		local arms = {}
		for _, s in { -1, 1 } do
			local hinge = CFrame.new(bx + s * half, floorH + 2.4, L.GateZ)
			local closed = hinge * CFrame.new(-s * half / 2, 0, 0)
			local open = hinge * CFrame.Angles(0, 0, s * -math.rad(80)) * CFrame.new(-s * half / 2, 0, 0)
			local arm = deco(part(m, "GateArm", Vector3.new(half, 0.45, 0.45), closed, C.snow))
			table.insert(arms, { part = arm, closed = closed, open = open })
		end
		local gate = part(
			m,
			"GateBlocker",
			Vector3.new(L.GateGap, 6, 1),
			CFrame.new(bx, floorH + 3, L.GateZ),
			cfg.Colour
		)
		gate.Transparency = 1
		-- stats board over the gate, facing the yard (-Z) so you read it as
		-- you walk up; the rim is the bay's colour. It hangs high enough to
		-- walk (and jump) under, just below the canopy (Josh, 6 Nov 2026).
		local sb = L.StatsBoard
		local statsPart = part(
			m,
			"StatsBoard",
			Vector3.new(9.8, sb.Height, 0.6),
			CFrame.new(bx, floorH + sb.Clearance + sb.Height / 2, L.GateZ),
			cfg.Colour:Lerp(BLACK, 0.2)
		)
		for _, s in { -1, 1 } do
			column(
				m,
				"StatsPost",
				sb.Clearance + sb.Height,
				0.6,
				Vector3.new(bx + s * 5.5, floorH, L.GateZ + 0.8),
				C.coal
			)
		end
		local bg = panel(statsPart, Enum.NormalId.Front, C.navy)
		local stats = {
			title = row(bg, "Title", 0.05, 0.2, "", Color3.new(1, 1, 1), cfg.Colour),
			status = row(bg, "Status", 0.3, 0.18, "", C.gold),
			crew = row(bg, "Crew", 0.52, 0.16, "", Color3.new(1, 1, 1)),
			mode = row(bg, "Mode", 0.72, 0.16, "", Color3.fromRGB(169, 179, 218)),
		}
		stats.title.Text = string.format("BAY %d  %s", cfg.Number, string.upper(cfg.Kind))
		stats.title.TextXAlignment = Enum.TextXAlignment.Center
		stats.mode.Text = MODE[cfg.Kind] or ""
		-- BOARDING NOW! sign on the canopy, readable from both sides
		local boardingSign, boarding = sign(
			m,
			"BoardingSign",
			"BOARDING NOW!",
			16,
			3.6,
			CFrame.new(bx, floorH + 17.4, cz + 2),
			C.red,
			Color3.new(1, 1, 1),
			true,
			C.gold
		)
		for _, s in { -1, 1 } do
			column(m, "BoardingSignPost", 1.6, 0.4, Vector3.new(bx + s * 6, floorH + 14.5, cz + 2), C.gold)
		end
		lightAt(m, Vector3.new(bx, floorH + 11, cz), 20, 1)
		-- board zone between the gate and the platform edge
		local bz = L.BoardZone
		local zone = part(
			m,
			cfg.Kind .. "Zone",
			Vector3.new(bz.HalfWidth * 2, 0.2, bz.Z1 - bz.Z0),
			CFrame.new(bx, floorH + 0.1, (bz.Z0 + bz.Z1) / 2),
			cfg.Colour,
			Enum.Material.Neon
		)
		zone.CanCollide = false
		zone.Transparency = 0.3
		table.insert(bays, {
			kind = cfg.Kind,
			number = cfg.Number,
			x = bx,
			colour = cfg.Colour,
			sleighColour = cfg.Sleigh,
			zone = zone,
			gate = gate,
			arms = arms,
			stats = stats,
			boarding = boarding,
			boardingSign = boardingSign,
			home = CFrame.new(bx - 3, 2, L.SleighZ) * CFrame.Angles(0, math.rad(-90), 0),
		})
	end
	return bays
end

function LobbyMap.build(parent: Instance): Hub
	local model = Instance.new("Model")
	model.Name = "SleighStationLobby"
	local floorH = Config.LobbyMap.FloorHeight
	buildYard(model)
	buildScenery(model)
	local boards = buildWorkshop(model, floorH)
	local showOff = buildShowOff(model)
	buildPath(model)
	local bays = buildStation(model, floorH)
	Parts.settle(model)
	model:SetAttribute("DetailRoot", true) -- clients drop far dressing (Shared.Detail)
	model.Parent = parent
	return {
		model = model,
		spawn = Config.Map.HubSpawn,
		bays = bays,
		departureBoards = boards,
		showOff = showOff,
	}
end

return LobbyMap
