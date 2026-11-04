--[[
	Builds the Sleigh Station lobby: the Naughty Workshop (spawn inside), the
	show-off yard (top crews podium, giant weekly present, Most Wanted wall), a
	present-lined path that forks three ways at a wooden signpost, and the
	Sleigh Station with a gate, stats board, "BOARDING NOW!" sign and board zone
	per bay. Layout numbers live in Config.LobbyMap.

	Like MapBuilder it connects no events, so tests can build it outside
	Roblox. Station.luau drives the bays (gates, boards, sleighs, seating).
	Plain parts only: approved models replace stand-ins through Assets.
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

export type Hub = {
	model: Model,
	spawn: CFrame,
	bays: { Bay },
	departureBoards: { TextLabel },
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

local function surfaceText(
	p: BasePart,
	face: Enum.NormalId,
	text: string,
	bg: Color3,
	fg: Color3,
	font: Enum.Font?
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
	return label
end

-- A sign board with text on its -Z face (and +Z if twoSided).
local function sign(
	parent: Instance,
	name: string,
	text: string,
	w: number,
	h: number,
	cf: CFrame,
	bg: Color3,
	fg: Color3,
	twoSided: boolean?
): (BasePart, { TextLabel })
	local p = part(parent, name, Vector3.new(w, h, 0.6), cf, bg)
	local labels = { surfaceText(p, Enum.NormalId.Front, text, bg, fg) }
	if twoSided then
		table.insert(labels, surfaceText(p, Enum.NormalId.Back, text, bg, fg))
	end
	return p, labels
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
	part(f, "BackWall", Vector3.new(W + 2, w.Height, 2), CFrame.new(0, w.Height / 2, w.Z0), C.wall)
	for _, x in { w.X0, w.X1 } do
		part(f, "SideWall", Vector3.new(2, w.Height, D), CFrame.new(x, w.Height / 2, cz), C.wall)
	end
	part(f, "FrontHeader", Vector3.new(W + 2, 5, 2), CFrame.new(0, w.Height - 2.5, w.Z1), C.wall)
	for _, x in { -13, 13 } do
		part(
			f,
			"Pillar",
			Vector3.new(2.4, w.Height - 5, 2.4),
			CFrame.new(x, (w.Height - 5) / 2, w.Z1),
			C.gold
		)
	end
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
	for i, col in { C.red, C.green, Color3.fromRGB(61, 123, 255), C.purple, C.gold } do
		deco(
			part(
				f,
				"Stocking",
				Vector3.new(1.2, 2.4, 0.6),
				CFrame.new(-5.6 + (i - 1) * 2.8, floorH + 9, w.Z0 + 4.5),
				col
			)
		)
	end
	for _, s in { -1, 1 } do
		part(
			f,
			"Armchair",
			Vector3.new(4, 2, 4),
			CFrame.new(s * 10, floorH + 1.4, -53) * CFrame.Angles(0, -s * 0.5, 0),
			if s < 0 then C.purple else C.teal
		)
	end
	part(
		f,
		"Tree",
		Vector3.new(7, 11, 7),
		CFrame.new(-34, floorH + 5.5, -28),
		Color3.fromRGB(29, 138, 69),
		nil,
		"Part"
	).Shape =
		Enum.PartType.Cylinder
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

local function buildYard(model: Model)
	local y = Config.LobbyMap.Yard
	local m = Instance.new("Model")
	m.Name = "Yard"
	m.Parent = model
	part(m, "Snow", Vector3.new(400, 2, 400), CFrame.new(0, -1, 20), C.snow, Enum.Material.Snow)
	deco(
		part(
			m,
			"YardFloor",
			Vector3.new(y.X1 - y.X0, 0.1, y.Z1 - y.Z0),
			CFrame.new((y.X0 + y.X1) / 2, 0.05, (y.Z0 + y.Z1) / 2),
			C.yard
		)
	)
	-- candy-cane fence on three sides
	for _, x in { y.X0, y.X1 } do
		part(m, "Fence", Vector3.new(1, 2.2, y.Z1 - y.Z0), CFrame.new(x, 1.1, (y.Z0 + y.Z1) / 2), C.snow)
	end
	part(m, "Fence", Vector3.new(y.X1 - y.X0, 2.2, 1), CFrame.new(0, 1.1, y.Z1), C.snow)
	for _, l in { { -56, -12 }, { 36, -12 }, { -50, 34 }, { 42, 36 }, { -60, 60 }, { 60, 60 } } do
		part(m, "LampPost", Vector3.new(0.5, 8, 0.5), CFrame.new(l[1], 4, l[2]), C.red)
		local bulb = deco(
			part(m, "Bulb", Vector3.new(1, 1, 1), CFrame.new(l[1], 8.2, l[2]), C.gold, Enum.Material.Neon)
		)
		bulb.Shape = Enum.PartType.Ball
	end
end

local function buildShowOff(model: Model)
	local L = Config.LobbyMap
	local m = Instance.new("Model")
	m.Name = "ShowOff"
	m.Parent = model
	-- Top crews podium (statues are stand-ins until avatars are cloned in)
	local P = L.Podium
	for _, s in
		{
			{ 0, 6, C.gold, 1 },
			{ -8, 4, Color3.fromRGB(200, 208, 224), 2 },
			{ 8, 2.6, Color3.fromRGB(208, 138, 74), 3 },
		}
	do
		local step = part(
			m,
			"PodiumStep" .. s[4],
			Vector3.new(7.5, s[2], 6),
			CFrame.new(P.X - s[1], s[2] / 2, P.Z),
			s[3]
		)
		surfaceText(step, Enum.NormalId.Back, tostring(s[4]), s[3], C.navy)
		for k = 0, 2 do
			part(
				m,
				"Statue",
				Vector3.new(1.6, 4, 1.4),
				CFrame.new(P.X - s[1] - 2.2 + k * 2.2, s[2] + 2, P.Z + 0.5),
				C.red
			)
		end
	end
	sign(m, "TopCrewsBoard", "TOP CREWS THIS WEEK", 17, 9, CFrame.new(P.X, 15, P.Z + 5), C.navy, C.gold)
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
	deco(part(m, "GiantRibbon", Vector3.new(11.1, 11.1, 2), giant.CFrame, C.red))
	deco(part(m, "GiantRibbon", Vector3.new(2, 11.1, 11.1), giant.CFrame, C.red))
	sign(
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
	local Wt = L.Wanted
	local wall = part(
		m,
		"WantedWall",
		Vector3.new(36, 15, 2),
		CFrame.new(Wt.X, 8.5, Wt.Z) * CFrame.Angles(0, math.rad(90), 0),
		C.darkWood,
		Enum.Material.Wood
	)
	for i = 0, 7 do
		local cf = wall.CFrame * CFrame.new(-13.5 + (i % 4) * 9, 3.5 - math.floor(i / 4) * 6.6, -1.2)
		local poster = sign(
			m,
			"WantedPoster",
			"WANTED",
			7,
			5.6,
			cf,
			Color3.fromRGB(241, 223, 180),
			Color3.fromRGB(122, 42, 26)
		)
		poster:SetAttribute("Rank", i + 1)
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
	local post = part(
		m,
		"SignpostStake",
		Vector3.new(0.9, 10, 0.9),
		CFrame.new(L.Fork.X, 5, L.Fork.Z),
		C.darkWood,
		Enum.Material.Wood
	)
	post:SetAttribute("Signpost", true)
	for k, bay in L.Bays do
		local label = string.upper(bay.Kind)
		if bay.X == 0 then
			local board = sign(
				m,
				"SignParty",
				"PARTY AHEAD",
				6.4,
				1.8,
				CFrame.new(L.Fork.X, 10.1, L.Fork.Z),
				C.wood,
				Color3.fromRGB(74, 42, 20),
				true
			)
			board.Material = Enum.Material.Wood
		else
			local dir = (branchEnd(bay) - Vector3.new(L.Fork.X, 0, L.Fork.Z)).Unit
			local y = if k == 1 then 7.6 else 5.6
			local origin = Vector3.new(L.Fork.X, y, L.Fork.Z)
			-- plank runs along dir, text on both faces
			local cf = CFrame.lookAt(origin + dir * 3.4, origin + dir * 10)
				* CFrame.Angles(0, math.rad(90), 0)
			local plank =
				sign(m, "Sign" .. bay.Kind, label, 6.4, 1.6, cf, C.wood, Color3.fromRGB(74, 42, 20), true)
			plank.Material = Enum.Material.Wood
			part(
				m,
				"SignTip",
				Vector3.new(0.6, 1.6, 1.2),
				CFrame.lookAt(origin + dir * 7.2, origin + dir * 10) * CFrame.Angles(0, math.rad(90), 0),
				C.wood,
				Enum.Material.Wood,
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
			part(m, "CanopyPost", Vector3.new(1, 13, 1), CFrame.new(x, floorH + 6.5, z), C.gold)
		end
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
		-- stats board over the gate, facing the yard
		local statsPart = part(
			m,
			"StatsBoard",
			Vector3.new(9.8, 6.8, 0.6),
			CFrame.new(bx, floorH + 8, L.GateZ) * CFrame.Angles(0, math.pi, 0),
			C.coal
		)
		for _, s in { -1, 1 } do
			part(
				m,
				"StatsPost",
				Vector3.new(0.6, 8, 0.6),
				CFrame.new(bx + s * 5.5, floorH + 4, L.GateZ - 0.8),
				C.coal
			)
		end
		local gui = surfaceGui(statsPart, Enum.NormalId.Front)
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = C.navy
		bg.BorderSizePixel = 0
		bg.Parent = gui
		local function row(name: string, y: number, h: number, color: Color3, back: Color3?): TextLabel
			local l = Instance.new("TextLabel")
			l.Name = name
			l.Position = UDim2.fromScale(0.05, y)
			l.Size = UDim2.fromScale(0.9, h)
			l.BackgroundTransparency = if back then 0 else 1
			l.BackgroundColor3 = back or C.navy
			l.TextColor3 = color
			l.TextScaled = true
			l.Font = Enum.Font.FredokaOne
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Text = ""
			l.Parent = bg
			return l
		end
		local stats = {
			title = row("Title", 0.03, 0.2, Color3.new(1, 1, 1), cfg.Colour),
			status = row("Status", 0.3, 0.18, C.gold),
			crew = row("Crew", 0.52, 0.16, Color3.new(1, 1, 1)),
			mode = row("Mode", 0.72, 0.16, Color3.fromRGB(169, 179, 218)),
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
			true
		)
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
	local boards = buildWorkshop(model, floorH)
	buildShowOff(model)
	buildPath(model)
	local bays = buildStation(model, floorH)
	model.Parent = parent
	return {
		model = model,
		spawn = Config.Map.HubSpawn,
		bays = bays,
		departureBoards = boards,
	}
end

return LobbyMap
