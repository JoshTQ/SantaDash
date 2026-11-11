--[[
	Plays one cutscene on this client: letterbox bars, a scripted camera, big
	comic text pops, a Skip button and a few local gags (hats flying off, a
	present bonking you, route markers). Scene data and timing live in
	ReplicatedStorage.Shared.Cutscenes; the server only says which scene, when
	it started and what to look at.

	Everything here is local to this player: skipping never affects anyone
	else, and nothing the server relies on is changed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Cutscenes = require(ReplicatedStorage.Shared.Cutscenes)
local Util = require(ReplicatedStorage.Shared.Util)

local player = Players.LocalPlayer
local FONT = Enum.Font.FredokaOne
local BIND = "SleighHeistCutscene"
local BAR = 0.11 -- letterbox bar height, fraction of the screen

local CutscenePlayer = {}

local current = nil -- the scene playing now, with everything to clean up

local function controls()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: any):GetControls()
	end)
	return if ok then module else nil
end

local function buildGui(onSkip: () -> ())
	local gui = Instance.new("ScreenGui")
	gui.Name = "SleighHeistCutscene"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	gui.ResetOnSpawn = false

	local tint = Instance.new("Frame")
	tint.Size = UDim2.fromScale(1, 1)
	tint.BorderSizePixel = 0
	tint.BackgroundTransparency = 1
	tint.Parent = gui

	local bars = {}
	for i, y in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, y)
		bar.Position = UDim2.fromScale(0, y)
		bar.Size = UDim2.fromScale(1, 0)
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.fromRGB(11, 16, 34)
		bar.Parent = gui
		bars[i] = bar
		TweenService:Create(bar, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, BAR) }):Play()
	end

	local pop = Instance.new("TextLabel")
	pop.AnchorPoint = Vector2.new(0.5, 0.5)
	pop.Position = UDim2.fromScale(0.5, 0.42)
	pop.Size = UDim2.fromScale(0.9, 0.16)
	pop.BackgroundTransparency = 1
	pop.Font = FONT
	pop.TextScaled = true
	pop.TextStrokeTransparency = 0
	pop.TextStrokeColor3 = Color3.fromRGB(11, 16, 34)
	pop.Text = ""
	pop.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 96
	limit.Parent = pop

	-- Big tap target bottom right, inside the lower bar (mobile first).
	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -16, 1 - BAR / 2, 0)
	skip.Size = UDim2.fromOffset(120, 44)
	skip.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	skip.BackgroundTransparency = 0.8
	skip.TextColor3 = Color3.new(1, 1, 1)
	skip.Font = FONT
	skip.TextSize = 22
	skip.Text = "SKIP >"
	skip.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 22)
	corner.Parent = skip
	skip.Activated:Connect(onSkip)

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, pop, tint
end

-- Plays a SoundAssets sound inside the cutscene GUI, so Skip (which destroys
-- the GUI) cuts it off. `late` starts it part-way in when we joined late.
-- A key with no Sound yet is silent.
local function playSfx(state, key: string?, late: number)
	local folder = key and ReplicatedStorage:FindFirstChild("SoundAssets")
	local template = folder and folder:FindFirstChild(key :: string)
	if template and template:IsA("Sound") then
		local sound = template:Clone()
		sound.Parent = state.gui -- a Sound under PlayerGui plays 2D for this player only
		sound.TimePosition = late
		sound:Play()
	end
end

-- Every hat near the camera pops off and spins away (local copies only).
local function hatsOff(state, centre: Vector3)
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = Util.rootOf(other)
		if character and root and (root.Position - centre).Magnitude < 120 then
			for _, accessory in character:GetChildren() do
				local handle = accessory:IsA("Accessory") and accessory:FindFirstChild("Handle")
				if
					handle
					and handle:IsA("BasePart")
					and (accessory :: Accessory).AccessoryType == Enum.AccessoryType.Hat
				then
					local flying = handle:Clone()
					for _, child in flying:GetChildren() do
						if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
							child:Destroy()
						end
					end
					flying.Anchored = true
					flying.CanCollide = false
					flying.Parent = workspace
					table.insert(state.props, flying)
					state.hidden[handle] = handle.LocalTransparencyModifier
					handle.LocalTransparencyModifier = 1
					local target = flying.CFrame
						* CFrame.new(math.random(-6, 6), 14, math.random(-6, 6))
						* CFrame.Angles(math.random() * 6, math.random() * 6, 0)
					TweenService
						:Create(flying, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							CFrame = target,
						})
						:Play()
				end
			end
		end
	end
