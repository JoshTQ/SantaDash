--[[
	Gingerbread Mansion: the one real box under the hall tree gives itself
	away with a little wobble now and then (HouseKit sets its Wobble
	attribute; Run clears it once opened). Only boxes near the camera move.
]]

local RunService = game:GetService("RunService")

local RANGE = 60
local boxes: { [BasePart]: CFrame } = {}

local function add(d: Instance)
	if d:IsA("BasePart") and d.Name == "TreeBox" then
		boxes[d] = d.CFrame
	end
end

for _, d in workspace:GetDescendants() do
	add(d)
end
workspace.DescendantAdded:Connect(add)
workspace.DescendantRemoving:Connect(function(d)
	boxes[d :: any] = nil
end)

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- Wobble in short bursts: about a third of the time.
	local on = math.sin(t * 1.3) > 0.3
	for box, rest in boxes do
		if box:GetAttribute("Wobble") and (box.Position - camera.CFrame.Position).Magnitude < RANGE then
			local tilt = if on then math.sin(t * 9) * 0.06 else 0
			local cf = rest * CFrame.Angles(0, 0, tilt)
			box.CFrame = cf
			local ribbon = box:FindFirstChild("Ribbon")
			if ribbon and ribbon:IsA("BasePart") then
				ribbon.CFrame = cf
			end
		end
	end
end)
