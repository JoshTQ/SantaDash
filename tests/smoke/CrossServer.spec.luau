--[[
	Cross-server matchmaking, end to end (Josh, 2 Nov 2026: "thorough match
	making test coverage"). Several lobby servers and run servers run the real
	Main.server side by side in a headless cloud (tests/headless/Cloud.luau)
	with a shared MemoryStore queue, MessagingService and teleports:

	  rider walks into a bay -> sits -> ticket in the shared queue -> some
	  lobby server packs a crew -> reserves a run server -> announces it ->
	  every lobby server teleports its own riders -> the run server admits
	  exactly that crew -> the run starts.

	Plus the failure paths: MemoryStore down, publish/subscribe/reserve/
	teleport failures, riders hopping off or leaving, strangers at the run
	server, and duplicate or malformed messages.
]]

local QUEUE = "SleighHeist_PublicCrews_v1"
local TOPIC = "SleighHeist_CrewReady_v1"

local BAY_NUMBER = { Public = 1, Party = 2, Private = 3 }

-- Short stops so whole runs fit in a few virtual minutes.
local function fastRuns(Config)
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
end

local function newCloud(tweak: ((Config: any) -> ())?)
	return cloud({
		configure = function(Config)
			fastRuns(Config)
			if tweak then
				tweak(Config)
			end
		end,
	})
end

local function humanoidOf(player)
	return player.Character and player.Character:FindFirstChild("Humanoid")
end

local function seated(player): boolean
	local humanoid = humanoidOf(player)
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function phase(c, world, kind: string)
	local StationClock = world.load("ReplicatedStorage.Shared.StationClock")
	return StationClock.phaseAt(kind, BAY_NUMBER[kind], c.now)
end

-- Waits for the next time this bay is boarding with at least `left` seconds to go.
local function waitForBoarding(c, world, kind: string, left: number?)
	c:waitUntil(function()
		local p = phase(c, world, kind)
		return p.name == "Boarding" and p.endsAt - c.now >= (left or 4)
	end, 120, kind .. " boarding")
end

-- Walks players into a bay's board zone (they sit down on the next tick).
local function board(c, world, kind: string, players: { any })
	local zone = world.engine.workspace:FindFirstChild(kind .. "Zone", true)
	assert(zone, "no " .. kind .. " board zone")
	for _, player in players do
		world.engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
	end
	c:waitUntil(function()
		for _, player in players do
			if not seated(player) then
				return false
			end
		end
		return true
	end, 5, "riders to sit down")
end

local function joinAll(c, world, names: { string })
	local out = {}
	for _, name in names do
		table.insert(out, c:join(world, name))
	end
	return out
end

-- The server a player is in now (nil if they left the game).
local function serverOf(c, name: string)
	local world = c:find(name)
	return world
end

local function stops(c, name: string): number
	local world, player = c:find(name)
	return if world then #world.engine:hudMessages(player, "Stop") else 0
end

local function inRunServer(c, names: { string })
	local first = serverOf(c, names[1])
	if not first or first.kind ~= "Run" then
		return nil
	end
	for _, name in names do
		if serverOf(c, name) ~= first then
			return nil
		end
	end
	return first
end

local function teleportsTo(c, placeId: number)
	local out = {}
	for _, t in c.teleports do
		if t.placeId == placeId then
			table.insert(out, t)
		end
	end
	return out
end

local function topicMessages(c)
	local out = {}
	for _, m in c.published do
		if m.topic == TOPIC then
			table.insert(out, m)
		end
	end
	return out
end

local function hasWarning(c, text: string): boolean
	for _, w in c:warnings() do
		if string.find(w, text, 1, true) then
			return true
		end
	end
	return false
end

describe("Cross-server matchmaking: Public sleighs", function()
	it("queues a ticket the moment a Public rider sits down", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public")
			board(c, lobby, "Public", { ann })
			c:wait(0.5)
			local tickets = c:queued(QUEUE)
			expect(#tickets).toBe(1)
			expect(tickets[1].kind).toBe("Public")
			expect(tickets[1].members).toEqual({ ann.UserId })
			expect(tickets[1].servers).toEqual({ lobby.jobId })
			expect(tickets[1].since).toBeNear(c.now, 1)
		end)
	end)

	it("packs riders from two lobby servers into one crew on one run server", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local ann = c:join(a, "Ann")
			local bo = c:join(b, "Bo")
			waitForBoarding(c, a, "Public", 8)
			board(c, a, "Public", { ann })
			board(c, b, "Public", { bo })
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Bo" }) ~= nil
			end, 30, "both riders on one run server")

			expect(#c.reservations).toBe(1)
			expect(#topicMessages(c)).toBe(1) -- the crew spans servers, so it is announced
			local run = inRunServer(c, { "Ann", "Bo" })
			expect(run.code).toBe(c.reservations[1].code)

			-- Same TeleportData for both, naming exactly this crew.
			local data = topicMessages(c)[1].data.data
			expect(data.kind).toBe("Public")
			expect(#data.members).toBe(2)
			expect(data.members).toContain(ann.UserId)
			expect(data.members).toContain(bo.UserId)
			for _, t in teleportsTo(c, c.RunPlace) do
				expect(t.code).toBe(run.code)
				expect(t.data.crewId).toBe(data.crewId)
			end

			-- The whole crew is in, so the run starts without waiting for the arrival timeout.
			c:waitUntil(function()
				return stops(c, "Ann") > 0 and stops(c, "Bo") > 0
			end, 10, "the run to start")
			expect(c:queued(QUEUE)).toHaveLength(0)
		end)
	end)

	it("waits PublicWaitSeconds for more riders, then leaves part-full", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			local satAt = c.now
			local wait = lobby.Config.Matchmaking.PublicWaitSeconds
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 30, "Ann to be teleported")
			local waited = c.now - satAt
			expect(waited).toBeGreaterThanOrEqual(wait)
			expect(waited).toBeLessThan(wait + lobby.Config.Matchmaking.PackEverySeconds + 1)
			-- One server only: nobody else to tell.
			expect(#topicMessages(c)).toBe(0)
		end)
	end)

	it("sends a full crew of 6 from three servers as soon as it is packed", function()
		local c = newCloud()
		local lobbies = { c:lobby(), c:lobby(), c:lobby() }
		local names = { "A1", "A2", "B1", "B2", "C1", "C2" }
		c:run(function()
			local riders = {}
			for i, world in lobbies do
				riders[i] = joinAll(c, world, { names[i * 2 - 1], names[i * 2] })
			end
			waitForBoarding(c, lobbies[1], "Public", 11)
			local satAt = c.now
			for i, world in lobbies do
				board(c, world, "Public", riders[i])
			end
			c:waitUntil(function()
				return inRunServer(c, names) ~= nil
			end, 30, "the full crew on one run server")
			expect(c.now - satAt).toBeLessThan(lobbies[1].Config.Matchmaking.PublicWaitSeconds)
			expect(#c.reservations).toBe(1)
			c:waitUntil(function()
				return stops(c, "A1") > 0
			end, 10, "the run to start")
			for _, name in names do
				expect(stops(c, name)).toBeGreaterThan(0)
			end
		end)
	end)

	it("splits 7 riders into a full crew now and a crew of 1 later, on separate run servers", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local early = joinAll(c, a, { "A1", "A2", "A3", "A4" })
			local late = joinAll(c, b, { "B1", "B2", "B3" })
			waitForBoarding(c, a, "Public", 11)
			board(c, a, "Public", early)
			c:wait(1) -- B's riders sit a moment later, so they are newer tickets
			board(c, b, "Public", late)
			c:waitUntil(function()
				return #c.reservations >= 2
			end, 40, "two crews")
			c:waitUntil(function()
				for _, name in { "A1", "A2", "A3", "A4", "B1", "B2", "B3" } do
					if serverOf(c, name).kind ~= "Run" then
						return false
					end
				end
				return true
			end, 10, "everyone on a run server")
			-- Oldest first: A's four plus two of B's fill the first sleigh.
			local first = inRunServer(c, { "A1", "A2", "A3", "A4" })
			expect(first).never.toBeNil()
			local count = 0
			for _, name in { "B1", "B2", "B3" } do
				if serverOf(c, name) == first then
					count += 1
				end
			end
			expect(count).toBe(2)
			expect(#first.engine.Players:GetPlayers()).toBe(6)
			expect(c:queued(QUEUE)).toHaveLength(0)
		end)
	end)

	it("packs each ticket once even though every lobby server packs on the same beat", function()
		local c = newCloud()
		local lobbies = { c:lobby(), c:lobby(), c:lobby(), c:lobby() }
		c:run(function()
			local riders = {}
			for i, world in lobbies do
				riders[i] = c:join(world, "R" .. i)
			end
			waitForBoarding(c, lobbies[1], "Public", 11)
			for i, world in lobbies do
				board(c, world, "Public", { riders[i] })
			end
			c:waitUntil(function()
				return inRunServer(c, { "R1", "R2", "R3", "R4" }) ~= nil
			end, 30, "one crew of four")
			c:wait(10)
			expect(#c.reservations).toBe(1)
			expect(#teleportsTo(c, c.RunPlace)).toBe(4) -- one per server, each with one rider
			expect(#topicMessages(c)).toBe(1)
		end)
	end)

	it("does not duplicate waiting tickets while a crew is still filling", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			for _ = 1, 4 do
				c:wait(2)
				expect(#c:queued(QUEUE)).toBe(1)
			end
		end)
	end)

	it("does not teleport a rider who hopped off before the crew formed", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local ann, bo = c:join(lobby, "Ann"), c:join(lobby, "Bo")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann, bo })
			humanoidOf(bo).Jump = true
			c:wait(0.5)
			expect(seated(bo)).toBe(false)
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 30, "Ann's crew to leave")
			c:wait(2)
			expect(serverOf(c, "Bo")).toBe(lobby)
			expect(#lobby.engine:hudMessages(bo, "Stop")).toBe(0)
		end)
	end)

	it("frees a hopped-off rider's seat, so the crew doesn't wait for them", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local ann, hop = c:join(a, "Ann"), c:join(a, "Hop")
			local bo = c:join(b, "Bo")
			waitForBoarding(c, a, "Public", 11)
			board(c, a, "Public", { ann, hop })
			board(c, b, "Public", { bo })
			c:wait(1) -- Hop's ticket is in the queue
			humanoidOf(hop).Jump = true
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Bo" }) ~= nil
			end, 30, "Ann and Bo's crew")
			local data = topicMessages(c)[1].data.data
			expect(#data.members).toBe(2) -- Hop's seat was given back
			expect(data.members).never.toContain(hop.UserId)
			expect(serverOf(c, "Hop")).toBe(a)
			-- Everyone the run server expects is here, so it starts straight away.
			local arrived = c.now
			c:waitUntil(function()
				return stops(c, "Ann") > 0
			end, 10, "the run to start")
			expect(c.now - arrived).toBeLessThan(5)
		end)
	end)

	it("skips riders who left the game while queued", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local ann = c:join(a, "Ann")
			local bo = c:join(b, "Bo")
			waitForBoarding(c, a, "Public", 11)
			board(c, a, "Public", { ann })
			board(c, b, "Public", { bo })
			b.engine:removePlayer(bo)
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 30, "Ann's crew to leave")
			expect(serverOf(c, "Bo")).toBeNil()
			-- Bo's ticket left with the crew, so the run server waits for the
			-- arrival timeout, then starts with whoever arrived.
			local run = serverOf(c, "Ann")
			c:waitUntil(function()
				return stops(c, "Ann") > 0
			end, run.Config.Places.ArrivalTimeoutSeconds + 5, "the run to start without Bo")
			expect(#run.engine.Players:GetPlayers()).toBe(1)
		end)
	end)
end)

