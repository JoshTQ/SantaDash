--[[
	Run place server: receives one crew from the lobby place (see
	shared/Handoff.luau), plays runs back to back for it ("Next run in 5..."),
	and sends anyone who leaves the crew back to the lobby place.

	Each run server is a reserved server holding exactly one crew, so there is
	one Run at a time here (slot 1). Studio: players with no TeleportData are
	admitted as a test crew.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Handoff = require(ReplicatedStorage.Shared.Handoff)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local Run = require(script.Parent.Run)

local RunHost = {}

local hud: RemoteEvent
local spawn: CFrame
local crew: Handoff.Data? = nil
local waiting: { Player } = {} -- in this server, not in a run
local expected = 0
local departAt = math.huge
local requeue = false
local current = nil -- the Run in progress (or being built)
local lastMap: string? = nil

local function send(player: Player, kind: string, data: any)
	if player.Parent == Players then
		hud:FireClient(player, kind, data)
	end
end

local function sendQueue()
	local data = { departAt = departAt, count = #waiting, requeue = requeue, waiting = false }
	for _, player in waiting do
		send(player, "Queue", data)
	end
end

-- Back to the lobby place (or the waiting spot when there is none, e.g. Studio).
local function toLobby(player: Player)
	Util.removeValue(waiting, player)
	if Config.Places.Lobby ~= 0 and not RunService:IsStudio() then
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(Config.Places.Lobby, { player })
		end)
		if ok then
			return
		end
		warn("[RunHost] teleport to lobby failed: " .. tostring(err))
	end
	Util.teleport(player, spawn)
	send(player, "QueueClear", {})
end

local function onFinished(_run, survivors: { Player })
	current = nil
	waiting = {}
	for i, player in survivors do
		table.insert(waiting, player)
		Util.teleport(player, spawn * CFrame.new((i - 1) * 4, 0, 0))
	end
	expected = #waiting
	requeue = true
	departAt = Util.now() + Config.Run.RequeueSeconds
	sendQueue()
end

local function launch()
	local players = waiting
	waiting = {}
	current = true -- reserved while the route builds
	task.spawn(function()
		local ok, run = pcall(Run.new, 1, players, onFinished, lastMap)
		if not ok then
			warn("[RunHost] failed to build a route: " .. tostring(run))
			current = nil
			waiting = players
			departAt = Util.now() + Config.Run.RequeueSeconds
			sendQueue()
			return
		end
		current = run
		lastMap = run.mapId
		for _, player in players do
			if run:hasPlayer(player) and player.Parent == Players then
				send(player, "QueueClear", {})
			else
				run:removePlayer(player) -- left while the route was building
			end
		end
		run:start()
	end)
end

local function admit(player: Player)
	local joined = Handoff.read(player:GetJoinData().TeleportData)
	if not crew and joined then
		crew = joined
		expected = #joined.members
		departAt = Util.now() + Config.Places.ArrivalTimeoutSeconds
	end
	local isTester = RunService:IsStudio() and not joined
	if not isTester and not (crew and Handoff.admits(crew, joined, player.UserId)) then
		toLobby(player) -- not part of this crew
		return
	end
	if isTester and departAt == math.huge then
		expected = 1
		departAt = Util.now() + Config.Lobby.QuickJoinSeconds
	end
	table.insert(waiting, player)
	sendQueue()
end

local function leave(player: Player, leftGame: boolean)
	Util.removeValue(waiting, player)
	if type(current) == "table" and current:hasPlayer(player) then
		current:removePlayer(player)
	end
	if not leftGame then
		toLobby(player)
	else
		sendQueue()
	end
end

function RunHost.start(hub)
	hud = Remotes.get("Hud")
	spawn = hub.spawn

	Players.PlayerAdded:Connect(admit)
	for _, player in Players:GetPlayers() do
		task.spawn(admit, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		leave(player, true)
	end)
	Remotes.get("LeaveCrew").OnServerEvent:Connect(function(player)
		leave(player, false)
	end)
	Remotes.get("Input").OnServerEvent:Connect(function(player, action)
		if type(current) == "table" and typeof(action) == "string" then
			current:onInput(player, action)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			if not current and Handoff.shouldDepart(#waiting, expected, Util.now(), departAt, requeue) then
				local ok, err = pcall(launch)
				if not ok then
					warn("[RunHost] launch failed: " .. tostring(err))
				end
			end
		end
	end)
end

return RunHost
