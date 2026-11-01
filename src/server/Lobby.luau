--[[
	Sleigh Station lobby: what happens to riders when a station sleigh leaves.

	Station (bays, gates, seating) calls back here. Once both places are
	published (Matchmaker.enabled) riders go cross-server: Public riders queue
	the moment they sit down, a Party group queues when its sleigh leaves (and
	is topped up with randoms), a Private sleigh teleports straight to its own
	run server. Until then, in Studio, or when the queue has not formed a crew
	within Config.Matchmaking.LocalFallbackSeconds, the crew runs here in this
	server (the original greybox path). After a local run the crew is requeued
	together ("Next run in 5...").

	Not in yet: join-a-friend, drop-in at the next stop.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local Matchmaker = require(script.Parent.Matchmaker)
local Run = require(script.Parent.Run)
local Station = require(script.Parent.Station)

type Crew = {
	players: { Player },
	departAt: number,
	requeue: boolean,
	waiting: boolean,
	launching: boolean,
}

local Lobby = {}

local crews: { Crew } = {}
local runsBySlot: { [number]: any } = {}
local runOf: { [Player]: any } = {}
local crewOf: { [Player]: Crew } = {}
local hud: RemoteEvent
local hubSpawn: CFrame

local function send(player: Player, kind: string, data: any)
	if player.Parent == Players then
		hud:FireClient(player, kind, data)
	end
end

local function sendCrew(crew: Crew)
	local data = {
		departAt = crew.departAt,
		count = #crew.players,
		requeue = crew.requeue,
		waiting = crew.waiting,
	}
	for _, player in crew.players do
		send(player, "Queue", data)
	end
end

local function newCrew(delay: number, requeue: boolean): Crew
	local crew = {
		players = {},
		departAt = Util.now() + delay,
		requeue = requeue,
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

-- Same-server crew leaving now (local fallback).
local function departLocally(players: { Player })
	local crew = newCrew(0, false)
	for _, player in players do
		if player.Parent == Players and not runOf[player] and not crewOf[player] then
			Matchmaker.cancel(player)
			table.insert(crew.players, player)
			crewOf[player] = crew
		end
	end
	sendCrew(crew)
end

local function backToHub(players: { Player })
	for i, player in players do
		Matchmaker.cancel(player)
		Station.release(player)
		if player.Parent == Players then
			Util.teleport(player, hubSpawn * CFrame.new((i - 1) * 4, 0, 0))
			send(player, "QueueClear", {})
		end
	end
end

local stationHandlers = {
	seated = function(bay, player: Player)
		if bay.kind == "Public" and Matchmaker.enabled() then
			Matchmaker.enqueue("Public", { player })
		end
	end,
	unseated = function(_bay, player: Player)
		Matchmaker.cancel(player)
	end,
	depart = function(bay, riders: { Player })
		if #riders == 0 then
			return
		elseif not Matchmaker.enabled() then
			departLocally(riders)
		elseif bay.kind == "Party" then
			Matchmaker.enqueueParty(riders)
		elseif bay.kind == "Private" then
			Matchmaker.sendPrivate(riders)
		end
		-- Public riders are already queued (they queue when they sit down).
	end,
}

function Lobby.leave(player: Player, leftGame: boolean?)
	Matchmaker.cancel(player)
	Station.release(player)
	local crew = crewOf[player]
	if crew and not crew.launching then
		crewOf[player] = nil
		Util.removeValue(crew.players, player)
		if #crew.players == 0 then
			Util.removeValue(crews, crew)
		else
			sendCrew(crew)
		end
		if not leftGame then
			send(player, "QueueClear", {})
		end
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
	local overdue = Matchmaker.overdue(t)
	while #overdue > 0 do
		departLocally(table.move(overdue, 1, math.min(#overdue, Config.Lobby.CrewMax), 1, {}))
		for _ = 1, math.min(#overdue, Config.Lobby.CrewMax) do
			table.remove(overdue, 1)
		end
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

function Lobby.start(hub)
	hud = Remotes.get("Hud")
	hubSpawn = hub.spawn

	Station.start(hub, stationHandlers)
	if Matchmaker.enabled() then
		Matchmaker.start(function(players)
			backToHub(players)
		end)
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
