--[[
	The Sleigh Station timetable (pure, unit tested).

	Every bay loops: a sleigh pulls in (Arriving), the gate opens and the
	"BOARDING NOW!" sign lights (Boarding), the gate shuts and the sleigh
	leaves (Departing), then the track is empty for a moment (Away). Bays are
	staggered so they never all leave at once. Driven by the server clock, so
	every lobby server shows the same timetable.
]]

local Config = require(script.Parent.Config)

local StationClock = {}

StationClock.StaggerSeconds = 4

export type Phase = {
	name: string, -- "Arriving" | "Boarding" | "Departing" | "Away"
	startsAt: number,
	endsAt: number,
	cycle: number, -- increases by one per sleigh
}

local function lengths(kind: string): { { any } }
	local lm = Config.LobbyMap
	return {
		{ "Arriving", lm.ArriveSeconds },
		{ "Boarding", lm.BoardSeconds[kind] },
		{ "Departing", lm.DepartSeconds },
		{ "Away", lm.GapSeconds },
	}
end

local function total(phases: { { any } }): number
	local sum = 0
	for _, entry in phases do
		sum += entry[2]
	end
	return sum
end

function StationClock.cycleLength(kind: string): number
	return total(lengths(kind))
end

-- The phase bay `number` of `kind` is in at time t.
function StationClock.phaseAt(kind: string, number: number, t: number): Phase
	local phases = lengths(kind)
	local length = total(phases)
	local shifted = t - (number - 1) * StationClock.StaggerSeconds
	local cycle = math.floor(shifted / length)
	local at = cycle * length + (number - 1) * StationClock.StaggerSeconds
	for _, entry in phases do
		local endsAt = at + entry[2]
		if t < endsAt then
			return { name = entry[1], startsAt = at, endsAt = endsAt, cycle = cycle }
		end
		at = endsAt
	end
	-- Floating point edge: t landed exactly on the cycle end.
	return StationClock.phaseAt(kind, number, t + 1e-6)
end

return StationClock
