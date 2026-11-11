--[[
	Sleigh Station lobby: riders go into the game queue the moment they sit in
	a station sleigh (Josh, 11 Nov 2026). The sleigh's takeoff is only an
	animation; nobody waits for it.

	Station (bays, gates, seating) calls back here.
	  Public   each rider is queued on their own as they sit down.
	  Party    the riders are held together while friends climb in (they
	           already see "in the queue"), then queued as one group that is
	           topped up with randoms (PartyGather: full sleigh, every friend
	           aboard, nobody new for Config.Lobby.GatherSeconds, or takeoff).
	  Private  held together the same way, then off to their own run (bots
	           fill the empty seats).
	Every step is confirmed on screen (Hud "Queue" + "Banner"). Hopping off
	the sleigh, Leave queue or leaving the game takes a rider out.

	Once both places are published (Matchmaker.enabled) the queue is the
	shared cross-server one; until then, in Studio, the same rules run on this
	server's own list (Matchmaker.packLocal) and the crew runs here (the
	original greybox path). Anyone the shared queue hasn't placed within
	Config.Matchmaking.LocalFallbackSeconds also runs here. After a local run
	the crew is requeued together ("Next run in 5...").

	Not in yet: join-a-friend, drop-in at the next stop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CrewPacker = require(ReplicatedStorage.Shared.CrewPacker)
local PartyGather = require(ReplicatedStorage.Shared.PartyGather)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local Analytics = require(script.Parent.Analytics)
local Matchmaker = require(script.Parent.Matchmaker)
local Onboarding = require(script.Parent.Onboarding)
local Telemetry = require(script.Parent.Telemetry)
local Run = require(script.Parent.Run)
local Station = require(script.Parent.Station)

type Crew = {
	players: { Player },
	departAt: number,
	requeue: boolean,
	found: boolean, -- formed from the queue (not a requeue after a run)
	waiting: boolean,
	launching: boolean,
}

-- A Party or Private sleigh's riders, held together while friends climb in.
type Gathering = {
	bay: any,
	kind: string,
	players: { Player },
	startedAt: number,
	lastBoardAt: number,
}

local Lobby = {}

-- On-screen confirmations (the Hud shows them as a banner).
Lobby.Text = {
	Queued = "You're in the queue! Finding your crew... (jump to hop off)",
	Gathering = "You're in the queue! Waiting for your friends to climb in... (jump to hop off)",
	PrivateGathering = "Private sleigh! Waiting for your friends to climb in... (jump to hop off)",
	Found = "Crew found! Off to the street!",
	Left = "You hopped off. You're out of the queue.",
	Failed = "Couldn't reach the sleigh. Hop back on to try again!",
}

local crews: { Crew } = {}
local runsBySlot: { [number]: any } = {}
local runOf: { [Player]: any } = {}
local crewOf: { [Player]: Crew } = {}
local seated: { [Player]: boolean } = {} -- in a station sleigh seat (for LeftLobby)
local gatherings: { [any]: Gathering } = {} -- by bay
local gatheringOf: { [Player]: Gathering } = {}
local lastParty: { [any]: { Player } } = {} -- the group a Party bay queued this boarding, for late friends
local friendsOf: { [Player]: { [number]: boolean } } = {}
local hud: RemoteEvent
local hubSpawn: CFrame

local function send(player: Player, kind: string, data: any)
	if player.Parent == Players then
		hud:FireClient(player, kind, data)
	end
end

local function banner(player: Player, text: string)
	send(player, "Banner", { text = text, seconds = 3 })
end

local function sendCrew(crew: Crew)
	local data = {
		state = if crew.found then "Found" else nil,
		departAt = crew.departAt,
		count = #crew.players,
		requeue = crew.requeue,
		waiting = crew.waiting,
	}
	for _, player in crew.players do
		send(player, "Queue", data)
	end
end

-- "In the queue, finding your crew" for players waiting on a ticket.
local function sendSearching(players: { Player })
	for _, player in players do
		send(player, "Queue", {
			state = "Searching",
			kind = Matchmaker.queued(player),
			since = Matchmaker.queuedSince(player) or Util.now(),
			count = #players,
		})
	end
end

local function sendGathering(g: Gathering)
	for _, player in g.players do
		send(player, "Queue", {
			state = "Gathering",
			kind = g.kind,
			since = g.startedAt,
			count = #g.players,
		})
	end
end

local function newCrew(delay: number, requeue: boolean): Crew
	local crew = {
		players = {},
		departAt = Util.now() + delay,
		requeue = requeue,
		found = false,
		waiting = false,
		launching = false,
	}
	table.insert(crews, crew)
	return crew
end

local function freeSlot(): number?
	for slot = 1, Config.Lobby.MaxRunsPerServer do
		if not runsBySlot[slot] then
			return slot
		end
	end
	return nil
end

-- Takes a player out of a local crew that hasn't launched. True if they were in one.
local function leaveLocalCrew(player: Player): boolean
	local crew = crewOf[player]
	if not crew or crew.launching then
		return false
	end
	crewOf[player] = nil
	Util.removeValue(crew.players, player)
	if #crew.players == 0 then
		Util.removeValue(crews, crew)
	else
		sendCrew(crew)
	end
	return true
end

-- Takes a player out of a Party/Private sleigh's group. True if they were in one.
local function leaveGathering(player: Player): boolean
	local g = gatheringOf[player]
	if not g then
		return false
	end
	gatheringOf[player] = nil
	Util.removeValue(g.players, player)
	if #g.players == 0 then
		if gatherings[g.bay] == g then
			gatherings[g.bay] = nil
		end
	else
		sendGathering(g)
	end
	return true
end

local function forgetParty(player: Player)
	for _, group in lastParty do
		Util.removeValue(group, player)
	end
end

local function onRunFinished(run, survivors: { Player })
	runsBySlot[run.slot] = nil
	local crew = newCrew(Config.Run.RequeueSeconds, true)
	for i, player in survivors do
		runOf[player] = nil
		Util.teleport(player, hubSpawn * CFrame.new((i - 1) * 4, 0, 0))
		table.insert(crew.players, player)
		crewOf[player] = crew
	end
	sendCrew(crew)
end

-- Builds the route over a few frames, then starts the run.
local function launch(crew: Crew, slot: number)
	crew.launching = true
	runsBySlot[slot] = true -- reserved while building
	for _, player in crew.players do
		Station.release(player)
	end
	task.spawn(function()
		local ok, run = pcall(Run.new, slot, crew.players, onRunFinished)
		Util.removeValue(crews, crew)
		if not ok then
			warn("[Lobby] failed to build a route: " .. tostring(run))
			runsBySlot[slot] = nil
			for _, player in crew.players do
				crewOf[player] = nil
				send(player, "QueueClear", {})
			end
			return
		end
		runsBySlot[slot] = run
		for _, player in table.clone(crew.players) do
			crewOf[player] = nil
			if run:hasPlayer(player) and player.Parent == Players then
				runOf[player] = run
				send(player, "QueueClear", {})
			else
				run:removePlayer(player) -- left while the route was building
			end
		end
		run:start()
	end)
end

-- A crew formed on this server leaves now (same-server queue or fallback).
local function departLocally(players: { Player })
	local crew = newCrew(0, false)
	crew.found = true
	for _, player in players do
		if player.Parent == Players and not runOf[player] and not crewOf[player] then
			Matchmaker.cancel(player)
			leaveGathering(player)
			table.insert(crew.players, player)
			crewOf[player] = crew
		end
	end
	if #crew.players == 0 then
		Util.removeValue(crews, crew)
		return
	end
	Analytics.crewFound(crew.players)
	for _, player in crew.players do
		banner(player, Lobby.Text.Found)
	end
	sendCrew(crew)
end

-- A teleport or reservation gave up: back to the hub, out of the queue.
local function backToHub(players: { Player })
	for i, player in players do
		Matchmaker.cancel(player)
		leaveGathering(player)
		forgetParty(player)
		Station.release(player)
		if player.Parent == Players then
			Util.teleport(player, hubSpawn * CFrame.new((i - 1) * 4, 0, 0))
			send(player, "QueueClear", {})
			banner(player, Lobby.Text.Failed)
		end
	end
end

-- Cross-server: this server's riders of a crew are about to teleport.
local function onFound(players: { Player })
	for _, player in players do
		forgetParty(player)
		banner(player, Lobby.Text.Found)
		send(player, "Queue", { state = "Found", count = #players })
	end
end

-- Roblox friends, loaded once when a player joins (a web call: yields, can fail).
local function loadFriends(player: Player)
	local set: { [number]: boolean } = {}
	friendsOf[player] = set
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(player.UserId)
	end)
	if not ok then
		warn("[Lobby] could not load friends: " .. tostring(pages))
		return
	end
	for _ = 1, 10 do -- Roblox caps friends lists; 10 pages covers it
		for _, friend in pages:GetCurrentPage() do
			set[friend.Id] = true
		end
		if pages.IsFinished or not pcall(pages.AdvanceToNextPageAsync, pages) then
			break
		end
	end
end

local function areFriends(a: Player, b: Player): boolean
	local fa, fb = friendsOf[a], friendsOf[b]
	return (fa ~= nil and fa[b.UserId] == true) or (fb ~= nil and fb[a.UserId] == true)
end

-- Players in the lobby who could still climb into a sleigh.
local function stillInLobby(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if
			not runOf[player]
			and not crewOf[player]
			and not gatheringOf[player]
			and not Matchmaker.queued(player)
			and not Station.isAboard(player)
		then
			table.insert(out, player)
		end
	end
	return out
end

-- Hands a Party or Private group to the matchmaker.
local function submit(g: Gathering, reason: string)
	if gatherings[g.bay] == g then
		gatherings[g.bay] = nil
	end
	local players = {}
	for _, player in g.players do
		if gatheringOf[player] == g then
			gatheringOf[player] = nil
			if player.Parent == Players then
				table.insert(players, player)
			end
		end
	end
	if #players == 0 then
		return
	end
	Telemetry.count("MatchGroupQueued", g.kind .. " " .. reason, #players)
	if g.kind == "Party" then
		Matchmaker.enqueueParty(players)
		lastParty[g.bay] = table.clone(players)
		sendSearching(players)
	elseif Matchmaker.enabled() then
		Matchmaker.sendPrivate(players)
		onFound(players)
	else
		departLocally(players)
	end
end

-- A friend climbing into a Party sleigh just after their group was queued
-- joins it again, as long as none of the group has been picked yet.
local function reopenParty(bay): { Player }?
	local group = lastParty[bay]
	if not group or #group == 0 then
		return nil
	end
	for _, player in group do
		if player.Parent == Players and Matchmaker.queued(player) ~= "Party" then
			return nil -- already on their way
		end
	end
	lastParty[bay] = nil
	local out = {}
	for _, player in group do
		if player.Parent == Players then
			Matchmaker.cancel(player)
			table.insert(out, player)
		end
	end
	return out
end

local function joinGathering(bay, player: Player)
	local now = Util.now()
	local g = gatherings[bay]
	if not g then
		g = { bay = bay, kind = bay.kind, players = {}, startedAt = now, lastBoardAt = now }
		gatherings[bay] = g
		if bay.kind == "Party" then
			for _, friend in reopenParty(bay) or {} do
				table.insert(g.players, friend)
				gatheringOf[friend] = g
			end
		end
	end
	local gathering = g :: Gathering
	table.insert(gathering.players, player)
	gatheringOf[player] = gathering
	gathering.lastBoardAt = now
	banner(player, if bay.kind == "Private" then Lobby.Text.PrivateGathering else Lobby.Text.Gathering)
	sendGathering(gathering)
end

local stationHandlers = {
	seated = function(bay, player: Player)
		if runOf[player] then
			return -- mid-run (same-server runs share the place with the station)
		end
		Onboarding.complete(player, "Board")
		seated[player] = true
		Analytics.boarded(player)
		leaveLocalCrew(player) -- walked onto a sleigh while their old crew counted down
		if bay.kind == "Public" then
			-- Already waiting on a Public ticket (dropped back on the platform
			-- after a takeoff): keep their place in the queue.
			if Matchmaker.queued(player) ~= "Public" then
				Matchmaker.cancel(player)
				Matchmaker.enqueue("Public", { player })
			end
			banner(player, Lobby.Text.Queued)
			sendSearching({ player })
		else
			Matchmaker.cancel(player)
			forgetParty(player)
			joinGathering(bay, player)
		end
	end,
	unseated = function(_bay, player: Player)
		seated[player] = nil
		local wasQueued = Matchmaker.queued(player) ~= nil
		local wasGathering = leaveGathering(player)
		local wasInCrew = leaveLocalCrew(player)
		forgetParty(player)
		Matchmaker.cancel(player)
		if wasQueued or wasGathering or wasInCrew then
			Telemetry.count("MatchQueueLeft", "HopOff")
			if player.Parent == Players then
				send(player, "QueueClear", {})
				banner(player, Lobby.Text.Left)
			end
		end
	end,
	-- Takeoff is an animation: Public riders are queued already, and a Party
	-- or Private group still waiting for friends goes now.
	depart = function(bay, _riders: { Player })
		local g = gatherings[bay]
		if g then
			submit(g, "Takeoff")
		end
		lastParty[bay] = nil
	end,
}

-- What a player was doing in the lobby, for LeftLobby (fixed labels only).
local function doing(player: Player): string
	if crewOf[player] then
		return "Crew leaving"
	elseif Matchmaker.queued(player) or gatheringOf[player] then
		return "Queued for a crew"
	elseif seated[player] then
		return "Sitting in a sleigh"
	end
	return "Exploring"
end

-- The local run a player is in (tests check crews stay together).
function Lobby.runOf(player: Player): any?
	return runOf[player]
end

function Lobby.leave(player: Player, leftGame: boolean?)
	if leftGame then
		local run = runOf[player]
		if run then
			local st = run.players[player]
			Analytics.leftRun(player, run, "Quit the game", st and st.jingle)
		else
			Analytics.leftLobby(player, doing(player))
		end
		seated[player] = nil
	end
	local wasQueued = Matchmaker.queued(player) ~= nil
	local wasGathering = leaveGathering(player)
	forgetParty(player)
	Matchmaker.cancel(player)
	Station.release(player)
	local wasInCrew = leaveLocalCrew(player)
	if wasQueued or wasGathering or wasInCrew then
		Telemetry.count("MatchQueueLeft", if leftGame then "LeftGame" else "Button")
		if not leftGame then
			send(player, "QueueClear", {})
		end
	end
	if leftGame then
		friendsOf[player] = nil
	end

	local run = runOf[player]
	if run then
		runOf[player] = nil
		run:removePlayer(player)
		if not leftGame then
			Util.teleport(player, hubSpawn)
		end
	end
end

local function tick()
	local t = Util.now()
	-- Party and Private sleighs: send each group once its friends are in.
	if next(gatherings) then
		local lobby = stillInLobby()
		for _, g in table.clone(gatherings) do
			local reason = PartyGather.ready(g.players, g.lastBoardAt, t, lobby, areFriends)
			if reason then
				submit(g, reason)
			end
		end
	end
	-- Same-server queue (places not published).
	for _, crew in Matchmaker.packLocal(t) do
		departLocally(crew)
	end
	-- Shared queue not answering: run here.
	for _, crew in CrewPacker.fit(Matchmaker.overdue(t), Config.Lobby.CrewMax) do
		Telemetry.count("MatchLocalFallback", nil, #crew)
		departLocally(crew)
	end
	for _, crew in table.clone(crews) do
		if crew.launching then
			continue
		elseif #crew.players == 0 then
			Util.removeValue(crews, crew)
		elseif t >= crew.departAt or #crew.players >= Config.Lobby.CrewMax then
			local slot = freeSlot()
			if slot then
				launch(crew, slot)
			elseif not crew.waiting then
				crew.waiting = true -- every street is busy; leave as soon as one frees up
				sendCrew(crew)
			end
		end
	end
end

-- First-time players: a trail from the workshop to the Public bay.
local function teachBoarding(hub, player: Player)
	local publicBay = nil
	for _, bay in hub.bays or {} do
		if bay.kind == "Public" then
			publicBay = bay
			break
		end
	end
	for _ = 1, 20 do -- tips progress loads in the background
		if Onboarding.state(player) or player.Parent ~= Players then
			break
		end
		task.wait(0.5)
	end
	if publicBay and not runOf[player] and not crewOf[player] then
		Onboarding.teach(player, "Board", publicBay.zone.Position)
	end
end

function Lobby.start(hub)
	hud = Remotes.get("Hud")
	hubSpawn = hub.spawn

	local function watch(player: Player)
		task.spawn(loadFriends, player)
		player.CharacterAdded:Connect(function()
			task.spawn(teachBoarding, hub, player)
		end)
		if player.Character then
			task.spawn(teachBoarding, hub, player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Station.start(hub, stationHandlers)
	if Matchmaker.enabled() then
		Matchmaker.start(backToHub, onFound)
	end

	Remotes.get("LeaveCrew").OnServerEvent:Connect(function(player)
		Lobby.leave(player)
	end)

	Remotes.get("Input").OnServerEvent:Connect(function(player, action)
		local run = runOf[player]
		if run and typeof(action) == "string" then
			run:onInput(player, action)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		Lobby.leave(player, true)
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Lobby] tick failed: " .. tostring(err))
			end
		end
	end)
end

return Lobby
