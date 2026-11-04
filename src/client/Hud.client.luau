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

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local CutscenePlayer = require(script.Parent:WaitForChild("CutscenePlayer"))

local player = Players.LocalPlayer
local hud = Remotes.get("Hud")
local leaveCrew = Remotes.get("LeaveCrew")
local input = Remotes.get("Input")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 80, 80)
local GOLD = Color3.fromRGB(255, 200, 60)
local HOUSE_STOPS = #Config.Run.StopKinds - 1

local gui = Instance.new("ScreenGui")
gui.Name = "SleighHeistHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

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

-- Top right: noise meter and Krampus bells.
local noisePanel = panel(UDim2.fromOffset(240, 84), UDim2.new(1, -12, 0, 8), Vector2.new(1, 0))
label(noisePanel, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 2), 18).Text = "NOISE"
local noiseFill = bar(noisePanel, UDim2.fromOffset(10, 28))
local bellsLabel = label(noisePanel, UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 52), 20)
bellsLabel.TextColor3 = RED

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

-- Centre: banner.
local banner = label(gui, UDim2.new(0.8, 0, 0, 90), UDim2.new(0.1, 0, 0.2, 0), 34)
banner.TextWrapped = true
local bannerToken = 0

-- Hiding / snatched panel with the big TAP button (Space works too).
local krampusPanel = panel(UDim2.fromOffset(320, 130), UDim2.new(0.5, 0, 1, -250), Vector2.new(0.5, 0))
local krampusLabel = label(krampusPanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 22)
local krampusFill = bar(krampusPanel, UDim2.fromOffset(10, 38))
button(krampusPanel, "TAP! (Space)", UDim2.fromOffset(140, 50), UDim2.new(0, 10, 0, 66), tap)
local unhideButton = button(
	krampusPanel,
	"Come out",
	UDim2.fromOffset(140, 50),
	UDim2.new(1, -150, 0, 66),
	function()
		input:FireServer("Unhide")
	end
)

-- Bottom centre: sleigh queue.
local queuePanel = panel(UDim2.fromOffset(380, 100), UDim2.new(0.5, 0, 1, -110), Vector2.new(0.5, 0))
local queueLabel = label(queuePanel, UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 4), 24)
queueLabel.TextWrapped = true
button(queuePanel, "Leave crew", UDim2.fromOffset(160, 34), UDim2.new(0.5, -80, 0, 58), leave)

-- Bottom left: quit the run back to the hub.
local quitButton = button(gui, "Back to hub", UDim2.fromOffset(130, 30), UDim2.new(0, 12, 1, -42), leave)
quitButton.Visible = false

-- Under the stop timer: the running map event and its countdown.
local eventPanel = panel(UDim2.fromOffset(240, 34), UDim2.new(0.5, 0, 0, 98), Vector2.new(0.5, 0))
eventPanel.BackgroundColor3 = Color3.fromRGB(60, 110, 170)
local eventLabel = label(eventPanel, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 22)

-- Bottom right: snowballs and the throw button (F / R2 / tap).
local snowPanel = panel(UDim2.fromOffset(170, 96), UDim2.new(1, -12, 1, -110), Vector2.new(1, 0))
local snowLabel = label(snowPanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 22)
button(snowPanel, "THROW (F)", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 38), function()
	input:FireServer("Throw")
end)

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
local resultsBody = label(resultsPanel, UDim2.new(1, -24, 1, -110), UDim2.fromOffset(12, 56), 20)
resultsBody.TextYAlignment = Enum.TextYAlignment.Top
resultsBody.TextXAlignment = Enum.TextXAlignment.Left
resultsBody.RichText = true
local resultsFooter = label(resultsPanel, UDim2.new(1, 0, 0, 36), UDim2.new(0, 0, 1, -44), 22)

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
local snowfall: BasePart? = nil -- follows the camera while it snows
local splatUntil = 0

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
	bannerToken += 1
	local token = bannerToken
	banner.Text = text
	task.delay(seconds, function()
		if bannerToken == token then
			banner.Text = ""
		end
	end)
