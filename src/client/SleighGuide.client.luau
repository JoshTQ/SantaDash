--[[
	Always-on gold guide line from your Santa to the sleigh, plus a "SLEIGH 230"
	marker over it that shows through walls (rules in shared/SleighGuide).
	Local only: each player sees just their own line.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SleighGuide = require(ReplicatedStorage.Shared.SleighGuide)
local Util = require(ReplicatedStorage.Shared.Util)
local CutscenePlayer = require(script.Parent:WaitForChild("CutscenePlayer"))

local player = Players.LocalPlayer
local hud = Remotes.get("Hud")

local state: SleighGuide.State? = nil

-- The far end: an invisible anchor on the sleigh deck with the marker on it.
local anchor = Instance.new("Part")
anchor.Name = "SleighGuideEnd"
anchor.Size = Vector3.one
anchor.Transparency = 1
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.CanTouch = false
local to = Instance.new("Attachment")
to.Position = Vector3.new(0, 3, 0)
-- Both ends point their primary axis up, so the curve sizes arc the line
-- over hedges and trees instead of bending it sideways.
to.Axis = Vector3.yAxis
to.SecondaryAxis = Vector3.xAxis
to.Parent = anchor

local marker = Instance.new("BillboardGui")
marker.Size = UDim2.fromOffset(170, 40)
marker.StudsOffset = Vector3.new(0, 9, 0)
marker.AlwaysOnTop = true
marker.LightInfluence = 0
local text = Instance.new("TextLabel")
text.Size = UDim2.fromScale(1, 1)
text.BackgroundTransparency = 1
text.TextScaled = true
text.Font = Enum.Font.FredokaOne
text.TextStrokeTransparency = 0
text.Parent = marker
marker.Parent = anchor

local beam = Instance.new("Beam")
beam.Attachment1 = to
beam.LightEmission = 1
beam.FaceCamera = true
beam.Segments = 40
beam.TextureSpeed = 1
beam.Transparency = NumberSequence.new(0.15)
beam.Parent = anchor

local from: Attachment? = nil

local function hide()
	anchor.Parent = nil
end

hud.OnClientEvent:Connect(function(kind: string, data)
	if kind == "Stop" then
		state = { stop = data.stop, phase = data.phase, sleighAt = data.sleighAt }
	elseif kind == "RunEnd" then
		state = nil
		hide()
	end
end)

while true do
	task.wait(0.1)
	local root = Util.rootOf(player)
	local at = root and root.Position
	if not SleighGuide.shows(state, at, CutscenePlayer.isPlaying()) then
		hide()
		continue
	end
	local s = state :: SleighGuide.State
	local sleighAt = s.sleighAt :: Vector3
	if not from or from.Parent ~= root then
		if from then
			from:Destroy()
		end
		from = Instance.new("Attachment")
		from.Name = "SleighGuideFrom"
		from.Axis = Vector3.yAxis
		from.SecondaryAxis = Vector3.xAxis
		from.Parent = root
		beam.Attachment0 = from
	end
	local distance = ((sleighAt - (at :: Vector3)) * Vector3.new(1, 0, 1)).Magnitude
	local style = SleighGuide.style(distance, s.phase == "Horn")
	anchor.CFrame = CFrame.new(sleighAt)
	beam.Color = ColorSequence.new(style.color)
	beam.Width0 = style.width * 0.6
	beam.Width1 = style.width
	beam.CurveSize0 = style.curve
	beam.CurveSize1 = -style.curve * 0.5
	text.Text = SleighGuide.label(distance)
	text.TextColor3 = style.color
	anchor.Parent = workspace
end
