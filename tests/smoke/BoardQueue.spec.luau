--[[
	"As soon as they get in the sleigh, put them in the game queue" (Josh,
	11 Nov 2026). The sleigh's takeoff is only an animation. Single-server
	lobby (Main.server in one headless world, same-server queue); the
	cross-server side is in CrossServer.spec.

	Public riders queue the moment they sit. Party and Private riders are in
	the queue on their screens straight away, and the group goes to the
	matchmaker once every friend is aboard, the sleigh is full, nobody new
	has climbed in for GatherSeconds, or the sleigh takes off.
]]

local BAY_NUMBER = { Public = 1, Party = 2, Private = 3 }

local function fastRuns(Config)
	Config.Run.StopSeconds = 24
	Config.Run.LightsOnAt = 6
	Config.Run.HornAt = 12
	Config.Run.ResultsSeconds = 2
end

local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 120)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function messages(engine, player, kind)
	return engine:hudMessages(player, kind)
end

local function last(engine, player, kind)
	local list = messages(engine, player, kind)
	return list[#list] and list[#list].data
end

local function count(engine, player, kind)
	return #messages(engine, player, kind)
end

local function bannered(engine, player, text: string): boolean
	for _, m in messages(engine, player, "Banner") do
		if m.data.text == text then
			return true
		end
	end
	return false
end

local function inRun(engine, player): boolean
	return count(engine, player, "Stop") > 0
end

local function seated(player): boolean
	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

local function boot(configure: ((Config: any) -> ())?)
	local world = headless()
	local engine = world.engine
	local Config = world.load("ReplicatedStorage.Shared.Config")
	fastRuns(Config)
	if configure then
		configure(Config)
	end
	world.run(function()
		world.runScript("ServerScriptService.Server.Main")
		world.wait(0.5)
	end)
	return world, engine, Config, world.load("ServerScriptService.Server.Lobby")
end

local function phase(world, kind: string)
	return world
		.load("ReplicatedStorage.Shared.StationClock")
		.phaseAt(kind, BAY_NUMBER[kind], world.engine.now)
end

local function waitForBoarding(world, kind: string, left: number?)
	waitUntil(world, function()
		local p = phase(world, kind)
		return p.name == "Boarding" and p.endsAt - world.engine.now >= (left or 4)
	end, 200, kind .. " boarding")
end

-- Walks players into a bay's board zone and waits until they have sat down
-- (a crew can form and whisk them off before the next check).
local function walkOn(world, kind: string, players: { any })
	local engine = world.engine
	local zone = engine.workspace:FindFirstChild(kind .. "Zone", true)
	assert(zone, "no " .. kind .. " board zone")
	local before = {}
	for _, player in players do
		before[player] = count(engine, player, "Banner")
		engine:teleport(player, zone.Position + Vector3.new(0, 3, 0))
	end
	waitUntil(world, function()
		for _, player in players do
			if not seated(player) and count(engine, player, "Banner") == before[player] then
				return false
			end
		end
		return true
	end, 5, "riders to sit down")
end

-- Jump: the Santa gets up out of the sleigh seat.
local function hopOff(player)
	player.Character.Humanoid.Jump = true
end

-- Everyone is in the same run on this server.
local function sameRun(world, players: { any }): boolean
	local Lobby = world.load("ServerScriptService.Server.Lobby")
	local run = Lobby.runOf(players[1])
	if not run then
		return false
	end
	for _, p in players do
		if Lobby.runOf(p) ~= run then
			return false
		end
	end
	return true
end

describe("queue the moment you board (Josh, 11 Nov)", function()
	it("a Public rider is queued and told so the moment they sit, long before takeoff", function()
		local world, engine, Config, Lobby = boot(function(Config)
			Config.LobbyMap.BoardSeconds.Public = 40 -- takeoff is a long way off
		end)
		world.run(function()
			local a = engine:addPlayer("A")
			waitForBoarding(world, "Public", 30)
			local takeoff = phase(world, "Public").endsAt
			walkOn(world, "Public", { a })
			world.wait(0.2)
			expect(bannered(engine, a, Lobby.Text.Queued)).toBe(true)
			local q = last(engine, a, "Queue")
			expect(q.state).toBe("Searching")
			expect(q.kind).toBe("Public")
			expect(q.since).toBeNear(engine.now, 1)
			waitUntil(world, function()
				return inRun(engine, a)
			end, 20, "the run")
			expect(engine.now).toBeLessThan(takeoff) -- nobody waited for the sleigh
			expect(bannered(engine, a, Lobby.Text.Found)).toBe(true)
		end)
	end)

	it("keeps the takeoff animation: the sleigh still leaves on its timetable", function()
		local world, engine = boot(function(Config)
			Config.Matchmaking.PublicWaitSeconds = 20 -- still waiting when the sleigh goes
		end)
		world.run(function()
			local a = engine:addPlayer("A")
			waitForBoarding(world, "Public", 4)
			walkOn(world, "Public", { a })
			local sleigh = nil
			for _, d in engine.workspace:GetDescendants() do
				if
					d.Name == "StationSleigh"
					and (d:GetPivot().Position - a.Character.HumanoidRootPart.Position).Magnitude < 40
				then
					sleigh = d
				end
			end
			expect(sleigh).never.toBeNil()
			local home = sleigh:GetPivot().Position
			waitUntil(world, function()
				return phase(world, "Public").name == "Departing"
			end, 20, "takeoff")
			world.wait(2)
			expect((sleigh:GetPivot().Position - home).Magnitude).toBeGreaterThan(5) -- it flies off
			-- Dropped back on the platform, still in the queue.
			waitUntil(world, function()
				return phase(world, "Public").name == "Away"
			end, 10, "the sleigh to be gone")
			world.wait(0.3)
			expect(seated(a)).toBe(false)
			expect(last(engine, a, "Queue").state).toBe("Searching")
			expect(count(engine, a, "QueueClear")).toBe(0)
			waitUntil(world, function()
				return inRun(engine, a)
			end, 30, "the run")
		end)
	end)

	it("climbing back onto a Public sleigh while still queued keeps your place", function()
		local world, engine = boot(function(Config)
			Config.Matchmaking.PublicWaitSeconds = 60
		end)
		world.run(function()
			local a = engine:addPlayer("A")
			waitForBoarding(world, "Public", 4)
			walkOn(world, "Public", { a })
			local since = last(engine, a, "Queue").since
			waitUntil(world, function()
				return phase(world, "Public").name == "Away"
			end, 30, "the sleigh to be gone")
			waitForBoarding(world, "Public", 2)
			walkOn(world, "Public", { a })
			world.wait(0.2)
			expect(last(engine, a, "Queue").since).toBe(since)
		end)
	end)

	it("hopping off takes you out of the queue, with a message", function()
		local world, engine, Config, Lobby = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			waitForBoarding(world, "Public", 10)
			walkOn(world, "Public", { a })
			world.wait(1)
			hopOff(a)
			engine:teleport(a, Config.Map.HubSpawn.Position)
			world.wait(0.5)
			expect(bannered(engine, a, Lobby.Text.Left)).toBe(true)
			expect(count(engine, a, "QueueClear")).toBe(1)
			world.wait(Config.Matchmaking.PublicWaitSeconds + 5)
			expect(inRun(engine, a)).toBe(false)
		end)
	end)

	it("a Santa who walks onto a sleigh while their old crew counts down isn't in two crews", function()
		local world, engine, Config = boot(function(Config)
			Config.Run.RequeueSeconds = 30
		end)
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			waitForBoarding(world, "Public", 8)
			walkOn(world, "Public", { a, b })
			waitUntil(world, function()
				local q = last(engine, a, "Queue")
				return q ~= nil and q.requeue == true
			end, 300, "the requeue after the run")
			-- A wanders off and boards a fresh Public sleigh instead.
			waitForBoarding(world, "Public", 4)
			walkOn(world, "Public", { a })
			world.wait(0.3)
			expect(last(engine, b, "Queue").count).toBe(1) -- B's crew lost A
			expect(last(engine, a, "Queue").state).toBe("Searching")
			local runsBefore = count(engine, a, "RunEnd")
			waitUntil(world, function()
				return count(engine, a, "Stop") > 0
					and last(engine, a, "Stop").stop ~= nil
					and count(engine, a, "QueueClear") >= 2
			end, 30, "A's new run")
			expect(count(engine, a, "RunEnd")).toBe(runsBefore)
		end)
	end)