end

-- A present drops out of the sky and bonks this Santa on the head.
local function dropPresent(state)
	local root = Util.rootOf(player)
	if not root then
		return
	end
	local box = Instance.new("Part")
	box.Size = Vector3.new(1.6, 1.6, 1.6)
	box.Color = Color3.fromRGB(62, 230, 176)
	box.Anchored = true
	box.CanCollide = false
	box.CFrame = root.CFrame * CFrame.new(0, 16, 0)
	box.Parent = workspace
	table.insert(state.props, box)
	local fall =
		TweenService:Create(box, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = root.CFrame * CFrame.new(0, 3.6, 0) * CFrame.Angles(0, 0, 0.6),
		})
	fall:Play()
	fall.Completed:Connect(function()
		if box.Parent then
			TweenService:Create(box, TweenInfo.new(0.3), {
				CFrame = root.CFrame * CFrame.new(2.5, 0.8, 0) * CFrame.Angles(0, 0, 1.6),
			}):Play()
		end
	end)
end

-- A one-shot particle burst at a world position (fireworks, snow spray).
local function burst(state, position: Vector3, color: Color3, options: { [string]: any })
	local holder = Instance.new("Part")
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Size = Vector3.one
	holder.Position = position
	holder.Parent = workspace
	table.insert(state.props, holder)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = options.glow or 0
	emitter.Speed = options.speed
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = options.lifetime
	emitter.Drag = options.drag or 1.5
	emitter.Acceleration = Vector3.new(0, options.gravity or -12, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, options.size),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = holder
	emitter:Emit(options.count)

	if options.glow then
		local flash = Instance.new("PointLight")
		flash.Color = color
		flash.Range = 60
		flash.Brightness = 6
		flash.Parent = holder
		TweenService:Create(flash, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	end
end

-- Getaway: a firework bursts in the sky above the Lair.
local function firework(state, at: Vector3, colorName: string?)
	local color = Cutscenes.Colors[colorName or "gold"] or Cutscenes.Colors.gold
	burst(state, at, color, {
		speed = NumberRange.new(30, 45),
		lifetime = NumberRange.new(0.9, 1.4),
		size = 1.2,
		count = 140,
		glow = 1,
		drag = 2.5,
	})
end

-- Left Behind: the departing sleigh sprays this Santa with snow.
local function snowPuff(state)
	local root = Util.rootOf(player)
	if root then
		burst(state, root.Position + Vector3.new(0, 2, 0), Cutscenes.Colors.snow, {
			speed = NumberRange.new(8, 18),
			lifetime = NumberRange.new(0.5, 0.9),
			size = 1.6,
			count = 70,
			gravity = -30,
		})
	end
end

-- Numbered glowing markers over each Sleigh Stop during the Takeoff swoop.
local function showMarks(state, marks: { Vector3 }?, hold: number)
	for i, position in marks or {} do
		local holder = Instance.new("Part")
		holder.Transparency = 1
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.Size = Vector3.one
		holder.Position = position + Vector3.yAxis * 12
		holder.Parent = workspace
		local board = Instance.new("BillboardGui")
		board.Size = UDim2.fromOffset(64, 64)
		board.AlwaysOnTop = true
		board.Parent = holder
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundColor3 = Cutscenes.Colors.mint
		text.TextColor3 = Color3.fromRGB(11, 16, 34)
		text.Font = FONT
		text.TextScaled = true
		text.Text = if i == #marks then "!" else tostring(i)
		text.Parent = board
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = text
		table.insert(state.props, holder)
		task.delay(hold, function()
			holder:Destroy()
		end)
	end
end

function CutscenePlayer.stop()
	local state = current
	if not state then
		return
	end
	current = nil
	RunService:UnbindFromRenderStep(BIND)
	state.gui:Destroy()
	for _, prop in state.props do
		prop:Destroy()
	end
	for handle, transparency in state.hidden do
		if handle.Parent then
			handle.LocalTransparencyModifier = transparency
		end
	end
	local camera = workspace.CurrentCamera
	camera.FieldOfView = state.fov
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = Util.humanoidOf(player)
	if humanoid then
		camera.CameraSubject = humanoid
	end
	if state.controls then
		state.controls:Enable()
	end
end

function CutscenePlayer.isPlaying(): boolean
	return current ~= nil
end

-- data: { id, startedAt, anchor: CFrame, follow: Instance?, marks: {Vector3}?, map: string? }
function CutscenePlayer.play(data)
	local scene = Cutscenes.get(data.id)
	if not scene or Util.now() - data.startedAt >= scene.seconds then
		return -- unknown, or it already ended (we joined late)
	end
	CutscenePlayer.stop()

	local camera = workspace.CurrentCamera
	local state = {
		props = {},
		hidden = {},
		fov = camera.FieldOfView,
		controls = controls(),
		shake = nil :: { power: number, untilT: number }?,
		lastT = -1,
	}
	state.gui, state.pop, state.tint = buildGui(CutscenePlayer.stop)
	current = state
	if state.controls then
		state.controls:Disable()
	end
	camera.CameraType = Enum.CameraType.Scriptable

	local tintColor = scene.tint and Cutscenes.Colors[scene.tint.color]
	local rng = Random.new()

	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function()
		if current ~= state then
			return
		end
		local t = Util.now() - data.startedAt
		if t >= scene.seconds then
			CutscenePlayer.stop()
			return
		end

		local follow = data.follow
		local root = Util.rootOf(player)
		local frames: Cutscenes.Frames = {
			anchor = data.anchor,
			follow = if follow and follow.Parent then (follow :: Model):GetPivot() else nil,
			self = if root then root.CFrame else nil,
		}
		local eye, look, fov = Cutscenes.camera(scene, t, frames)

		for _, cue in Cutscenes.cuesBetween(scene, state.lastT, t) do
			if cue.kind == "sfx" then
				playSfx(state, cue.key, math.max(0, t - cue.at))
			elseif cue.kind == "shake" then
				state.shake = { power = cue.power or 1, untilT = cue.at + (cue.hold or 0.3) }
			elseif cue.kind == "hatsOff" then
				hatsOff(state, eye)
			elseif cue.kind == "drop" then
				dropPresent(state)
			elseif cue.kind == "fireworks" and cue.offset then
				firework(state, data.anchor:PointToWorldSpace(cue.offset), cue.color)
			elseif cue.kind == "snowPuff" then
				snowPuff(state)
			elseif cue.kind == "marks" then
				showMarks(state, data.marks, cue.hold or 2)
			end
		end
		state.lastT = t

		if state.shake and t < state.shake.untilT then
			local p = state.shake.power
			eye += Vector3.new(rng:NextNumber(-p, p), rng:NextNumber(-p, p), rng:NextNumber(-p, p))
		end
		if (eye - look).Magnitude > 0.01 then
			camera.CFrame = CFrame.lookAt(eye, look)
		end
		camera.FieldOfView = fov

		local pop = Cutscenes.popAt(scene, t)
		if pop then
			-- data.swap replaces a whole pop (the Getaway's "LOOT x2" without the List).
			local text = if data.swap and data.swap[pop.text] then data.swap[pop.text] else pop.text
			state.pop.Text = (string.gsub(text, "{map}", data.map or ""))
			state.pop.TextColor3 = Cutscenes.Colors[pop.color]
			local grow = math.clamp((t - pop.at) / 0.12, 0, 1) -- slams in
			state.pop.Size = UDim2.fromScale(0.9, 0.16 * (pop.size or 1) * (0.6 + 0.4 * grow))
			state.pop.Rotation = -4
		else
			state.pop.Text = ""
		end

		if tintColor then
			local pulse = scene.tint and scene.tint.pulse or 0
			state.tint.BackgroundColor3 = tintColor
			state.tint.BackgroundTransparency = 0.82 + 0.1 * math.sin(t * pulse * math.pi * 2)
		end
	end)
end

return CutscenePlayer
