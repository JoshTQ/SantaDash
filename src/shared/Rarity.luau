--[[
	Present rarities and their drop odds (game-design.md "Rarity").

	Mythic and Secret are never random: they only come from challenges, so
	they are not in the odds table and luck (the Lucky Sack) can never touch
	them. Luck multiplies the weights of Rare, Epic and Legendary only.
	Odds are shown to players before any purchase that changes them, as
	Roblox's paid random items policy requires.
]]

local Rarity = {}

Rarity.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

-- Random drop weights (percent at luck 1). Must add up to 100.
Rarity.Weights = {
	{ name = "Common", weight = 60 },
	{ name = "Uncommon", weight = 25 },
	{ name = "Rare", weight = 10 },
	{ name = "Epic", weight = 4.2 },
	{ name = "Legendary", weight = 0.8 },
}

-- Earned only, never rolled, sold or boosted.
Rarity.EarnedOnly = { Mythic = true, Secret = true }

local LUCKY = { Rare = true, Epic = true, Legendary = true }

export type Odd = { name: string, percent: number }

-- The odds at a luck multiplier (1 = normal), as percentages adding to 100.
function Rarity.odds(luck: number?): { Odd }
	local l = math.max(1, luck or 1)
	local total = 0
	local weights = {}
	for i, entry in Rarity.Weights do
		local w = if LUCKY[entry.name] then entry.weight * l else entry.weight
		weights[i] = w
		total += w
	end
	local out = {}
	for i, entry in Rarity.Weights do
		table.insert(out, { name = entry.name, percent = weights[i] / total * 100 })
	end
	return out
end

-- Rolls one random rarity (never Mythic or Secret).
function Rarity.roll(rng: Random, luck: number?): string
	local r = rng:NextNumber() * 100
	local odds = Rarity.odds(luck)
	for _, odd in odds do
		r -= odd.percent
		if r <= 0 then
			return odd.name
		end
	end
	return odds[#odds].name
end

-- "12.5%", "0.8%", "<0.1%": what the store and present cards show.
function Rarity.format(percent: number): string
	if percent < 0.1 then
		return "<0.1%"
	end
	local rounded = math.floor(percent * 10 + 0.5) / 10
	if rounded == math.floor(rounded) then
		return string.format("%d%%", rounded)
	end
	return string.format("%.1f%%", rounded)
end

return Rarity