describe("Sleigh Station bays", function()
	it("seats at most a crew of 6 per sleigh and shows the count on the bay board", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local riders = joinAll(c, lobby, { "R1", "R2", "R3", "R4", "R5", "R6", "R7" })
			waitForBoarding(c, lobby, "Public", 8)
			local zone = lobby.engine.workspace:FindFirstChild("PublicZone", true)
			for _, player in riders do
				lobby.engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
			end
			c:wait(1)
			local sat = 0
			for _, player in riders do
				if seated(player) then
					sat += 1
				end
			end
			expect(sat).toBe(6)
			expect(seated(riders[7])).toBe(false)
			local shows = false
			for _, d in lobby.engine.workspace:GetDescendants() do
				if d:IsA("TextLabel") and d.Text == "CREW 6/6" then
					shows = true
				end
			end
			expect(shows).toBe(true)
		end)
	end)

	it("runs the crew on this server while the places are unpublished", function()
		local c = newCloud(function(Config)
			Config.Places.Lobby = 0
			Config.Places.Run = 0
		end)
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public")
			board(c, lobby, "Public", { ann })
			expect(#c:queued(QUEUE)).toBe(0)
			c:waitUntil(function()
				return #lobby.engine:hudMessages(ann, "Stop") > 0
			end, 30, "a run on the lobby server")
			expect(#c.teleports).toBe(0)
			expect(#c.reservations).toBe(0)
		end)
	end)
end)

describe("Cross-server matchmaking: Party and Private sleighs", function()
	it("tops up a Party group with a waiting Public rider from another server", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local friends = joinAll(c, a, { "Ann", "Amy" })
			local bo = c:join(b, "Bo")
			-- Bo sits on a Public sleigh a few seconds before the Party sleigh
			-- leaves, so he is still waiting when the Party group queues.
			c:waitUntil(function()
				local party = phase(c, a, "Party")
				local public = phase(c, b, "Public")
				local left = party.endsAt - c.now
				return party.name == "Boarding" and public.name == "Boarding" and left > 3 and left < 9
			end, 120, "a Public sleigh boarding just before the Party sleigh leaves")
			board(c, a, "Party", friends)
			board(c, b, "Public", { bo })
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Amy", "Bo" }) ~= nil
			end, 30, "the Party crew with Bo")
			local data = topicMessages(c)[1].data.data
			expect(data.kind).toBe("Party")
			expect(#data.members).toBe(3)
			expect(#c.reservations).toBe(1)
		end)
	end)

	it("never splits a Party group across sleighs", function()
		local c = newCloud(function(Config)
			Config.Matchmaking.PublicWaitSeconds = 60
		end)
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local party = joinAll(c, a, { "P1", "P2", "P3", "P4" })
			local randoms = joinAll(c, b, { "R1", "R2", "R3" })
			waitForBoarding(c, b, "Public", 11)
			board(c, b, "Public", randoms) -- 3 randoms + 4 friends = 7: someone waits
			waitForBoarding(c, a, "Party")
			board(c, a, "Party", party)
			c:waitUntil(function()
				return serverOf(c, "P1").kind == "Run"
			end, 60, "the Party crew to leave")
			local run = inRunServer(c, { "P1", "P2", "P3", "P4" })
			expect(run).never.toBeNil()
			expect(#run.engine.Players:GetPlayers()).toBeLessThanOrEqual(6)
		end)
	end)

	it("sends a Private sleigh straight to its own run server, with no queue", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local friends = joinAll(c, lobby, { "Ann", "Amy" })
			local stranger = c:join(lobby, "Sam")
			waitForBoarding(c, lobby, "Private")
			board(c, lobby, "Private", friends)
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Amy" }) ~= nil
			end, 60, "the Private crew to leave")
			expect(#c:queued(QUEUE)).toBe(0)
			expect(#topicMessages(c)).toBe(0)
			local t = teleportsTo(c, c.RunPlace)
			expect(#t).toBe(1)
			expect(t[1].data.kind).toBe("Private")
			expect(serverOf(c, "Sam")).toBe(lobby)
			expect(stranger.Parent).never.toBeNil()
			c:waitUntil(function()
				return stops(c, "Ann") > 0 and stops(c, "Amy") > 0
			end, 10, "the Private run to start")
		end)
	end)

	it("an empty Private sleigh reserves nothing", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Private")
			c:waitUntil(function()
				return phase(c, lobby, "Private").name == "Away"
			end, 60, "the sleigh to leave")
			expect(#c.reservations).toBe(0)
		end)
	end)
end)

describe("Cross-server: queued the moment you board (Josh, 11 Nov)", function()
	local function banners(world, player): { string }
		local out = {}
		for _, m in world.engine:hudMessages(player, "Banner") do
			table.insert(out, m.data.text)
		end
		return out
	end

	local function lastQueue(world, player)
		local list = world.engine:hudMessages(player, "Queue")
		return list[#list] and list[#list].data
	end

	it("tells a Public rider they're queued, then that the crew is found, before the teleport", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local Lobby = lobby.load("ServerScriptService.Server.Lobby")
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			c:wait(0.3)
			expect(banners(lobby, ann)).toContain(Lobby.Text.Queued)
			expect(lastQueue(lobby, ann).state).toBe("Searching")
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 30, "Ann to be teleported")
			expect(banners(lobby, ann)).toContain(Lobby.Text.Found)
			expect(lastQueue(lobby, ann).state).toBe("Found")
		end)
	end)

	it("puts a Party of friends in the shared queue while their sleigh is still boarding", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			local amy = c:join(lobby, "Amy", { ann })
			waitForBoarding(c, lobby, "Party", 14)
			local takeoff = phase(c, lobby, "Party").endsAt
			board(c, lobby, "Party", { ann, amy })
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Amy" }) ~= nil
			end, 10, "the party's run server")
			expect(c.now).toBeLessThan(takeoff)
			local t = teleportsTo(c, c.RunPlace)
			expect(t[1].data.kind).toBe("Party")
			expect(#t[1].data.members).toBe(2)
		end)
	end)

	it("a friend who climbs in just after the Party was queued joins the same crew", function()
		local c = newCloud(function(Config)
			Config.Matchmaking.PackEverySeconds = 20 -- the Party ticket sits in the queue a while
		end)
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			local amy = c:join(lobby, "Amy", { ann })
			local bo = c:join(lobby, "Bo") -- not yet a friend Roblox knows about
			waitForBoarding(c, lobby, "Party", 16)
			board(c, lobby, "Party", { ann, amy })
			c:waitUntil(function()
				return lastQueue(lobby, ann).state == "Searching"
			end, 5, "the party to be queued")
			c:wait(1)
			board(c, lobby, "Party", { bo })
			c:wait(lobby.Config.Lobby.GatherSeconds + 1) -- Bo isn't a friend, so the group waits for quiet
			-- The group's ticket was swapped for one holding all three.
			local three = nil
			for _, ticket in c:queued(QUEUE) do
				if #ticket.members == 3 then
					three = ticket
				end
			end
			expect(three).never.toBeNil()
			expect(three.kind).toBe("Party")
			expect(three.members).toContain(bo.UserId)
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Amy", "Bo" }) ~= nil
			end, 60, "one crew of three")
			expect(#c.reservations).toBe(1)
		end)
	end)

	it("sends a Private sleigh of friends as soon as everyone is aboard", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local Lobby = lobby.load("ServerScriptService.Server.Lobby")
			local ann = c:join(lobby, "Ann")
			local amy = c:join(lobby, "Amy", { ann })
			waitForBoarding(c, lobby, "Private", 14)
			local takeoff = phase(c, lobby, "Private").endsAt
			board(c, lobby, "Private", { ann })
			c:wait(1)
			expect(banners(lobby, ann)).toContain(Lobby.Text.PrivateGathering)
			expect(#c.reservations).toBe(0) -- waiting for Amy
			board(c, lobby, "Private", { amy })
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Amy" }) ~= nil
			end, 10, "the Private run server")
			expect(c.now).toBeLessThan(takeoff)
			expect(#c:queued(QUEUE)).toBe(0) -- Private never touches the shared queue
		end)
	end)

	it("hopping off a Party sleigh before the group goes keeps you out of its crew", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			local amy = c:join(lobby, "Amy", { ann })
			c:join(lobby, "Bo", { ann }) -- keeps the group waiting
			waitForBoarding(c, lobby, "Party", 16)
			board(c, lobby, "Party", { ann, amy })
			c:wait(1)
			humanoidOf(amy).Jump = true
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 30, "Ann's crew")
			c:wait(2)
			expect(serverOf(c, "Amy")).toBe(lobby)
			local data = teleportsTo(c, c.RunPlace)[1].data
			expect(data.members).never.toContain(amy.UserId)
		end)
	end)
