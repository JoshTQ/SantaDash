--[[
	Player analytics: the funnels and labels Roblox's Creator Dashboard shows.
	Pure data and rules so it runs in tests; server/Analytics.luau sends the
	events (AnalyticsService) and docs/ANALYTICS.md says where to find them.

	Funnels (Creator Dashboard > Analytics > Funnels):

	  Onboarding  a brand-new player's first game, once per player (Roblox's
	              one-time onboarding funnel). Every step is on the path every
	              new player walks, in order, so a drop between two steps is a
	              real drop-off. (Roblox counts a skipped step as done, so
	              optional things such as grabbing a present are custom
	              events, not steps.)
	  Lobby       every lobby visit: loaded in -> sat in a sleigh -> crew found.
	  Run         every run: started -> each stop -> finished.
	  Shop        every store visit: opened -> prompt shown -> bought.

	Red-team notes:
	- Step numbers are what Roblox stores. Never renumber or reorder a step
	  after launch; add new steps to the end (or start a new funnel name).
	- Field values are a few fixed labels (buckets), never names or ids:
	  Roblox folds anything past 8,000 distinct values into "Other", and
	  nothing that identifies a child is ever sent.
]]

local Config = require(script.Parent.Config)

local Funnels = {}

export type Step = { id: string, name: string }

local function stopSteps(prefix: string): { Step }
	local out = {}
	for i, kind in Config.Run.StopKinds do
		if kind == "Finale" then
			table.insert(out, { id = prefix .. i, name = "Reached Krampus's Lair" })
		else
			table.insert(out, { id = prefix .. i, name = "Landed at Stop " .. i })
		end
	end
	return out
end

local function list(...: { Step }): { Step }
	local out = {}
	for _, part in { ... } do
		for _, step in part do
			table.insert(out, step)
		end
	end
	return out
end

-- The first game, in the order a new player meets it. The 15 Nov slice has
-- 3 stops, so: 1 Joined ... 6 Stop 1, 7 Stop 2, 8 Lair, 9 Finished, 10 Second run.
Funnels.Onboarding = list(
	{
		{ id = "Joined", name = "Joined the game" },
		{ id = "LoadedIn", name = "Loaded in" },
		{ id = "Boarded", name = "Sat in a sleigh" },
		{ id = "CrewFound", name = "Crew found" },
		{ id = "RunStarted", name = "First run started" },
	},
	stopSteps("Stop"),
	{
		{ id = "Finished", name = "First heist finished" },
		{ id = "SecondRun", name = "Second run started" },
	}
)

Funnels.Lobby = {
	{ id = "LoadedIn", name = "Loaded into the lobby" },
	{ id = "Boarded", name = "Sat in a sleigh" },
	{ id = "CrewFound", name = "Crew found" },
}

Funnels.Run = list({ { id = "RunStarted", name = "Run started" } }, stopSteps("Stop"), {
	{ id = "Finished", name = "Run finished" },
})

Funnels.Shop = {
	{ id = "Opened", name = "Opened the store" },
	{ id = "Prompted", name = "Purchase prompt shown" },
	{ id = "Bought", name = "Bought" },
}

-- Funnel names as Roblox shows them (LogFunnelStepEvent's funnelName).
Funnels.Names = { Lobby = "Lobby", Run = "Run", Shop = "Shop" }

-- The step number of an id in a funnel, or nil.
function Funnels.step(funnel: { Step }, id: string): number?
	for i, step in funnel do
		if step.id == id then
			return i
		end
	end
	return nil
end

-- The id of a stop's step (shared by the Onboarding and Run funnels).
function Funnels.stopId(index: number): string
	return "Stop" .. index
end

-- Onboarding status from saved data:
--   "veteran"  never enters the funnel (-1, or an old save first seen now)
--   "new"      brand new: start the funnel (log step 1)
--   "active"   in the funnel; log later steps
--   "done"     reached the last step
function Funnels.status(saved: number?, playSeconds: number?, persistent: boolean): string
	local step = if type(saved) == "number" then saved else 0
	if step < 0 then
		return "veteran"
	elseif step >= #Funnels.Onboarding then
		return "done"
	elseif step > 0 then
		return "active"
	end
	-- Undecided. Unsaved data (DataStore down, Studio) can't tell a veteran
	-- from a new player, and can't remember the steps: stay out.
	if not persistent then
		return "unknown"
	end
	if (playSeconds or 0) < Config.Analytics.NewPlayerSeconds then
		return "new"
	end
	return "veteran"
end

-- A step is logged only the first time it is passed, and only forwards:
-- Roblox counts any skipped earlier step as done, and only the first log of
-- a step counts, so replays would only burn the rate limit.
function Funnels.shouldLog(saved: number, step: number): boolean
	return saved >= 1 and step > saved and step <= #Funnels.Onboarding
end

-- How experienced a player is, by runs started (including this one).
function Funnels.runsLabel(runs: number): string
	if runs <= 1 then
		return "1st run"
	elseif runs == 2 then
		return "2nd run"
	elseif runs <= 5 then
		return "3-5 runs"
	elseif runs <= 20 then
		return "6-20 runs"
	end
	return "21+ runs"
end

-- "First game" or "Played before": the split used on every custom event.
-- "Unknown" while saved data hasn't loaded (or can't be trusted).
function Funnels.experienceLabel(status: string?): string
	if status == "new" or status == "active" then
		return "First game"
	elseif status == "done" or status == "veteran" then
		return "Played before"
	end
	return "Unknown"
end

function Funnels.crewLabel(players: number): string
	if players <= 1 then
		return "Solo"
	end
	return "Crew of " .. math.min(players, Config.Lobby.CrewMax)
end

-- Where in a run a player was (phase names come from Run.luau).
function Funnels.runSpot(stopIndex: number, phase: string?): string
	if stopIndex <= 0 then
		return "Takeoff"
	end
	local kind = Config.Run.StopKinds[stopIndex]
	local place = if kind == "Finale" then "Lair" else "Stop " .. stopIndex
	if phase == "Results" then
		return "Results"
	end
	return place .. ": " .. (phase or "?")
end

-- Total playtime as a bucket (purchases, quitting).
function Funnels.playtimeLabel(seconds: number): string
	local minutes = seconds / 60
	if minutes < 3 then
		return "Under 3 min"
	elseif minutes < 10 then
		return "3-10 min"
	elseif minutes < 30 then
		return "10-30 min"
	elseif minutes < 60 then
		return "30-60 min"
	elseif minutes < 180 then
		return "1-3 h"
	end
	return "3 h+"
end

-- How long something took, as a bucket (time in the lobby before a crew).
function Funnels.waitLabel(seconds: number): string
	if seconds < 10 then
		return "Under 10 s"
	elseif seconds < 30 then
		return "10-30 s"
	elseif seconds < 60 then
		return "30-60 s"
	elseif seconds < 180 then
		return "1-3 min"
	end
	return "3 min+"
end

-- Problems with the step lists (tests and a startup check).
function Funnels.validate(): { string }
	local problems = {}
	for name, funnel in
		{ Onboarding = Funnels.Onboarding, Lobby = Funnels.Lobby, Run = Funnels.Run, Shop = Funnels.Shop }
	do
		local seen = {}
		if #funnel > 100 then
			table.insert(problems, name .. " has more than Roblox's 100 steps")
		end
		for _, step in funnel do
			if seen[step.id] then
				table.insert(problems, name .. " repeats step " .. step.id)
			end
			seen[step.id] = true
		end
	end
	return problems
end

return Funnels
