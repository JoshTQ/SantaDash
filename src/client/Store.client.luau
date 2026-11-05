--[[
	Greybox store panel: a Shop button and a list of what the server says this
	player may buy (server/Store.luau decides; this only shows it). Paid
	random items list their normal and boosted odds before the Buy button.
	Plain frames, no art.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local HudLayout = require(ReplicatedStorage.Shared.HudLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local store = Remotes.get("Store")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 200, 60)

local gui = Instance.new("ScreenGui")
gui.Name = "SleighHeistStore"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")
local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
local function fit()
	local camera = workspace.CurrentCamera
	uiScale.Scale = HudLayout.scale(camera and camera.ViewportSize)
end
fit()

local function corner(parent: Instance)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = parent
end

local function text(parent: Instance, className: string, props: { [string]: any }): any
	local t = Instance.new(className)
	t.BackgroundTransparency = 1
	t.TextColor3 = WHITE
	t.Font = FONT
	t.TextSize = 20
	t.TextWrapped = true
	for k, v in props do
		t[k] = v
	end
	t.Parent = parent
	return t
end

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(460, 420)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(20, 25, 45)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.Parent = gui
corner(panel)

text(panel, "TextLabel", {
	Size = UDim2.new(1, -60, 0, 36),
	Position = UDim2.fromOffset(14, 6),
	Text = "Naughty Shop",
	TextSize = 28,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local close = text(panel, "TextButton", {
	Size = UDim2.fromOffset(40, 36),
	Position = UDim2.new(1, -48, 0, 6),
	Text = "X",
	TextSize = 26,
})
local status = text(panel, "TextLabel", {
	Size = UDim2.new(1, -28, 0, 26),
	Position = UDim2.fromOffset(14, 42),
	TextSize = 18,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -20, 1, -80)
list.Position = UDim2.fromOffset(10, 72)
list.BackgroundTransparency = 1
list.ScrollBarThickness = 8
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.Parent = list

local shopButton = text(gui, "TextButton", {
	Size = UDim2.fromOffset(130, 34),
	Position = UDim2.fromOffset(12, 150),
	Text = "Shop",
	BackgroundTransparency = 0,
	BackgroundColor3 = Color3.fromRGB(60, 140, 70),
})
corner(shopButton)

local toast = text(gui, "TextLabel", {
	Size = UDim2.new(0.6, 0, 0, 40),
	Position = UDim2.new(0.2, 0, 0.12, 0),
	TextSize = 24,
	TextStrokeTransparency = 0.3,
	Visible = false,
})
local toastToken = 0

local function clearList()
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function card(item, order: number)
	local oddsLines = item.odds and #item.odds or 0
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -12, 0, 78 + (if oddsLines > 0 then 22 + oddsLines * 18 else 0))
	frame.BackgroundColor3 = Color3.fromRGB(40, 48, 80)
	frame.LayoutOrder = order
	frame.Parent = list
	corner(frame)
	text(frame, "TextLabel", {
		Size = UDim2.new(1, -130, 0, 26),
		Position = UDim2.fromOffset(10, 4),
		Text = item.name,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	text(frame, "TextLabel", {
		Size = UDim2.new(1, -130, 0, 44),
		Position = UDim2.fromOffset(10, 30),
		Text = item.blurb,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local buy = text(frame, "TextButton", {
		Size = UDim2.fromOffset(104, 40),
		Position = UDim2.new(1, -114, 0, 18),
		Text = "R$ " .. item.price,
		BackgroundTransparency = 0,
		BackgroundColor3 = if item.buyable then Color3.fromRGB(60, 140, 70) else Color3.fromRGB(90, 90, 100),
		AutoButtonColor = item.buyable,
	})
	corner(buy)
	if not item.buyable then
		buy.Text = "Soon"
	end
	buy.Activated:Connect(function()
		if item.buyable then
			store:FireServer("Buy", item.id)
		end
	end)
	if oddsLines > 0 then
		-- Odds before purchase (Roblox paid random items policy).
		text(frame, "TextLabel", {
			Size = UDim2.new(1, -20, 0, 20),
			Position = UDim2.fromOffset(10, 76),
			Text = "Odds per present:  normal  ->  with this",
			TextSize = 16,
			TextColor3 = GOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		for i, row in item.odds do
			text(frame, "TextLabel", {
				Size = UDim2.new(1, -20, 0, 18),
				Position = UDim2.fromOffset(18, 78 + i * 18),
				Text = string.format("%s:  %s  ->  %s", row.name, row.base, row.boosted),
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
		end
	end
end

local function render(snapshot)
	clearList()
	if snapshot.loading then
		status.Text = "Loading..."
		return
	end
	local bits = { string.format("Coal: %d", snapshot.coal or 0) }
	if (snapshot.breakouts or 0) > 0 then
		table.insert(bits, string.format("Break-outs: %d", snapshot.breakouts))
	end
	if snapshot.blessing then
		table.insert(bits, "Blessed by " .. snapshot.blessing.by .. "!")
	end
	status.Text = table.concat(bits, "   ")
	if (snapshot.opensIn or 0) > 0 then
		local m, s = snapshot.opensIn // 60, snapshot.opensIn % 60
		text(list, "TextLabel", {
			Size = UDim2.new(1, -12, 0, 60),
			Text = string.format("The shop opens in %d:%02d. Go grab some presents first!", m, s),
		})
	elseif #snapshot.items == 0 then
		text(list, "TextLabel", { Size = UDim2.new(1, -12, 0, 60), Text = "Nothing on sale right now." })
	end
	for i, item in snapshot.items do
		card(item, i)
	end
end

local function setOpen(open: boolean)
	panel.Visible = open
	if open then
		fit()
		store:FireServer("Open")
	end
end

shopButton.Activated:Connect(function()
	setOpen(not panel.Visible)
end)
close.Activated:Connect(function()
	setOpen(false)
end)
UserInputService.InputBegan:Connect(function(inputObject, processed)
	if not processed and inputObject.KeyCode == Enum.KeyCode.B then
		setOpen(not panel.Visible)
	end
end)

store.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "Catalog" then
		if panel.Visible then
			render(data)
		end
	elseif kind == "Notice" then
		toastToken += 1
		local token = toastToken
		toast.Text = data
		toast.Visible = true
		task.delay(3, function()
			if toastToken == token then
				toast.Visible = false
			end
		end)
	end
end)