end)

describe("Cross-server matchmaking: the run server", function()
	it("admits only the crew and sends strangers back to the lobby place", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 30, "Ann's crew to leave")
			local run = serverOf(c, "Ann")
			local Handoff = run.load("ReplicatedStorage.Shared.Handoff")

			-- Someone with another crew's data, and someone with none.
			run.engine:addPlayer("Gatecrasher", {
				userId = 9001,
				joinData = { TeleportData = Handoff.make("another-crew", "Public", { 9001 }) },
			})
			run.engine:addPlayer("NoData", { userId = 9002 })
			c:waitUntil(function()
				return serverOf(c, "Gatecrasher") == lobby and serverOf(c, "NoData") == lobby
			end, 10, "strangers back in the lobby")
			expect(serverOf(c, "Ann")).toBe(run)
		end)
	end)

	it("starts with whoever arrived once ArrivalTimeoutSeconds is up", function()
		local c = newCloud()
		local code = "code-manual"
		table.insert(c.reservations, { code = code })
		local run = c:start("Run", code) -- starting a server reads files, so not inside run
		c:run(function()
			local Handoff = run.load("ReplicatedStorage.Shared.Handoff")
			local data = Handoff.make("crew-1", "Public", { 7001, 7002, 7003 })
			run.engine:addPlayer("Ann", { userId = 7001, joinData = { TeleportData = data } })
			local arrivedAt = c.now
			c:waitUntil(function()
				return stops(c, "Ann") > 0
			end, 30, "the run to start")
			expect(c.now - arrivedAt).toBeNear(run.Config.Places.ArrivalTimeoutSeconds, 2)
		end)
	end)

	it("keeps the crew together for the next run, and sends leavers back to the lobby place", function()
		local c = newCloud()
		local lobby = c:lobby()
		c:run(function()
			local friends = joinAll(c, lobby, { "Ann", "Amy" })
			waitForBoarding(c, lobby, "Private")
			board(c, lobby, "Private", friends)
			c:waitUntil(function()
				return stops(c, "Ann") > 0
			end, 60, "the run to start")
			local run = serverOf(c, "Ann")
			-- The whole run (3 short stops), then "Next run in 5..." on the same server.
			c:waitUntil(function()
				local world, ann = c:find("Ann")
				for _, m in world.engine:hudMessages(ann, "Queue") do
					if m.data.requeue then
						return true
					end
				end
				return false
			end, 300, "the requeue countdown")
			expect(serverOf(c, "Ann")).toBe(run)
			expect(serverOf(c, "Amy")).toBe(run)

			local _, amy = c:find("Amy")
			local leave = run.find("ReplicatedStorage"):FindFirstChild("LeaveCrew", true)
			leave.OnServerEvent:Fire(amy)
			c:waitUntil(function()
				return serverOf(c, "Amy") == lobby
			end, 10, "Amy back in the lobby")
			expect(serverOf(c, "Ann")).toBe(run)
		end)
	end)
