--[[
	Pure elf bot decisions (no Instances), so they can be unit tested.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local E = Config.ElfBots

local ElfBrain = {}

export type PresentCandidate = { present: any, position: Vector3 }

function ElfBrain.wantsBots(crewSize: number): boolean
	return crewSize <= E.MaxCrewForBots
end

-- A mix of designs: every variant appears once (in random order) before any
-- repeats, so two bots are always one A and one D.
function ElfBrain.pickVariants(rng: Random, count: number): { string }
	local pool = table.clone(E.Variants)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local picks = {}
	for i = 1, count do
		picks[i] = pool[i] or E.Variants[rng:NextInteger(1, #E.Variants)]
	end
	return picks
end

-- The untaken present nearest their Santa, within GrabRange of the Santa.
function ElfBrain.pickPresent(owner: Vector3, candidates: { PresentCandidate }): PresentCandidate?
	local best, bestDistance = nil, E.GrabRange
	for _, c in candidates do
		local distance = (c.position - owner).Magnitude
		if distance <= bestDistance then
			best, bestDistance = c, distance
		end
	end
	return best
end

-- Where bot number `index` stands relative to its Santa: behind, to alternate sides.
function ElfBrain.followOffset(index: number): Vector3
	local side = if index % 2 == 1 then -1 else 1
	return Vector3.new(side * 3, 0, 4 + math.floor((index - 1) / 2) * 3)
end

return ElfBrain
