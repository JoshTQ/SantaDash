--[[
	Greybox HUD: stop timer and phase, Jingle, sack, noise meter, banners,
	sleigh queue, Krampus bells, hiding (breath), snatched (wiggle) and the
	results screen, and random map events (event chip, Blizzard fog and snow,
	snowballs, splats). Plain frames, no art. Cutscenes play in CutscenePlayer.
]]

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BodyHeat = require(ReplicatedStorage.Shared.BodyHeat)
local Config = require(ReplicatedStorage.Shared.Config)
local HudFeedback = require(ReplicatedStorage.Shared.HudFeedback)
local HudLayout = require(ReplicatedStorage.Shared.HudLayout)
local QueueText = require(ReplicatedStorage.Shared.QueueText)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local CutscenePlayer = require(script.Parent:WaitForChild("CutscenePlayer"))
local PuppetPlayer = require(script.Parent:WaitForChild("PuppetPlayer"))

local player = Players.LocalPlayer
local hud = Remotes.get("Hud")
local leaveCrew = Remotes.get("LeaveCrew")
local input = Remotes.get("Input")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 80, 80)
local GOLD = Color3.fromRGB(255, 200, 60)
local HOUSE_STOPS = #Config.Run.StopKinds - 1
local BREAKOUT_PRICE = 0
for _, item in Config.Store.Items do
	if item.id == "InstantBreakout" then
		BREAKOUT_PRICE = item.price
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "SleighHeistHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- Phones: scale the HUD to the screen, keep out of the thumbstick and jump
-- button corners (HudLayout).
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local touch = UserInputService.TouchEnabled == true
local spots = HudLayout.spots(touch)
local lastViewport: Vector2? = nil
local function fitToScreen()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	if viewport ~= lastViewport then
		lastViewport = viewport
		uiScale.Scale = HudLayout.scale(viewport)
	end
end
fitToScreen()

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = WHITE
	l.TextStrokeTransparency = 0.3
	l.Font = FONT
	l.TextSize = textSize or 22
	l.Text = ""
	l.Parent = parent
	return l
end

local function panel(size: UDim2, position: UDim2, anchor: Vector2): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor
	f.BackgroundColor3 = Color3.fromRGB(20, 25, 45)
	f.BackgroundTransparency = 0.25
	f.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = f
	f.Parent = gui
	return f
end

local function button(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	onClick: () -> ()
): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	b.TextColor3 = WHITE
	b.Font = FONT
	b.TextSize = 20
	b.Text = text
	-- Rounded with a dark rim, like the tip card, so buttons read as buttons.
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Color3.fromRGB(20, 25, 45)
	rim.Thickness = 2
	rim.Parent = b
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function bar(parent: Instance, position: UDim2): Frame
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, -20, 0, 18)
	back.Position = position
	back.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	back.Parent = parent
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

local function setBar(fill: Frame, pct: number, from: Color3, to: Color3)
	pct = math.clamp(pct, 0, 1)
	fill.Size = UDim2.fromScale(pct, 1)
	fill.BackgroundColor3 = from:Lerp(to, pct)
end

local function leave()
	leaveCrew:FireServer()
end

-- Which device the button labels are for: phones never see "(Space)".
local function lastInputName(): string?
	local ok, inputType = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	return if ok and inputType then inputType.Name else nil
end
local device = HudFeedback.deviceFor(lastInputName(), touch)
local keyed: { [TextButton]: string } = {} -- button -> action
local function relabel()
	for b, action in keyed do
		b.Text = HudFeedback.keyHint(action, device)
	end
end
local lastInputChanged = (UserInputService :: any).LastInputTypeChanged
if lastInputChanged then
	lastInputChanged:Connect(function(inputType)
		local now = HudFeedback.deviceFor(inputType.Name, touch)
		-- Mouse moves and stray inputs shouldn't flip a phone to keyboard
		-- labels unless a real keyboard is attached.
		if now ~= device and (now ~= "Keyboard" or UserInputService.KeyboardEnabled) then
			device = now
			relabel()
		end
	end)
end

local function tap()
	input:FireServer("Tap")
end

-- Top centre: stop and timer.
local stopPanel = panel(UDim2.fromOffset(300, 84), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
local stopLabel = label(stopPanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 22)
local timerLabel = label(stopPanel, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 34), 40)

-- Top left: Jingle and sack.
local statsPanel = panel(UDim2.fromOffset(250, 96), UDim2.fromOffset(12, 8), Vector2.zero)
local jingleLabel = label(statsPanel, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 4))
local sackLabel = label(statsPanel, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 34))
local bankedLabel = label(statsPanel, UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 64), 18)
for _, l in { jingleLabel, sackLabel, bankedLabel } do
	l.TextXAlignment = Enum.TextXAlignment.Left
end
jingleLabel.TextColor3 = GOLD

