--[[
	Funnel steps and labels (shared/Funnels.luau): stable step numbers, who
	enters the first-game funnel, forwards-only logging, and fixed labels.
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Funnels = load("ReplicatedStorage.Shared.Funnels")

local function ids(funnel): string
	local out = {}
	for _, step in funnel do
		table.insert(out, step.id)
	end
	return table.concat(out, ",")
end

describe("Funnels steps", function()
	it("keeps the launch onboarding step numbers (Roblox stores the numbers)", function()
		-- Changing this order after launch breaks the dashboard: add new
		-- steps to the end instead.
		expect(ids(Funnels.Onboarding)).toBe(
			"Joined,LoadedIn,Boarded,CrewFound,RunStarted,Stop1,Stop2,Stop3,Finished,SecondRun"
		)
		expect(Funnels.step(Funnels.Onboarding, "Joined")).toBe(1)
		expect(Funnels.step(Funnels.Onboarding, "SecondRun")).toBe(10)
		expect(Funnels.step(Funnels.Onboarding, "Nope")).toBeNil()
	end)

	it("has one step per stop in the Run funnel, with the Lair named", function()
		expect(#Funnels.Run).toBe(#Config.Run.StopKinds + 2)
		expect(Funnels.Run[2].name).toBe("Landed at Stop 1")
		expect(Funnels.Run[#Config.Run.StopKinds + 1].name).toBe("Reached Krampus's Lair")
		expect(Funnels.stopId(2)).toBe("Stop2")
	end)

	it("passes its own checks and stays inside Roblox's limits", function()
		expect(#Funnels.validate()).toBe(0)
		local count = 0
		for _ in Funnels.Names do
			count += 1
		end
		expect(count + 1 <= 10).toBeTruthy() -- + the onboarding funnel; Roblox allows 10
	end)

	it("keeps step names readable and short", function()
		for _, funnel in { Funnels.Onboarding, Funnels.Lobby, Funnels.Run, Funnels.Shop } do
			for _, step in funnel do
				expect(#step.name <= 40).toBeTruthy()
			end
		end
	end)
end)

describe("Funnels.status", function()
	it("starts brand-new saves and keeps old ones out for good", function()
		expect(Funnels.status(0, 0, true)).toBe("new")
		expect(Funnels.status(nil, 30, true)).toBe("new")
		expect(Funnels.status(0, Config.Analytics.NewPlayerSeconds + 1, true)).toBe("veteran")
		expect(Funnels.status(-1, 0, true)).toBe("veteran")
	end)

	it("carries on mid-funnel and stops at the end", function()
		expect(Funnels.status(4, 9999, true)).toBe("active")
		expect(Funnels.status(4, 9999, false)).toBe("active")
		expect(Funnels.status(#Funnels.Onboarding, 0, true)).toBe("done")
	end)

	it("stays out when saved data can't be trusted (DataStore down, Studio)", function()
		expect(Funnels.status(0, 0, false)).toBe("unknown")
		expect(Funnels.status("junk" :: any, 0, true)).toBe("new")
	end)
end)

describe("Funnels.shouldLog", function()
	it("only logs forwards, inside the funnel, once it has started", function()
		expect(Funnels.shouldLog(1, 2)).toBe(true)
		expect(Funnels.shouldLog(1, 5)).toBe(true) -- a skipped step: Roblox counts it as done
		expect(Funnels.shouldLog(5, 5)).toBe(false)
		expect(Funnels.shouldLog(5, 3)).toBe(false)
		expect(Funnels.shouldLog(0, 2)).toBe(false)
		expect(Funnels.shouldLog(-1, 2)).toBe(false)
		expect(Funnels.shouldLog(1, #Funnels.Onboarding + 1)).toBe(false)
	end)
end)

describe("Funnels labels", function()
	it("buckets runs, playtime and waits into a few fixed labels", function()
		expect(Funnels.runsLabel(0)).toBe("1st run")
		expect(Funnels.runsLabel(1)).toBe("1st run")
		expect(Funnels.runsLabel(2)).toBe("2nd run")
		expect(Funnels.runsLabel(5)).toBe("3-5 runs")
		expect(Funnels.runsLabel(20)).toBe("6-20 runs")
		expect(Funnels.runsLabel(500)).toBe("21+ runs")
		expect(Funnels.playtimeLabel(0)).toBe("Under 3 min")
		expect(Funnels.playtimeLabel(179)).toBe("Under 3 min")
		expect(Funnels.playtimeLabel(180)).toBe("3-10 min")
		expect(Funnels.playtimeLabel(45 * 60)).toBe("30-60 min")
		expect(Funnels.playtimeLabel(2 * 3600)).toBe("1-3 h")
		expect(Funnels.playtimeLabel(10 * 3600)).toBe("3 h+")
		expect(Funnels.waitLabel(5)).toBe("Under 10 s")
		expect(Funnels.waitLabel(45)).toBe("30-60 s")
		expect(Funnels.waitLabel(600)).toBe("3 min+")
	end)

	it("names crews, experience and where in a run someone was", function()
		expect(Funnels.crewLabel(1)).toBe("Solo")
		expect(Funnels.crewLabel(4)).toBe("Crew of 4")
		expect(Funnels.crewLabel(99)).toBe("Crew of " .. Config.Lobby.CrewMax)
		expect(Funnels.experienceLabel("new")).toBe("First game")
		expect(Funnels.experienceLabel("active")).toBe("First game")
		expect(Funnels.experienceLabel("done")).toBe("Played before")
		expect(Funnels.experienceLabel("veteran")).toBe("Played before")
		expect(Funnels.experienceLabel("unknown")).toBe("Unknown")
		expect(Funnels.experienceLabel(nil)).toBe("Unknown")
		expect(Funnels.runSpot(0, "Takeoff")).toBe("Takeoff")
		expect(Funnels.runSpot(1, "Sneak")).toBe("Stop 1: Sneak")
		expect(Funnels.runSpot(#Config.Run.StopKinds, "Horn")).toBe("Lair: Horn")
		expect(Funnels.runSpot(2, "Results")).toBe("Results")
	end)
end)

describe("Funnels in-game labels", function()
	it("names stops and run areas", function()
		expect(Funnels.stopLabel(0)).toBe("Takeoff")
		expect(Funnels.stopLabel(1)).toBe("Stop 1")
		expect(Funnels.stopLabel(#Config.Run.StopKinds)).toBe("Lair")
		expect(Funnels.areaLabel(1, "Sneak")).toBe("Stop 1")
		expect(Funnels.areaLabel(1, "Flight")).toBe("Flight")
		expect(Funnels.areaLabel(3, "Results")).toBe("Results")
		expect(Funnels.areaLabel(0, "Takeoff")).toBe("Takeoff")
		expect(Funnels.runSpot(1, "Flight")).toBe("Stop 1: Flight")
	end)

	it("buckets load time, frame rate and runs on a server", function()
		expect(Funnels.loadLabel(4)).toBe("Under 10 s")
		expect(Funnels.loadLabel(15)).toBe("10-20 s")
		expect(Funnels.loadLabel(30)).toBe("20-40 s")
		expect(Funnels.loadLabel(90)).toBe("40 s+")
		expect(Funnels.fpsLabel(8)).toBe("Under 15 fps")
		expect(Funnels.fpsLabel(25)).toBe("15-30 fps")
		expect(Funnels.fpsLabel(45)).toBe("30-50 fps")
		expect(Funnels.fpsLabel(60)).toBe("50+ fps")
		expect(Funnels.runsHereLabel(0)).toBe("No runs")
		expect(Funnels.runsHereLabel(1)).toBe("1 run")
		expect(Funnels.runsHereLabel(3)).toBe("2-3 runs")
		expect(Funnels.runsHereLabel(9)).toBe("4+ runs")
	end)
end)
