--[[
	Saved player data, shared by the lobby and run places (one DataStore,
	one key per player). The one place that touches the DataStore: everything
	else reads and writes through get / waitFor / update.

	  PlayerData.start()                 hook Players + BindToClose (Main does this)
	  PlayerData.get(player)             data, or nil while loading
	  PlayerData.waitFor(player, secs?)  data once loaded (defaults if saving is off)
	  PlayerData.update(player, fn)      change data in fn(data); saved on the next autosave
	  PlayerData.saveNow(player)         save right away; true only if it reached the DataStore
	  PlayerData.isPersistent(player)    false in Studio or when the DataStore failed
	  PlayerData.onChanged(fn)           fn(player, data) after every update

	Session lock: each saved value carries { jobId, time }. A server only
	writes while it holds the lock, so a teleport between places can't load
	the same player twice and overwrite newer data. The lock is refreshed on
	every autosave and released when the player leaves. A lock older than
	Config.PlayerData.LockSeconds (a crashed server) is taken over.

	If loading fails (DataStore down, or Studio without SaveInStudio), the
	player gets fresh defaults and nothing is saved, so tips still show. The
	store refuses purchases for such players (isPersistent is false), because
	a purchase it can't save must not be granted.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerDefaults = require(ReplicatedStorage.Shared.PlayerDefaults)

local PlayerData = {}

type Entry = {
	data: { [string]: any },
	persistent: boolean,
	loaded: boolean,
	released: boolean,
	lastTick: number,
}

local entries: { [Player]: Entry } = {}
local listeners: { (Player, any) -> () } = {}
local store: any = nil
local started = false
local closing = false

local function clock(): number
	return os.time()
end

local function keyFor(userId: number): string
	return "p_" .. tostring(userId)
end

local function jobId(): string
	local id = game.JobId
	return if id == nil or id == "" then "studio" else id
end

-- Pure: can this server take the saved value's lock? (exported for tests)
function PlayerData.canLock(saved: any, myJob: string, now: number): boolean
	local lock = type(saved) == "table" and saved.lock
	if not lock then
		return true
	end
	return lock.jobId == myJob or now - (lock.time or 0) >= Config.PlayerData.LockSeconds
end

-- Tests and Studio tools can hand in a DataStore stand-in (GetAsync-free:
-- only UpdateAsync is used).
function PlayerData.useStore(dataStore: any)
	store = dataStore
end

local function openStore(): any
	if store then
		return store
	end
	if RunService:IsStudio() and not Config.PlayerData.SaveInStudio then
		return nil
	end
	local ok, result = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore(Config.PlayerData.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore unavailable, saving is off:", result)
	end
	return store
end

-- Loads with the lock; returns data or nil (fail).
local function load(userId: number): { [string]: any }?
	local ds = openStore()
	if not ds then
		return nil
	end
	local cfg = Config.PlayerData
	for attempt = 1, cfg.LoadAttempts do
		local loaded = nil
		local blocked = false
		local ok, err = pcall(function()
			ds:UpdateAsync(keyFor(userId), function(saved)
				local now = clock()
				-- Last attempt: a lock that never let go (the old server is
				-- stuck) is taken over rather than leaving the player unsaved.
				if not PlayerData.canLock(saved, jobId(), now) and attempt < cfg.LoadAttempts then
					blocked = true
					return nil -- leave it alone, try again shortly
				end
				local value = if type(saved) == "table" then saved else {}
				value.data = PlayerDefaults.reconcile(value.data or PlayerDefaults.new())
				value.lock = { jobId = jobId(), time = now }
				loaded = value.data
				return value
			end)
		end)
		if ok and loaded then
			return loaded
		end
		if not ok then
			warn("[PlayerData] load failed:", err)
		elseif not blocked then
			return nil
		end
		task.wait(cfg.RetrySeconds)
	end
	return nil
end

-- Writes data while we hold the lock. release = drop the lock (leaving).
local function write(userId: number, data: { [string]: any }, release: boolean): boolean
	local ds = openStore()
	if not ds then
		return false
	end
	local wrote = false
	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(userId), function(saved)
			if type(saved) == "table" and saved.lock and saved.lock.jobId ~= jobId() then
				return nil -- another server took over: never overwrite its newer data
			end
			wrote = true
			return {
				data = data,
				lock = if release then nil else { jobId = jobId(), time = clock() },
			}
		end)
	end)
	if not ok then
		warn("[PlayerData] save failed:", err)
		return false
	end
	return wrote
end

local function tickPlaytime(entry: Entry)
	local now = clock()
	entry.data.playSeconds += math.max(0, now - entry.lastTick)
	entry.lastTick = now
end

local function notify(player: Player, data)
	for _, fn in listeners do
		task.spawn(fn, player, data)
	end
end

function PlayerData.get(player: Player): { [string]: any }?
	local entry = entries[player]
	if entry and entry.loaded then
		tickPlaytime(entry)
		return entry.data
	end
	return nil
end

function PlayerData.waitFor(player: Player, timeout: number?): { [string]: any }?
	local deadline = os.clock() + (timeout or 15)
	while player.Parent == Players and os.clock() < deadline do
		local data = PlayerData.get(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return PlayerData.get(player)
end

function PlayerData.isPersistent(player: Player): boolean
	local entry = entries[player]
	return entry ~= nil and entry.loaded and entry.persistent and not entry.released
end

function PlayerData.update(player: Player, fn: (data: { [string]: any }) -> ()): boolean
	local data = PlayerData.get(player)
	if not data then
		return false
	end
	fn(data)
	notify(player, data)
	return true
end

function PlayerData.onChanged(fn: (Player, any) -> ())
	table.insert(listeners, fn)
end

function PlayerData.saveNow(player: Player): boolean
	local entry = entries[player]
	if not (entry and entry.loaded and entry.persistent) or entry.released then
		return false
	end
	tickPlaytime(entry)
	local ok = write(player.UserId, entry.data, false)
	if not ok then
		-- Lost the lock (or the store failed): stop pretending to save.
		entry.persistent = false
	end
	return ok
end

-- Loads a player now (Main calls this through start; tests call it directly).
function PlayerData.load(player: Player)
	if entries[player] then
		return
	end
	local entry: Entry = {
		data = PlayerDefaults.new(),
		persistent = false,
		loaded = false,
		released = false,
		lastTick = clock(),
	}
	entries[player] = entry
	local data = load(player.UserId)
	if entries[player] ~= entry then
		return -- left while loading
	end
	if data then
		entry.data = data
		entry.persistent = true
	end
	entry.lastTick = clock()
	entry.loaded = true
	if player.Parent ~= Players then
		PlayerData.release(player)
		return
	end
	notify(player, entry.data)
end

-- Final save and unlock (player left, or server closing).
function PlayerData.release(player: Player)
	local entry = entries[player]
	if not entry or entry.released then
		return
	end
	entry.released = true
	if entry.loaded and entry.persistent then
		tickPlaytime(entry)
		write(player.UserId, entry.data, true)
	end
	if entries[player] == entry then
		entries[player] = nil
	end
end

function PlayerData.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(function(player)
		PlayerData.load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerData.load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		PlayerData.release(player)
	end)
	local function onClose()
		closing = true
		local pending = 0
		for player in entries do
			pending += 1
			task.spawn(function()
				PlayerData.release(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	pcall(function()
		game:BindToClose(onClose)
	end)
	task.spawn(function()
		while not closing do
			task.wait(Config.PlayerData.AutosaveSeconds)
			for player, entry in entries do
				if entry.loaded and entry.persistent and not entry.released then
					task.spawn(PlayerData.saveNow, player)
				end
			end
		end
	end)
end

-- Tests: forget everything between specs.
function PlayerData._reset()
	table.clear(entries)
	table.clear(listeners)
	store = nil
	started = false
	closing = false
end

return PlayerData
