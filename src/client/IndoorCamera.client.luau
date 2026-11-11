--[[
	Indoor camera (rules in shared/IndoorCamera; Josh, 11 Nov 2026: the camera
	was janky inside houses). Walls between the camera and your Santa fade out
	(Invisicam, also set on StarterPlayer in the project files), and under a
	roof with walls round you the camera can't zoom out through them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IndoorCamera = require(ReplicatedStorage.Shared.IndoorCamera)

local player = Players.LocalPlayer
pcall(function()
	player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
end)

local outdoorMax = player.CameraMaxZoomDistance
local state = IndoorCamera.newState()
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

local DIRECTIONS = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }
local acc = 0

local function hit(from: Vector3, dir: Vector3, range: number): number?
	local result = workspace:Raycast(from, dir * range, params)
	if result and result.Instance.CanCollide then
		return result.Distance
	end
	return nil
end

RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	if not root or not camera or camera.CameraType == Enum.CameraType.Scriptable then
		return -- cutscenes drive the camera themselves
	end
	params.FilterDescendantsInstances = { character }
	local at = root.Position
	local ceiling = hit(at, Vector3.yAxis, IndoorCamera.CeilingRange)
	local walls = {}
	if ceiling then
		for i, dir in DIRECTIONS do
			walls[i] = hit(at, dir, IndoorCamera.WallRange)
		end
	end
	local indoors = IndoorCamera.step(state, IndoorCamera.inside(ceiling, walls), os.clock())
	local want = IndoorCamera.maxZoom(indoors, outdoorMax)
	if player.CameraMaxZoomDistance ~= want then
		player.CameraMaxZoomDistance = want
	end
end)
