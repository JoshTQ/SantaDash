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

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
params.RespectCanCollide = true

local function seeThroughModel(part: Instance): Instance?
	local node = part.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and PromptSight.SeeThrough[node.Name] then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function visible(from: Vector3, prompt: ProximityPrompt, character: Model): boolean
	local target = prompt.Parent :: BasePart
	local goal = target.Position
	local skip = { character, target }
	local model = target.Parent
	if model and model:IsA("Model") and #model:GetChildren() <= PromptSight.SmallModel then
		table.insert(skip, model) -- the present's ribbon and bow, not a whole house
	end
	for _ = 0, PromptSight.MaxSkips do
		params.FilterDescendantsInstances = skip
		local result = workspace:Raycast(from, goal - from, params)
		if not result then
			return true
		end
		local through = seeThroughModel(result.Instance)
		if through then
			table.insert(skip, through)
		else
			return not PromptSight.blocked(result.Position, goal, target.Size)
		end
	end
	return true
end

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
		local want = if near and not visible(from, prompt, character :: Model) then 0 else reach
		if prompt.MaxActivationDistance ~= want then
			prompt.MaxActivationDistance = want
		end
	end
end)
