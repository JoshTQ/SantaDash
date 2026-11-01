--[[
	Pure loot and House Card rolls. No Instances here, so it is easy to test.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Loot = {}

local TYPE_ORDER = { "Cosy", "Normal", "Risky" }

local function weightedPick(rng: Random, weights: { [string]: number }, order: { string }): string
	local total = 0
	for _, key in order do
		total += weights[key] or 0
	end
	local roll = rng:NextNumber() * total
	for _, key in order do
		roll -= weights[key] or 0
		if roll <= 0 and (weights[key] or 0) > 0 then
			return key
		end
	end
	return order[1]
end

-- Rolls the House Card types for one street, honouring stop escalation and the
-- "always at least one Cosy house" rule. Index 1 is the landing (Near) house.
function Loot.rollStreet(rng: Random, stopIndex: number, houseCount: number): { string }
	local weights = Config.Houses.StopWeights[stopIndex] or Config.Houses.StopWeights.Default
	local types = {}
	local cosyCount = 0
	for i = 1, houseCount do
		types[i] = weightedPick(rng, weights, TYPE_ORDER)
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
	local total = 0
	for _, entry in Config.Presents.Sizes do
		total += entry.Weight
	end
	local roll = rng:NextNumber() * total
	for _, entry in Config.Presents.Sizes do
		roll -= entry.Weight
		if roll <= 0 then
			return entry.Size
		end
	end
	return Config.Presents.Sizes[1].Size
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

return Loot
