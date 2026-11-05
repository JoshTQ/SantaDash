--[[
	First-time player tips (client side): the tip card and the guide trail.

	Hud kinds from server/Onboarding.luau:
		Tip { id, seconds }   queue a tip card (wording from shared/Tutorial)
		TipDone { id }        the player did it: drop that card
		Guide { at? }         a glowing trail from your Santa to `at`; {} clears it

	One card at a time, never while a cutscene plays. The card's X switches
	tips off for good (Input "TipsOff"). The trail clears itself once you
	reach the spot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local HudLayout = require(ReplicatedStorage.Shared.HudLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local Util = require(ReplicatedStorage.Shared.Util)
local CutscenePlayer = require(script.Parent:WaitForChild("CutscenePlayer"))

local player = Players.LocalPlayer
local hud = Remotes.get("Hud")
local input = Remotes.get("Input")
local touch = UserInputService.TouchEnabled == true

local GOLD = Color3.fromRGB(255, 200, 60)
local ARRIVED = 10 -- studs: close enough, the trail goes away

local gui = Instance.new("ScreenGui")
gui.Name = "SleighHeistTips"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui

-- Top centre, under the stop timer and the event chip; clear of the phone
-- thumbstick and jump button corners.
local card = Instance.new("Frame")
card.Size = UDim2.fromOffset(440, 58)
card.Position = UDim2.new(0.5, 0, 0, 140)
card.AnchorPoint = Vector2.new(0.5, 0)
card.BackgroundColor3 = GOLD
card.Visible = false
card.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = card

local text = Instance.new("TextLabel")
text.Size = UDim2.new(1, -70, 1, 0)
text.Position = UDim2.fromOffset(14, 0)
text.BackgroundTransparency = 1
text.Font = Enum.Font.FredokaOne
text.TextColor3 = Color3.fromRGB(60, 30, 10)
text.TextScaled = true
text.TextXAlignment = Enum.TextXAlignment.Left
text.Parent = card
local textLimit = Instance.new("UITextSizeConstraint")
textLimit.MaxTextSize = 28
textLimit.Parent = text

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(46, 46)
close.Position = UDim2.new(1, -52, 0, 6)
close.BackgroundColor3 = Color3.fromRGB(60, 30, 10)
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.FredokaOne
close.TextSize = 26
close.Text = "X"
close.Parent = card
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0)
closeCorner.Parent = close

----------------------------------------------------------------------------
-- Tip queue
----------------------------------------------------------------------------

local queue: { { id: string, seconds: number } } = {}
local current: { id: string, seconds: number }? = nil
local currentUntil = 0
local off = false

local function hideCard()
	current = nil
	card.Visible = false
end

local function showNext()
	local tip = table.remove(queue, 1)
	if not tip then
		return
	end
	current = tip
	currentUntil = Util.now() + tip.seconds
	text.Text = Tutorial.text(tip.id, touch)
	card.Visible = true
end

----------------------------------------------------------------------------
-- Guide trail
----------------------------------------------------------------------------

local guide: { at: Vector3, beam: Beam, from: Attachment, to: Attachment, marker: BasePart }? = nil

local function clearGuide()
	if guide then
		guide.beam:Destroy()
		guide.from:Destroy()
		guide.to:Destroy()
		guide.marker:Destroy()
		guide = nil
	end
end

local function setGuide(at: Vector3)
	clearGuide()
	local root = Util.rootOf(player)
	if not root then
		return
	end
	-- A local-only glowing ring on the spot, and a beam to it.
	local marker = Instance.new("Part")
	marker.Name = "TipMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.4, 8, 8)
	marker.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90))
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Material = Enum.Material.Neon
	marker.Color = GOLD
	marker.Transparency = 0.35
	marker.Parent = workspace
	local to = Instance.new("Attachment")
	to.Position = Vector3.new(0, 2, 0)
	to.Parent = marker
	local from = Instance.new("Attachment")
	from.Name = "TipTrailFrom"
	from.Parent = root
	local beam = Instance.new("Beam")
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(GOLD)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Width0 = 0.6
	beam.Width1 = 1.2
	beam.Segments = 20
	beam.CurveSize0 = 6 -- a gentle arc reads better than a straight line
	beam.Transparency = NumberSequence.new(0.2)
	beam.Parent = marker
	guide = { at = at, beam = beam, from = from, to = to, marker = marker }
end

----------------------------------------------------------------------------
-- Server messages
----------------------------------------------------------------------------

hud.OnClientEvent:Connect(function(kind: string, data)
	if kind == "Tip" and not off and Tutorial.get(data.id) then
		table.insert(queue, { id = data.id, seconds = data.seconds or 5 })
	elseif kind == "TipDone" then
		for i = #queue, 1, -1 do
			if queue[i].id == data.id then
				table.remove(queue, i)
			end
		end
		if current and current.id == data.id then
			hideCard()
		end
	elseif kind == "Guide" then
		if data.at and not off then
			setGuide(data.at)
		else
			clearGuide()
		end
	elseif kind == "RunEnd" then
		clearGuide()
	end
end)

-- Listening now: the server holds tips until this arrives.
input:FireServer("TipsReady")

close.Activated:Connect(function()
	off = true
	table.clear(queue)
	hideCard()
	clearGuide()
	input:FireServer("TipsOff")
end)

-- Respawns get a new root part: re-anchor the trail.
player.CharacterAdded:Connect(function(character)
	if guide then
		local at = guide.at
		character:WaitForChild("HumanoidRootPart", 5)
		setGuide(at)
	end
end)

while true do
	task.wait(0.1)
	local camera = workspace.CurrentCamera
	uiScale.Scale = HudLayout.scale(camera and camera.ViewportSize)
	local cutscene = CutscenePlayer.isPlaying()
	card.Visible = current ~= nil and not cutscene
	if current and not cutscene and Util.now() >= currentUntil then
		hideCard()
	end
	if not current and not cutscene then
		showNext()
	elseif current and cutscene then
		currentUntil = Util.now() + current.seconds -- restart it once the cutscene ends
	end
	local root = Util.rootOf(player)
	if guide and root then
		local flat = (guide.at - root.Position) * Vector3.new(1, 0, 1)
		if flat.Magnitude < ARRIVED then
			clearGuide()
		end
	end
end
