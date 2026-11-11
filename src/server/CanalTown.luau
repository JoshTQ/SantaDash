--[[
	Frozen Canal Town map features (see shared/Maps/FrozenCanal and
	MapFeatures). Everything is greybox Parts until the canal kit (stalls,
	hoops, rink edge, floes, bridge) is approved; the security dogs use the
	approved DogCorgi / DogTin models from ServerStorage.Assets when present.

	build() functions add Instances only (no events) so Lune can build them.
	They stash what the runtime needs on stop.canal:
	  iceZones   canal ice segments (IceZone, CrackZone on the middle pieces)
	  splashZones  ice that can break into floes (CrackZone segments + the lake)
	  hoops      boost hoop trigger parts
	  dogs       { kind, points (world), offset }
	  rink       { centre, radius, snowbanks }
	  lake       the lake ice part

	CanalTown.breakZone(zonePart) turns any IceZone part into water with floes
	(the Lair's floe hop, and the Thin Ice map event).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Maps = require(ReplicatedStorage.Shared.Maps)
local SantaMoves = require(ReplicatedStorage.Shared.SantaMoves)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Util = require(ReplicatedStorage.Shared.Util)
local CanalRules = require(script.Parent.CanalRules)
local Boots = require(script.Parent.Boots)
local PopInHouses = require(script.Parent.PopInHouses)
local GuardDogs = require(script.Parent.GuardDogs)
local Swimming = require(script.Parent.Swimming)

local C = Config.Canal
local CanalTown = {}

local ICE = Color3.fromRGB(175, 220, 245)
local WATER = Color3.fromRGB(40, 95, 150)
local LANE_ICE = Color3.fromRGB(120, 185, 235) -- thick lane ice, a shade deeper than the lake
local SNOW = Color3.fromRGB(240, 245, 252)
local HEDGE = Color3.fromRGB(40, 120, 70)
local PAVEMENT = Color3.fromRGB(205, 200, 215)
local KERB = Color3.fromRGB(160, 160, 175)
local CANDY = Color3.fromRGB(215, 40, 50)
local WHITE = Color3.fromRGB(250, 250, 250)
local GOLD = Color3.fromRGB(255, 200, 60)
local WOOD = Color3.fromRGB(130, 85, 55)
local DOOR_COLOURS = {
	Color3.fromRGB(200, 40, 55),
	Color3.fromRGB(45, 120, 80),
	Color3.fromRGB(50, 90, 170),
	Color3.fromRGB(110, 65, 40),
}
local FACADES = {
	Color3.fromRGB(240, 170, 180),
	Color3.fromRGB(170, 210, 240),
	Color3.fromRGB(250, 220, 150),
	Color3.fromRGB(190, 230, 190),
	Color3.fromRGB(215, 190, 240),
	Color3.fromRGB(150, 95, 70),
}
local STALLS = { "COCOA", "GINGERBREAD", "BAUBLES", "ROASTED NUTS", "TOYS", "CANDY CANES", "MITTENS" }

-- zone part -> floe keepouts (zone space) and its floes once broken
local keepoutsFor: { [BasePart]: { CanalRules.Keepout } } = setmetatable({}, { __mode = "k" }) :: any
local floesFor: { [BasePart]: { BasePart } } = setmetatable({}, { __mode = "k" }) :: any
local floeBoxes: { [BasePart]: { CanalRules.Box } } = setmetatable({}, { __mode = "k" }) :: any

----------------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------------

local function label(part: BasePart, text: string, color: Color3, offsetY: number, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = maxDistance or 120
	gui.LightInfluence = 0
	local text_ = Instance.new("TextLabel")
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Text = text
	text_.TextColor3 = color
	text_.TextStrokeTransparency = 0
	text_.TextScaled = true
	text_.Font = Enum.Font.FredokaOne
	text_.Parent = gui
	gui.Parent = part
end

local function canalState(stop)
	if not stop.canal then
		stop.canal = { iceZones = {}, splashZones = {}, hoops = {}, dogs = {} }
	end
	return stop.canal
end

-- Another feature of this map that applies to this stop (e.g. the rink).
local function sibling(ctx, kind: string)
	for _, f in ctx.map.features do
		if f.kind == kind and Maps.featureOnStop(f, ctx.stop.plan.index) then
			return f
		end
	end
	return nil
end

local function streetEnd(ctx): number
	local lake = sibling(ctx, "FloeLake")
	if lake then
		return lake.from
	end
	return Config.Rings.Far.Distance + ctx.map.layout.StreetOverrun
end

-- z ranges (stop space) the street dressing leaves clear at this stop.
local function clearRanges(ctx): { { number } }
	local ranges = {}
	local rink = sibling(ctx, "IceRink")
	if rink then
		table.insert(ranges, { rink.centre.Z - rink.radius - 8, rink.centre.Z + rink.radius + 8 })
	end
	return ranges
end

local function inRanges(z: number, ranges: { { number } }): boolean
	for _, r in ranges do
		if z >= r[1] and z <= r[2] then
			return true
		end
	end
	return false
end

-- A box from a to b (stop space, at height y with the given height), as one part.
local function wall(
	ctx,
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	height: number,
	color: Color3,
	material
)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return nil
	end
	local mid = (a + b) / 2
	local cf = ctx.origin * CFrame.lookAt(mid, mid + (b - a)) * CFrame.new(0, height / 2, 0)
	return ctx.newPart(ctx.model, name, Vector3.new(width, height, length), cf, color, material)
end

local function ball(ctx, name: string, at: Vector3, diameter: number, color: Color3, material)
	local part =
		ctx.newPart(ctx.model, name, Vector3.one * diameter, ctx.origin * CFrame.new(at), color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

-- Christmas bulbs along a sagging strand from a to b (stop space).
local function strand(ctx, a: Vector3, b: Vector3, sag: number, spacing: number)
	local n = math.max(2, math.floor((b - a).Magnitude / spacing))
	for i = 0, n do
		local t = i / n
		local p = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		ball(ctx, "Bulb", p, 0.7, C.LightColours[i % #C.LightColours + 1], Enum.Material.Neon).CanCollide =
			false
	end
end

-- A warm PointLight so lamps and decorations light the snow at night.
local function glow(part: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = part
end

----------------------------------------------------------------------------
-- CanalStreet: pavements, front gardens, hedges, fences, canal barriers
----------------------------------------------------------------------------

local function pavements(ctx, zEnd: number, ranges)
	local half = ctx.map.layout.RoadWidth / 2
	local z0 = ctx.map.layout.StreetStart
	for _, side in { -1, 1 } do
		local x = side * (half + C.Promenade / 2)
		-- Split around clear ranges (the rink) so the square stays open.
		local cuts = { z0 }
		for _, r in ranges do
			table.insert(cuts, r[1])
			table.insert(cuts, r[2])
		end
		table.insert(cuts, zEnd)
		for i = 1, #cuts - 1, 2 do
			local a, b = cuts[i], cuts[i + 1]
			if b > a then
				wall(ctx, "Pavement", Vector3.new(x, 0, a), Vector3.new(x, 0, b), C.Promenade, 0.4, PAVEMENT)
				wall(
					ctx,
					"Kerb",
					Vector3.new(side * (half + 0.3), 0, a),
					Vector3.new(side * (half + 0.3), 0, b),
					0.6,
					0.6,
					KERB
				)
			end
		end
	end
end

-- Bollards with gold chains along both canal edges; gaps (marked ICE) let
-- Santas onto the skate lane.
local function barriers(ctx, zEnd: number, ranges, gaps: { number })
	local half = ctx.map.layout.RoadWidth / 2
	local z0 = ctx.map.layout.StreetStart + 4
	local function isGap(z)
		for _, g in gaps do
			if math.abs(z - g) < 6 then
				return true
			end
		end
		return inRanges(z, ranges)
	end
	for _, side in { -1, 1 } do
		local x = side * (half + 0.9)
		local runStart: number?, prev: number? = nil, nil
		-- One chain along each run of bollards between gaps.
		local function chain()
			if runStart and prev and prev > runStart then
				local part = wall(
					ctx,
					"Chain",
					Vector3.new(x, 1.8, runStart),
					Vector3.new(x, 1.8, prev),
					0.25,
					0.25,
					GOLD
				)
				if part then
					part.Material = Enum.Material.Neon
				end
			end
			runStart, prev = nil, nil
		end
		local z = z0
		while z <= zEnd - 2 do
			if isGap(z) then
				chain()
			else
				ctx.newPart(
					ctx.model,
					"Bollard",
					Vector3.new(1, 2.6, 1),
					ctx.origin * CFrame.new(x, 1.3, z),
					WHITE
				).Material =
					Enum.Material.SmoothPlastic
				ctx.newPart(
					ctx.model,
					"BollardBand",
					Vector3.new(1.1, 0.4, 1.1),
					ctx.origin * CFrame.new(x, 1.9, z),
					CANDY
				)
				runStart = runStart or z
				prev = z
			end
			z += 8
		end
		chain()
	end
	for _, g in gaps do
		for _, side in { -1, 1 } do
			local sign = ctx.newPart(
				ctx.model,
				"IceSign",
				Vector3.new(0.5, 5, 0.5),
				ctx.origin * CFrame.new(side * (half + 1.5), 2.5, g + 6),
				CANDY
			)
			label(sign, "ICE ⛸", Color3.fromRGB(150, 220, 255), 3.5, 90)
		end
	end
end

local function lamps(ctx, zEnd: number, ranges)
	local half = ctx.map.layout.RoadWidth / 2
	local z = ctx.map.layout.StreetStart + 20
	while z < zEnd - 10 do
		if not inRanges(z, ranges) then
			for _, side in { -1, 1 } do
				local x = side * (half + C.Promenade - 0.8)
				ctx.newPart(
					ctx.model,
					"LampPost",
					Vector3.new(0.6, 10, 0.6),
					ctx.origin * CFrame.new(x, 5, z),
					CANDY
				)
				local lamp = ball(
					ctx,
					"LampGlow",
					Vector3.new(x, 10.5, z),
					1.6,
					Color3.fromRGB(255, 235, 170),
					Enum.Material.Neon
				)
				glow(lamp, Color3.fromRGB(255, 210, 150), 24)
			end
			-- Lights strung across the canal between each pair of lamps.
			local x = half + C.Promenade - 0.8
			strand(ctx, Vector3.new(-x, 10, z), Vector3.new(x, 10, z), 2.5, 4)
		end
		z += 44
	end
end

-- Front garden, fence and hedges around one street house (side +/-1).
local function garden(ctx, house)
	local layout = ctx.map.layout
	local side, z = house.side, house.distance
	local halfW = house.size.Z / 2
	local inner = layout.RoadWidth / 2 + C.Promenade -- pavement's outer edge
	local front = layout.SideOffset - house.size.X / 2 -- house front face
	local back = layout.SideOffset + house.size.X / 2 + 2
	local zA, zB = z - halfW - 4, z + halfW + 4

	-- Snowy lawn and a stepping-stone path from the gate to the door.
	wall(
		ctx,
		"Lawn",
		Vector3.new(side * (inner + front) / 2, 0, zA),
		Vector3.new(side * (inner + front) / 2, 0, zB),
		front - inner,
		0.3,
		SNOW,
		Enum.Material.Snow
	)
	local stones = math.max(2, math.floor((front - inner) / 3.5))
	for i = 1, stones do
		local x = side * (inner + (front - inner) * (i - 0.5) / stones)
		local stone = ctx.newPart(
			ctx.model,
			"SteppingStone",
			Vector3.new(0.3, 2.6, 2.6),
			ctx.origin * CFrame.new(x, 0.35, z) * CFrame.Angles(0, 0, math.pi / 2),
			KERB
		)
		stone.Shape = Enum.PartType.Cylinder
	end
	-- Shrubs by the house front, and a snowman on some lawns.
	for _, dz in { -halfW + 3, halfW - 3 } do
		ball(ctx, "Shrub", Vector3.new(side * (front - 2.5), 1.6, z + dz), 3.4, HEDGE, Enum.Material.Grass)
		ball(ctx, "ShrubSnow", Vector3.new(side * (front - 2.5), 3, z + dz), 2, SNOW, Enum.Material.Snow)
	end
	if ctx.rng:NextNumber() < 0.5 then
		local sx, sz = side * (inner + 4), z + (if ctx.rng:NextNumber() < 0.5 then -halfW + 4 else halfW - 4)
		ball(ctx, "Snowman", Vector3.new(sx, 1.6, sz), 3.4, SNOW, Enum.Material.Snow)
		ball(ctx, "Snowman", Vector3.new(sx, 4.1, sz), 2.4, SNOW, Enum.Material.Snow)
		ball(ctx, "Snowman", Vector3.new(sx, 5.9, sz), 1.7, SNOW, Enum.Material.Snow)
	end

	-- Picket fence along the pavement with a gate gap at the path. The landing
	-- house stays open so the crew can run straight in from the Sleigh Stop.
	if not house.isLanding then
		local x = side * (inner + 0.4)
		for _, span in { { zA, z - 4 }, { z + 4, zB } } do
			for _, y in { 1.2, 2.4 } do
				wall(
					ctx,
					"FenceRail",
					Vector3.new(x, y, span[1]),
					Vector3.new(x, y, span[2]),
					0.3,
					0.4,
					WHITE
				)
			end
			local p = span[1]
			local red = false
			while p <= span[2] + 0.01 do
				ctx.newPart(
					ctx.model,
					"Picket",
					Vector3.new(0.4, 3.4, 0.7),
					ctx.origin * CFrame.new(x, 1.7, p),
					if red then CANDY else WHITE
				)
				red = not red
				p += 2
			end
		end
		for _, gz in { z - 4, z + 4 } do
			ctx.newPart(
				ctx.model,
				"GatePost",
				Vector3.new(0.9, 4, 0.9),
				ctx.origin * CFrame.new(x, 2, gz),
				CANDY
			)
			ball(ctx, "GateLight", Vector3.new(x, 4.4, gz), 1.1, GOLD, Enum.Material.Neon)
		end
	end

	-- Hedges between neighbours and along the back, with a gap at the back so
	-- the back-window route still works.
	for _, hz in { zA - 1, zB + 1 } do
		wall(
			ctx,
			"Hedge",
			Vector3.new(side * inner, 0, hz),
			Vector3.new(side * back, 0, hz),
			3,
			4.4,
			HEDGE,
			Enum.Material.Grass
		)
	end
	local hx = side * (back + 1)
	wall(
		ctx,
		"Hedge",
		Vector3.new(hx, 0, zA - 1),
		Vector3.new(hx, 0, z - 4),
		3,
		4.4,
		HEDGE,
		Enum.Material.Grass
	)
	wall(
		ctx,
		"Hedge",
		Vector3.new(hx, 0, z + 4),
		Vector3.new(hx, 0, zB + 1),
		3,
		4.4,
		HEDGE,
		Enum.Material.Grass
	)
end

-- Townhouses and low hedges fill the stretches between the stop's real
-- houses, so the canal reads as a street. Each is one solid block with a real
-- front door: walk up and PopInHouses swaps the block for a cosy room (Josh,
-- 11 Nov 2026: "most houses on the map are closed with no entry").
local function terraces(ctx, zEnd: number, ranges, houses, plaza: Vector3, skipBand: boolean)
	local layout = ctx.map.layout
	local inner = layout.RoadWidth / 2 + C.Promenade
	local z = layout.StreetStart + 26
	while z < zEnd - 20 do
		for _, side in { -1, 1 } do
			local free = not inRanges(z, ranges)
			for _, h in houses do
				if (h.side == side or h.side == 0) and math.abs(h.distance - z) < h.size.Z / 2 + 26 then
					free = false
				end
			end
			if side * plaza.X > 0 and math.abs(z - plaza.Z) < 30 then
				free = false
			end
			if free then
				local height = ctx.rng:NextInteger(16, 26)
				local color = FACADES[ctx.rng:NextInteger(1, #FACADES)]
				local x = side * (layout.SideOffset + 14)
				local block = ctx.newPart(
					ctx.model,
					"Townhouse",
					Vector3.new(24, height, 34),
					ctx.origin * CFrame.new(x, height / 2, z),
					color
				)
				-- PopInHouses hides and restores it: never culled by Detail.
				block:SetAttribute("KeepDetail", true)
				local roof = ctx.newPart(
					ctx.model,
					"TownhouseRoof",
					Vector3.new(26, 2, 36),
					ctx.origin * CFrame.new(x, height + 1, z),
					SNOW,
					Enum.Material.Snow
				)
				roof.CanCollide = true
				local face = x - side * 12.2
				-- Christmas lights along the eaves and a wreath over the door.
				strand(
					ctx,
					Vector3.new(face - side * 0.6, height - 0.4, z - 16),
					Vector3.new(face - side * 0.6, height - 0.4, z + 16),
					0.8,
					2.6
				)
				-- A real front door with a wreath on it. It swings open (and the
				-- room inside is built) when a Santa walks up: PopInHouses.
				local P = Config.PopIn
				local door = ctx.newPart(
					ctx.model,
					"PopInDoor",
					Vector3.new(0.5, P.DoorHeight, P.DoorWidth),
					ctx.origin * CFrame.new(face - side * 0.25, P.DoorHeight / 2, z),
					DOOR_COLOURS[(math.floor(z / 40) + (if side > 0 then 1 else 0)) % #DOOR_COLOURS + 1],
					Enum.Material.Wood
				)
				door:SetAttribute("KeepDetail", true)
				local wreath = ctx.newPart(
					ctx.model,
					"Wreath",
					Vector3.new(0.6, 3, 3),
					ctx.origin * CFrame.new(face - side * 0.7, P.DoorHeight * 0.7, z),
					HEDGE,
					Enum.Material.Grass
				)
				wreath.Shape = Enum.PartType.Cylinder
				wreath:SetAttribute("KeepDetail", true)
				local bow = ball(
					ctx,
					"WreathBow",
					Vector3.new(face - side * 0.9, P.DoorHeight * 0.7 - 1.1, z),
					0.8,
					CANDY,
					Enum.Material.Neon
				)
				bow:SetAttribute("KeepDetail", true)
				ctx.stop.popIns = ctx.stop.popIns or {}
				table.insert(ctx.stop.popIns, {
					block = block,
					door = door,
					wreath = { wreath, bow },
					-- Room frame: centre of the floor, LookVector out of the front door.
					frame = ctx.origin * CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x - side, 0, z)),
					size = Vector3.new(24, height, 34),
					color = color,
					-- Its own seed (not ctx.rng, so the rest of the map rolls as before).
					seed = ctx.stop.plan.index * 100000 + math.floor(z) * 2 + (if side > 0 then 1 else 0),
				})
				for row = 1, math.floor((height - 4) / 7) do
					for _, dz in { -10, 0, 10 } do
						if row == 1 and dz == 0 then
							continue -- the front door is here
						end
						ctx.newPart(
							ctx.model,
							"Window",
							Vector3.new(0.3, 3.4, 3.4),
							ctx.origin * CFrame.new(face, 3 + row * 6, z + dz),
							Color3.fromRGB(255, 225, 150),
							Enum.Material.Neon
						)
					end
				end
				if not skipBand then
					wall(
						ctx,
						"Hedge",
						Vector3.new(side * (inner + 1.5), 0, z - 17),
						Vector3.new(side * (inner + 1.5), 0, z + 17),
						2.4,
						3,
						HEDGE,
						Enum.Material.Grass
					)
				end
			end
		end
		z += 40
	end
end

local CanalStreet = {}

function CanalStreet.build(ctx)
	local zEnd = streetEnd(ctx)
	local ranges = clearRanges(ctx)
	local houses = ctx.stop.plan.houses
	local landing = ctx.landing

	-- Sleigh Stop plaza (on the ground, never ice).
	local plaza = landing.Position
	ctx.newPart(
		ctx.model,
		"Plaza",
		Vector3.new(40, 0.3, 40),
		ctx.origin * CFrame.new(plaza + Vector3.new(0, 0.15, 0)),
		Color3.fromRGB(215, 195, 200),
		Enum.Material.Cobblestone
	)

	pavements(ctx, zEnd, ranges)
	-- Gaps onto the ice: by the Sleigh Stop (cross to the landing house), every
	-- 110 studs, and in front of each house.
	local gaps = { 2 }
	local g = 110
	while g < zEnd - 20 do
		table.insert(gaps, g)
		g += 110
	end
	for _, h in houses do
		if h.side ~= 0 and h.distance < zEnd then
			table.insert(gaps, h.distance)
		end
	end
	barriers(ctx, zEnd, ranges, gaps)
	lamps(ctx, zEnd, ranges)
	for _, h in houses do
		if h.side ~= 0 then
			garden(ctx, h)
		end
	end
	terraces(ctx, zEnd, ranges, houses, plaza, sibling(ctx, "ChristmasMarket") ~= nil)
end

----------------------------------------------------------------------------
-- SkateCanal: the main canal between stops, boost hoops, skating, splashes
----------------------------------------------------------------------------

local function hoop(ctx, cf: CFrame)
	local state = canalState(ctx.stop)
	local world = ctx.origin * cf
	for _, x in { -4.5, 4.5 } do
		ctx.newPart(
			ctx.model,
			"HoopPost",
			Vector3.new(1, 9, 1),
			world * CFrame.new(x, 4.5, 0),
			GOLD,
			Enum.Material.Neon
		)
	end
	ctx.newPart(
		ctx.model,
		"HoopTop",
		Vector3.new(10, 1, 1),
		world * CFrame.new(0, 9.5, 0),
		GOLD,
		Enum.Material.Neon
	)
	local trigger =
		ctx.newPart(ctx.model, "BoostHoop", Vector3.new(8, 8, 2), world * CFrame.new(0, 4.5, 0), GOLD)
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger:SetAttribute("Trigger", true) -- keeps Touched through Parts.settle
	table.insert(state.hoops, trigger)
end

local function chevron(ctx, cf: CFrame, color: Color3)
	for _, s in { -1, 1 } do
		local arm = ctx.newPart(
			ctx.model,
			"Chevron",
			Vector3.new(0.8, 0.1, 5),
			ctx.origin * cf * CFrame.new(s * 1.6, 0.3, 0) * CFrame.Angles(0, s * math.rad(35), 0),
			color,
			Enum.Material.Neon
		)
		arm.CanCollide = false
	end
end

local function iceSegment(ctx, frame: CFrame, from: number, to: number, crack: boolean)
	local state = canalState(ctx.stop)
	local length = to - from
	local part = ctx.newPart(
		ctx.model,
		"CanalIce",
		Vector3.new(length, C.IceTop, C.Width),
		ctx.origin * frame * CFrame.new((from + to) / 2, C.IceTop / 2, 0),
		ICE,
		Enum.Material.Ice
	)
	part:SetAttribute("IceZone", true)
	part:SetAttribute("CrackZone", crack)
	table.insert(state.iceZones, part)
	if crack then
		table.insert(state.splashZones, part)
	end
	return part
end

-- A signpost: a candy post with a board and a big label (seen from 160 studs).
local function signpost(ctx, at: Vector3, text: string)
	ctx.newPart(
		ctx.model,
		"SignPost",
		Vector3.new(0.8, 9, 0.8),
		ctx.origin * CFrame.new(at + Vector3.new(0, 4.5, 0)),
		CANDY
	)
	local board = ctx.newPart(
		ctx.model,
		"SignBoard",
		Vector3.new(7, 2.4, 0.4),
		ctx.origin * CFrame.new(at + Vector3.new(0, 8, 0)),
		WOOD,
		Enum.Material.Wood
	)
	label(board, text, GOLD, 3.2, 160)
end

-- What a sign calls a stop: "STOP 2", or the Lair at the finale.
local function stopName(index: number): string
	if Config.Run.StopKinds[index] == "Finale" then
		return "KRAMPUS'S LAIR"
	end
	return "STOP " .. index
end

-- The FloeLake feature of another stop, if it has one.
local function lakeOf(ctx, index: number)
	for _, f in ctx.map.features do
		if f.kind == "FloeLake" and Maps.featureOnStop(f, index) then
			return f
		end
	end
	return nil
end

-- The back lane from this street's far end to the next stop's (or to the
-- edge of the Lair lake), plus the link down the street canal to it.
local function backLane(ctx)
	local layout = ctx.map.layout
	local B = C.BackLane
	local i = ctx.stop.plan.index
	local zEnd = streetEnd(ctx)
	if not sibling(ctx, "FloeLake") then
		-- The street canal carries on past the vault into the back lane.
		local from, to = zEnd - 1, B.Z + B.Width / 2
		local link = ctx.newPart(
			ctx.model,
			"BackLink",
			Vector3.new(layout.RoadWidth, C.IceTop, to - from),
			ctx.origin * CFrame.new(0, C.IceTop / 2, (from + to) / 2),
			ICE,
			Enum.Material.Ice
		)
		link:SetAttribute("IceZone", true)
		link:SetAttribute("CrackZone", false)
		table.insert(canalState(ctx.stop).iceZones, link)
	end
	if i >= #Config.Run.StopKinds then
		return
	end
	local here = Maps.stopOrigin(layout, i)
	local nextOrigin = here:Inverse() * Maps.stopOrigin(layout, i + 1)
	local nextLake = lakeOf(ctx, i + 1)
	-- Ends in this stop's space: the next street's link, or the lake's near edge.
	local endAt = nextOrigin * Vector3.new(if nextLake then -nextLake.halfWidth + 4 else 0, 0, B.Z)
	local a = Vector3.new(0, 0, B.Z)
	local flat = (endAt - a) * Vector3.new(1, 0, 1)
	local length = flat.Magnitude
	local frame = CFrame.fromMatrix(a, flat.Unit, Vector3.yAxis)
	local start = layout.RoadWidth / 2
	local finish = if nextLake then length else length - layout.RoadWidth / 2
	for _, seg in CanalRules.segments(start, finish) do
		local part = iceSegment(ctx, frame, seg.from, seg.to, seg.crack)
		part.Size = Vector3.new(part.Size.X, part.Size.Y, B.Width)
		part.Name = "BackLaneIce"
	end
	-- Low snowbanks, chevrons towards the next stop, a few hoops and lamps.
	for _, side in { -1, 1 } do
		local bank = ctx.newPart(
			ctx.model,
			"CanalBank",
			Vector3.new(finish - start, 1, 2),
			ctx.origin * frame * CFrame.new((start + finish) / 2, 0.5, side * (B.Width / 2 + 1)),
			SNOW,
			Enum.Material.Snow
		)
		bank.CanCollide = false
	end
	local d = start + 40
	while d < finish - 30 do
		chevron(
			ctx,
			frame * CFrame.new(d, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			Color3.fromRGB(255, 215, 90)
		)
		d += 60
	end
	d = start + 150
	while d < finish - 100 do
		hoop(ctx, frame * CFrame.new(d, 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
		d += 220
	end
	d = start + 70
	local side = 1
	while d < finish - 40 do
		local at = (frame * CFrame.new(d, 0, side * (B.Width / 2 + 3))).Position
		ctx.newPart(
			ctx.model,
			"LampPost",
			Vector3.new(0.6, 10, 0.6),
			ctx.origin * CFrame.new(at + Vector3.new(0, 5, 0)),
			CANDY
		)
		local lamp = ball(
			ctx,
			"LampGlow",
			at + Vector3.new(0, 10.5, 0),
			1.6,
			Color3.fromRGB(255, 235, 170),
			Enum.Material.Neon
		)
		glow(lamp, Color3.fromRGB(255, 210, 150), 22)
		side = -side
		d += 140
	end
	-- Signs at the junction: where each way goes.
	local sideX = layout.RoadWidth / 2 + 4
	signpost(ctx, Vector3.new(sideX, 0, B.Z - B.Width / 2 - 4), stopName(i + 1) .. "  >>")
	if i > 1 then
		signpost(ctx, Vector3.new(-sideX, 0, B.Z - B.Width / 2 - 4), "<<  " .. stopName(i - 1))
	end
end

local SkateCanal = {}

function SkateCanal.build(ctx)
	local layout = ctx.map.layout
	local i = ctx.stop.plan.index
	local z = layout.FootPathZ
	-- A basin where the street canal meets the main canal.
	iceSegment(ctx, CFrame.new(0, 0, z), -40, 40, false)

	-- Hoops down the street canal.
	local zEnd = streetEnd(ctx)
	for _, hz in { 120, 320 } do
		if hz < zEnd - 30 and not inRanges(hz, clearRanges(ctx)) then
			hoop(ctx, CFrame.new(0, 0, hz))
		end
	end

	backLane(ctx)
	-- Signs where the street canal meets the main canal.
	local sideX = layout.RoadWidth / 2 + 4
	if i < #Config.Run.StopKinds then
		signpost(ctx, Vector3.new(sideX, 0, z + C.Width / 2 + 4), stopName(i + 1) .. "  >>")
	end
	if i > 1 then
		signpost(ctx, Vector3.new(-sideX, 0, z + C.Width / 2 + 4), "<<  " .. stopName(i - 1))
	end
	if i >= #Config.Run.StopKinds then
		return
	end
	-- The main canal to the next stop, along the on-foot path.
	local here = Maps.stopOrigin(layout, i)
	local nextAt = here:Inverse() * Maps.stopOrigin(layout, i + 1) * Vector3.new(0, 0, z)
	local a = Vector3.new(0, 0, z)
	local flat = (nextAt - a) * Vector3.new(1, 0, 1)
	local length = flat.Magnitude
	-- Local frame: +X runs along the canal towards the next stop.
	local frame = CFrame.fromMatrix(a, flat.Unit, Vector3.yAxis)
	for _, seg in CanalRules.segments(40, length - 40) do
		iceSegment(ctx, frame, seg.from, seg.to, seg.crack)
	end
	-- Low snowbanks along both edges, hoops and chevrons towards the next stop.
	for _, s in { -1, 1 } do
		local bank = ctx.newPart(
			ctx.model,
			"CanalBank",
			Vector3.new(length - 80, 1, 2),
			ctx.origin * frame * CFrame.new(length / 2, 0.5, s * (C.Width / 2 + 1)),
			SNOW,
			Enum.Material.Snow
		)
		bank.CanCollide = false
	end
	local d = 100
	while d < length - 80 do
		hoop(ctx, frame * CFrame.new(d, 0, 0) * CFrame.Angles(0, math.pi / 2, 0))
		d += 120
	end
	-- Lamp posts along both banks, with lights strung along the bank between them.
	d = 70
	local prev: number? = nil
	while d < length - 60 do
		for _, sz in { -1, 1 } do
			local at = (frame * CFrame.new(d, 0, sz * (C.Width / 2 + 3))).Position
			ctx.newPart(
				ctx.model,
				"LampPost",
				Vector3.new(0.6, 10, 0.6),
				ctx.origin * CFrame.new(at + Vector3.new(0, 5, 0)),
				CANDY
			)
			local lamp = ball(
				ctx,
				"LampGlow",
				at + Vector3.new(0, 10.5, 0),
				1.6,
				Color3.fromRGB(255, 235, 170),
				Enum.Material.Neon
			)
			glow(lamp, Color3.fromRGB(255, 210, 150), 24)
			if prev then
				local from = (frame * CFrame.new(prev, 0, sz * (C.Width / 2 + 3))).Position
				strand(ctx, from + Vector3.new(0, 9.6, 0), at + Vector3.new(0, 9.6, 0), 3, 4.2)
			end
		end
		prev = d
		d += 80
	end
	d = 60
	while d < length - 40 do
		for _, off in { -12, 12 } do
			chevron(
				ctx,
				frame * CFrame.new(d, 0, off) * CFrame.Angles(0, -math.pi / 2, 0),
				Color3.fromRGB(255, 215, 90)
			)
		end
		d += 50
	end
end

-- Every 0.1 s: skating speed for Santas on ice, boosted after a hoop.
function SkateCanal.start(ctx)
	local run, stop = ctx.run, ctx.stop
	if not stop.canal then
		return nil
	end
	local boostUntil: { [Player]: number } = {}
	local splashAt: { [Player]: number } = {}
	local splashZones: { BasePart } = {}
	local connections = {}

	-- Hoops and splash zones of this stop and the one before: a Santa who
	-- missed the sleigh skates the previous stop's canal while this one is on.
	local index = stop.plan.index
	for _, s in { run.route.stops[index - 1], stop } do
		local state = s.canal
		if state then
			for _, trigger in state.hoops do
				table.insert(
					connections,
					trigger.Touched:Connect(function(hit)
						local player = Util.playerFromHit(hit)
						if player and run:_free(player) then
							boostUntil[player] = Util.now() + C.HoopBoostSeconds
							SoundPlayer.at("HoopBoost", trigger)
						end
					end)
				)
			end
			for _, zone in state.splashZones do
				table.insert(splashZones, zone)
			end
		end
	end

	local acc = 0
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 0.1 then
				return
			end
			acc = 0
			local t = Util.now()
			for player, st in run.players do
				local humanoid = Util.humanoidOf(player)
				if humanoid and run:_free(player) then
					local base = run:baseWalkSpeed(st)
					local onIce = humanoid.FloorMaterial == Enum.Material.Ice
					local character = humanoid.Parent :: Instance
					Boots.setOnIce(character :: Model, onIce) -- the blades' gold trail
					local speed = CanalRules.walkSpeed(
						base,
						onIce,
						(boostUntil[player] or 0) > t,
						character:GetAttribute("SkateSpeed"),
						character:GetAttribute("HoopSpeed")
					)
					if humanoid.WalkSpeed ~= speed then
						humanoid.WalkSpeed = speed
					end
					-- Clients lean, sway and spray ice for Santas gliding on ice.
					local root_ = humanoid.RootPart
					local v = if root_ then root_.AssemblyLinearVelocity else Vector3.zero
					local skating = onIce and Vector3.new(v.X, 0, v.Z).Magnitude > 4
					if character:GetAttribute(SantaMoves.SKATE_ATTRIBUTE) ~= skating then
						character:SetAttribute(SantaMoves.SKATE_ATTRIBUTE, skating)
					end
					-- Water is polled, not Touched: a Santa who keeps walking on
					-- broken ice never re-touches it, so Touched let them stroll
					-- across the lake and skip the floe hop.
					local root = humanoid.RootPart
					if root and (splashAt[player] or 0) + 1 < t then
						local zone = CanalTown.waterUnder(splashZones, root, Util.standHeight(humanoid, root))
						if zone then
							splashAt[player] = t
							CanalTown.splash(run, player, zone)
						end
					end
				end
			end
		end)
	)

	return function()
		for _, c in connections do
			c:Disconnect()
		end
		for player in run.players do
			run:_applyPerks(player)
			if player.Character then
				player.Character:SetAttribute(SantaMoves.SKATE_ATTRIBUTE, nil)
			end
		end
	end
end

-- The broken zone (from `zones`) whose water `root` is standing in, if any.
function CanalTown.waterUnder(zones: { BasePart }, root: BasePart, standHeight: number): BasePart?
	local at = root.CFrame.Position
	for _, zone in zones do
		-- Swim water (the Lair lake) is real water: you swim, no SPLOOSH.
		if zone:GetAttribute("Broken") and not zone:GetAttribute("SwimWater") then
			local boxes = floeBoxes[zone]
			if not boxes then
				boxes = {} -- floes are anchored: measure them once
				for _, floe in floesFor[zone] or {} do
					table.insert(boxes, CanalTown.floeBox(floe))
				end
				floeBoxes[zone] = boxes
			end
			if CanalRules.inWater({ cframe = zone.CFrame, size = zone.Size }, boxes, at, standHeight) then
				return zone
			end
		end
	end
	return nil
end

-- SPLOOSH: back onto the nearest floe of that zone.
function CanalTown.splash(run, player: Player, zone: BasePart)
	local root = Util.rootOf(player)
	local floes = floesFor[zone]
	if not root or not floes or #floes == 0 then
		return
	end
	local points = {}
	for _, f in floes do
		table.insert(points, f.CFrame.Position)
	end
	local best = CanalRules.nearest(points, root.CFrame.Position)
	if best then
		Util.teleport(player, CFrame.new(points[best] + Vector3.new(0, 4, 0)))
		SoundPlayer.at("Splash", root.CFrame.Position)
		run:_banner(player, "SPLOOSH! Brrr... hop floe to floe!", 2)
	end
end

-- A floe part as a CanalRules.Box: round floes are flat cylinders.
function CanalTown.floeBox(floe: BasePart): CanalRules.Box
	if floe.Shape == Enum.PartType.Cylinder then
		return { cframe = floe.CFrame, size = floe.Size, radius = floe.Size.Z / 2 }
	end
	return { cframe = floe.CFrame, size = floe.Size }
end

-- Turns an IceZone part into water with hoppable floes. Safe to call twice.
-- Returns the floe parts (one per disc: floes are round and lumpy). Used by
-- the Lair's floe hop and the Thin Ice event. A zone marked SwimWater (the
-- Lair lake) has real terrain water under it, so the ice just goes and you
-- swim (server/Swimming); other zones turn into a water-coloured slab.
function CanalTown.breakZone(zone: BasePart, rng: Random?): { BasePart }
	if zone:GetAttribute("Broken") then
		return floesFor[zone] or {}
	end
	zone:SetAttribute("Broken", true)
	if zone:GetAttribute("SwimWater") then
		zone.Transparency = 1
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
	else
		zone.Color = WATER
		zone.Material = Enum.Material.Glass
		zone.Transparency = 0.15
	end
	local r = rng or Random.new()
	local floes = {}
	local folder = Instance.new("Folder")
	folder.Name = "Floes"
	for _, f in CanalRules.floeLayout(zone.Size.X, zone.Size.Z, r, keepoutsFor[zone]) do
		for k, disc in f.discs do
			local floe = Instance.new("Part")
			floe.Name = "Floe"
			floe.Shape = Enum.PartType.Cylinder
			floe.Anchored = true
			-- lobes sit a hair lower so overlapping tops don't flicker
			local height = C.FloeTop - (k - 1) * 0.04
			floe.Size = Vector3.new(height, disc.r * 2, disc.r * 2)
			floe.CFrame = zone.CFrame
				* CFrame.new(disc.x, height / 2 - zone.Size.Y / 2, disc.z)
				* CFrame.Angles(0, 0, math.pi / 2)
			floe.Color = Color3.fromRGB(225, 242, 252)
			floe.Material = Enum.Material.Ice
			floe.TopSurface = Enum.SurfaceType.Smooth
			floe.BottomSurface = Enum.SurfaceType.Smooth
			floe:SetAttribute("IceZone", true)
			floe:SetAttribute("Floe", true)
			floe.Parent = folder
			table.insert(floes, floe)
		end
	end
	folder.Parent = zone
	floesFor[zone] = floes
	return floes
end

----------------------------------------------------------------------------
-- ChristmasMarket: stalls along the pavements, security dogs on patrol
----------------------------------------------------------------------------

local ChristmasMarket = {}

function ChristmasMarket.build(ctx)
	local layout = ctx.map.layout
	local state = canalState(ctx.stop)
	local inner = layout.RoadWidth / 2 + C.Promenade
	local n = 0
	for _, side in { -1, 1 } do
		local z = 60
		while z <= 390 do
			local nearHouse = false
			for _, h in ctx.stop.plan.houses do
				if h.side == side and math.abs(h.distance - z) < h.size.Z / 2 + 10 then
					nearHouse = true
				end
			end
			if not nearHouse then
				n += 1
				local x = side * (inner + 3)
				local counter = ctx.newPart(
					ctx.model,
					"StallCounter",
					Vector3.new(4, 3.4, 9),
					ctx.origin * CFrame.new(x, 1.7, z),
					WOOD,
					Enum.Material.Wood
				)
				for _, dz in { -4.2, 4.2 } do
					ctx.newPart(
						ctx.model,
						"StallPost",
						Vector3.new(0.6, 8, 0.6),
						ctx.origin * CFrame.new(x - side * 1.6, 4, z + dz),
						WOOD,
						Enum.Material.Wood
					)
				end
				for k = 0, 3 do
					ctx.newPart(
						ctx.model,
						"StallRoof",
						Vector3.new(6, 0.6, 2.4),
						ctx.origin * CFrame.new(x, 8.2, z - 3.6 + k * 2.4) * CFrame.Angles(0, 0, side * 0.25),
						if k % 2 == 0 then CANDY else WHITE
					)
				end
				label(counter, STALLS[(n - 1) % #STALLS + 1], GOLD, 7.5, 80)
			end
			z += 30
		end
	end

	-- Dog patrols: up and down each pavement, two dogs a side, mixed designs.
	for d = 1, C.Dogs.Count do
		local side = if d % 2 == 0 then 1 else -1
		local x = side * (layout.RoadWidth / 2 + C.Promenade / 2)
		table.insert(state.dogs, {
			kind = if d <= C.Dogs.Count / 2 then "DogCorgi" else "DogTin",
			points = {
				(ctx.origin * CFrame.new(x, 0, 50)).Position,
				(ctx.origin * CFrame.new(x, 0, 395)).Position,
			},
			offset = (d - 1) * 17,
		})
	end
end

-- An anchored, non-colliding Part for runtime stand-ins (dogs, polisher).
local function block(model: Model, name: string, size: Vector3, offset: Vector3, color: Color3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(offset)
	part.Color = color
	part.Anchored = true
	part.CanCollide = false
	part.Parent = model
	return part
end

function ChristmasMarket.start(ctx)
	local run, stop = ctx.run, ctx.stop
	if not stop.canal then
		return nil
	end
	-- Patrols start spread along their beat, then look, listen and sniff
	-- (GuardDogs / DogBrain): walking past one is no longer safe.
	local specs = {}
	for _, spec in stop.canal.dogs do
		local pos, facing = CanalRules.patrolAt(spec.points, C.Dogs.Speed, spec.offset)
		local towardEnd = facing:Dot(spec.points[#spec.points] - spec.points[1]) >= 0
		local at = pos + Vector3.new(0, 3, 0)
		table.insert(specs, {
			kind = spec.kind,
			at = CFrame.lookAt(at, at + facing),
			patrol = spec.points,
			startIndex = if towardEnd then #spec.points else 1,
			cooldown = C.Dogs.CorgiCooldown,
		})
	end
	local aboard = Config.Map.SleighStopRadius
	return GuardDogs.start(run, specs, run.route.model, function(position)
		-- MapBuilder.isAboard (not required here: MapBuilder loads this module)
		local rel = stop.deckCFrame:PointToObjectSpace(position)
		return Vector3.new(rel.X, 0, rel.Z).Magnitude <= aboard and rel.Y >= -4 and rel.Y <= 12
	end)
end

----------------------------------------------------------------------------
-- IceRink: Ice Rink Square with a giant tree, carollers and the ice polisher
----------------------------------------------------------------------------

local IceRink = {}

function IceRink.build(ctx)
	local f = ctx.feature
	local state = canalState(ctx.stop)
	local c, r = f.centre, f.radius
	local rink = ctx.newPart(
		ctx.model,
		"RinkIce",
		Vector3.new(0.3, r * 2, r * 2),
		ctx.origin * CFrame.new(c + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		ICE,
		Enum.Material.Ice
	)
	rink.Shape = Enum.PartType.Cylinder
	rink:SetAttribute("IceZone", true)
	table.insert(state.iceZones, rink)
	-- Boards around the edge with four openings (the canal runs through two).
	local segments = 28
	for k = 0, segments - 1 do
		local a = (k + 0.5) / segments * math.pi * 2
		local open = false
		for _, gapAngle in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
			local diff = math.abs((a - gapAngle + math.pi) % (2 * math.pi) - math.pi)
			if diff < 0.2 then
				open = true
			end
		end
		if not open then
			local at = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			ctx.newPart(
				ctx.model,
				"RinkBoard",
				Vector3.new(1, 2.6, 2 * math.pi * r / segments + 0.4),
				ctx.origin
					* CFrame.lookAt(at + Vector3.new(0, 1.3, 0), c + Vector3.new(0, 1.3, 0))
					* CFrame.Angles(0, math.pi / 2, 0),
				if k % 2 == 0 then CANDY else WHITE
			)
		end
	end
	-- The giant tree in the middle.
	ctx.newPart(
		ctx.model,
		"TreeTrunk",
		Vector3.new(2.4, 4, 2.4),
		ctx.origin * CFrame.new(c + Vector3.new(0, 2, 0)),
		WOOD,
		Enum.Material.Wood
	)
	for k, w in { 14, 11, 8, 5 } do
		local tier = ctx.newPart(
			ctx.model,
			"TreeTier",
			Vector3.new(6, w, w),
			ctx.origin * CFrame.new(c + Vector3.new(0, 2 + k * 5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			HEDGE,
			Enum.Material.Grass
		)
		tier.Shape = Enum.PartType.Cylinder
	end
	ball(ctx, "TreeStar", c + Vector3.new(0, 26, 0), 2.6, GOLD, Enum.Material.Neon)
	-- Carollers by the boards (stand-ins) and snowbanks the polisher scoops you into.
	for k, a in { 0.6, 0.75, 0.9 } do
		local at = c + Vector3.new(math.cos(a) * (r + 6), 0, math.sin(a) * (r + 6))
		local caroller = ctx.newPart(
			ctx.model,
			"Caroller",
			Vector3.new(2, 5, 1.4),
			ctx.origin * CFrame.new(at + Vector3.new(0, 2.5, 0)),
			FACADES[k],
			Enum.Material.Fabric
		)
		if k == 2 then
			label(caroller, "♪ Deck the halls ♪", WHITE, 4, 80)
		end
	end
	state.rink = { centre = (ctx.origin * CFrame.new(c)).Position, radius = r, snowbanks = {} }
	for _, a in { math.pi / 4, 3 * math.pi / 4, 5 * math.pi / 4, 7 * math.pi / 4 } do
		local at = c + Vector3.new(math.cos(a) * (r + 7), 0, math.sin(a) * (r + 7))
		ball(ctx, "Snowbank", at + Vector3.new(0, 1, 0), 7, SNOW, Enum.Material.Snow).CanCollide = false
		table.insert(state.rink.snowbanks, (ctx.origin * CFrame.new(at)).Position)
	end
end

local function standInPolisher(): Model
	local model = Instance.new("Model")
	model.Name = "IcePolisher"
	local body = block(model, "Body", Vector3.new(4, 4, 6), Vector3.zero, Color3.fromRGB(60, 140, 220))
	block(model, "Brush", Vector3.new(5, 1, 1.4), Vector3.new(0, -1.6, -3.2), GOLD)
	model.PrimaryPart = body
	label(body, "ICE POLISHER", WHITE, 4, 80)
	return model
end

function IceRink.start(ctx)
	local run, stop = ctx.run, ctx.stop
	if not (stop.canal and stop.canal.rink) then
		return nil
	end
	local rink = stop.canal.rink
	local polisher = standInPolisher()
	polisher.Parent = run.route.model
	SoundPlayer.loop("PolisherHum", polisher.PrimaryPart :: BasePart)
	local t0 = Util.now()
	local scoopedAt: { [Player]: number } = {}
	local connection = RunService.Heartbeat:Connect(function()
		local t = Util.now()
		local pos, facing = CanalRules.polisherAt(rink.centre, rink.radius * 0.6, t - t0)
		local at = pos + Vector3.new(0, 2.3, 0)
		polisher:PivotTo(CFrame.lookAt(at, at + facing))
		for player in run.players do
			local root = Util.rootOf(player)
			if root and run:_free(player) and (scoopedAt[player] or 0) + 2 < t then
				if CanalRules.inReach(root.CFrame.Position, pos, C.Polisher.HitRadius) then
					scoopedAt[player] = t
					local bank = rink.snowbanks[CanalRules.nearest(rink.snowbanks, root.CFrame.Position) or 1]
					SoundPlayer.at("PolisherScoop", pos)
					Util.teleport(player, CFrame.new(bank + Vector3.new(0, 4, 0)))
					run:_banner(player, "WHOOSH! The ice polisher scooped you into a snowbank!", 2.5)
				end
			end
		end
	end)
	return function()
		connection:Disconnect()
		polisher:Destroy()
	end
end

----------------------------------------------------------------------------
-- FloeLake: the Lair's lake, island and bell bridge; Krampus stomps it into floes
----------------------------------------------------------------------------

local FloeLake = {}

----------------------------------------------------------------------------
-- Lair grounds: rocky shore, the Keep Out gate, the island's fence, lanterns,
-- dead trees, coal heaps, ice spires and purple mist (Josh, 2 Nov: "make the
-- area around the Lair more interesting"). Spooky-fun, never scary.
----------------------------------------------------------------------------

local ROCK = Color3.fromRGB(85, 80, 100)
local IRON = Color3.fromRGB(35, 30, 45)
local DEADWOOD = Color3.fromRGB(70, 50, 45)
local SPOOKY = { Color3.fromRGB(170, 90, 255), Color3.fromRGB(110, 255, 160) } -- purple, green
local HORN = Color3.fromRGB(235, 220, 190)

local function rock(ctx, at: Vector3, size: number)
	local part = ctx.newPart(
		ctx.model,
		"LairRock",
		Vector3.new(size * ctx.rng:NextNumber(1, 1.6), size, size * ctx.rng:NextNumber(1, 1.4)),
		ctx.origin
			* CFrame.new(at + Vector3.new(0, size * 0.3, 0))
			* CFrame.Angles(
				ctx.rng:NextNumber(-0.3, 0.3),
				ctx.rng:NextNumber(0, math.pi),
				ctx.rng:NextNumber(-0.3, 0.3)
			),
		ROCK,
		Enum.Material.Slate
	)
	return part
end

-- A bare, crooked tree: a leaning trunk and three forked branches.
local function deadTree(ctx, base: Vector3, h: number)
	local lean = CFrame.Angles(
		ctx.rng:NextNumber(-0.15, 0.15),
		ctx.rng:NextNumber(0, math.pi * 2),
		ctx.rng:NextNumber(-0.15, 0.15)
	)
	local root = ctx.origin * CFrame.new(base) * lean
	ctx.newPart(
		ctx.model,
		"DeadTree",
		Vector3.new(1.4, h, 1.4),
		root * CFrame.new(0, h / 2, 0),
		DEADWOOD,
		Enum.Material.Wood
	)
	for k = 1, 3 do
		local y = h * (0.5 + k * 0.14)
		local len = h * (0.45 - k * 0.08)
		local cf = root
			* CFrame.new(0, y, 0)
			* CFrame.Angles(0, k * 2.1, 0)
			* CFrame.Angles(0, 0, -0.9)
			* CFrame.new(0, len / 2, 0)
		ctx.newPart(ctx.model, "DeadBranch", Vector3.new(0.6, len, 0.6), cf, DEADWOOD, Enum.Material.Wood).CanCollide =
			false
	end
end

local function lantern(ctx, at: Vector3, color: Color3)
	ctx.newPart(
		ctx.model,
		"LanternPost",
		Vector3.new(0.7, 8, 0.7),
		ctx.origin * CFrame.new(at + Vector3.new(0, 4, 0)),
		IRON,
		Enum.Material.Metal
	)
	ctx.newPart(
		ctx.model,
		"LanternArm",
		Vector3.new(2.4, 0.4, 0.4),
		ctx.origin * CFrame.new(at + Vector3.new(1, 8, 0)),
		IRON,
		Enum.Material.Metal
	)
	local flame = ball(ctx, "LanternFlame", at + Vector3.new(2, 7, 0), 1.4, color, Enum.Material.Neon)
	flame.CanCollide = false
	glow(flame, color, 26)
end

-- Witch fire (Josh, 2 Nov: "evil fire, scary castle lantern vibes"): a
-- glowing core with a real Roblox Fire in Krampus's green and purple. It's
-- decoration only and never hurts anyone.
local EVIL = { Color3.fromRGB(90, 255, 120), Color3.fromRGB(185, 80, 255) }

local function evilFire(ctx, at: Vector3, size: number, color: Color3)
	local core = ball(ctx, "EvilFlame", at, size * 0.35, color, Enum.Material.Neon)
	core.CanCollide = false
	core.CanQuery = false
	local fire = Instance.new("Fire")
	fire.Color = color
	fire.SecondaryColor = Color3.new(color.R * 0.3, color.G * 0.3, color.B * 0.3)
	fire.Size = size
	fire.Heat = size * 1.5
	fire.Parent = core
	glow(core, color, size * 4 + 10)
	return core
end

local function torch(ctx, at: Vector3, color: Color3)
	ctx.newPart(
		ctx.model,
		"Torch",
		Vector3.new(0.8, 5, 0.8),
		ctx.origin * CFrame.new(at + Vector3.new(0, 2.5, 0)),
		IRON,
		Enum.Material.Metal
	)
	evilFire(ctx, at + Vector3.new(0, 5.6, 0), 4, color)
end

-- A stone pillar topped with an iron bowl of witch fire.
local function brazier(ctx, at: Vector3, color: Color3)
	ctx.newPart(
		ctx.model,
		"BrazierPillar",
		Vector3.new(2.8, 6, 2.8),
		ctx.origin * CFrame.new(at + Vector3.new(0, 3, 0)),
		ROCK,
		Enum.Material.Slate
	)
	local bowl = ctx.newPart(
		ctx.model,
		"BrazierBowl",
		Vector3.new(1.2, 4.2, 4.2),
		ctx.origin * CFrame.new(at + Vector3.new(0, 6.6, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		IRON,
		Enum.Material.Metal
	)
	bowl.Shape = Enum.PartType.Cylinder
	evilFire(ctx, at + Vector3.new(0, 7.6, 0), 7, color)
end

-- A castle lantern: an iron post and arm with a caged flame hanging from it.
local function castleLantern(ctx, at: Vector3, out: number, color: Color3)
	ctx.newPart(
		ctx.model,
		"CastleLanternPost",
		Vector3.new(0.6, 9, 0.6),
		ctx.origin * CFrame.new(at + Vector3.new(0, 4.5, 0)),
		IRON,
		Enum.Material.Metal
	)
	ctx.newPart(
		ctx.model,
		"CastleLanternArm",
		Vector3.new(2.6, 0.4, 0.4),
		ctx.origin * CFrame.new(at + Vector3.new(out * 1.1, 8.8, 0)),
		IRON,
		Enum.Material.Metal
	)
	local c = at + Vector3.new(out * 2.2, 6.6, 0)
	for _, dy in { -1.3, 1.3 } do
		ctx.newPart(
			ctx.model,
			"CageCap",
			Vector3.new(1.8, 0.3, 1.8),
			ctx.origin * CFrame.new(c + Vector3.new(0, dy, 0)),
			IRON,
			Enum.Material.Metal
		).CanCollide =
			false
	end
	for _, d in
		{
			Vector3.new(0.8, 0, 0.8),
			Vector3.new(-0.8, 0, 0.8),
			Vector3.new(0.8, 0, -0.8),
			Vector3.new(-0.8, 0, -0.8),
		}
	do
		ctx.newPart(
			ctx.model,
			"CageBar",
			Vector3.new(0.18, 2.6, 0.18),
			ctx.origin * CFrame.new(c + d),
			IRON,
			Enum.Material.Metal
		).CanCollide =
			false
	end
	evilFire(ctx, c, 2, color)
end

-- Goat horns on top of the gate: three tilted segments curling outwards.
local function horn(ctx, base: Vector3, side: number)
	local cf = ctx.origin * CFrame.new(base)
	for k = 1, 3 do
		local len = 3.4 - k * 0.6
		cf = cf * CFrame.Angles(0, 0, -side * 0.55) * CFrame.new(0, len / 2, 0)
		ctx.newPart(ctx.model, "GateHorn", Vector3.new(1.6 - k * 0.35, len, 1.6 - k * 0.35), cf, HORN)
		cf = cf * CFrame.new(0, len / 2, 0)
	end
end

-- A crooked, whimsical castle wall round the Lair (Josh, 2 Nov): leaning
-- stone towers with curly candy-striped spires, candy-striped battlements
-- strung with Christmas lights, and two wide gates (front to the bridge,
-- back to the lake) so a chased Santa is never trapped inside.
local CASTLE = Color3.fromRGB(95, 85, 115)
local CASTLE_DARK = Color3.fromRGB(70, 62, 88)

local function curlySpire(ctx, top: Vector3, radius: number)
	local cf = ctx.origin * CFrame.new(top)
	local lean = ctx.rng:NextNumber(0.18, 0.32) * (if ctx.rng:NextNumber() < 0.5 then -1 else 1)
	local w = radius * 2.2
	for k = 1, 6 do
		local h = 2.2
		cf = cf * CFrame.Angles(0, 0.5, lean * 0.6) * CFrame.new(0, h / 2, 0)
		local tier = ctx.newPart(
			ctx.model,
			"SpireTier",
			Vector3.new(h, w, w),
			cf * CFrame.Angles(0, 0, math.pi / 2),
			if k % 2 == 0 then WHITE else CANDY
		)
		tier.Shape = Enum.PartType.Cylinder
		cf = cf * CFrame.new(0, h / 2, 0)
		w *= 0.72
	end
	local tip = ball(ctx, "SpireBauble", Vector3.zero, 2, GOLD, Enum.Material.Neon)
	tip.CFrame = cf * CFrame.new(0, 1, 0)
	tip.CanCollide = false
end

local function castleWall(ctx, centre: Vector3, radius: number, front: number, gapAt)
	local rng = ctx.rng
	local towers = 12
	local spots = {}
	for k = 0, towers - 1 do
		local a = front + (k + 0.5) / towers * math.pi * 2
		table.insert(spots, a)
	end
	local function at(a: number, rad: number): Vector3
		return centre + Vector3.new(math.sin(a) * rad, 0, math.cos(a) * rad)
	end
	-- Wall runs between neighbouring towers, unless the run crosses a gate.
	for k, a in spots do
		local b = spots[k % #spots + 1]
		if b < a then
			b += math.pi * 2
		end
		local mid = (a + b) / 2
		if not gapAt(mid, 0.3) then
			local p, q = at(a, radius), at(b, radius)
			local height = rng:NextNumber(9, 11)
			wall(
				ctx,
				"CastleWall",
				p,
				q,
				3,
				height,
				if k % 2 == 0 then CASTLE else CASTLE_DARK,
				Enum.Material.Slate
			)
			-- Candy-striped battlements and a string of lights along the top.
			local n = math.floor((q - p).Magnitude / 3)
			for m = 0, n - 1 do
				if m % 2 == 0 then
					local mp = p:Lerp(q, (m + 0.5) / n)
					ctx.newPart(
						ctx.model,
						"Battlement",
						Vector3.new(2.2, 1.8, 2.2),
						ctx.origin * CFrame.lookAt(mp, mp + (q - p)) * CFrame.new(0, height + 0.9, 0),
						if m % 4 == 0 then CANDY else WHITE
					)
				end
			end
			local inward = (centre - (p + q) / 2).Unit
			strand(
				ctx,
				p + inward * 1.8 + Vector3.new(0, height - 1, 0),
				q + inward * 1.8 + Vector3.new(0, height - 1, 0),
				1.4,
				2.6
			)
		end
	end
	-- Leaning towers (taller either side of each gate), every other one with witch fire.
	for k, a in spots do
		local p = at(a, radius)
		local byGate = gapAt(a, 0.55)
		local h = if byGate then rng:NextNumber(22, 26) else rng:NextNumber(15, 20)
		local rad = if byGate then 5 else 4
		local lean = CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06))
		local base = ctx.origin * CFrame.new(p) * lean
		local tower = ctx.newPart(
			ctx.model,
			"CastleTower",
			Vector3.new(h, rad * 2, rad * 2),
			base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			CASTLE,
			Enum.Material.Slate
		)
		tower.Shape = Enum.PartType.Cylinder
		for _, y in { h * 0.45, h * 0.7 } do
			ctx.newPart(
				ctx.model,
				"TowerWindow",
				Vector3.new(1.4, 2.4, 0.4),
				base * CFrame.new(0, y, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -rad),
				EVIL[k % 2 + 1],
				Enum.Material.Neon
			).CanCollide =
				false
		end
		local topAt = ctx.origin:PointToObjectSpace((base * CFrame.new(0, h, 0)).Position)
		if k % 2 == 0 then
			local bowl = ctx.newPart(
				ctx.model,
				"TowerBrazier",
				Vector3.new(1, rad * 1.6, rad * 1.6),
				ctx.origin * CFrame.new(topAt + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				IRON,
				Enum.Material.Metal
			)
			bowl.Shape = Enum.PartType.Cylinder
			evilFire(ctx, topAt + Vector3.new(0, 1.8, 0), 6, EVIL[(k // 2) % 2 + 1])
		else
			curlySpire(ctx, topAt, rad)
		end
		-- A giant bauble hanging off the tower's outer face.
		local out = (p - centre).Unit
		ball(
			ctx,
			"TowerBauble",
			p + out * (rad + 1.2) + Vector3.new(0, h * 0.55, 0),
			2.6,
			C.LightColours[k % #C.LightColours + 1],
			Enum.Material.Glass
		).CanCollide =
			false
	end
	-- A big wreath with a bow over the front gate.
	local gate = at(front, radius) + Vector3.new(0, 16, 0)
	local wreath = ctx.newPart(
		ctx.model,
		"GateWreath",
		Vector3.new(1, 9, 9),
		ctx.origin * CFrame.new(gate) * CFrame.Angles(0, front + math.pi / 2, 0),
		HEDGE,
		Enum.Material.Grass
	)
	wreath.Shape = Enum.PartType.Cylinder
	wreath.CanCollide = false
	ball(ctx, "GateBow", gate - Vector3.new(0, 3.6, 0), 2.2, CANDY, Enum.Material.Neon).CanCollide = false
	strand(
		ctx,
		at(front - 0.33, radius) + Vector3.new(0, 14, 0),
		at(front + 0.33, radius) + Vector3.new(0, 14, 0),
		3,
		2.4
	)
end

-- Wonky stacks of giant presents inside the walls.
local function presentStack(ctx, base: Vector3)
	local rng = ctx.rng
	local y = 0
	for k = 1, rng:NextInteger(2, 4) do
		local size = 5 - k + rng:NextNumber(0, 1)
		local cf = ctx.origin
			* CFrame.new(
				base + Vector3.new(rng:NextNumber(-0.6, 0.6), y + size / 2, rng:NextNumber(-0.6, 0.6))
			)
			* CFrame.Angles(
				rng:NextNumber(-0.12, 0.12),
				rng:NextNumber(0, math.pi),
				rng:NextNumber(-0.12, 0.12)
			)
		ctx.newPart(
			ctx.model,
			"GiantPresent",
			Vector3.one * size,
			cf,
			C.LightColours[rng:NextInteger(1, #C.LightColours)]
		)
		for _, sz in { Vector3.new(1.03, 1.03, 0.15), Vector3.new(0.15, 1.03, 1.03) } do
			ctx.newPart(ctx.model, "GiantRibbon", sz * size, cf, GOLD).CanCollide = false
		end
		y += size * 0.95
	end
end

local function lairGrounds(ctx, f, bridgeFrom: number)
	local rng = ctx.rng
	local w, z0, z1 = f.halfWidth, f.from, f.to
	local isl, r = f.island, f.islandRadius

	-- A rocky, snowy shore so the lake isn't a rectangle: mounds and boulders
	-- all round the edge, leaving the street canal and the bridge open.
	local perimeter = {}
	local step = 20
	for x = -w, w, step do
		table.insert(perimeter, Vector3.new(x, 0, z0))
		table.insert(perimeter, Vector3.new(x, 0, z1))
	end
	for z = z0 + step, z1 - step, step do
		table.insert(perimeter, Vector3.new(-w, 0, z))
		table.insert(perimeter, Vector3.new(w, 0, z))
	end
	for _, p in perimeter do
		if not (p.Z == z0 and math.abs(p.X) < 30) then
			local inward = Vector3.new(-math.sign(p.X) * rng:NextNumber(0, 10), 0, 0)
			if p.Z == z0 or p.Z == z1 then
				inward = Vector3.new(0, 0, (if p.Z == z0 then 1 else -1) * rng:NextNumber(0, 10))
			end
			local size = rng:NextNumber(14, 30)
			local mound = ball(
				ctx,
				"ShoreMound",
				p + inward - Vector3.new(0, size * 0.32, 0),
				size,
				SNOW,
				Enum.Material.Snow
			)
			mound.CanCollide = true
			if rng:NextNumber() < 0.45 then
				rock(ctx, p + inward * 1.4, rng:NextNumber(4, 9))
			end
		end
	end

	-- The Keep Out gate where the bridge starts: rock pillars, horns, bells, torches.
	local gz = bridgeFrom - 3
	for _, sx in { -1, 1 } do
		ctx.newPart(
			ctx.model,
			"GatePillar",
			Vector3.new(3, 16, 3),
			ctx.origin * CFrame.new(sx * 7, 8, gz),
			ROCK,
			Enum.Material.Slate
		)
		horn(ctx, Vector3.new(sx * 7, 16, gz), sx)
		torch(ctx, Vector3.new(sx * 10.5, 0, gz - 3), EVIL[1])
	end
	local beam = ctx.newPart(
		ctx.model,
		"GateBeam",
		Vector3.new(17, 2.4, 2.4),
		ctx.origin * CFrame.new(0, 14.5, gz),
		IRON,
		Enum.Material.Metal
	)
	label(beam, "KEEP OUT!", Color3.fromRGB(255, 120, 120), 3, 160)
	for _, bx in { -3.5, 0, 3.5 } do
		ctx.newPart(
			ctx.model,
			"GateChain",
			Vector3.new(0.3, 2.4, 0.3),
			ctx.origin * CFrame.new(bx, 12.1, gz),
			IRON,
			Enum.Material.Metal
		).CanCollide =
			false
		ball(ctx, "GateBell", Vector3.new(bx, 10.4, gz), 1.6, GOLD, Enum.Material.Neon).CanCollide = false
	end

	-- The island: a ring of boulders, a spiked iron fence with a gate facing
	-- the bridge, spooky lanterns, dead trees and heaps of coal.
	local towardBridge = math.atan2(0, bridgeFrom - isl.Z) -- angle a of (sin a, cos a) pointing up the bridge
	local function gapAt(a: number, width: number): boolean
		local diff = math.abs((a - towardBridge + math.pi) % (2 * math.pi) - math.pi)
		return diff < width
	end
	-- Castle gates: the front faces the bridge, the back opens onto the lake.
	local function gateAt(a: number, width: number): boolean
		return gapAt(a, width) or gapAt(a + math.pi, width)
	end
	for k = 0, 17 do
		local a = k / 18 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		if not gateAt(a, 0.35) then
			rock(
				ctx,
				isl + Vector3.new(math.sin(a) * (r - 2), 0, math.cos(a) * (r - 2)),
				rng:NextNumber(4, 8)
			)
		end
	end
	castleWall(ctx, isl, r - 11, towardBridge, gateAt)
	for k = 1, 3 do
		local a = towardBridge + math.pi * (0.4 + k * 0.4)
		presentStack(ctx, isl + Vector3.new(math.sin(a) * (r - 18), 0.3, math.cos(a) * (r - 18)))
	end
	for k = 0, 5 do
		local a = towardBridge + (k + 0.5) / 6 * math.pi * 2
		lantern(ctx, isl + Vector3.new(math.sin(a) * (r - 15), 0, math.cos(a) * (r - 15)), SPOOKY[k % 2 + 1])
	end
	-- Braziers of witch fire round the island's rim, and a ring of fire pots
	-- burning on the ice all round it (open where the bridge lands).
	for k = 0, 7 do
		local a = towardBridge + (k + 0.5) / 8 * math.pi * 2
		brazier(ctx, isl + Vector3.new(math.sin(a) * (r - 4), 0.3, math.cos(a) * (r - 4)), EVIL[k % 2 + 1])
	end
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		if not gateAt(a, 0.2) then -- open at the bridge and at the Lair Lane (back gate)
			local at = isl + Vector3.new(math.sin(a) * (r + 5), 0, math.cos(a) * (r + 5))
			local pot = ctx.newPart(
				ctx.model,
				"FirePot",
				Vector3.new(1.4, 2.4, 2.4),
				ctx.origin * CFrame.new(at + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				IRON,
				Enum.Material.Metal
			)
			pot.Shape = Enum.PartType.Cylinder
			evilFire(ctx, at + Vector3.new(0, 1.8, 0), 3, EVIL[k % 2 + 1])
		end
	end
	for k = 1, 4 do
		local a = towardBridge + math.pi * (0.35 + k * 0.32)
		deadTree(
			ctx,
			isl + Vector3.new(math.sin(a) * (r - 4), 0.3, math.cos(a) * (r - 4)),
			rng:NextNumber(12, 18)
		)
	end
	for k = 1, 3 do
		local a = towardBridge + k * 1.9 + 0.6
		local c = isl + Vector3.new(math.sin(a) * (r - 17), 0, math.cos(a) * (r - 17))
		for _ = 1, 5 do
			ball(
				ctx,
				"Coal",
				c
					+ Vector3.new(
						rng:NextNumber(-1.6, 1.6),
						rng:NextNumber(0.3, 1.4),
						rng:NextNumber(-1.6, 1.6)
					),
				rng:NextNumber(1.2, 2.2),
				Color3.fromRGB(28, 28, 32),
				Enum.Material.Slate
			).CanCollide =
				false
		end
	end
	local sign = ctx.newPart(
		ctx.model,
		"NaughtySign",
		Vector3.new(5, 2.4, 0.4),
		ctx.origin * CFrame.new(isl + Vector3.new(9, 4.4, -(r - 16))) * CFrame.Angles(0, 0, 0.12),
		WOOD,
		Enum.Material.WoodPlanks
	)
	ctx.newPart(
		ctx.model,
		"NaughtySignPost",
		Vector3.new(0.5, 4, 0.5),
		ctx.origin * CFrame.new(isl + Vector3.new(9, 2, -(r - 16))),
		WOOD,
		Enum.Material.Wood
	)
	label(sign, "NAUGHTY ONLY", Color3.fromRGB(255, 220, 120), 2.5, 90)

	-- Ice spires and dead trees on the shore; glowing purple mist over the lake.
	for _ = 1, 9 do
		local x = rng:NextNumber(-w + 25, w - 25)
		local z = rng:NextNumber(z0 + 25, z1 - 25)
		local p = Vector3.new(x, 0, z)
		local flat = (p - isl) * Vector3.new(1, 0, 1)
		if flat.Magnitude > r + 14 and math.abs(x) > 14 then
			for k = 1, 3 do
				local h = rng:NextNumber(5, 14)
				local spire = ctx.newPart(
					ctx.model,
					"IceSpire",
					Vector3.new(1.6, h, 1.6),
					ctx.origin
						* CFrame.new(
							p + Vector3.new(rng:NextNumber(-2, 2), h / 2 - 0.5, rng:NextNumber(-2, 2))
						)
						* CFrame.Angles(
							rng:NextNumber(-0.3, 0.3),
							rng:NextNumber(0, 1.5),
							rng:NextNumber(-0.3, 0.3)
						),
					Color3.fromRGB(170, 230, 255),
					Enum.Material.Glass
				)
				spire.Transparency = 0.25
				spire.CanCollide = k == 1
			end
		end
	end
	for k = 0, 9 do
		local side = if k % 2 == 0 then -1 else 1
		local z = z0 + 20 + (z1 - z0 - 40) * (k / 9)
		deadTree(ctx, Vector3.new(side * (w + rng:NextNumber(4, 14)), 0, z), rng:NextNumber(12, 20))
	end
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2 + 0.4
		local p = isl + Vector3.new(math.sin(a) * (r + 22), 0.6, math.cos(a) * (r + 22))
		local mist = ctx.newPart(
			ctx.model,
			"LairMist",
			Vector3.new(0.4, 34, 34),
			ctx.origin * CFrame.new(p) * CFrame.Angles(0, 0, math.pi / 2),
			SPOOKY[1],
			Enum.Material.Neon
		)
		mist.Shape = Enum.PartType.Cylinder
		mist.Transparency = 0.88
		mist.CanCollide = false
		mist.CanQuery = false
	end
end

function FloeLake.build(ctx)
	local f = ctx.feature
	local state = canalState(ctx.stop)
	local length = f.to - f.from
	local midZ = (f.from + f.to) / 2
	local lake = ctx.newPart(
		ctx.model,
		"LakeIce",
		Vector3.new(f.halfWidth * 2, C.IceTop, length),
		ctx.origin * CFrame.new(0, C.IceTop / 2, midZ),
		ICE,
		Enum.Material.Ice
	)
	lake:SetAttribute("IceZone", true)
	lake:SetAttribute("CrackZone", false) -- only Krampus's stomp breaks the lake
	lake:SetAttribute("SwimWater", true) -- real water under it: Santas swim (server/Swimming)
	table.insert(state.iceZones, lake)
	table.insert(state.splashZones, lake)
	state.lake = lake

	local island = ctx.newPart(
		ctx.model,
		"Island",
		Vector3.new(0.4, f.islandRadius * 2, f.islandRadius * 2),
		ctx.origin * CFrame.new(f.island + Vector3.new(0, 0.35, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		SNOW,
		Enum.Material.Snow
	)
	island.Shape = Enum.PartType.Cylinder
	-- A collar of thick shore ice round the island that never breaks: the fire
	-- pots stand on it and swimmers climb out onto it to warm up.
	local collar = ctx.newPart(
		ctx.model,
		"IslandIce",
		Vector3.new(0.4, (f.islandRadius + 9) * 2, (f.islandRadius + 9) * 2),
		ctx.origin * CFrame.new(f.island + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		ICE,
		Enum.Material.Ice
	)
	collar.Shape = Enum.PartType.Cylinder
	state.swim = {
		island = (ctx.origin * CFrame.new(f.island)).Position,
		warmRadius = f.islandRadius + Config.BodyHeat.FireRadius,
		bridgeFrom = (ctx.origin * CFrame.new(0, 0, f.from - 6)).Position,
		bridgeTo = (ctx.origin * CFrame.new(0, 0, f.island.Z - f.islandRadius + 4)).Position,
		islandRadius = f.islandRadius,
	}

	-- The bell bridge: never breaks; ring-able bells hang along it.
	local bridgeFrom, bridgeTo = f.from - 6, f.island.Z - f.islandRadius + 4
	wall(
		ctx,
		"BellBridge",
		Vector3.new(0, 0, bridgeFrom),
		Vector3.new(0, 0, bridgeTo),
		10,
		1,
		WOOD,
		Enum.Material.WoodPlanks
	)
	for _, s in { -1, 1 } do
		wall(
			ctx,
			"BridgeRail",
			Vector3.new(s * 4.8, 3, bridgeFrom),
			Vector3.new(s * 4.8, 3, bridgeTo),
			0.5,
			0.5,
			CANDY
		)
		local z = bridgeFrom + 12
		while z < bridgeTo - 4 do
			ctx.newPart(
				ctx.model,
				"BellPost",
				Vector3.new(0.6, 6, 0.6),
				ctx.origin * CFrame.new(s * 4.8, 3, z),
				WOOD,
				Enum.Material.Wood
			)
			ball(ctx, "BridgeBell", Vector3.new(s * 4.8, 5.4, z), 1.4, GOLD, Enum.Material.Neon)
			if z + 12 < bridgeTo - 4 then
				castleLantern(ctx, Vector3.new(s * 5.4, 0.5, z + 12), s, EVIL[if s < 0 then 1 else 2])
			end
			z += 24
		end
	end
	-- Floes keep clear of the island and the bridge (zone space).
	keepoutsFor[lake] = {
		{ x = f.island.X, z = f.island.Z - midZ, radius = f.islandRadius + 8 }, -- + the fire pots
		{ x = 0, z = (bridgeFrom + bridgeTo) / 2 - midZ, halfX = 5, halfZ = (bridgeTo - bridgeFrom) / 2 },
	}
	-- The Lair Lane: the back lane from the stop before arrives at the lake's
	-- side; a solid lane (as high as the bridge, so never water) carries on to
	-- the castle's back gate.
	if ctx.stop.plan.index > 1 then
		local B = C.BackLane
		local w, top = B.LairLaneWidth, B.LairLaneTop
		local gateZ = f.island.Z + f.islandRadius - 6
		local laneZ = math.min(B.Z, f.to - w)
		local pieces = {
			{ a = Vector3.new(-f.halfWidth - 2, 0, laneZ), b = Vector3.new(w / 2, 0, laneZ) },
			{ a = Vector3.new(0, 0, laneZ + w / 2), b = Vector3.new(0, 0, gateZ) },
		}
		for _, piece in pieces do
			local lane = wall(ctx, "LairLane", piece.a, piece.b, w, top, LANE_ICE, Enum.Material.Ice)
			lane:SetAttribute("IceZone", true)
			lane:SetAttribute("CrackZone", false)
			table.insert(state.iceZones, lane)
			local mid = (piece.a + piece.b) / 2
			local size = (piece.b - piece.a)
			table.insert(keepoutsFor[lake], {
				x = mid.X,
				z = mid.Z - midZ,
				halfX = math.abs(size.X) / 2 + w / 2 + 2,
				halfZ = math.abs(size.Z) / 2 + w / 2 + 2,
			})
		end
		for k = 1, 5 do
			local x = -f.halfWidth + k * f.halfWidth / 6
			chevron(ctx, CFrame.new(x, top - 0.2, laneZ) * CFrame.Angles(0, -math.pi / 2, 0), GOLD)
		end
		for k = 1, 2 do
			local z = laneZ - k * (laneZ - gateZ) / 3
			chevron(ctx, CFrame.new(0, top - 0.2, z), GOLD)
		end
		local lanterns = {
			Vector3.new(-f.halfWidth + 30, 0, laneZ + w / 2 + 0.5),
			Vector3.new(-f.halfWidth / 2, 0, laneZ + w / 2 + 0.5),
			Vector3.new(w / 2 + 0.5, 0, (laneZ + gateZ) / 2),
		}
		for k, at in lanterns do
			castleLantern(ctx, at, 1, EVIL[k % 2 + 1])
		end
		signpost(ctx, Vector3.new(-f.halfWidth + 6, top, laneZ - w / 2 - 1), "KRAMPUS'S LAIR  >>")
	end
	lairGrounds(ctx, f, bridgeFrom)
	-- Red beacon over the Lair island.
	local beacon = ctx.newPart(
		ctx.model,
		"LairBeacon",
		Vector3.new(3, 160, 3),
		ctx.origin * CFrame.new(f.island + Vector3.new(0, 80, 0)),
		CANDY,
		Enum.Material.Neon
	)
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.Transparency = 0.5
end

function FloeLake.start(ctx)
	local run, stop = ctx.run, ctx.stop
	if not (stop.canal and stop.canal.lake) then
		return nil
	end
	local lake = stop.canal.lake
	local unfill = Swimming.fillWater(lake)
	local stopSwimming = Swimming.start(run, stop.canal.swim)
	local thread = task.delay(C.StompDelay, function()
		run:_banner(
			nil,
			"KRAMPUS STOMPS! The ice breaks up. Hop the floes, swim, or take the bell bridge!",
			4
		)
		SoundPlayer.at("KrampusStomp", lake)
		SoundPlayer.at("IceCrack", lake)
		CanalTown.breakZone(lake)
	end)
	return function()
		pcall(task.cancel, thread)
		stopSwimming()
		unfill()
	end
end

----------------------------------------------------------------------------
-- Woodland: pine forest and snowy hills around each stop
----------------------------------------------------------------------------

local PINE = Color3.fromRGB(30, 95, 60)
local Woodland = {}

-- Forest bands either side of the street (stop space), clear of the main
-- canal and the Lair lake. Neighbouring stops each fill half the gap.
local function woodlandAreas(ctx): ({ CanalRules.Rect }, { CanalRules.Rect })
	local W = C.Woodland
	local i, last = ctx.stop.plan.index, #Config.Run.StopKinds
	local z0, z1 = -W.Edge, Config.Rings.Far.Distance + W.Edge
	local outer = W.Inner + W.Band
	-- The first and last stops get a deep forest on their outside edge, on
	-- the snowfield that Woodland.build lays past the route's ground.
	local left = if i == 1 then -W.Inner - W.Edge else -outer
	local right = if i == last then W.Inner + W.Edge else outer
	local regions = {
		{ x0 = left, x1 = -W.Inner, z0 = z0, z1 = z1 },
		{ x0 = W.Inner, x1 = right, z0 = z0, z1 = z1 },
		{ x0 = -W.Inner, x1 = W.Inner, z0 = streetEnd(ctx) + 20, z1 = z1 }, -- past the street's end
	}
	local z = ctx.map.layout.FootPathZ
	local B = C.BackLane
	local keepouts = {
		{ x0 = -1e4, x1 = 1e4, z0 = z - C.Width / 2 - 8, z1 = z + C.Width / 2 + 8 },
		{ x0 = -1e4, x1 = 1e4, z0 = B.Z - B.Width / 2 - 10, z1 = B.Z + B.Width / 2 + 10 }, -- the back lane
		{ x0 = -20, x1 = 20, z0 = streetEnd(ctx) - 10, z1 = B.Z }, -- its link down the street
	}
	local lake = sibling(ctx, "FloeLake")
	if lake then
		table.insert(
			keepouts,
			{ x0 = -lake.halfWidth - 4, x1 = lake.halfWidth + 4, z0 = lake.from - 4, z1 = lake.to + 4 }
		)
	end
	return regions, keepouts
end

function Woodland.build(ctx)
	local regions, keepouts = woodlandAreas(ctx)
	-- A snowfield under the whole forest (a hair below the route's ground) so
	-- the outer forest and the hills' edges never hang over the void.
	local lo, hi = Vector3.new(math.huge, 0, math.huge), Vector3.new(-math.huge, 0, -math.huge)
	for _, r in regions do
		lo = Vector3.new(math.min(lo.X, r.x0), 0, math.min(lo.Z, r.z0))
		hi = Vector3.new(math.max(hi.X, r.x1), 0, math.max(hi.Z, r.z1))
	end
	local pad = C.Woodland.HillRadius[2] * 2
	lo -= Vector3.new(pad, 0, pad)
	hi += Vector3.new(pad, 0, pad)
	ctx.newPart(
		ctx.model,
		"Snowfield",
		Vector3.new(hi.X - lo.X, 2, hi.Z - lo.Z),
		ctx.origin * CFrame.new((lo.X + hi.X) / 2, -1.05, (lo.Z + hi.Z) / 2),
		SNOW,
		Enum.Material.Snow
	)
	local trees, hills = CanalRules.woodland(ctx.rng, regions, keepouts)
	for _, h in hills do
		-- A big sunk ball: only a gentle cap of `height` shows above the snow.
		local sphere = (h.radius * h.radius + h.height * h.height) / (2 * h.height)
		ball(ctx, "SnowHill", Vector3.new(h.x, h.height - sphere, h.z), sphere * 2, SNOW, Enum.Material.Snow)
	end
	for _, t in trees do
		local base = Vector3.new(t.x, t.y, t.z)
		local h = t.height
		ctx.newPart(
			ctx.model,
			"PineTrunk",
			Vector3.new(1.6, h * 0.25, 1.6),
			ctx.origin * CFrame.new(base + Vector3.new(0, h * 0.125, 0)),
			WOOD,
			Enum.Material.Wood
		)
		for k, frac in { 0.55, 0.32 } do
			local width = h * frac
			local tier = ctx.newPart(
				ctx.model,
				"PineTier",
				Vector3.new(h * 0.4, width, width),
				ctx.origin
					* CFrame.new(base + Vector3.new(0, h * (0.2 + k * 0.3), 0))
					* CFrame.Angles(0, 0, math.pi / 2),
				PINE,
				Enum.Material.Grass
			)
			tier.Shape = Enum.PartType.Cylinder
		end
		ball(ctx, "PineSnow", base + Vector3.new(0, h * 0.98, 0), h * 0.14, SNOW, Enum.Material.Snow)
		if t.lit then
			for k = 0, 5 do
				local a = k * 1.9
				local r = h * (0.27 - k * 0.025)
				local p = base + Vector3.new(math.cos(a) * r, h * (0.25 + k * 0.11), math.sin(a) * r)
				ball(ctx, "Bulb", p, 0.9, C.LightColours[k % #C.LightColours + 1], Enum.Material.Neon).CanCollide =
					false
			end
		end
	end
end

-- Filler townhouses open up as Santas walk to their doors (PopInHouses).
function CanalStreet.start(ctx)
	return PopInHouses.start(ctx.run, ctx.stop)
end

CanalTown.features = {
	Woodland = Woodland,
	CanalStreet = CanalStreet,
	SkateCanal = SkateCanal,
	ChristmasMarket = ChristmasMarket,
	IceRink = IceRink,
	FloeLake = FloeLake,
}

return CanalTown