-- Top right: noise meter (what a full meter brings, and a red glow as it
-- nears full) and Krampus bells.
local noisePanel = panel(UDim2.fromOffset(270, 104), UDim2.new(1, -12, 0, 8), Vector2.new(1, 0))
local noiseTitle = label(noisePanel, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 2), 22)
noiseTitle.Text = "NOISE 0%"
local noiseFill = bar(noisePanel, UDim2.fromOffset(10, 30))
local noiseBack = noiseFill.Parent :: Frame
noiseBack.Size = UDim2.new(1, -20, 0, 24)
local noiseHint = label(noisePanel, UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 56), 18)
local bellsLabel = label(noisePanel, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 78), 20)
bellsLabel.TextColor3 = RED
local noiseGlow = Instance.new("UIStroke")
noiseGlow.Color = RED
noiseGlow.Thickness = 0
noiseGlow.Parent = noisePanel
local noiseLevel = 0 -- 0..1, the last meter value
local NOISE_HINT = {
	-- Short enough for 18 px in the panel (16 px read as ~10 on phones).
	dogs = "Full = dogs + early horn!",
	krampus = "Full = KRAMPUS comes!",
}

-- The glow pulses once the meter is three-quarters full.
task.spawn(function()
	while true do
		local t = os.clock()
		if noisePanel.Visible and noiseLevel >= 0.75 then
			noiseGlow.Thickness = if noiseLevel >= 1 then 4 else 2 + math.sin(t * 8) * 1.5
		else
			noiseGlow.Thickness = 0
		end
		task.wait(0.05)
	end
end)

-- Red edge glow while Krampus is near.
local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.BorderSizePixel = 0
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(200, 0, 0)
stroke.Thickness = 0
stroke.Parent = vignette
vignette.Parent = gui

-- Krampus off screen and close: a red arrow on the screen edge points at him
-- (HudFeedback.edgeArrow), with his name just inside it.
local krampusArrow = Instance.new("Frame")
krampusArrow.Name = "KrampusArrow"
krampusArrow.Size = UDim2.fromOffset(56, 56)
krampusArrow.AnchorPoint = Vector2.new(0.5, 0.5)
krampusArrow.BackgroundTransparency = 1
krampusArrow.Visible = false
krampusArrow.Parent = gui
local arrowShaft = Instance.new("Frame")
arrowShaft.Size = UDim2.fromOffset(30, 12)
arrowShaft.Position = UDim2.fromOffset(4, 22)
arrowShaft.BackgroundColor3 = RED
arrowShaft.BorderSizePixel = 0
arrowShaft.Parent = krampusArrow
local arrowHead = Instance.new("Frame") -- a square turned 45 degrees
arrowHead.Size = UDim2.fromOffset(26, 26)
arrowHead.Position = UDim2.fromOffset(24, 15)
arrowHead.Rotation = 45
arrowHead.BackgroundColor3 = RED
arrowHead.BorderSizePixel = 0
arrowHead.Parent = krampusArrow
for _, part in { arrowShaft, arrowHead } do
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.new(1, 1, 1)
	rim.Thickness = 2
	rim.Parent = part
end
local arrowLabel = label(gui, UDim2.fromOffset(110, 24), UDim2.new(), 18)
arrowLabel.AnchorPoint = Vector2.new(0.5, 0.5)
arrowLabel.TextColor3 = RED
arrowLabel.Text = "KRAMPUS!"
arrowLabel.Visible = false

local function hideKrampusArrow()
	krampusArrow.Visible = false
	arrowLabel.Visible = false
end

local function showKrampusArrow(target: Vector3, distance: number)
	local camera = workspace.CurrentCamera
	if not camera or distance > HudFeedback.ArrowRange or not (camera :: any).WorldToScreenPoint then
		hideKrampusArrow()
		return
	end
	local point, onScreen = camera:WorldToScreenPoint(target)
	local size = gui.AbsoluteSize / math.max(uiScale.Scale, 0.01)
	local spot = HudFeedback.edgeArrow(point, onScreen, size)
	if not spot then
		hideKrampusArrow()
		return
	end
	krampusArrow.Position = UDim2.fromOffset(spot.x, spot.y)
	krampusArrow.Rotation = spot.rotation
	-- The name sits 48 px further in, towards the middle of the screen.
	local inward = Vector2.new(size.X / 2 - spot.x, size.Y / 2 - spot.y)
	local at = Vector2.new(spot.x, spot.y) + (if inward.Magnitude > 0 then inward.Unit * 48 else Vector2.zero)
	arrowLabel.Position = UDim2.fromOffset(at.X, at.Y)
	-- Brighter as he closes in.
	local fade = math.clamp((distance - 30) / (HudFeedback.ArrowRange - 30), 0, 0.6)
	arrowShaft.BackgroundTransparency = fade
	arrowHead.BackgroundTransparency = fade
	krampusArrow.Visible = true
	arrowLabel.Visible = true
end

