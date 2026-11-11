--[[
	Teleports that survive Roblox's everyday hiccups (launch hardening, 5 Nov
	2026). TeleportAsync fails now and then (flood limits, a busy server), and
	Roblox's own advice is to retry, so:

	- a call that errors is tried Config.Matchmaking.Attempts times with
	  backoff, for whoever is still in the server;
	- a teleport that started and then failed (TeleportInitFailed with
	  Failure or Flooded) is tried again for that player alone, up to the same
	  number of tries in all;
	- anything else (the run server is gone or full, no permission) gives up
	  at once.

	Giving up calls giveUp(players, reason) so the caller can put them back
	somewhere sensible (the hub, the waiting spot). Every failure is counted
	in Telemetry.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Analytics = require(script.Parent.Analytics)
local Telemetry = require(script.Parent.Telemetry)

local Teleporter = {}

export type GiveUp = (players: { Player }, reason: string) -> ()

type Trip = {
	placeId: number,
	options: TeleportOptions?,
	tries: number,
	giveUp: GiveUp,
}

local trips: { [Player]: Trip } = {} -- teleports Roblox accepted and hasn't finished
local started = false

local function retryable(result: Enum.TeleportResult): boolean
	return result == Enum.TeleportResult.Failure or result == Enum.TeleportResult.Flooded
end

local function backoff(try: number): number
	return Config.Matchmaking.RetryBackoffSeconds * 2 ^ (try - 1)
end

local function stillHere(players: { Player }): { Player }
	local out = {}
	for _, player in players do
		if player.Parent == Players then
			table.insert(out, player)
		end
	end
	return out
end

-- Teleports players (yields while it retries). Returns true once Roblox has
-- accepted the teleport; false after giving up (giveUp has been called).
function Teleporter.send(
	players: { Player },
	placeId: number,
	options: TeleportOptions?,
	giveUp: GiveUp
): boolean
	if #players == 0 then
		return true
	end
	local tries = 0
	local ok, err = Util.retry(Config.Matchmaking.Attempts, Config.Matchmaking.RetryBackoffSeconds, function()
		tries += 1
		local here = stillHere(players)
		if #here > 0 then
			TeleportService:TeleportAsync(placeId, here, options)
		end
	end)
	if tries > 1 then
		Telemetry.count("TeleportRetried", "call", tries - 1)
	end
	if not ok then
		warn("[Teleporter] teleport failed: " .. tostring(err))
		Telemetry.count("TeleportFailed", "call")
		giveUp(players, "teleport")
		return false
	end
	for _, player in players do
		trips[player] = { placeId = placeId, options = options, tries = 1, giveUp = giveUp }
	end
	Analytics.teleporting(players, true) -- leaving this server isn't quitting
	return true
end

-- Stop tracking a player (they left, or the teleport worked).
function Teleporter.forget(player: Player)
	trips[player] = nil
end

-- How many teleports are being tracked (tests).
function Teleporter.inFlight(): number
	local n = 0
	for _ in trips do
		n += 1
	end
	return n
end

local function giveUp(player: Player, trip: Trip, why: string)
	if trips[player] == trip then
		trips[player] = nil
	end
	warn("[Teleporter] a player could not teleport: " .. why)
	Analytics.teleporting({ player }, false)
	Telemetry.count("TeleportFailed", why)
	trip.giveUp({ player }, "teleport")
end

local function onInitFailed(player: Player, result: Enum.TeleportResult)
	local trip = trips[player]
	if not trip or result == Enum.TeleportResult.IsTeleporting then
		return -- not ours, or an earlier try is still going
	end
	if not retryable(result) or trip.tries >= Config.Matchmaking.Attempts then
		giveUp(player, trip, result.Name)
		return
	end
	trip.tries += 1
	Telemetry.count("TeleportRetried", result.Name)
	task.delay(backoff(trip.tries - 1), function()
		if trips[player] ~= trip or player.Parent ~= Players then
			return
		end
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(trip.placeId, { player }, trip.options)
		end)
		if not ok then
			giveUp(player, trip, "call: " .. tostring(err))
		end
	end)
end

function Teleporter.start()
	if started then
		return
	end
	started = true
	TeleportService.TeleportInitFailed:Connect(onInitFailed)
	Players.PlayerRemoving:Connect(Teleporter.forget)
end

return Teleporter
