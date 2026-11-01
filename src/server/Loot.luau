--[[
	Pure loot rules: House Card rolls, stop plans, present values, banking and
	results. No Instances here, so it runs in unit tests outside Roblox.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local Loot = {}

export type PresentPlan = {
	size: number,
	value: number,
	ringMultiplier: number,
	threats: number,
	naughtyList: boolean?,
}

export type HousePlan = {
	typeName: string,
	ring: string,
	side: number, -- -1 left of the road, 1 right, 0 across the end
	distance: number, -- studs down the street
	size: Vector3,
	locked: boolean,
	chimney: boolean,
	hideSpots: number,
	isLanding: boolean,
	presents: { PresentPlan },
}

export type StopPlan = {
	index: number,
	kindName: string,
	banner: string,
	escapeMultiplier: number?,
	houses: { HousePlan },
}

export type PlayerState = {
	jingle: number,
	sackCount: number,
	sackValue: number,
	banked: number,
	grabs: number,
	escapeMultiplier: number?,
}

local TYPE_ORDER = { "Cosy", "Normal", "Risky" }

function Loot.rollHouseType(rng: Random, stopIndex: number): string
	local weights = Config.Houses.StopWeights[stopIndex] or Config.Houses.StopWeights.Default
	local entries = {}
	for _, name in TYPE_ORDER do
		table.insert(entries, { name, weights[name] or 0 })
	end
	return Util.weightedPick(rng, entries)
end

-- Rolls the House Card types for one street, honouring stop escalation and the
-- "always at least one Cosy house" rule. Index 1 is the landing (Near) house.
function Loot.rollStreet(rng: Random, stopIndex: number, houseCount: number): { string }
	local types = {}
	local cosyCount = 0
	for i = 1, houseCount do
		types[i] = Loot.rollHouseType(rng, stopIndex)
		if types[i] == "Cosy" then
			cosyCount += 1
		end
	end
	if cosyCount < Config.Houses.MinCosyPerStreet and houseCount > 0 then
		types[1] = "Cosy" -- the landing house is the friendliest place to be generous
	end
	return types
end

function Loot.rollSize(rng: Random): number
	return Util.weightedPick(rng, Config.Presents.Sizes)
end

-- Size-squared value, ring multiplier, +25% per threat in the house.
function Loot.presentValue(size: number, ringMultiplier: number, threats: number): number
	local base = Config.Presents.BaseValue * size * size
	local bonus = 1 + threats * Config.Houses.ThreatLootBonus
	return math.floor(base * ringMultiplier * bonus + 0.5)
end

function Loot.jingleForGrab(ringMultiplier: number): number
	return math.floor(Config.Presents.JinglePerGrab * ringMultiplier + 0.5)
end

function Loot.noiseForGrab(stopIndex: number, threats: number): number
	local stopMult = Config.Noise.StopMultiplier[stopIndex] or 1
	return Config.Noise.PerGrab * stopMult * (1 + threats * Config.Noise.PerThreatMultiplier)
end

local function planPresent(rng: Random, size: number?, ringMultiplier: number, threats: number): PresentPlan
	local s = size or Loot.rollSize(rng)
	return {
		size = s,
		value = Loot.presentValue(s, ringMultiplier, threats),
		ringMultiplier = ringMultiplier,
		threats = threats,
	}
end

local function planHouse(
	rng: Random,
	typeName: string,
	ring: string,
	side: number,
	distance: number,
	isLanding: boolean
): HousePlan
	local houseType = Config.Houses.Types[typeName]
	local mult = Config.Rings[ring].LootMultiplier
	local count = houseType.Presents
		or (Config.Houses.PresentsPerHouse[ring] + (houseType.ExtraPresents or 0))
	local presents = {}
	for _ = 1, count do
		table.insert(presents, planPresent(rng, houseType.PresentSize, mult, houseType.Threats))
	end
	if houseType.NaughtyList then
		table.insert(presents, {
			size = 1,
			value = Config.Presents.NaughtyListValue,
			ringMultiplier = mult,
			threats = houseType.Threats,
			naughtyList = true,
		})
	end
	return {
		typeName = typeName,
		ring = ring,
		side = side,
		distance = distance,
		size = houseType.Size or Config.Map.HouseSize,
		locked = houseType.Locked == true,
		chimney = not houseType.NoChimney,
		hideSpots = if houseType.Locked then 0 else houseType.HideSpots or Config.Houses.HideSpots,
		isLanding = isLanding,
		presents = presents,
	}
end

-- Everything one stop contains, decided up front so MapBuilder only builds it.
function Loot.planStop(rng: Random, stopIndex: number): StopPlan
	local kindName = Config.Run.StopKinds[stopIndex]
	local kind = Config.StopKinds[kindName]
	local types = Loot.rollStreet(rng, stopIndex, #kind.Slots)
	local houses = {}
	for i, slotIndex in kind.Slots do
		local slot = Config.Street.Slots[slotIndex]
		local typeName = if i > 1 and kind.ForceType then kind.ForceType else types[i]
		local distance = Config.Rings[slot.Ring].Distance + slot.Extra
		table.insert(houses, planHouse(rng, typeName, slot.Ring, slot.Side, distance, i == 1))
	end
	local endType = Config.Houses.Types[kind.EndHouse]
	table.insert(
		houses,
		planHouse(rng, kind.EndHouse, "Far", 0, Config.Rings.Far.Distance + endType.Extra, false)
	)
	return {
		index = stopIndex,
		kindName = kindName,
		banner = string.format(kind.Banner, stopIndex),
		escapeMultiplier = kind.EscapeMultiplier,
		houses = houses,
	}
end

-- Hidden loot along the walk between two stops.
function Loot.planOnFoot(rng: Random): { PresentPlan }
	local presents = {}
	for _ = 1, Config.Presents.OnFootPresents do
		table.insert(presents, planPresent(rng, nil, Config.Presents.OnFootMultiplier, 0))
	end
	return presents
end

function Loot.newPlayerState(): PlayerState
	return {
		jingle = Config.Jingle.Start,
		sackCount = 0,
		sackValue = 0,
		banked = 0,
		grabs = 0,
		escapeMultiplier = nil,
	}
end

-- Returns false (and changes nothing) when the sack is full.
function Loot.grab(state: PlayerState, present: PresentPlan): boolean
	if state.sackCount >= Config.Sack.Capacity then
		return false
	end
	state.sackCount += 1
	state.sackValue += present.value
	state.grabs += 1
	state.jingle += Loot.jingleForGrab(present.ringMultiplier)
	return true
end

-- Leaving a stop on the sleigh banks the sack; leaving the finale also escapes.
function Loot.bank(state: PlayerState, escapeMultiplier: number?)
	state.banked += state.sackValue
	state.sackValue = 0
	state.sackCount = 0
	if escapeMultiplier then
		state.escapeMultiplier = escapeMultiplier
	end
end

function Loot.finalLoot(state: PlayerState): number
	return state.banked * (state.escapeMultiplier or 1)
end

export type ResultRow = { name: string, loot: number, coal: number, escaped: boolean, grabs: number }

-- entries: { { name, state } }. Sorted best thief first.
function Loot.results(entries: { { any } }): { ResultRow }
	local rows = {}
	for _, entry in entries do
		local name, state = entry[1], entry[2]
		local loot = Loot.finalLoot(state)
		table.insert(rows, {
			name = name,
			loot = loot,
			coal = math.floor(loot * Config.Coal.PerLootValue),
			escaped = state.escapeMultiplier ~= nil,
			grabs = state.grabs,
		})
	end
	table.sort(rows, function(a, b)
		return a.loot > b.loot
	end)
	return rows
end

return Loot