end)

describe("Party sleighs hold friends together", function()
	it("queues two friends the moment both are aboard, without waiting for takeoff", function()
		local world, engine, Config = boot()
		world.run(function()
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			engine:addPlayer("Stranger") -- not a friend: nobody waits for them
			waitForBoarding(world, "Party", 15)
			local takeoff = phase(world, "Party").endsAt
			walkOn(world, "Party", { ann })
			world.wait(0.6)
			expect(last(engine, ann, "Queue").state).toBe("Gathering") -- Amy is still in the lobby
			world.wait(2)
			expect(last(engine, ann, "Queue").state).toBe("Gathering")
			walkOn(world, "Party", { amy })
			world.wait(0.6)
			expect(engine.now).toBeLessThan(takeoff - 5)
			waitUntil(world, function()
				return inRun(engine, ann) and inRun(engine, amy)
			end, 10, "the party's run")
			expect(sameRun(world, { ann, amy })).toBe(true)
			expect(engine.now).toBeLessThan(takeoff)
			expect(last(engine, ann, "Player")).never.toBeNil()
			expect(Config.Lobby.GatherSeconds).toBeGreaterThan(0)
		end)
	end)

	it("waits for a friend who is still in the lobby, then leaves together", function()
		local world, engine = boot()
		world.run(function()
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			local bo = engine:addPlayer("Bo", { friends = { ann } })
			waitForBoarding(world, "Party", 16)
			walkOn(world, "Party", { ann, amy })
			world.wait(3) -- Bo, a friend of Ann's, is still in the lobby
			expect(last(engine, ann, "Queue").state).toBe("Gathering")
			expect(last(engine, ann, "Queue").count).toBe(2)
			walkOn(world, "Party", { bo })
			waitUntil(world, function()
				return inRun(engine, ann) and inRun(engine, bo)
			end, 10, "the party's run")
			expect(sameRun(world, { ann, amy, bo })).toBe(true)
		end)
	end)

	it("a group of non-friends goes once nobody new has climbed in for GatherSeconds", function()
		local world, engine, Config = boot()
		world.run(function()
			local a = engine:addPlayer("A")
			local b = engine:addPlayer("B")
			waitForBoarding(world, "Party", 16)
			walkOn(world, "Party", { a })
			world.wait(2)
			walkOn(world, "Party", { b })
			local lastBoard = engine.now
			waitUntil(world, function()
				return last(engine, a, "Queue").state ~= "Gathering"
			end, 15, "the group to be queued")
			expect(engine.now - lastBoard).toBeGreaterThanOrEqual(Config.Lobby.GatherSeconds - 0.6)
			waitUntil(world, function()
				return inRun(engine, a) and inRun(engine, b)
			end, 10, "their run")
			expect(sameRun(world, { a, b })).toBe(true)
		end)
	end)

	it("a full Party sleigh goes at once", function()
		local world, engine, Config = boot(function(Config)
			Config.Lobby.GatherSeconds = 60
		end)
		world.run(function()
			local crew = {}
			for i = 1, Config.Lobby.CrewMax do
				crew[i] = engine:addPlayer("P" .. i)
			end
			waitForBoarding(world, "Party", 12)
			walkOn(world, "Party", crew)
			local fullAt = engine.now
			waitUntil(world, function()
				return inRun(engine, crew[1])
			end, 5, "the full party's run")
			expect(engine.now - fullAt).toBeLessThan(3)
			expect(sameRun(world, crew)).toBe(true)
		end)
	end)

	it("takeoff sends a group still waiting for friends", function()
		local world, engine = boot(function(Config)
			Config.Lobby.GatherSeconds = 60
		end)
		world.run(function()
			local ann = engine:addPlayer("Ann")
			engine:addPlayer("Amy", { friends = { ann } }) -- never boards
			waitForBoarding(world, "Party", 4)
			walkOn(world, "Party", { ann })
			local takeoff = phase(world, "Party").endsAt
			waitUntil(world, function()
				return inRun(engine, ann)
			end, 40, "Ann's run")
			expect(engine.now).toBeGreaterThanOrEqual(takeoff)
		end)
	end)

	it("tops up a Party group with a Public rider who is waiting", function()
		local world, engine = boot()
		world.run(function()
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			local bo = engine:addPlayer("Bo")
			waitUntil(world, function()
				local party, public = phase(world, "Party"), phase(world, "Public")
				return party.name == "Boarding"
					and public.name == "Boarding"
					and party.endsAt - world.engine.now > 4
					and public.endsAt - world.engine.now > 4
			end, 200, "Public and Party boarding together")
			walkOn(world, "Public", { bo })
			walkOn(world, "Party", { ann, amy })
			waitUntil(world, function()
				return inRun(engine, ann) and inRun(engine, bo)
			end, 10, "the topped-up crew")
			expect(sameRun(world, { ann, amy, bo })).toBe(true)
		end)
	end)

	it("a friend hopping off is out of the group, and the rest go without them", function()
		local world, engine, Config, Lobby = boot()
		world.run(function()
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			local bo = engine:addPlayer("Bo", { friends = { ann, amy } })
			waitForBoarding(world, "Party", 18)
			walkOn(world, "Party", { ann, amy })
			world.wait(1)
			expect(last(engine, ann, "Queue").state).toBe("Gathering") -- Bo is still in the lobby
			hopOff(amy) -- Amy changes her mind
			world.wait(0.5)
			expect(seated(amy)).toBe(false)
			expect(bannered(engine, amy, Lobby.Text.Left)).toBe(true)
			expect(last(engine, ann, "Queue").count).toBe(1)
			walkOn(world, "Party", { bo })
			local boardedAt = engine.now
			-- Amy might climb back in, so the group gives her GatherSeconds.
			waitUntil(world, function()
				return inRun(engine, ann)
			end, Config.Lobby.GatherSeconds + 4, "the party's run")
			expect(engine.now - boardedAt).toBeGreaterThanOrEqual(Config.Lobby.GatherSeconds - 0.6)
			expect(sameRun(world, { ann, bo })).toBe(true)
			expect(inRun(engine, amy)).toBe(false)
		end)
	end)

	it("a friend leaving the game while the group waits doesn't strand anyone", function()
		local world, engine = boot()
		world.run(function()
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			local bo = engine:addPlayer("Bo", { friends = { ann } })
			waitForBoarding(world, "Party", 16)
			walkOn(world, "Party", { ann, amy })
			world.wait(1)
			engine:removePlayer(bo) -- the friend they were waiting for left
			waitUntil(world, function()
				return inRun(engine, ann) and inRun(engine, amy)
			end, 10, "the party's run")
			engine:removePlayer(amy)
			world.wait(1)
			expect(inRun(engine, ann)).toBe(true)
		end)
	end)

	it("falls back to the GatherSeconds wait when Roblox can't load friends", function()
		local world, engine, Config = boot()
		world.run(function()
			engine.friendsDown = true
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			waitForBoarding(world, "Party", 16)
			walkOn(world, "Party", { ann, amy })
			local satAt = engine.now
			waitUntil(world, function()
				return inRun(engine, ann) and inRun(engine, amy)
			end, 15, "the party's run")
			expect(engine.now - satAt).toBeGreaterThanOrEqual(Config.Lobby.GatherSeconds - 0.6)
			expect(sameRun(world, { ann, amy })).toBe(true)
			local warned = false
			for _, w in engine.warnings do
				if string.find(w, "could not load friends", 1, true) then
					warned = true
				end
			end
			expect(warned).toBe(true)
		end)
	end)

	it("Leave queue gets you off a Party sleigh and out of the group", function()
		local world, engine, _, _ = boot()
		world.run(function()
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			engine:addPlayer("Bo", { friends = { ann } }) -- keeps the group waiting
			waitForBoarding(world, "Party", 16)
			walkOn(world, "Party", { ann, amy })
			world.wait(0.5)
			world.load("ReplicatedStorage.Shared.Remotes").get("LeaveCrew").OnServerEvent:Fire(amy)
			world.wait(0.5)
			expect(seated(amy)).toBe(false)
			expect(last(engine, ann, "Queue").count).toBe(1)
			expect(count(engine, amy, "QueueClear")).toBe(1)
		end)
	end)
end)