end)

describe("Cross-server matchmaking: when things fail", function()
	it("falls back to a run on this server when MemoryStore is down", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.memoryStore = true
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			local satAt = c.now
			c:waitUntil(function()
				return #lobby.engine:hudMessages(ann, "Stop") > 0
			end, 60, "a local run")
			expect(c.now - satAt).toBeGreaterThanOrEqual(lobby.Config.Matchmaking.LocalFallbackSeconds)
			expect(serverOf(c, "Ann")).toBe(lobby)
			expect(#c.teleports).toBe(0)
			expect(hasWarning(c, "could not queue")).toBe(true)
		end)
	end)

	it("retries a crew whose run server could not be reserved", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.reserve = true
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			c:wait(lobby.Config.Matchmaking.PublicWaitSeconds + 3)
			expect(hasWarning(c, "could not start a crew")).toBe(true)
			expect(#c:queued(QUEUE)).toBe(1) -- the ticket went back in the queue
			c.faults.reserve = false
			c:waitUntil(function()
				return serverOf(c, "Ann").kind == "Run"
			end, 10, "the retry")
		end)
	end)

	it("sends Private riders back to the hub when no server can be reserved", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.reserve = true
		c:run(function()
			local friends = joinAll(c, lobby, { "Ann", "Amy" })
			waitForBoarding(c, lobby, "Private")
			board(c, lobby, "Private", friends)
			c:waitUntil(function()
				return #lobby.engine:hudMessages(friends[1], "QueueClear") > 0
			end, 60, "Ann back at the hub")
			c:wait(0.5)
			expect(hasWarning(c, "could not reserve")).toBe(true)
			for _, player in friends do
				expect(seated(player)).toBe(false)
				expect(serverOf(c, player.Name)).toBe(lobby)
			end
		end)
	end)

	it("sends riders back to the hub when the teleport call fails", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.teleport = true
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			c:waitUntil(function()
				return #lobby.engine:hudMessages(ann, "QueueClear") > 0
			end, 30, "Ann back at the hub")
			c:wait(0.5)
			expect(hasWarning(c, "teleport failed")).toBe(true)
			expect(serverOf(c, "Ann")).toBe(lobby)
			expect(seated(ann)).toBe(false)
		end)
	end)

	it("sends riders back to the hub when the teleport fails after it started", function()
		local c = newCloud()
		local lobby = c:lobby()
		c.faults.teleportInit = true
		c:run(function()
			local ann = c:join(lobby, "Ann")
			waitForBoarding(c, lobby, "Public", 11)
			board(c, lobby, "Public", { ann })
			c:waitUntil(function()
				return #lobby.engine:hudMessages(ann, "QueueClear") > 0
			end, 30, "Ann back at the hub")
			expect(hasWarning(c, "could not teleport")).toBe(true)
			expect(serverOf(c, "Ann")).toBe(lobby)
		end)
	end)

	it("retries the crew when the announcement can't be published", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c.faults.publish = true
		c:run(function()
			local ann, bo = c:join(a, "Ann"), c:join(b, "Bo")
			waitForBoarding(c, a, "Public", 11)
			board(c, a, "Public", { ann })
			board(c, b, "Public", { bo })
			c:wait(a.Config.Matchmaking.PublicWaitSeconds + 3)
			expect(hasWarning(c, "could not start a crew")).toBe(true)
			expect(serverOf(c, "Ann")).toBe(a) -- nobody left without the others hearing
			c.faults.publish = false
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Bo" }) ~= nil
			end, 10, "the retry")
		end)
	end)

	it("a lobby server that can't subscribe runs its riders locally after the fallback wait", function()
		local c = newCloud()
		local a = c:lobby()
		c.faults.subscribe = true
		local b = c:lobby()
		c.faults.subscribe = false
		c:run(function()
			local ann, bo = c:join(a, "Ann"), c:join(b, "Bo")
			waitForBoarding(c, a, "Public", 11)
			board(c, a, "Public", { ann })
			board(c, b, "Public", { bo })
			c:waitUntil(function()
				return #b.engine:hudMessages(bo, "Stop") > 0
			end, 60, "Bo's local run")
			expect(hasWarning(c, "could not subscribe")).toBe(true)
			expect(serverOf(c, "Bo")).toBe(b)
			expect(serverOf(c, "Ann").kind).toBe("Run")
		end)
	end)

	it("ignores duplicate and malformed crew announcements", function()
		local c = newCloud()
		local a, b = c:lobby(), c:lobby()
		c:run(function()
			local ann, bo = c:join(a, "Ann"), c:join(b, "Bo")
			waitForBoarding(c, a, "Public", 11)
			board(c, a, "Public", { ann })
			board(c, b, "Public", { bo })
			c:waitUntil(function()
				return inRunServer(c, { "Ann", "Bo" }) ~= nil
			end, 30, "the crew")
			local sent = #c.teleports
			local message = topicMessages(c)[1].data
			local messaging = b.engine:service("MessagingService")
			for _, junk in { message, "nonsense", { code = 5 }, { code = "x", data = { v = 99 } } } do
				messaging:PublishAsync(TOPIC, junk)
			end
			c:wait(2)
			expect(#c.teleports).toBe(sent)
			expect(#c:_errors()).toBe(0)
		end)
	end)
end)