end

local function setInRun(inRun: boolean)
	stopPanel.Visible = inRun
	statsPanel.Visible = inRun
	noisePanel.Visible = inRun
	quitButton.Visible = inRun
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
	setBar(noiseFill, data.value / Config.Noise.Max, Color3.fromRGB(120, 220, 120), RED)
end

function handlers.Player(data)
	setInRun(true)
	jingleLabel.Text = "Jingle: " .. data.jingle
	sackLabel.Text = string.format("Sack: %d/%d  (%d)", data.sackCount, Config.Sack.Capacity, data.sackValue)
	bankedLabel.Text = "Banked in sleigh: " .. data.banked .. (if data.rush then "  · Rush" else "")
end

function handlers.Krampus(data)
	krampusModel = data.model
	if not krampusModel then
		setText(bellsLabel, "")
		stroke.Thickness = 0
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
	if data.hidden then
		krampusLabel.Text = "Hiding! Tap to hold your breath"
		setBar(krampusFill, data.breath, RED, Color3.fromRGB(120, 200, 255))
	end
end

function handlers.Captive(data)
	setTapMode(data.captive)
	unhideButton.Visible = false
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

function handlers.Results(data)
	setInRun(false)
	stopState = nil
	resultsPanel.Visible = true
	local best = data.rows[1]
	resultsTitle.Text = if best then "Best thief: " .. best.name else "Run over"
	local lines = {}
	for i, row in data.rows do
		table.insert(
			lines,
			string.format(
				"%d. <b>%s</b>  loot %d  ->  %d Coal  %s",
				i,
				row.name,
				row.loot,
				row.coal,
				if row.escaped then "(escaped x2)" else "(missed the sleigh)"
			)
		)
	end
	resultsBody.Text = table.concat(lines, "\n")
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
		if not savedFog then
			savedFog = { Lighting.FogStart, Lighting.FogEnd, Lighting.FogColor }
		end
		Lighting.FogStart = 0
		Lighting.FogEnd = data.fogEnd
		Lighting.FogColor = data.fogColor
		if not snowfall then
			local part = Instance.new("Part")
			part.Name = "Snowfall"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.Transparency = 1
			part.Size = Vector3.new(120, 1, 120)
			local emitter = Instance.new("ParticleEmitter")
			emitter.Rate = 600
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

function handlers.Splat(data)
	splatUntil = Util.now() + data.seconds
	splatLabel.Text = "SPLAT! (" .. data.by .. ")"
end

function handlers.Cutscene(data)
	CutscenePlayer.play(data)
end

function handlers.RunEnd()
	CutscenePlayer.stop()
	handlers.MapEvent({})
	handlers.Weather({})
	handlers.Snowballs({ count = 0 })
	setInRun(false)
	setTapMode(false)
	handlers.Krampus({})
	stopState = nil
	resultsPanel.Visible = false
end

hud.OnClientEvent:Connect(function(kind: string, data)
	local handler = handlers[kind]
	if handler then
		handler(data)
	end
end)

-- Countdowns and Krampus distance change at most a few times a second, so the
-- HUD refreshes every 0.1 s instead of every frame.
while true do
	task.wait(0.1)
	if stopState and stopState.stop > 0 and stopState.phase ~= "Flight" then
		setText(timerLabel, Util.clock(secondsLeft(stopState.departAt)))
	end
	if queueState then
		local prefix = if queueState.requeue then "Heist again together! " else ""
		setText(
			queueLabel,
			if queueState.waiting
				then prefix .. "Waiting for a free street... (" .. queueState.count .. " Santas)"
				else string.format(
					"%sSleigh leaves in %d  ·  %d/%d Santas",
					prefix,
					secondsLeft(queueState.departAt),
					queueState.count,
					Config.Lobby.CrewMax
				)
		)
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
