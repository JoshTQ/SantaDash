--[[
	Level of detail on this client (see Shared.Detail): far-away dressing on
	the routes and the hub leaves this client's scene and comes back as the
	camera nears it. Roots are the workspace Models the server marks with the
	DetailRoot attribute.

	Turn it off for a test session with the Workspace attribute DetailOff = true.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Detail = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Detail"))

local function quality(): number
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return if ok and type(level) == "number" then level else 0
end

local culler =
	Detail.new(Detail.profile(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled, quality()))

local tracking: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function track(root: Instance)
	if tracking[root] or not root:IsA("Model") or not root:GetAttribute("DetailRoot") then
		return
	end
	tracking[root] = true
	-- A frame's grace so the whole model has replicated; late parts join below.
	task.defer(function()
		if not root.Parent then
			return
		end
		culler:add(root)
		root.DescendantAdded:Connect(function(d)
			if culler.roots[root] then
				task.defer(function()
					if d.Parent then
						culler:addPart(d, root)
					end
				end)
			end
		end)
		root.AncestryChanged:Connect(function(_, parent)
			if not parent then
				culler:drop(root)
			end
		end)
	end)
end

for _, child in workspace:GetChildren() do
	track(child)
end
workspace.ChildAdded:Connect(track)
workspace.ChildRemoved:Connect(function(child)
	if culler.roots[child] then
		culler:drop(child)
	end
end)

local acc = 0
local last: Vector3? = nil
RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local at = camera.CFrame.Position
	if workspace:GetAttribute("DetailOff") then
		culler:showAll()
		return
	end
	-- A jump (respawn, carried off, cutscene cut): bring the new spot back now.
	if last and (at - last).Magnitude > Detail.JumpStuds then
		culler:step(at, math.huge, true)
	end
	last = at
	acc += dt
	if acc >= Detail.StepSeconds then
		acc = 0
		culler:step(at)
	end
end)
