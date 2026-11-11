--[[
	Remote events shared by server and client.

	Hud (server -> client): fire(kind: string, data: table). Kinds:
		Queue, QueueClear, Stop, Banner, Noise, Player, Results, RunEnd,
		Krampus, KrampusTease, Hide, Captive, MapEvent, Weather, Snowballs, Splat, Cutscene,
		Tip, TipDone, Guide (first-time player tips, server/Onboarding.luau)
	LeaveCrew (client -> server): leave the queue or the current run.
	Input (client -> server): "Tap" (breath / wiggle), "Unhide", "Throw" (snowball),
		"Breakout" (use an Instant Break-out while snatched), or
		"TipsReady" / "TipsOff" (first-time tips).
	Store (both ways): see server/Store.luau.
	ClientError (client -> server): a client script error, for Telemetry.
	ClientStats (client -> server): device, load time, frame rate and
		cutscene freezes (shared/ClientStats.luau), for Analytics.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local FOLDER_NAME = "Remotes"
local NAMES = { "Hud", "LeaveCrew", "Input", "Store", "ClientError", "ClientStats" }

local function serverFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

-- Server only: create every remote up front so clients can WaitForChild them.
function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init is server only")
	local folder = serverFolder()
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	if RunService:IsServer() then
		local remote = serverFolder():FindFirstChild(name)
		assert(remote, "Unknown remote " .. name .. " (call Remotes.init first)")
		return remote :: RemoteEvent
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME):WaitForChild(name) :: RemoteEvent
end

return Remotes