-- Under the stop timer, one column that only takes the room of what is
-- showing: the map event chip, body heat, the banner and the tip card
-- (Tips.client parents its card here). They used to sit at fixed heights,
-- so the banner wrote over the tip card and the heat bar hid under it.
local topStack = Instance.new("Frame")
topStack.Name = HudLayout.TopStack.name
topStack.Size = UDim2.fromOffset(HudLayout.TopStack.width, 0)
topStack.Position = UDim2.new(0.5, 0, 0, HudLayout.TopStack.y)
topStack.AnchorPoint = Vector2.new(0.5, 0)
topStack.BackgroundTransparency = 1
topStack.Parent = gui
local stackLayout = Instance.new("UIListLayout")
stackLayout.FillDirection = Enum.FillDirection.Vertical
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
stackLayout.Padding = UDim.new(0, 6)
stackLayout.Parent = topStack

local function stacked(f: GuiObject, key: string)
	f.Position = UDim2.new()
	f.AnchorPoint = Vector2.zero
	f.LayoutOrder = HudLayout.TopStack.order[key]
	f.Parent = topStack
end

-- Banners: up to three dark pills (HudFeedback.feedAdd), newest at the
-- bottom, so a busy moment never wipes a warning; each reads on bright snow.
local bannersFrame = Instance.new("Frame")
bannersFrame.Name = "Banners"
bannersFrame.Size = UDim2.new(1, 0, 0, 0)
bannersFrame.AutomaticSize = Enum.AutomaticSize.Y
bannersFrame.BackgroundTransparency = 1
bannersFrame.Visible = false
stacked(bannersFrame, "banner")
local bannersLayout = Instance.new("UIListLayout")
bannersLayout.FillDirection = Enum.FillDirection.Vertical
bannersLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bannersLayout.SortOrder = Enum.SortOrder.LayoutOrder
bannersLayout.Padding = UDim.new(0, 4)
bannersLayout.Parent = bannersFrame
local bannerPills: { { frame: Frame, text: TextLabel } } = {}
for i = 1, HudFeedback.BannerMax do
	local pill = Instance.new("Frame")
	pill.Name = "Banner" .. i
	pill.LayoutOrder = i
	pill.Size = UDim2.new(1, 0, 0, 0)
	pill.AutomaticSize = Enum.AutomaticSize.Y
	pill.BackgroundColor3 = Color3.fromRGB(20, 25, 45)
	pill.BackgroundTransparency = 0.35
	pill.Visible = false
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0, 14)
	pillCorner.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = pill
	pill.Parent = bannersFrame
	local text = label(pill, UDim2.new(1, 0, 0, 0), UDim2.new(), 30)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextWrapped = true
	bannerPills[i] = { frame = pill, text = text }
end
local bannerFeed: { HudFeedback.FeedEntry } = {}
local function drawBanners()
	for i, pill in bannerPills do
		local e = bannerFeed[i]
		pill.frame.Visible = e ~= nil
		pill.text.Text = if e then e.text else ""
		-- Older lines step down in size so the newest reads first.
		pill.text.TextSize = if e and i < #bannerFeed then 24 else 30
	end
	bannersFrame.Visible = #bannerFeed > 0
end

-- Hiding / snatched panel with the big TAP button (Space works too).
local krampusPanel = panel(UDim2.fromOffset(320, 130), UDim2.new(0.5, 0, 1, -250), Vector2.new(0.5, 0))
local krampusLabel = label(krampusPanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 22)
local krampusFill = bar(krampusPanel, UDim2.fromOffset(10, 38))
local tapButton = button(krampusPanel, "TAP!", UDim2.fromOffset(140, 50), UDim2.new(0, 10, 0, 66), tap)
keyed[tapButton] = "Tap"
local unhideButton = button(
	krampusPanel,
	"Come out",
	UDim2.fromOffset(140, 50),
	UDim2.new(1, -150, 0, 66),
	function()
		input:FireServer("Unhide")
	end
)
-- Snatched: use an Instant Break-out (or buy one; the server checks the store rules).
local breakoutButton = button(
	krampusPanel,
	"Break out",
	UDim2.fromOffset(140, 50),
	UDim2.new(1, -150, 0, 66),
	function()
		input:FireServer("Breakout")
	end
)
breakoutButton.BackgroundColor3 = Color3.fromRGB(60, 140, 70)
breakoutButton.Visible = false

-- Bottom centre: sleigh queue.
local queuePanel = panel(UDim2.fromOffset(380, 100), UDim2.new(0.5, 0, 1, -110), Vector2.new(0.5, 0))
local queueLabel = label(queuePanel, UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 4), 24)
queueLabel.TextWrapped = true
local queueButton =
	button(queuePanel, "Leave queue", UDim2.fromOffset(160, 34), UDim2.new(0.5, -80, 0, 58), leave)