describe("Private sleighs", function()
	it("friends go straight to their own run once both are aboard, with no randoms", function()
		local world, engine, _, Lobby = boot()
		world.run(function()
			local ann = engine:addPlayer("Ann")
			local amy = engine:addPlayer("Amy", { friends = { ann } })
			local bo = engine:addPlayer("Bo")
			waitUntil(world, function()
				local private, public = phase(world, "Private"), phase(world, "Public")
				return private.name == "Boarding"
					and public.name == "Boarding"
					and private.endsAt - world.engine.now > 6
					and public.endsAt - world.engine.now > 4
			end, 200, "Public and Private boarding together")
			local takeoff = phase(world, "Private").endsAt
			walkOn(world, "Public", { bo }) -- a random waiting for a crew
			walkOn(world, "Private", { ann })
			world.wait(0.3)
			expect(bannered(engine, ann, Lobby.Text.PrivateGathering)).toBe(true)
			expect(last(engine, ann, "Queue").kind).toBe("Private")
			walkOn(world, "Private", { amy })
			waitUntil(world, function()
				return inRun(engine, ann) and inRun(engine, amy)
			end, 5, "the Private run")
			expect(engine.now).toBeLessThan(takeoff)
			expect(sameRun(world, { ann, amy })).toBe(true)
			expect(inRun(engine, bo)).toBe(false) -- never pulled into a Private crew
		end)
	end)
end)
