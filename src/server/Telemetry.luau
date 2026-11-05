--[[
	Crash and error analytics (launch hardening, 5 Nov 2026).

	Counts, per server:
	- ServerError: every server script error (ScriptContext.Error);
	- ClientError: client script errors, reported by ErrorReporter.client
	  over the ClientError remote (capped per player);
	- Warning: every warning in the server's output (LogService), which
	  covers all the "[Matchmaker] ..." style fallbacks;
	- any event the game counts itself (Telemetry.count), e.g. TeleportFailed,
	  MatchCrewFormed, MatchLocalFallback, RunBuildFailed.

	Every Config.Telemetry.FlushSeconds (and when the server closes) the counts
	go to Roblox's Custom Events with AnalyticsService:LogCustomEvent, so they
	show in the Creator Dashboard (Analytics > Custom Events), split by
	CustomField01 = what happened (a short signature with numbers, ids and
	names stripped) and CustomField02 = "Lobby" or "Run". Custom events need a
	player in the server to attach to; with nobody here the counts wait.

	Kid safety: no player names, user ids or chat text are ever sent. Paths
	like Players.<name>.PlayerScripts are cut before the message is counted.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")

local Config = require(ReplicatedStorage.Shared.Config)

local Telemetry = {}

local counts: { [string]: { [string]: number } } = {} -- event -> signature -> count, since the last flush
local totals: { [string]: number } = {} -- event -> count since the server started
local reports: { [Player]: number } = {} -- client error reports accepted per player
local placeKind = "Lobby"
local started = false
local busy = false -- re-entrancy guard: never count our own failures

-- A short, name-free summary of an error or warning, so the same bug
-- always lands in the same bucket.
function Telemetry.signature(text: any): string
	local s = string.match(tostring(text), "^[^\n]*") or ""
	s = string.gsub(s, "Players%.[^%.%s:]+%.", "Players.<player>.")
	s = string.gsub(s, "ServerScriptService%.Server%.", "")
	s = string.gsub(s, "ReplicatedStorage%.Shared%.", "")
	s = string.gsub(s, "Players%.<player>%.PlayerScripts%.", "")
	s = string.gsub(s, "%x+%-%x+%-%x+%-%x+%-%x+", "<id>")
	s = string.gsub(s, '"[^"]*"', "<s>")
	s = string.gsub(s, "'[^']*'", "<s>")
	s = string.gsub(s, "%d+%.?%d*", "#")
	s = string.gsub(s, "%s+", " ")
	s = string.match(s, "^%s*(.-)%s*$") or s
	if s == "" then
		s = "(empty)"
	end
	return string.sub(s, 1, Config.Telemetry.SignatureLength)
end

-- Counts `n` (default 1) of an event, optionally split by a short detail.
function Telemetry.count(event: string, detail: string?, n: number?)
	local amount = n or 1
	local bucket = counts[event]
	if not bucket then
		bucket = {}
		counts[event] = bucket
	end
	local key = detail or ""
	if bucket[key] == nil then
		local distinct = 0
		for _ in bucket do
			distinct += 1
		end
		if distinct >= Config.Telemetry.MaxSignaturesPerFlush then
			key = "Other"
		end
	end
	bucket[key] = (bucket[key] or 0) + amount
	totals[event] = (totals[event] or 0) + amount
end

-- Counts an error or warning under its signature.
function Telemetry.error(event: string, message: any)
	if busy then
		return
	end
	busy = true
	pcall(function()
		Telemetry.count(event, Telemetry.signature(message))
	end)
	busy = false
end

-- Everything counted since the server started (tests, debugging).
function Telemetry.totals(): { [string]: number }
	return table.clone(totals)
end

-- What the next flush will send.
function Telemetry.pending(): { [string]: { [string]: number } }
	local out = {}
	for event, bucket in counts do
		out[event] = table.clone(bucket)
	end
	return out
end

-- Sends the counts to Roblox. Returns how many events were logged.
function Telemetry.flush(): number
	local player = Players:GetPlayers()[1]
	if not player or next(counts) == nil then
		return 0
	end
	local batch = counts
	counts = {}
	local sent = 0
	busy = true
	for event, bucket in batch do
		for detail, n in bucket do
			local fields = { CustomField02 = placeKind }
			if detail ~= "" then
				fields.CustomField01 = detail
			end
			local ok = pcall(function()
				AnalyticsService:LogCustomEvent(player, event, n, fields)
			end)
			if ok then
				sent += 1
			else
				totals.TelemetryDropped = (totals.TelemetryDropped or 0) + 1
			end
		end
	end
	busy = false
	return sent
end

-- A client says one of its scripts errored.
function Telemetry.clientError(player: Player, message: any)
	if type(message) ~= "string" then
		return
	end
	local n = reports[player] or 0
	if n >= Config.Telemetry.ClientErrorsPerPlayer then
		return
	end
	reports[player] = n + 1
	Telemetry.error("ClientError", string.sub(message, 1, 400))
end

-- kind: "Lobby" or "Run". Needs Remotes.init first.
function Telemetry.start(kind: string, clientErrors: RemoteEvent?)
	placeKind = kind
	if started then
		return
	end
	started = true

	ScriptContext.Error:Connect(function(message)
		Telemetry.error("ServerError", message)
	end)
	LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageWarning then
			Telemetry.error("Warning", message)
		end
	end)
	if clientErrors then
		clientErrors.OnServerEvent:Connect(Telemetry.clientError)
	end
	Players.PlayerRemoving:Connect(function(player)
		reports[player] = nil
		if #Players:GetPlayers() <= 1 then
			Telemetry.flush() -- the last one out still carries the counts
		end
	end)
	pcall(function()
		game:BindToClose(Telemetry.flush)
	end)

	task.spawn(function()
		while true do
			task.wait(Config.Telemetry.FlushSeconds)
			Telemetry.flush()
		end
	end)
end

return Telemetry
