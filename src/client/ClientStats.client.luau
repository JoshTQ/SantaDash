--[[
	Measures how smoothly the game runs on this device and tells the server
	(shared/ClientStats.luau has the rules, server/Analytics.luau logs it):
	the device type and load time once, each cutscene's frame rate, stutters
	and freezes when it ends, and the same for normal play every minute.
	Only numbers and the cutscene id are sent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClientStats = require(ReplicatedStorage.Shared.ClientStats)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CutscenePlayer = require(script.Parent.CutscenePlayer)

local remote = Remotes.get("ClientStats")
local hud = Remotes.get("Hud")

local function loadSeconds(): number?
	local ok, t = pcall(function()
		return time() -- seconds since this client started the game
	end)
	return if ok and type(t) == "number" then t else nil
end

local camera = workspace.CurrentCamera
remote:FireServer({
	kind = "Hello",
	device = ClientStats.device(UserInputService, camera and camera.ViewportSize),
	load = loadSeconds(),
})

local lastCutsceneId: string? = nil
hud.OnClientEvent:Connect(function(kind, data)
	if kind == "Cutscene" and type(data) == "table" and type(data.id) == "string" then
		lastCutsceneId = data.id
	end
end)

local play = ClientStats.newSegment()
local scene: ClientStats.Segment? = nil
local sceneId: string? = nil

local function report(kind: string, segment: ClientStats.Segment, id: string?)
	if segment.frames == 0 then
		return
	end
	local out: { [string]: any } = ClientStats.summary(segment) :: any
	out.kind = kind
	out.id = id
	remote:FireServer(out)
end

RunService.Heartbeat:Connect(function(dt: number)
	local playing = CutscenePlayer.isPlaying()
	if playing and not scene then
		scene = ClientStats.newSegment()
		sceneId = lastCutsceneId
	elseif not playing and scene then
		report("Cutscene", scene, sceneId)
		scene, sceneId = nil, nil
	end
	if scene then
		ClientStats.addFrame(scene, dt)
		return
	end
	ClientStats.addFrame(play, dt)
	if play.seconds >= ClientStats.ReportSeconds then
		report("Perf", play)
		play = ClientStats.newSegment()
	end
end)