-- Top left, under the stats: quit the run back to the hub (never in the
-- bottom-left, where a phone's thumbstick is). Two taps: the first only asks,
-- so a stray thumb on a phone never throws away a run.
local QUIT_TEXT = "Back to hub"
local quitArmedUntil = 0
local quitButton: TextButton
quitButton = button(gui, QUIT_TEXT, UDim2.fromOffset(130, 30), spots.quit, function()
	local go, armedUntil = HudFeedback.confirmLeave(Util.now(), quitArmedUntil)
	quitArmedUntil = armedUntil
	if go then
		quitButton.Text = QUIT_TEXT
		leave()
	else
		quitButton.Text = "Tap again to leave"
	end
end)
quitButton.Visible = false

-- Music on/off, saved with the player's data (server/Settings).
local function musicText(): string
	return if player:GetAttribute("MusicOff") == true then "Music: OFF" else "Music: ON"
end
local musicButton = button(gui, musicText(), UDim2.fromOffset(130, 30), spots.musicHub, function()
	input:FireServer("Music", player:GetAttribute("MusicOff") == true)
end)
musicButton.TextSize = 18
musicButton.BackgroundColor3 = Color3.fromRGB(60, 80, 140)
player:GetAttributeChangedSignal("MusicOff"):Connect(function()
	musicButton.Text = musicText()
end)

-- Under the stop timer: the running map event and its countdown.
local eventPanel = panel(UDim2.fromOffset(240, 34), UDim2.new(0.5, 0, 0, 98), Vector2.new(0.5, 0))
eventPanel.BackgroundColor3 = Color3.fromRGB(60, 110, 170)
stacked(eventPanel, "event")
local eventLabel = label(eventPanel, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 22)

-- Under that: body heat in Krampus's Lair (server/Swimming sets the player
-- attributes). Only shows while you're cooling down or warming back up.
local heatPanel = panel(UDim2.fromOffset(260, 58), UDim2.new(0.5, 0, 0, 138), Vector2.new(0.5, 0))
local heatLabel = label(heatPanel, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 2), 18)
local heatFill = bar(heatPanel, UDim2.fromOffset(10, 30))
heatPanel.Visible = false
stacked(heatPanel, "heat")
local function showHeat()
	local heat = player:GetAttribute(BodyHeat.ATTRIBUTE)
	local frozen = player:GetAttribute(BodyHeat.FROZEN_ATTRIBUTE) == true
	if type(heat) ~= "number" then
		heatPanel.Visible = false
		return
	end
	heatPanel.Visible = BodyHeat.visible(heat, frozen)
	heatLabel.Text = BodyHeat.label(heat, frozen)
	heatLabel.TextColor3 = if heat < 0.3 or frozen then Color3.fromRGB(140, 210, 255) else Color3.new(1, 1, 1)
	setBar(heatFill, heat, Color3.fromRGB(90, 170, 255), Color3.fromRGB(255, 140, 60))
end
player:GetAttributeChangedSignal(BodyHeat.ATTRIBUTE):Connect(showHeat)
player:GetAttributeChangedSignal(BodyHeat.FROZEN_ATTRIBUTE):Connect(showHeat)

-- Bottom right (above the jump button on phones): snowballs and the throw
-- button (F / R2 / tap).
local snowPanel = panel(UDim2.fromOffset(170, 96), spots.snow, Vector2.new(1, 0))
local snowLabel = label(snowPanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 22)
local throwButton = button(snowPanel, "THROW", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 38), function()
	input:FireServer("Throw")
end)
keyed[throwButton] = "Throw"
relabel()

-- Above that: the Naughty List's pass button while you carry it (Q / L1 / tap; G and L2 are the dog bone).
local listSpot =
	UDim2.new(spots.snow.X.Scale, spots.snow.X.Offset, spots.snow.Y.Scale, spots.snow.Y.Offset - 106)
local listPanel = panel(UDim2.fromOffset(190, 96), listSpot, Vector2.new(1, 0))
local listLabel = label(listPanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 20)
listLabel.Text = "You have the List!"
listLabel.TextColor3 = GOLD
local passButton = button(
	listPanel,
	"PASS LIST",
	UDim2.new(1, -20, 0, 50),
	UDim2.fromOffset(10, 38),
	function()
		input:FireServer("PassList")
	end
)
keyed[passButton] = "PassList"

-- Middle of the screen: the Lair's Cuckoo Watch (server/CuckooWatch).
-- In the top column, above the banners, so a "SPOTTED!" banner and the
-- big cuckoo words never sit on top of each other.
local cuckooLabel = label(gui, UDim2.fromOffset(520, 60), UDim2.new(), 48)
cuckooLabel.Name = "Cuckoo"
cuckooLabel.Visible = false
stacked(cuckooLabel, "cuckoo")
local cuckooToken = 0

-- Dog treats (Config.DogAI.Bone): left of the snowballs, G / L2 / tap.
local bonePanel = panel(UDim2.fromOffset(170, 96), spots.bone, Vector2.new(1, 0))
local boneLabel = label(bonePanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 22)
local boneButton = button(bonePanel, "BONE", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 38), function()
	input:FireServer("Bone")
end)
keyed[boneButton] = "Bone"
relabel()

