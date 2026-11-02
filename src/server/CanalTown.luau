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
local Util = require(ReplicatedStorage.Shared.Util)
local Assets = require(script.Parent.Assets)
local CanalRules = require(script.Parent.CanalRules)
local Loot = require(script.Parent.Loot)

local C = Config.Canal
local CanalTown = {}

local ICE = Color3.fromRGB(175, 220, 245)
local WATER = Color3.fromRGB(40, 95, 150)
local SNOW = Color3.fromRGB(240, 245, 252)
local HEDGE = Color3.fromRGB(40, 120, 70)
local PAVEMENT = Color3.fromRGB(205, 200, 215)
local KERB = Color3.fromRGB(160, 160, 175)
local CANDY = Color3.fromRGB(215, 40, 50)
local WHITE = Color3.fromRGB(250, 250, 250)
local GOLD = Color3.fromRGB(255, 200, 60)
local WOOD = Color3.fromRGB(130, 85, 55)
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
				ball(
					ctx,
					"LampGlow",
					Vector3.new(x, 10.5, z),
					1.6,
					Color3.fromRGB(255, 235, 170),
					Enum.Material.Neon
				)
			end
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

-- Townhouse fronts (not enterable) and low hedges fill the stretches between
-- the stop's real houses, so the canal reads as a street.
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
				ctx.newPart(
					ctx.model,
					"Townhouse",
					Vector3.new(24, height, 34),
					ctx.origin * CFrame.new(x, height / 2, z),
					color
				)
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
				for row = 1, math.floor((height - 4) / 7) do
					for _, dz in { -10, 0, 10 } do
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
						end
					end)
				)
			end
			for _, zone in state.splashZones do
				table.insert(
					connections,
					zone.Touched:Connect(function(hit)
						if not zone:GetAttribute("Broken") then
							return -- Santas skate on this all the time; only water splashes
						end
						local player = Util.playerFromHit(hit)
						if player and run.players[player] then
							local t = Util.now()
							if (splashAt[player] or 0) + 1 < t then
								splashAt[player] = t
								CanalTown.splash(run, player, zone)
							end
						end
					end)
				)
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
					local speed = CanalRules.walkSpeed(base, onIce, (boostUntil[player] or 0) > t)
					if humanoid.WalkSpeed ~= speed then
						humanoid.WalkSpeed = speed
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
		end
	end
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
		run:_banner(player, "SPLOOSH! Brrr... hop floe to floe!", 2)
	end
end

-- Turns an IceZone part into water with hoppable floes. Safe to call twice.
-- Returns the floes. Used by the Lair's floe hop and the Thin Ice event.
function CanalTown.breakZone(zone: BasePart, rng: Random?): { BasePart }
	if zone:GetAttribute("Broken") then
		return floesFor[zone] or {}
	end
	zone:SetAttribute("Broken", true)
	zone.Color = WATER
	zone.Material = Enum.Material.Glass
	zone.Transparency = 0.15
	local r = rng or Random.new()
	local floes = {}
	local folder = Instance.new("Folder")
	folder.Name = "Floes"
	for _, f in CanalRules.floeLayout(zone.Size.X, zone.Size.Z, r, keepoutsFor[zone]) do
		local floe = Instance.new("Part")
		floe.Name = "Floe"
		floe.Anchored = true
		floe.Size = Vector3.new(f.sizeX, C.FloeTop, f.sizeZ)
		floe.CFrame = zone.CFrame
			* CFrame.new(f.x, C.FloeTop / 2 - zone.Size.Y / 2, f.z)
			* CFrame.Angles(0, r:NextNumber(-0.08, 0.08), 0)
		floe.Color = Color3.fromRGB(225, 242, 252)
		floe.Material = Enum.Material.Ice
		floe.TopSurface = Enum.SurfaceType.Smooth
		floe.BottomSurface = Enum.SurfaceType.Smooth
		floe:SetAttribute("IceZone", true)
		floe:SetAttribute("Floe", true)
		floe.Parent = folder
		table.insert(floes, floe)
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

local function standInDog(kind: string): Model
	local model = Instance.new("Model")
	model.Name = kind
	local corgi = kind == "DogCorgi"
	local root = block(model, "HumanoidRootPart", Vector3.new(2, 2, 3), Vector3.new(0, 1.5, 0), WHITE)
	root.Transparency = 1
	local fur = if corgi then Color3.fromRGB(225, 140, 60) else Color3.fromRGB(185, 190, 200)
	block(model, "Body", Vector3.new(2, 1.6, if corgi then 3.4 else 4.4), Vector3.new(0, 1.4, 0), fur)
	block(model, "Head", Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 2.4, -2.2), fur)
	if corgi then
		block(model, "PatrolSled", Vector3.new(2.6, 0.4, 4.4), Vector3.new(0, 0.3, 0), CANDY)
	else
		block(model, "WindUpKey", Vector3.new(0.3, 1.4, 1.4), Vector3.new(0, 2.6, 0.8), GOLD)
	end
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	return model
end

