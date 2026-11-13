--[[
	Run maps. Each map is a pure definition in this folder (see SnowyStreet for
	the shape); gameplay (houses, presents, Krampus, the sleigh deck) is always
	built procedurally by MapBuilder from it, so every map gets the full loop.

	Adding a map: add <Id>.luau here, register it in Defs and Maps.Rotation,
	and add any new feature kinds to server/MapFeatures.luau and event kinds to
	server/MapEvents.luau.
]]

local Config = require(script.Parent.Config)

local Maps = {}

local Defs = {
	SnowyStreet = require(script.SnowyStreet),
	FrozenCanal = require(script.FrozenCanal),
}

Maps.Default = "SnowyStreet"
-- Runs pick from these at random, avoiding the map the crew just played.
-- Launch ships Frozen Canal Town only (Josh, 1 Nov 2026); SnowyStreet stays
-- as the greybox reference map and comes back once it has its own art.
Maps.Rotation = { "FrozenCanal" }

export type Look = { any } -- { Color3, Enum.Material? }

export type Layout = {
	Slots: { { Ring: string, Side: number, Extra: number } }, -- slot 1 = Near landing house
	-- Optional: which Slots each stop uses (by stop index), in place of the
	-- stop kind's Slots.
	StopSlots: { [number]: { number } }?,
	SideOffset: number,
	RoadWidth: number,
	StreetStart: number,
	StreetOverrun: number,
	StopSpacing: number,
	FootPathZ: number,
	CocoaMachine: Vector3,
	-- Optional: each stop's origin relative to the route base (+Z down that
	-- stop's street), the finale included. Default: StopSpacing apart along +X.
	StopOrigins: { CFrame }?,
	-- Optional: the end house (Vault / Lair) per stop kind, in stop space,
	-- e.g. { Finale = CFrame.new(0, 0, 520) * CFrame.Angles(0, math.pi, 0) }.
	EndHouseAt: { [string]: CFrame }?,
	-- Optional: each stop's Sleigh Stop (ground landing point) in stop space.
	-- Default: Config.Map.LandingAt, in front of the landing house.
	LandingAt: { CFrame }?,
}

export type MapEvent = { kind: string, weight: number, [string]: any }

export type Map = {
	id: string,
	name: string,
	palette: { Ground: Look, Road: Look, Path: Look },
	layout: Layout,
	features: { { kind: string, [string]: any } },
	-- Random map events this map can roll: { kind = "<MapEvents key>", weight = n }.
	events: { MapEvent },
	dressing: string?, -- ServerStorage.Maps.<dressing>: approved set dressing (art only)
}

local DEFAULT_PALETTE = {
	Ground = { Color3.fromRGB(235, 240, 250), Enum.Material.Snow },
	Road = { Color3.fromRGB(70, 74, 86), Enum.Material.SmoothPlastic },
	Path = { Color3.fromRGB(200, 210, 230), Enum.Material.SmoothPlastic },
}

local function defaultLayout(): Layout
	local m = Config.Map
	return {
		Slots = Config.Street.Slots,
		SideOffset = m.SideOffset,
		RoadWidth = m.RoadWidth,
		StreetStart = m.StreetStart,
		StreetOverrun = m.StreetOverrun,
		StopSpacing = m.StopSpacing,
		FootPathZ = m.FootPathZ,
		CocoaMachine = m.CocoaMachine,
	}
end

local cache: { [string]: Map } = {}

-- The full definition, with anything the map leaves out filled from Config.
function Maps.get(id: string?): Map
	local key = id or Maps.Default
	if cache[key] then
		return cache[key]
	end
	local def = Defs[key] :: any
	assert(def, "unknown map " .. tostring(key))
	local map = {
		id = def.id or key,
		name = def.name or key,
		palette = table.clone(DEFAULT_PALETTE),
		layout = defaultLayout(),
		features = def.features or {},
		events = def.events or {},
		dressing = def.dressing,
	}
	for k, v in def.palette or {} do
		map.palette[k] = v
	end
	for k, v in def.layout or {} do
		map.layout[k] = v
	end
	cache[key] = map
	return map
end

-- Where stop i sits, relative to the route base: the map's StopOrigins, else
-- StopSpacing apart along +X.
function Maps.stopOrigin(layout: Layout, i: number): CFrame
	local given = layout.StopOrigins and layout.StopOrigins[i]
	return given or CFrame.new((i - 1) * layout.StopSpacing, 0, 0)
end

-- A feature with `stops = { ... }` only builds and starts at those stops.
function Maps.featureOnStop(feature: { [string]: any }, stopIndex: number): boolean
	return feature.stops == nil or table.find(feature.stops, stopIndex) ~= nil
end

-- A random map from the rotation, not `last` when there is a choice.
function Maps.ids(): { string }
	local ids = {}
	for id in Defs do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

function Maps.pick(rng: Random, last: string?): string
	local options = {}
	for _, id in Maps.Rotation do
		if id ~= last then
			table.insert(options, id)
		end
	end
	if #options == 0 then
		return last or Maps.Default
	end
	return options[rng:NextInteger(1, #options)]
end

return Maps
