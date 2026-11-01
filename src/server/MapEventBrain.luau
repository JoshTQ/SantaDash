--[[
	Random map events: the pure rules (no Instances), so Lune can test them.
	Run asks for a plan at take-off; MapEvents.luau plays the event itself.

	Rules (game-design.md "Random map events"):
	- One roll per run (Config.MapEvents.Chance). A hit picks one event from the
	  map's pool by weight, at one of the allowed stops.
	- Never in a stop where Krampus can hunt (Config.Krampus.FirstStop onward),
	  and only on Street stops, so the Lair finale is never touched.
	- Warned WarningSeconds ahead, and always over before the horn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)

local MapEventBrain = {}

export type Plan = {
	kind: string,
	stop: number, -- stop index
	entry: { [string]: any }, -- the map's events entry (map-specific args)
	-- Seconds into that stop:
	warnAt: number,
	startAt: number,
	endAt: number,
}

local function enabled(kind: string): boolean
	local def = Config.MapEvents.Events[kind]
	return def ~= nil and def.Enabled == true
end

-- Stops an event may play at, for a route of these stop kinds.
function MapEventBrain.eligibleStops(stopKinds: { string }): { number }
	local stops = {}
	for _, i in Config.MapEvents.Stops do
		if stopKinds[i] == "Street" and i < Config.Krampus.FirstStop then
			table.insert(stops, i)
		end
	end
	return stops
end

-- The map's events that are switched on, as weighted entries.
function MapEventBrain.pool(map): { { any } }
	local entries = {}
	for _, entry in map.events or {} do
		if enabled(entry.kind) and (entry.weight or 0) > 0 then
			table.insert(entries, { entry, entry.weight })
		end
	end
	return entries
end

-- When it plays, in seconds into the stop. Always ends before the horn.
function MapEventBrain.timing(): (number, number, number)
	local cfg = Config.MapEvents
	local startAt = cfg.StartAt
	local endAt = math.min(startAt + cfg.MaxSeconds, Config.Run.HornAt)
	return math.max(0, startAt - cfg.WarningSeconds), startAt, endAt
end

-- This run's event, or nil (no roll, empty pool or nowhere it may play).
function MapEventBrain.plan(rng: Random, map, stopKinds: { string }): Plan?
	local stops = MapEventBrain.eligibleStops(stopKinds)
	local pool = MapEventBrain.pool(map)
	if #stops == 0 or #pool == 0 then
		return nil
	end
	if rng:NextNumber() >= Config.MapEvents.Chance then
		return nil
	end
	local entry = Util.weightedPick(rng, pool)
	local warnAt, startAt, endAt = MapEventBrain.timing()
	return {
		kind = entry.kind,
		stop = stops[rng:NextInteger(1, #stops)],
		entry = entry,
		warnAt = warnAt,
		startAt = startAt,
		endAt = endAt,
	}
end

-- Blizzard snowballs: a pile tops you up to the cap.
function MapEventBrain.takeSnowballs(have: number): number
	local cfg = Config.MapEvents.Events.Blizzard
	return math.min(cfg.MaxSnowballs, have + cfg.PileSnowballs)
end

function MapEventBrain.canThrow(have: number, lastThrowAt: number, t: number): boolean
	return have > 0 and t - lastThrowAt >= Config.MapEvents.Events.Blizzard.ThrowCooldown
end

-- Most crew splats during the event, for the "Snowball MVP" shout-out.
function MapEventBrain.mvp(splats: { [string]: number }): (string?, number)
	local bestName, best = nil, 0
	for name, count in splats do
		if count > best or (count == best and bestName ~= nil and name < bestName) then
			bestName, best = name, count
		end
	end
	return bestName, best
end

return MapEventBrain