function ChristmasMarket.start(ctx)
	local run, stop = ctx.run, ctx.stop
	if not stop.canal then
		return nil
	end
	local dogs = {}
	local dropped = {}
	for _, spec in stop.canal.dogs do
		local model = Assets.clone(spec.kind, { "Humanoid", "HumanoidRootPart" }) or standInDog(spec.kind)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
			end
		end
		model.Parent = run.route.model
		local _, size = model:GetBoundingBox()
		table.insert(dogs, {
			spec = spec,
			model = model,
			lift = size.Y / 2 + 0.4,
			clock = spec.offset,
			pausedUntil = 0,
			hitAt = {},
		})
	end

	local function dropPresent(player: Player, at: Vector3, value: number)
		local box = Instance.new("Part")
		box.Name = "DroppedPresent"
		box.Size = Vector3.one * 1.8
		box.CFrame = CFrame.new(at + Vector3.new(0, 0.9, 0))
		box.Color = Color3.fromRGB(230, 50, 60)
		box.Anchored = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Grab"
		prompt.ObjectText = "Present"
		prompt.HoldDuration = Config.Presents.GrabHoldSeconds
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = box
		local model = Instance.new("Model")
		model.Name = "DroppedPresent"
		box.Parent = model
		model.PrimaryPart = box
		model.Parent = run.route.model
		-- ringMultiplier 0: no Jingle for picking your own present back up.
		local present = {
			model = model,
			prompt = prompt,
			plan = { size = 1, value = value, ringMultiplier = 0, threats = 0 },
		}
		prompt.Triggered:Connect(function(by)
			run:_grab(by, present)
		end)
		table.insert(dropped, model)
		run:_banner(player, "WOOF! A corgi knocked a present out of your sack. Grab it back!", 2.5)
	end

	local connection = RunService.Heartbeat:Connect(function(dt)
		local t = Util.now()
		local santas = {}
		for player in run.players do
			local root = Util.rootOf(player)
			if root and run:_free(player) then
				table.insert(santas, { player = player, root = root })
			end
		end
		for _, dog in dogs do
			if dog.pausedUntil <= t then
				dog.clock += dt
			end
			local pos, facing = CanalRules.patrolAt(dog.spec.points, C.Dogs.Speed, dog.clock)
			local at = pos + Vector3.new(0, dog.lift, 0)
			dog.model:PivotTo(CFrame.lookAt(at, at + facing))
			if dog.pausedUntil > t then
				continue
			end
			for _, santa in santas do
				local player, root = santa.player, santa.root
				if (dog.hitAt[player] or 0) + C.Dogs.CorgiCooldown < t then
					local offset = (root.CFrame.Position - pos) * Vector3.new(1, 0, 1)
					if offset.Magnitude < C.Dogs.HitRadius then
						dog.hitAt[player] = t
						local away = if offset.Magnitude > 0.1 then offset.Unit else facing
						root.AssemblyLinearVelocity = away * C.Dogs.Knockback + Vector3.new(0, 25, 0)
						if dog.spec.kind == "DogCorgi" then
							local st = run.players[player]
							local value = Loot.dropOne(st)
							if value then
								run:_sendPlayer(player)
								dropPresent(
									player,
									root.CFrame.Position + away * 6 - Vector3.new(0, 2.5, 0),
									value
								)
							else
								run:_banner(
									player,
									"WOOF! The corgi bumped you. Your sack is empty, lucky!",
									2
								)
							end
						else
							dog.pausedUntil = t + C.Dogs.TinWindDown
							run:_banner(player, "BONK! The tin dog winds down... sneak past now!", 2)
						end
					end
				end
			end
		end
	end)

	return function()
		connection:Disconnect()
		for _, dog in dogs do
			dog.model:Destroy()
		end
		for _, model in dropped do
			model:Destroy()
		end
	end
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
				local offset = (root.CFrame.Position - pos) * Vector3.new(1, 0, 1)
				if offset.Magnitude < C.Polisher.HitRadius then
					scoopedAt[player] = t
					local bank = rink.snowbanks[CanalRules.nearest(rink.snowbanks, root.CFrame.Position) or 1]
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
			z += 24
		end
	end
	-- Floes keep clear of the island and the bridge (zone space).
	keepoutsFor[lake] = {
		{ x = f.island.X, z = f.island.Z - midZ, radius = f.islandRadius },
		{ x = 0, z = (bridgeFrom + bridgeTo) / 2 - midZ, halfX = 5, halfZ = (bridgeTo - bridgeFrom) / 2 },
	}
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
	local thread = task.delay(C.StompDelay, function()
		run:_banner(nil, "KRAMPUS STOMPS! The lake cracks into floes. Hop across or take the bell bridge!", 4)
		CanalTown.breakZone(stop.canal.lake)
	end)
	return function()
		pcall(task.cancel, thread)
	end
end

CanalTown.features = {
	CanalStreet = CanalStreet,
	SkateCanal = SkateCanal,
	ChristmasMarket = ChristmasMarket,
	IceRink = IceRink,
	FloeLake = FloeLake,
}

return CanalTown
