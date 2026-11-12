--[[
	The lobby's weekly leaderboards: Top Crews (podium board), Most Wanted
	(poster wall) and the Biggest Haul sign over the giant present.

	  Leaderboards.record(rows)   a run finished: rows = { { userId, loot } }
	                              for the real Santas (no elf bots). Run
	                              servers call this; it saves in the
	                              background with retries.
	  Leaderboards.fetch()        the week's top crews and Santas, or nil
	  Leaderboards.render(showOff, board, names, now)
	                              draws a fetched board onto the yard
	  Leaderboards.start(hub)     redraws the yard every RefreshSeconds

	Data lives in two OrderedDataStores per week (Config.Leaderboards), so
	the run place writes and every lobby server reads the same boards:
	  TopCrews_v1/<week>    key = Leaderboard.crewKey(ids), best single haul
	  MostWanted_v1/<week>  key = UserId, total loot got away with

	Tests hand in a DataStoreService stand-in (useService) and a name lookup
	(useNames).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Leaderboard = require(ReplicatedStorage.Shared.Leaderboard)
local Telemetry = require(script.Parent.Telemetry)

local Leaderboards = {}

export type Crew = { ids: { number }, haul: number }
export type Santa = { userId: number, haul: number }
export type Board = { crews: { Crew }, wanted: { Santa } }

local service: any = nil
local lookup: ((ids: { number }) -> { [number]: string })? = nil
local nameCache: { [number]: string } = {}
local clock: () -> number = os.time

function Leaderboards.useService(fake: any)
	service = fake
end

function Leaderboards.useNames(fn: ((ids: { number }) -> { [number]: string })?)
	lookup = fn
	nameCache = {}
end

function Leaderboards.useClock(fn: (() -> number)?)
	clock = fn or os.time
end

local function dataStores(): any
	return service or game:GetService("DataStoreService")
end

local function storeName(base: string, t: number): string
	return base .. "/" .. Leaderboard.weekKey(t)
end

local warned: { [string]: boolean } = {}

local function open(base: string, t: number): any?
	local ok, result = pcall(function()
		return dataStores():GetOrderedDataStore(storeName(base, t))
	end)
	if not ok then
		if not warned[base] then -- once per server, not every refresh
			warned[base] = true
			warn("[Leaderboards] can't open " .. base .. " (boards stay empty): " .. tostring(result))
		end
		return nil
	end
	return result
end

local function retry(what: string, fn: () -> ()): boolean
	local cfg = Config.Leaderboards
	for attempt = 1, cfg.WriteAttempts do
		local ok, err = pcall(fn)
		if ok then
			return true
		end
		warn(string.format("[Leaderboards] %s failed (try %d): %s", what, attempt, tostring(err)))
		if attempt < cfg.WriteAttempts then
			task.wait(cfg.RetrySeconds * attempt)
		end
	end
	Telemetry.count("LeaderboardWriteFailed", what)
	return false
end

function Leaderboards.canWrite(): boolean
	return service ~= nil or not RunService:IsStudio() or Config.Leaderboards.WriteInStudio
end

-- Saves one finished run. Returns once every write is done (or given up);
-- Run calls it in a task.spawn so results never wait on the DataStore.
function Leaderboards.record(rows: { { any } }): boolean
	if not Leaderboards.canWrite() then
		return false
	end
	local ids, total = {}, 0
	local santas = {}
	for _, r in rows do
		local userId, loot = r[1], math.floor(tonumber(r[2]) or 0)
		if type(userId) == "number" and userId > 0 then
			table.insert(ids, userId)
			if loot > 0 then
				total += loot
				table.insert(santas, { userId, loot })
			end
		end
	end
	local key = Leaderboard.crewKey(ids)
	if not key or total <= 0 then
		return false -- nothing got away: nothing to show off
	end
	local cfg = Config.Leaderboards
	local t = clock()
	local ok = true
	local crews = open(cfg.TopCrewsStore, t)
	if crews then
		ok = retry("TopCrews", function()
			crews:UpdateAsync(key, function(old)
				local best = Leaderboard.bestHaul(old, total)
				return if best == old then nil else best
			end)
		end) and ok
	else
		ok = false
	end
	local wanted = open(cfg.MostWantedStore, t)
	for _, s in santas do
		if wanted then
			ok = retry("MostWanted", function()
				wanted:IncrementAsync(tostring(s[1]), s[2])
			end) and ok
		else
			ok = false
		end
	end
	return ok
end

local function top(store: any, n: number): { { key: string, value: number } }
	local page = store:GetSortedAsync(false, n):GetCurrentPage()
	local out = {}
	for _, entry in page do
		if type(entry.value) == "number" and entry.value > 0 then
			table.insert(out, { key = entry.key, value = entry.value })
		end
	end
	return out
end

-- The week's boards, or nil if the DataStores can't be reached.
function Leaderboards.fetch(): Board?
	local cfg = Config.Leaderboards
	local t = clock()
	local crews, wanted = open(cfg.TopCrewsStore, t), open(cfg.MostWantedStore, t)
	if not crews or not wanted then
		return nil
	end
	local ok, result = pcall(function()
		local board: Board = { crews = {}, wanted = {} }
		for _, e in top(crews, cfg.TopCrews) do
			local ids = Leaderboard.crewIds(e.key)
			if #ids > 0 then
				table.insert(board.crews, { ids = ids, haul = e.value })
			end
		end
		for _, e in top(wanted, cfg.MostWanted) do
			local id = tonumber(e.key)
			if id then
				table.insert(board.wanted, { userId = id, haul = e.value })
			end
		end
		return board
	end)
	if not ok then
		warn("[Leaderboards] read failed: " .. tostring(result))
		Telemetry.count("LeaderboardReadFailed")
		return nil
	end
	return result
end

-- Roblox display names for ids we haven't seen yet, in one call.
local function robloxNames(ids: { number }): { [number]: string }
	local out = {}
	local ok, infos = pcall(function()
		return game:GetService("UserService"):GetUserInfosByUserIdsAsync(ids)
	end)
	if ok and type(infos) == "table" then
		for _, info in infos do
			out[info.Id] = info.DisplayName or info.Username
		end
	end
	for _, id in ids do
		if not out[id] then
			local found, name = pcall(function()
				return Players:GetNameFromUserIdAsync(id)
			end)
			if found then
				out[id] = name
			end
		end
	end
	return out
end

-- Names for every Santa on the board (players in this server first).
function Leaderboards.names(board: Board): { [number]: string }
	local missing = {}
	local function want(id: number)
		if nameCache[id] or table.find(missing, id) then
			return
		end
		local found, player = pcall(function()
			return Players:GetPlayerByUserId(id)
		end)
		if found and player then
			nameCache[id] = player.DisplayName
		else
			table.insert(missing, id)
		end
	end
	for _, crew in board.crews do
		for _, id in crew.ids do
			want(id)
		end
	end
	for _, s in board.wanted do
		want(s.userId)
	end
	if #missing > 0 then
		for id, name in (lookup or robloxNames)(missing) do
			nameCache[id] = name
		end
	end
	return nameCache
end

local function nameOf(names: { [number]: string }, id: number): string
	return names[id] or "Santa"
end

-- Draws a board onto the show-off yard. board = nil means the DataStores
-- couldn't be reached (Studio without API access, or an outage).
function Leaderboards.render(showOff: any, board: Board?, names: { [number]: string }, now: number)
	local crews = if board then board.crews else {}
	for i, label in showOff.crewRows do
		local crew = crews[i]
		label.Visible = crew ~= nil
		if crew then
			local list = {}
			for _, id in crew.ids do
				table.insert(list, nameOf(names, id))
			end
			label.Text =
				string.format("%d.  %s  ·  %s", i, Leaderboard.crewNames(list), Leaderboard.short(crew.haul))
		end
	end
	showOff.crewEmpty.Visible = #crews == 0
	showOff.crewEmpty.Text = if board
		then "Rob the most presents to stand up here!"
		else "Leaderboard is having a snow day. Back soon!"
	showOff.crewReset.Text = Leaderboard.resetText(Leaderboard.secondsLeft(now))

	local best = crews[1]
	for _, label in showOff.biggestHaul do
		label.Text = if best
			then "THIS WEEK'S BIGGEST HAUL: " .. Leaderboard.short(best.haul)
			else "THIS WEEK'S BIGGEST HAUL"
	end

	local wanted = if board then board.wanted else {}
	for i, poster in showOff.wanted do
		local s = wanted[i]
		poster.photo.Visible = s ~= nil
		poster.photo.Image = if s then Leaderboard.headshot(s.userId) else ""
		poster.name.Text = if s then nameOf(names, s.userId) else "???"
		poster.haul.Text = if s then Leaderboard.short(s.haul) .. " loot" else "Could be you!"
		poster.title.Text = if s then "WANTED #" .. i else "WANTED"
	end
end

-- One fetch and redraw. Returns the board (nil when offline).
function Leaderboards.refresh(showOff: any): Board?
	local board = Leaderboards.fetch()
	local names = if board then Leaderboards.names(board) else {}
	Leaderboards.render(showOff, board, names, clock())
	return board
end

function Leaderboards.start(hub: any)
	if not hub or not hub.showOff then
		return
	end
	task.spawn(function()
		while hub.model.Parent do
			Leaderboards.refresh(hub.showOff)
			task.wait(Config.Leaderboards.RefreshSeconds)
		end
	end)
end

return Leaderboards
