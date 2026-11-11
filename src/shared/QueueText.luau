--[[
	The line in the HUD's queue panel (pure, unit tested). Lobby sends a
	"Queue" message whenever a rider's place in the queue changes:

	  state "Gathering"  on a Party/Private sleigh, waiting for friends to climb in
	  state "Searching"  in the game queue, the matchmaker is finding a crew
	  state "Found"      a crew formed, off to the street
	  (no state)         a crew counting down to its next run (requeue after a run)

	plus kind ("Public" | "Party" | "Private"), since (unix seconds the wait
	started), count (riders in this group or crew), departAt, requeue and
	waiting (every street on this server is busy).
]]

local Config = require(script.Parent.Config)

local QueueText = {}

local function elapsed(since: number?, now: number): string
	local s = math.max(0, math.floor(now - (since or now)))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

function QueueText.line(q: { [string]: any }, now: number): string
	local count = q.count or 1
	local max = Config.Lobby.CrewMax
	if q.waiting then
		local prefix = if q.requeue then "Heist again together! " else "Crew found! "
		return prefix .. "Waiting for a free street... (" .. count .. " Santas)"
	elseif q.state == "Gathering" then
		if q.kind == "Private" then
			return string.format("Private sleigh  ·  %d aboard  ·  waiting for friends", count)
		end
		return string.format("In the queue! Waiting for your friends  ·  %d/%d aboard", count, max)
	elseif q.state == "Searching" then
		if q.kind == "Party" then
			return string.format(
				"In the queue! Topping up your party of %d  ·  %s",
				count,
				elapsed(q.since, now)
			)
		end
		return "In the queue! Finding your crew  ·  " .. elapsed(q.since, now)
	elseif q.state == "Found" then
		return string.format("Crew found! Off to the street...  ·  %d/%d Santas", count, max)
	end
	local prefix = if q.requeue then "Heist again together! " else ""
	local left = math.max(0, math.ceil((q.departAt or now) - now))
	return string.format("%sSleigh leaves in %d  ·  %d/%d Santas", prefix, left, count, max)
end

return QueueText