-- Full-screen splat when a crewmate's snowball hits you (cosmetic only).
local splatFrame = Instance.new("Frame")
splatFrame.Size = UDim2.fromScale(1, 1)
splatFrame.BackgroundColor3 = Color3.new(1, 1, 1)
splatFrame.BackgroundTransparency = 1
splatFrame.BorderSizePixel = 0
splatFrame.Parent = gui
local splatLabel = label(splatFrame, UDim2.new(1, 0, 0, 60), UDim2.fromScale(0, 0.45), 40)
splatLabel.TextColor3 = Color3.fromRGB(60, 110, 170)

-- Results.
local resultsPanel = panel(UDim2.fromOffset(460, 340), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
local resultsTitle = label(resultsPanel, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 8), 32)
resultsTitle.TextColor3 = GOLD
local resultsBody = label(resultsPanel, UDim2.new(1, -24, 1, -170), UDim2.fromOffset(12, 56), 20)
resultsBody.TextYAlignment = Enum.TextYAlignment.Top
resultsBody.TextXAlignment = Enum.TextXAlignment.Left
resultsBody.RichText = true
local resultsFooter = label(resultsPanel, UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 1, -44), 22)
-- Your own haul, big, above the footer: the number a kid actually cares about.
local resultsMine = label(resultsPanel, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 1, -82), 26)
resultsMine.TextColor3 = GOLD
local resultsSummary = label(resultsPanel, UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 1, -128), 18)
resultsSummary.TextWrapped = true
local resultsToken = 0

-- Floating "+12" numbers off the stats panel (HudFeedback.pops).
local POP_COLOURS = {
	sack = Color3.new(1, 1, 1),
	jingle = GOLD,
	bank = Color3.fromRGB(120, 230, 120),
	spill = RED,
	spend = Color3.fromRGB(255, 170, 90),
}
local popRise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function pop(p: HudFeedback.Pop)
	-- Right-aligned at the end of the stat's own row (the rows' text is
	-- left-aligned and short), rising and fading in under a second.
	local big = p.kind == "bank"
	local row = if p.kind == "jingle" or p.kind == "spend"
		then jingleLabel
		elseif big then bankedLabel
		else sackLabel
	local l = label(
		statsPanel,
		UDim2.fromOffset(90, 28),
		UDim2.new(1, -98, 0, row.Position.Y.Offset),
		if big then 28 else 24
	)
	l.Name = "Pop"
	l.TextXAlignment = Enum.TextXAlignment.Right
	l.TextColor3 = POP_COLOURS[p.kind] or WHITE
	l.Text = p.text
	local goal = {
		Position = l.Position - UDim2.fromOffset(0, if big then 36 else 24),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}
	local tween = TweenService:Create(l, popRise, goal)
	tween.Completed:Connect(function()
		l:Destroy()
	end)
	tween:Play()
end

-- A quick swell on a label (the sack when it fills, the banked line).
local function bump(l: TextLabel)
	local base = l:GetAttribute("BaseTextSize") or l.TextSize
	l:SetAttribute("BaseTextSize", base)
	l.TextSize = base + 6
	TweenService:Create(l, TweenInfo.new(0.35, Enum.EasingStyle.Back), { TextSize = base }):Play()
end

----------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------

local stopState: any = nil
local queueState: any = nil
local resultsEndsAt = 0
local krampusModel: Model? = nil
local tapMode = false -- hiding or snatched
local eventEndsAt: number? = nil
local eventName = ""
local savedFog: { any }? = nil -- Lighting fog before a weather event
local savedAtmosphere: { [string]: any }? = nil -- and the Atmosphere's look
local snowfall: BasePart? = nil -- follows the camera while it snows
local splatUntil = 0
local lastPlayerData: any = nil

-- Labels refreshed by the loop at the bottom only get written when the text changes.
local shown: { [TextLabel]: string } = {}
local function setText(l: TextLabel, text: string)
	if shown[l] ~= text then
		shown[l] = text
		l.Text = text
	end
end

local PHASE_TEXT = {
	Flight = "FLYING",
	Sneak = "SNEAK",
	LightsOn = "LIGHTS ON",
	Horn = "GET ON THE SLEIGH!",
}

local function secondsLeft(endsAt: number): number
	return math.max(0, math.ceil(endsAt - Util.now()))
end

local function showBanner(text: string, seconds: number)
	HudFeedback.feedAdd(bannerFeed, text, seconds)
	drawBanners()
end

local function setInRun(inRun: boolean)
	stopPanel.Visible = inRun
	statsPanel.Visible = inRun
	noisePanel.Visible = inRun
	quitButton.Visible = inRun
	musicButton.Position = if inRun then spots.music else spots.musicHub
end

