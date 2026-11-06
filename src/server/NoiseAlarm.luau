--[[
	Decisions for the noise alarm (Config.Noise.Alarm): what a full noise meter
	does on a stop where Krampus doesn't answer it. Pure, so Lune can test it;
	Run and AlarmDogs do the moving.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local NoiseAlarm = {}

-- Does a full meter set off the alarm on this stop? Krampus answers the
-- meter from NoiseArrivalFrom on, and his Lair (the Finale) is his anyway.
function NoiseAlarm.applies(stopIndex: number, kindName: string?): boolean
	if not Config.Noise.Alarm.Enabled or kindName == "Finale" then
		return false
	end
	return stopIndex < Config.Krampus.NoiseArrivalFrom
end

-- The departure time after an alarm horn at `now`: HornSeconds away, but
-- never later than it already was (20 s left stays 20 s, Josh 6 Nov 2026).
function NoiseAlarm.departAt(now: number, departAt: number): number
	return math.min(departAt, now + Config.Noise.Alarm.HornSeconds)
end

export type Santa = { player: any, position: Vector3, safe: boolean }

-- The Santa a dog at `from` chases: the nearest one in SenseRange who isn't
-- safe (aboard at the Sleigh Stop). nil = nobody to chase.
function NoiseAlarm.target(from: Vector3, santas: { Santa }): Santa?
	local best, bestDistance = nil, Config.Noise.Alarm.SenseRange
	for _, santa in santas do
		if not santa.safe then
			local distance = Vector3.new(santa.position.X - from.X, 0, santa.position.Z - from.Z).Magnitude
			if distance <= bestDistance then
				best, bestDistance = santa, distance
			end
		end
	end
	return best
end

-- Where dog `index` of `count` starts, side by side across the street,
-- relative to the release point (studs, flat).
function NoiseAlarm.spawnOffset(index: number, count: number): Vector3
	return Vector3.new((index - (count + 1) / 2) * 5, 0, 0)
end

-- Phases a stop moves through, in order. The alarm horn can come before the
-- lights: a later phase never steps the stop back to an earlier one.
local RANK = { Sneak = 1, LightsOn = 2, Horn = 3 }

function NoiseAlarm.nextPhase(current: string, incoming: string): string
	local now, new = RANK[current], RANK[incoming]
	if now and new and new < now then
		return current
	end
	return incoming
end

return NoiseAlarm
