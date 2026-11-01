--[[
	Sleigh Station matchmaking.

	Quick Join: step on the pad and you board the next public sleigh. A sleigh
	departs QuickJoinSeconds after its first rider, or as soon as it is full.
	After a run the same crew is requeued together ("Next run in 5..."), and
	Quick Join players can fill any empty seats. LeaveCrew drops you out.

	Not in the greybox yet: Party/Private toggle, join-a-friend, drop-in at the
	next stop, elf bots for empty seats.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(script.Parent.MapBuilder)
local Run = require(script.Parent.Run)

type Crew = {
	players: { Player },
	departAt: number,
	requeue: boolean,
	waiting: boolean,
}

local Lobby = {}

local crews: { Crew } = {}
local runsBySlot: { [number]: any } = {}
local runOf: { [Player]: any } = {}
local crewOf: { [Player]: Crew } = {}
local hud: RemoteEvent

local HUB_RETURN = CFrame.new(0, 4, -50)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function sendCrew(crew: Crew)
	for _, player in crew.players do
		hud:FireClient(player, "Queue", {
			departAt = crew.departAt,
			count = #crew.players,
			max = Config.Lobby.CrewMax,
			requeue = crew.requeue,
			waiting = crew.waiting,
		})
	end
end

local function freeSlot(): number?
	for slot = 1, Config.Lobby.MaxRunsPerServer do
		if not runsBySlot[slot] then
			return slot
		end
	end
	return nil
end

local function removeCrew(crew: Crew)
	local index = table.find(crews, crew)
	if index then
		table.remove(crews, index)
	end
end

local function onRunFinished(run, survivors: { Player })
	runsBySlot[run.slot] = nil
	local crew: Crew = {
		players = {},
		departAt = now() + Config.Run.RequeueSeconds,
		requeue = true,
		waiting = false,
	}
	for i, player in survivors do
		runOf[player] = nil
		MapBuilder.teleportCharacter(player, HUB_RETURN * CFrame.new((i - 1) * 4, 0, 0))
		table.insert(crew.players, player)
		crewOf[player] = crew
	end
	if #crew.players > 0 then
		table.insert(crews, crew)
		sendCrew(crew)
	end
end

local function launch(crew: Crew, slot: number)
	-- Build first: if building fails the crew stays queued instead of vanishing.
	local run = Run.new(slot, crew.players, onRunFinished)
	removeCrew(crew)
	runsBySlot[slot] = run
	for _, player in crew.players do
		crewOf[player] = nil
		runOf[player] = run
		hud:FireClient(player, "QueueClear", {})
	end
	run:start()
end

function Lobby.quickJoin(player: Player)
	if runOf[player] or crewOf[player] then
		return
	end
	-- Fill the sleigh leaving soonest that still has room.
	local best: Crew? = nil
	for _, crew in crews do
		if #crew.players < Config.Lobby.CrewMax and (not best or crew.departAt < best.departAt) then
			best = crew
		end
	end
	local crew: Crew = best
		or {
			players = {},
			departAt = now() + Config.Lobby.QuickJoinSeconds,
			requeue = false,
			waiting = false,
		}
	if not best then
		table.insert(crews, crew)
	end
	table.insert(crew.players, player)
	crewOf[player] = crew
	sendCrew(crew)
end

function Lobby.leave(player: Player, leftGame: boolean?)
	local crew = crewOf[player]
	if crew then
		crewOf[player] = nil
		local index = table.find(crew.players, player)
		if index then
			table.remove(crew.players, index)
		end
		if #crew.players == 0 then
			removeCrew(crew)
		else
			sendCrew(crew)
		end
		if not leftGame then
			hud:FireClient(player, "QueueClear", {})
		end
	end

	local run = runOf[player]
	if run then
		runOf[player] = nil
		run:removePlayer(player)
		if not leftGame then
			MapBuilder.teleportCharacter(player, HUB_RETURN)
		end
	end
end

local function tick()
	local t = now()
	for _, crew in table.clone(crews) do
		if #crew.players == 0 then
			removeCrew(crew)
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

	hub.quickJoinPad.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			Lobby.quickJoin(player)
		end
	end)

	Remotes.get("LeaveCrew").OnServerEvent:Connect(function(player)
		Lobby.leave(player)
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