local function setTapMode(on: boolean)
	tapMode = on
	krampusPanel.Visible = on
	if on then
		ContextActionService:BindAction("SleighHeistTap", function(_, state)
			if state == Enum.UserInputState.Begin then
				tap()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	else
		ContextActionService:UnbindAction("SleighHeistTap")
	end
end

local handlers = {}

function handlers.Queue(data)
	queueState = data
	queuePanel.Visible = true
	resultsPanel.Visible = false
	queueButton.Text = if data.requeue then "Leave crew" else "Leave queue"
end

function handlers.QueueClear()
	queueState = nil
	queuePanel.Visible = false
end

function handlers.Stop(data)
	stopState = data
	setInRun(true)
	local phase = PHASE_TEXT[data.phase] or data.phase
	if data.stop == 0 then
		stopLabel.Text = "TAKE-OFF"
	elseif data.isFinale then
		stopLabel.Text = "KRAMPUS'S LAIR · " .. phase
	else
		stopLabel.Text = "STOP " .. data.stop .. "/" .. HOUSE_STOPS .. " · " .. phase
	end
	noiseHint.Text = NOISE_HINT[data.noiseThreat or ""] or ""
	local horn = data.phase == "Horn"
	stopLabel.TextColor3 = if horn then RED else WHITE
	timerLabel.TextColor3 = if horn then RED else WHITE
	if data.phase == "Flight" or data.stop == 0 then
		setText(timerLabel, "~")
	end
end

function handlers.Banner(data)
	showBanner(data.text, data.seconds or 3)
end

function handlers.Noise(data)
	noiseLevel = math.clamp(data.value / Config.Noise.Max, 0, 1)
	setBar(noiseFill, noiseLevel, Color3.fromRGB(120, 220, 120), RED)
	noiseTitle.Text = if noiseLevel >= 1
		then "NOISE FULL!"
		else ("NOISE %d%%"):format(math.floor(noiseLevel * 100))
	noiseTitle.TextColor3 = if noiseLevel >= 0.75 then RED else WHITE
end

function handlers.Player(data)
	setInRun(true)
	jingleLabel.Text = "Jingle: " .. data.jingle
	local full = HudFeedback.sackFull(data, Config.Sack.Capacity)
	sackLabel.Text = string.format(
		"Sack: %d/%d  (%d)%s",
		data.sackCount,
		data.sackCapacity or Config.Sack.Capacity,
		data.sackValue,
		if full then "  FULL" else ""
	)
	sackLabel.TextColor3 = if full then RED else WHITE
	bankedLabel.Text = "Banked in sleigh: " .. data.banked .. (if data.rush then "  · Rush" else "")
	local before = lastPlayerData
	lastPlayerData = data
	for _, p in HudFeedback.pops(before, data) do
		pop(p)
		if p.kind == "bank" then
			bump(bankedLabel)
		end
	end
	if full and before and not HudFeedback.sackFull(before, Config.Sack.Capacity) then
		bump(sackLabel)
	end
end

function handlers.Krampus(data)
	krampusModel = data.model
	if not krampusModel then
		setText(bellsLabel, "")
		stroke.Thickness = 0
		hideKrampusArrow()
	end
end

function handlers.KrampusTease()
	setText(bellsLabel, "* distant bells *")
	task.delay(5, function()
		if not krampusModel then
			setText(bellsLabel, "")
		end
	end)
end

function handlers.Hide(data)
	setTapMode(data.hidden)
	unhideButton.Visible = true
	breakoutButton.Visible = false
	if data.hidden then
		krampusLabel.Text = "Hiding! Tap to hold your breath"
		setBar(krampusFill, data.breath, RED, Color3.fromRGB(120, 200, 255))
	end
end

function handlers.Captive(data)
	setTapMode(data.captive)
	unhideButton.Visible = false
	if data.captive and data.breakout then
		-- Only sent on the snatch itself; wiggle updates keep the button as is.
		local offer = data.breakout
		breakoutButton.Text = if offer.owned > 0
			then string.format("Break out (%d left)", offer.owned)
			else "Break out  R$" .. BREAKOUT_PRICE
		breakoutButton.Visible = true
	elseif not data.captive or data.wiggles == 0 then
		breakoutButton.Visible = false
	end
	if data.captive then
		krampusLabel.Text = "SNATCHED! Tap to wiggle free"
		setBar(
			krampusFill,
			data.wiggles / data.needed,
			Color3.fromRGB(255, 160, 60),
			Color3.fromRGB(120, 220, 120)
		)
	end
end

-- Frost Zap: frozen in an ice cube, tap to crack out (server/KrampusMagic).
function handlers.Iced(data)
	setTapMode(data.iced)
	-- Only TAP! here: "Come out" (hiding) or "Break out" (snatched) left
	-- over from earlier would do nothing in an ice cube.
	unhideButton.Visible = false
	breakoutButton.Visible = false
	if data.iced then
		krampusLabel.Text = "FROZEN! Tap to crack out"
		setBar(
			krampusFill,
			data.taps / data.needed,
			Color3.fromRGB(127, 227, 255),
			Color3.fromRGB(120, 220, 120)
		)
	end
end

function handlers.Results(data)
	setInRun(false)
	stopState = nil
	resultsPanel.Visible = true
	local best = data.rows[1]
	resultsTitle.Text = if best then "Best thief: " .. best.name else "Run over"
	local lines = {}
	local mine = nil
	for i, row in data.rows do
		-- Display names aren't unique on Roblox: match on the user id.
		local me = if row.userId then row.userId == player.UserId else row.name == player.DisplayName
		if me then
			mine = row
		end
		local line = string.format(
			"%d. <b>%s</b>  loot %d  ->  %d Coal  %s",
			i,
			Util.escapeRichText(row.name),
			row.loot,
			row.coal,
			"(" .. HudFeedback.escapeText(row) .. ")"
		)
		table.insert(lines, if me then '<font color="#FFC83C">' .. line .. "</font>" else line)
	end
	resultsBody.Text = table.concat(lines, "\n")
	resultsSummary.Text = if mine
		then HudFeedback.summary(mine, player:GetAttribute("FirstHeist") == true)
		else ""
	resultsMine.Text = ""
	resultsToken += 1
	local token = resultsToken
	if mine then
		-- Count the Coal up, with a swell when it lands.
		local coal = mine.coal
		task.spawn(function()
			local started = Util.now()
			while resultsToken == token do
				local counted = HudFeedback.countUp(coal, Util.now() - started)
				resultsMine.Text = "You got +" .. counted .. " Coal!"
				if counted >= coal then
					bump(resultsMine)
					break
				end
				task.wait(0.03)
			end
		end)
	end
	resultsEndsAt = data.endsAt
end

-- The HUD chip for a running map event; empty data = it's over.
function handlers.MapEvent(data)
	eventEndsAt = data.endsAt
	eventPanel.Visible = data.endsAt ~= nil
	eventName = data.label or ""
end

-- Local-only weather, so other crews' runs in the same server are untouched.
function handlers.Weather(data)
	if data.kind == "Blizzard" then
		-- Roblox ignores Lighting fog while an Atmosphere exists (the night
		-- sky has one), so thicken that; plain fog covers places without it.
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if not savedFog then
			savedFog = { Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor }
			if atmosphere then
				savedAtmosphere = {
					atmosphere = atmosphere,
					Density = atmosphere.Density,
					Haze = atmosphere.Haze,
					Color = atmosphere.Color,
				}
			end
		end
		Lighting.FogStart = 0
		Lighting.FogEnd = data.fogEnd
		Lighting.FogColor = data.fogColor
		if atmosphere then
			atmosphere.Density = data.density or atmosphere.Density
			atmosphere.Haze = data.haze or atmosphere.Haze
			atmosphere.Color = data.fogColor
		end
		if not snowfall then
			local part = Instance.new("Part")
			part.Name = "Snowfall"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.Transparency = 1
			part.Size = Vector3.new(120, 1, 120)
			local emitter = Instance.new("ParticleEmitter")
			-- Phones fill-rate limit on particles: a lighter flurry there.
			emitter.Rate = if touch then Config.MapEvents.Events.Blizzard.SnowRatePhone else 600
			emitter.Lifetime = NumberRange.new(3, 4)
			emitter.Speed = NumberRange.new(18, 26)
			emitter.EmissionDirection = Enum.NormalId.Bottom
			emitter.SpreadAngle = Vector2.new(25, 25)
			emitter.Size = NumberSequence.new(0.35)
			emitter.Color = ColorSequence.new(Color3.new(1, 1, 1))
			emitter.LightEmission = 0.3
			emitter.Parent = part
			part.Parent = workspace
			snowfall = part
		end
	else
		if savedFog then
			Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor = table.unpack(savedFog)
			savedFog = nil
		end
		if savedAtmosphere then
			local atmosphere = savedAtmosphere.atmosphere
			atmosphere.Density = savedAtmosphere.Density
			atmosphere.Haze = savedAtmosphere.Haze
			atmosphere.Color = savedAtmosphere.Color
			savedAtmosphere = nil
		end
		if snowfall then
			snowfall:Destroy()
			snowfall = nil
		end
	end
end

function handlers.Snowballs(data)
	snowPanel.Visible = data.count > 0
	snowLabel.Text = "Snowballs: " .. data.count
	if data.count > 0 then
		ContextActionService:BindAction("SleighHeistThrow", function(_, state)
			if state == Enum.UserInputState.Begin then
				input:FireServer("Throw")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
	else
		ContextActionService:UnbindAction("SleighHeistThrow")
	end
end

function handlers.List(data)
	listPanel.Visible = data.carrying == true
	if data.carrying then
		ContextActionService:BindAction("SleighHeistPassList", function(_, state)
			if state == Enum.UserInputState.Begin then
				input:FireServer("PassList")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	else
		ContextActionService:UnbindAction("SleighHeistPassList")
	end
end

local CUCKOO_TEXT = {
	Warn = { "TICK TOCK... FREEZE!", GOLD },
	Look = { "CUCKOO! DON'T MOVE!", Color3.fromRGB(255, 90, 90) },
	Spotted = { "SPOTTED! KRAMPUS IS COMING!", Color3.fromRGB(255, 90, 90) },
}

function handlers.Cuckoo(data)
	cuckooToken += 1
	local cue = CUCKOO_TEXT[data.state]
	cuckooLabel.Visible = cue ~= nil
	if not cue then
		return
	end
	cuckooLabel.Text = cue[1]
	cuckooLabel.TextColor3 = cue[2]
	local token = cuckooToken
	task.delay(data.seconds or 1.5, function()
		if cuckooToken == token then
			cuckooLabel.Visible = false
		end
	end)
end

function handlers.Bones(data)
	bonePanel.Visible = data.count > 0
	boneLabel.Text = "Dog treats: " .. data.count
	if data.count > 0 then
		ContextActionService:BindAction("SleighHeistBone", function(_, state)
			if state == Enum.UserInputState.Begin then
				input:FireServer("Bone")
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.G, Enum.KeyCode.ButtonL2)
	else
		ContextActionService:UnbindAction("SleighHeistBone")
	end
end

function handlers.Splat(data)
	splatUntil = Util.now() + data.seconds
	splatLabel.Text = "SPLAT! (" .. data.by .. ")"
end

function handlers.Cutscene(data)
	CutscenePlayer.play(data)
end

-- The sleigh in flight and Krampus's scripted moves, posed smoothly here.
function handlers.Puppets(data)
	PuppetPlayer.play(data)
end

function handlers.RunEnd()
	CutscenePlayer.stop()
	PuppetPlayer.clear()
	handlers.MapEvent({})
	handlers.Weather({})
	handlers.Snowballs({ count = 0 })
	handlers.List({ carrying = false })
	handlers.Cuckoo({ state = "Off" })
	handlers.Bones({ count = 0 })
	setInRun(false)
	setTapMode(false)
	handlers.Krampus({})
	stopState = nil
	lastPlayerData = nil -- the next run's first update isn't a "spend"
	quitArmedUntil = 0
	quitButton.Text = QUIT_TEXT
	resultsPanel.Visible = false
end

hud.OnClientEvent:Connect(function(kind: string, data)
	local handler = handlers[kind]
	if handler then
		handler(data)
	end
end)

-- The Krampus arrow follows the camera every frame (the loop below is 10 Hz,
-- which looks jumpy while you turn).
local renderStepped = (RunService :: any).RenderStepped
if renderStepped then
	renderStepped:Connect(function()
		local root = Util.rootOf(player)
		if
			krampusModel
			and krampusModel.Parent
			and root
			and not tapMode
			and not CutscenePlayer.isPlaying()
		then
			local at = krampusModel:GetPivot().Position
			showKrampusArrow(at, (at - root.Position).Magnitude)
		elseif krampusArrow.Visible then
			hideKrampusArrow()
		end
	end)
end

-- Countdowns and Krampus distance change at most a few times a second, so the
-- HUD refreshes every 0.1 s instead of every frame.
local lastTick = Util.now()
while true do
	task.wait(0.1)
	fitToScreen() -- phones rotate and resize
	-- Cutscenes own the screen: the HUD hides under the letterbox, and
	-- banners wait for it (HudFeedback.feedTick).
	local cutscene = CutscenePlayer.isPlaying()
	gui.Enabled = not cutscene
	local nowClock = Util.now()
	if HudFeedback.feedTick(bannerFeed, nowClock - lastTick, cutscene) then
		drawBanners()
	end
	lastTick = nowClock
	if stopState and stopState.stop > 0 and stopState.phase ~= "Flight" then
		local left = secondsLeft(stopState.departAt)
		setText(timerLabel, Util.clock(left))
		-- The horn's last seconds throb so nobody misses the sleigh.
		local urgency = HudFeedback.timerUrgency(stopState.phase, left)
		timerLabel.TextSize = 40 + urgency * math.abs(math.sin(os.clock() * 6))
	else
		timerLabel.TextSize = 40
	end
	if quitArmedUntil > 0 and Util.now() >= quitArmedUntil then
		quitArmedUntil = 0
		quitButton.Text = QUIT_TEXT
	end
	if queueState then
		setText(queueLabel, QueueText.line(queueState, Util.now()))
	end
	if eventEndsAt then
		setText(eventLabel, eventName .. "  " .. Util.clock(secondsLeft(eventEndsAt)))
	end
	local splatLeft = splatUntil - Util.now()
	splatFrame.BackgroundTransparency = if splatLeft > 0 then 1 - math.min(0.45, splatLeft) else 1 -- never blinding
	splatLabel.Visible = splatLeft > 0
	local camera = workspace.CurrentCamera
	if snowfall and camera then
		snowfall.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
	end
	if resultsPanel.Visible then
		setText(resultsFooter, "Next run in " .. secondsLeft(resultsEndsAt) .. "...")
	end
	local root = Util.rootOf(player)
	if krampusModel and krampusModel.Parent and root and not tapMode then
		local distance = (krampusModel:GetPivot().Position - root.Position).Magnitude
		setText(
			bellsLabel,
			if distance < 30
				then "BELLS! BELLS! BELLS!"
				elseif distance < 70 then "Bells! Bells!"
				else "bells..."
		)
		stroke.Thickness = if distance < 30 then 12 elseif distance < 70 then 5 else 0
	end
end
