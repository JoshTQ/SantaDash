--[[
	Hides gift, search and hide prompts while a wall is between your Santa and
	them (rules in shared/PromptSight). Only touches MaxActivationDistance on
	this client, so the server's Enabled state is left alone.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PromptSight = require(ReplicatedStorage.Shared.PromptSight)

local player = Players.LocalPlayer
local tracked: { [ProximityPrompt]: number } = {} -- prompt -> its real reach

local function track(d: Instance)
	if d:IsA("ProximityPrompt") and d.Parent and d.Parent:IsA("BasePart") then
		if PromptSight.applies(d.ActionText, d.Parent.Name) and not tracked[d] then
			tracked[d] = d.MaxActivationDistance
		end
	end
end

for _, d in workspace:GetDescendants() do
	track(d)
end
workspace.DescendantAdded:Connect(function(d)
	-- ActionText and the parent are set before it's parented, but wait a frame
	-- in case a script fills them in after.
	task.defer(track, d)
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < PromptSight.Interval then
		return
	end
	acc = 0
	local character = player.Character
	local head = character
		and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not head or not head:IsA("BasePart") then
		return
	end
	local from = head.Position
	for prompt, reach in tracked do
		local target = prompt.Parent
		if not target or not target:IsA("BasePart") or not prompt:IsDescendantOf(workspace) then
			tracked[prompt] = nil -- packed away (pop-in rooms, grabbed gifts)
			continue
		end
		local near = (target.Position - from).Magnitude <= reach + PromptSight.Margin
		local want = if near and not PromptSight.sees(from, target, character) then 0 else reach
		if prompt.MaxActivationDistance ~= want then
			prompt.MaxActivationDistance = want
		end
	end
end)
