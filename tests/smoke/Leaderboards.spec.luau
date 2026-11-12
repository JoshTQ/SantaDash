--[[
	The lobby's weekly leaderboards, end to end (Josh, 12 Nov 2026: "Top
	crews and most wanted leaderboards aren't working". They were painted
	placeholders with nothing behind them.)

	  a crew finishes a run on a run server -> Run saves it to this week's
	  Top Crews and Most Wanted OrderedDataStores -> a lobby server (another
	  place) reads them -> the podium board, Wanted posters and Biggest Haul
	  sign show the crew.
]]

local function findIn(root, name: string)
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- The lobby's live board labels, found the way a player would see them.
local function boardOf(world)
	local lobby = world.engine.workspace:FindFirstChild("SleighStationLobby")
	assert(lobby, "no lobby built")
	local board = findIn(lobby, "TopCrewsBoard")
	local wall = {}
	for _, d in lobby:GetDescendants() do
		if d.Name == "WantedPoster" then
			wall[d:GetAttribute("Rank")] = d
		end
	end
	return {
		crew = function(i)
			return findIn(board, "Crew" .. i)
		end,
		empty = findIn(board, "Body"),
		poster = function(rank)
			local p = wall[rank]
			return { name = findIn(p, "Name").Text, haul = findIn(p, "Haul").Text, photo = findIn(p, "Photo") }
		end,
	}
end

describe("weekly leaderboards", function()
	it("a finished run lands on this week's boards", function()
		local world = headless()
		local engine = world.engine
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local saved = {}
		local svc = {
			GetOrderedDataStore = function(_, name)
				saved[name] = saved[name] or {}
				local data = saved[name]
				return {
					UpdateAsync = function(_, key, fn)
						data[key] = fn(data[key]) or data[key]
					end,
					IncrementAsync = function(_, key, delta)
						data[key] = (data[key] or 0) + delta
					end,
				}
			end,
		}
		world.load("ServerScriptService.Server.Leaderboards").useService(svc)
		local Leaderboard = world.load("ReplicatedStorage.Shared.Leaderboard")
		local Run = world.load("ServerScriptService.Server.Run")
		local a = engine:addPlayer("Ann", { userId = 701 })
		local b = engine:addPlayer("Bob", { userId = 702 })
		local finished = false
		world.run(function()
			local run = Run.new(1, { a, b }, function()
				finished = true
			end)
			run:start()
			local deadline = engine.now + 500
			while not (run.stopIndex == 1 and run.phase == "Sneak") do
				assert(engine.now < deadline, "never reached stop 1")
				world.wait(0.25)
			end
			local grabs = 0
			for _, present in run.route.stops[1].presents do
				if not present.taken and not present.inVault and grabs < 2 then
					engine.trigger(present.prompt, a)
					grabs += 1
				end
			end
			deadline = engine.now + 900
			while not finished do
				assert(engine.now < deadline, "run never finished")
				world.wait(0.5)
			end
		end)
		local results = engine:hudMessages(a, "Results")
		local rows = results[#results].data.rows
		local loot = {}
		local total = 0
		for _, r in rows do
			loot[r.userId] = r.loot
			total += r.loot
		end
		expect(loot[701]).toBeGreaterThan(0)

		-- one store per kind, named for this (headless) week
		local crews, wanted
		for name, data in saved do
			if string.find(name, "^TopCrews_v1/%d%d%d%d%-%d%d%-%d%d$") then
				crews = data
			elseif string.find(name, "^MostWanted_v1/%d%d%d%d%-%d%d%-%d%d$") then
				wanted = data
			end
		end
		expect(crews).never.toBeNil()
		-- the board counts the loot itself (paid 2X Loot only changes Coal)
		expect(crews[Leaderboard.crewKey({ 701, 702 })]).toBe(total)
		expect(wanted["701"]).toBe(loot[701])
		if loot[702] == 0 then
			expect(wanted["702"]).toBeNil()
		end
	end)

	it("a run server's haul shows up in another place's lobby", function()
		local c = cloud({
			configure = function(Config)
				Config.Leaderboards.RefreshSeconds = 5
			end,
		})
		local lobby = c:lobby()
		local run = c:start("Run", "code-1")
		local ann = c:join(lobby, "Ann")
		local bob = c:join(lobby, "Bob")
		local cy = c:join(lobby, "Cy")
		c:run(function()
			c:wait(1)
			local view = boardOf(lobby)
			expect(view.empty.Visible).toBe(true)
			expect(view.empty.Text).toBe("Rob the most presents to stand up here!")
			expect(view.poster(1).name).toBe("???")

			local Leaderboards = run.load("ServerScriptService.Server.Leaderboards")
			expect(Leaderboards.record({ { ann.UserId, 1200 }, { bob.UserId, 300 } })).toBe(true)
			expect(Leaderboards.record({ { cy.UserId, 600 } })).toBe(true)
			c:wait(6) -- the lobby's next refresh

			expect(view.empty.Visible).toBe(false)
			expect(view.crew(1).Text).toBe("1.  Ann & Bob  ·  1.5K")
			expect(view.crew(2).Text).toBe("2.  Cy  ·  600")
			expect(view.crew(3).Visible).toBe(false)
			expect(view.poster(1).name).toBe("Ann")
			expect(view.poster(1).haul).toBe("1.2K loot")
			expect(view.poster(2).name).toBe("Cy")
			expect(view.poster(3).name).toBe("Bob")
			expect(view.poster(1).photo.Image).toContain("id=" .. ann.UserId)
			local haul = findIn(lobby.engine.workspace, "BiggestHaul")
			expect(haul:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel").Text).toBe(
				"THIS WEEK'S BIGGEST HAUL: 1.5K"
			)
		end)
	end)

	it("a DataStore outage shows a snow day, then the boards come back", function()
		local c = cloud({
			configure = function(Config)
				Config.Leaderboards.RefreshSeconds = 5
				Config.Leaderboards.RetrySeconds = 0.5
			end,
		})
		c.faults.dataStore = true
		local lobby = c:lobby()
		local run = c:start("Run", "code-1")
		local ann = c:join(lobby, "Ann")
		c:run(function()
			c:wait(1)
			local view = boardOf(lobby)
			expect(view.empty.Text).toBe("Leaderboard is having a snow day. Back soon!")
			local Leaderboards = run.load("ServerScriptService.Server.Leaderboards")
			expect(Leaderboards.record({ { ann.UserId, 500 } })).toBe(false) -- gave up after retries
			c.faults.dataStore = false
			expect(Leaderboards.record({ { ann.UserId, 500 } })).toBe(true)
			c:wait(6)
			expect(view.crew(1).Text).toBe("1.  Ann  ·  500")
		end)
	end)
end)
