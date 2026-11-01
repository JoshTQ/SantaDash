--[[
	Greybox HUD: stop timer and phase, Jingle, sack, noise meter, banners,
	sleigh queue and the results screen. Plain frames, no art.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local hud = Remotes.get("Hud")
local leaveCrew = Remotes.get("LeaveCrew")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 80, 80)
local GOLD = Color3.fromRGB(255, 210, 80)

local gui = Instance.new("ScreenGui")
gui.Name = "SleighHeistHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
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

-- Top centre: stop and timer.
local stopPanel = panel(UDim2.fromOffset(300, 84), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
local stopLabel = label(stopPanel, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 4), 22)
local timerLabel = label(stopPanel, UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 34), 40)

-- Top left: Jingle and sack.
local statsPanel = panel(UDim2.fromOffset(240, 96), UDim2.fromOffset(12, 8), Vector2.zero)
local jingleLabel = label(statsPanel, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 4))
local sackLabel = label(statsPanel, UDim2.new(1, -16, 0, 28), UDim2.fromOffset(8, 34))
local bankedLabel = label(statsPanel, UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 64), 18)
for _, l in { jingleLabel, sackLabel, bankedLabel } do
	l.TextXAlignment = Enum.TextXAlignment.Left
end
jingleLabel.TextColor3 = GOLD

-- Top right: noise meter.
local noisePanel = panel(UDim2.fromOffset(240, 56), UDim2.new(1, -12, 0, 8), Vector2.new(1, 0))
local noiseTitle = label(noisePanel, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 2), 18)
noiseTitle.Text = "NOISE"
local noiseBack = Instance.new("Frame")
noiseBack.Size = UDim2.new(1, -20, 0, 18)
noiseBack.Position = UDim2.fromOffset(10, 28)
noiseBack.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
noiseBack.Parent = noisePanel
local noiseFill = Instance.new("Frame")
noiseFill.Size = UDim2.fromScale(0, 1)
noiseFill.BackgroundColor3 = Color3.fromRGB(120, 220, 120)
noiseFill.BorderSizePixel = 0
noiseFill.Parent = noiseBack

-- Centre: banner.
local banner = label(gui, UDim2.new(0.8, 0, 0, 50), UDim2.new(0.1, 0, 0.22, 0), 34)
banner.TextWrapped = true
local bannerToken = 0

-- Bottom centre: sleigh queue.
local queuePanel = panel(UDim2.fromOffset(380, 100), UDim2.new(0.5, 0, 1, -110), Vector2.new(0.5, 0))
local queueLabel = label(queuePanel, UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 4), 24)
queueLabel.TextWrapped = true
local leaveButton = Instance.new("TextButton")
leaveButton.Size = UDim2.fromOffset(160, 34)
leaveButton.Position = UDim2.new(0.5, -80, 0, 58)
leaveButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
leaveButton.TextColor3 = WHITE
leaveButton.Font = FONT
leaveButton.TextSize = 20
leaveButton.Text = "Leave crew"
leaveButton.Parent = queuePanel
leaveButton.Activated:Connect(function()
	leaveCrew:FireServer()
end)

-- Run "leave" button (small, bottom left) so a player can quit back to the hub.
local quitButton = leaveButton:Clone()
quitButton.Size = UDim2.fromOffset(130, 30)
quitButton.Position = UDim2.new(0, 12, 1, -42)
quitButton.Text = "Back to hub"
quitButton.Visible = false
quitButton.Parent = gui
quitButton.Activated:Connect(function()
	leaveCrew:FireServer()
end)

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
local resultsNextRun = 0

local PHASE_TEXT = {
	Takeoff = "TAKE-OFF",
	Flight = "FLYING",
	Sneak = "SNEAK",
	LightsOn = "LIGHTS ON",
	Horn = "GET ON THE SLEIGH!",
}

local function clock(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
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
	if data.stop == 0 then
		stopLabel.Text = "TAKE-OFF"
	elseif data.isFinale then
		stopLabel.Text = "FINALE · " .. (PHASE_TEXT[data.phase] or data.phase)
	else
		stopLabel.Text = "STOP "
			.. data.stop
			.. "/"
			.. (data.total - 1)
			.. " · "
			.. (PHASE_TEXT[data.phase] or data.phase)
	end
	stopLabel.TextColor3 = if data.phase == "Horn" then RED else WHITE
end

function handlers.Banner(data)
	showBanner(data.text, data.seconds or 3)
end

function handlers.Noise(data)
	local pct = math.clamp(data.value / data.max, 0, 1)
	noiseFill.Size = UDim2.fromScale(pct, 1)
	noiseFill.BackgroundColor3 = Color3.fromRGB(120, 220, 120):Lerp(RED, pct)
end

function handlers.Player(data)
	setInRun(true)
	jingleLabel.Text = "Jingle: " .. data.jingle
	sackLabel.Text = string.format("Sack: %d/%d  (%d)", data.sackCount, data.sackCapacity, data.sackValue)
	bankedLabel.Text = "Banked in sleigh: "
		.. data.banked
		.. (if data.perks.PeppermintRush then "  · Rush" else "")
end

function handlers.Results(data)
	setInRun(false)
	stopState = nil
	resultsPanel.Visible = true
	resultsTitle.Text = if data.bestThief then "Best thief: " .. data.bestThief else "Run over"
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
	resultsEndsAt = os.clock() + data.seconds
	resultsNextRun = data.nextRunIn
end

function handlers.RunEnd()
	setInRun(false)
	stopState = nil
	resultsPanel.Visible = false
end

hud.OnClientEvent:Connect(function(kind: string, data)
	local handler = handlers[kind]
	if handler then
		handler(data)
	end
end)

RunService.RenderStepped:Connect(function()
	local t = workspace:GetServerTimeNow()
	if stopState then
		if stopState.phase == "Flight" or stopState.stop == 0 then
			timerLabel.Text = "~"
		else
			timerLabel.Text = clock(stopState.departAt - t)
			timerLabel.TextColor3 = if stopState.phase == "Horn" then RED else WHITE
		end
	end
	if queueState then
		local left = math.max(0, math.ceil(queueState.departAt - t))
		local prefix = if queueState.requeue then "Heist again together! " else ""
		if queueState.waiting then
			queueLabel.Text = prefix .. "Waiting for a free street... (" .. queueState.count .. " Santas)"
		else
			queueLabel.Text = string.format(
				"%sSleigh leaves in %d  ·  %d/%d Santas",
				prefix,
				left,
				queueState.count,
				queueState.max
			)
		end
	end
	if resultsPanel.Visible then
		local left = math.max(0, math.ceil(resultsEndsAt - os.clock()))
		resultsFooter.Text = "Next run in " .. (left + resultsNextRun) .. "..."
	end
end)
