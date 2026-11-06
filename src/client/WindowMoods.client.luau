--[[
	Animates house windows near the camera (rules: shared/WindowMoods): TV
	panes flicker, empty rooms switch their light on now and then, lamps
	breathe. Only panes with a TV / Dark / Lamp Mood within WindowMoods.Range
	are touched, a few times a second, so phones barely notice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WindowMoods = require(ReplicatedStorage.Shared.WindowMoods)

local NEON = Enum.Material.Neon
local SMOOTH = Enum.Material.SmoothPlastic
local LIVE = { TV = true, Dark = true, Lamp = true }

local panes: { [BasePart]: { mood: string, seed: number } } = {}

local function add(d: Instance)
	if d:IsA("BasePart") then
		local mood = d:GetAttribute("Mood")
		if type(mood) == "string" and LIVE[mood] then
			panes[d] = { mood = mood, seed = WindowMoods.seed(d.Position) }
		end
	end
end

for _, d in workspace:GetDescendants() do
	add(d)
end
workspace.DescendantAdded:Connect(add)
workspace.DescendantRemoving:Connect(function(d)
	panes[d :: any] = nil
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 1 / WindowMoods.Rate then
		return
	end
	acc = 0
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for pane, info in panes do
		if (pane.Position - eye).Magnitude < WindowMoods.Range then
			local colour, glow = WindowMoods.look(info.mood, t, info.seed)
			if colour then
				pane.Color = colour
				pane.Material = if glow then NEON else SMOOTH
			end
		end
	end
end)
