--[[
	First-time player tips (server side). The rules and wording are in
	shared/Tutorial.luau; the card and the guide trail are drawn by
	client/Tips.client.luau.

	Lobby and Run call:
		Onboarding.teach(player, id, guideAt?)   show a tip once (and a trail to guideAt)
		Onboarding.complete(player, id)          the player did it (Grab, Board)
		Onboarding.clearGuide(player)            hide the trail
	Players can switch tips off with the card's X (Input "TipsOff").

	Saved data: the shared PlayerData module (store thread) keeps
	data.tutorial = { done = { [id] = true }, tipsOff = bool }. Until it is
	plugged in with Onboarding.start(store), progress is kept in memory for the
	server's lifetime, so tips still work (and repeat next session).

	"First heist!" tag: while a player still has core lessons to learn, a small
	tag floats over their Santa so friends know to help.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Tutorial = require(ReplicatedStorage.Shared.Tutorial)
local Util = require(ReplicatedStorage.Shared.Util)
local Analytics = require(script.Parent.Analytics)

export type Store = {
	waitFor: (player: Player, timeout: number?) -> any,
	update: (player: Player, fn: (data: any) -> ()) -> (),
}

local Onboarding = {}

Onboarding.RepeatSeconds = 60 -- an "action" tip the player hasn't done yet may come back after this
Onboarding.LoadTimeout = 10
Onboarding.TagName = "FirstHeistTag"

local states: { [Player]: Tutorial.State } = {}
local lastShown: { [Player]: { [string]: number } } = {}
-- Messages for players whose Tips script hasn't said "TipsReady" yet: a
-- remote fired before the client listens can go to another script or be lost.
local pending: { [Player]: { { kind: string, payload: any } } } = {}
local ready: { [Player]: boolean } = {}
local store: Store = nil :: any
local hud: RemoteEvent?

-- Progress kept in memory only (Studio, tests, or before PlayerData lands).
function Onboarding.memoryStore(): Store
	local data: { [Player]: any } = {}
	return {
		waitFor = function(player: Player)
			data[player] = data[player] or {}
			return data[player]
		end,
		update = function(player: Player, fn)
			data[player] = data[player] or {}
			fn(data[player])
		end,
	}
end

store = Onboarding.memoryStore()

local function send(player: Player, kind: string, payload: any)
	local waiting = pending[player]
	if waiting then
		table.insert(waiting, { kind = kind, payload = payload })
	elseif hud and player.Parent == Players then
		hud:FireClient(player, kind, payload)
	end
end

local function save(player: Player, state: Tutorial.State)
	local ok, err = pcall(store.update, player, function(data)
		local done = {}
		for id in state.done do
			done[id] = true
		end
		data.tutorial = { done = done, tipsOff = state.tipsOff }
	end)
	if not ok then
		warn("[Onboarding] could not save tips for " .. player.Name .. ": " .. tostring(err))
	end
end

-- The floating "First heist!" tag on a character.
local function setTag(player: Player, on: boolean)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local tag = root:FindFirstChild(Onboarding.TagName)
	if on and not tag then
		local gui = Instance.new("BillboardGui")
		gui.Name = Onboarding.TagName
		gui.Size = UDim2.fromOffset(120, 30)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 80
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
		label.BackgroundTransparency = 0.1
		label.TextColor3 = Color3.fromRGB(60, 30, 10)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = "First heist!"
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
		label.Parent = gui
		gui.Parent = root
	elseif not on and tag then
		tag:Destroy()
	end
end

local function refreshNew(player: Player)
	local state = states[player]
	local isNew = state ~= nil and Tutorial.isNew(state)
	player:SetAttribute("FirstHeist", isNew)
	setTag(player, isNew)
end

-- Loads a player's tips progress (yields up to LoadTimeout).
function Onboarding.load(player: Player)
	local ok, data = pcall(store.waitFor, player, Onboarding.LoadTimeout)
	if player.Parent ~= Players then
		return
	end
	-- No data (load failed or timed out): treat as new rather than skip tips.
	states[player] = Tutorial.normalise(if ok and type(data) == "table" then data.tutorial else nil)
	lastShown[player] = {}
	if pending[player] == nil and not ready[player] then
		pending[player] = {}
	end
	refreshNew(player)
end

function Onboarding.unload(player: Player)
	states[player] = nil
	lastShown[player] = nil
	pending[player] = nil
	ready[player] = nil
end

-- The player's Tips script is listening: send what was held back.
function Onboarding.clientReady(player: Player)
	ready[player] = true
	Analytics.loadedIn(player)
	local waiting = pending[player]
	pending[player] = nil
	for _, m in waiting or {} do
		send(player, m.kind, m.payload)
	end
end

function Onboarding.state(player: Player): Tutorial.State?
	return states[player]
end

function Onboarding.isNew(player: Player): boolean
	local state = states[player]
	return state ~= nil and Tutorial.isNew(state)
end

-- Shows a tip if this player hasn't learnt it. guideAt: draw a trail there.
-- Returns true if the tip was sent.
function Onboarding.teach(player: Player, id: string, guideAt: Vector3?): boolean
	local state = states[player]
	if not state or not Tutorial.shouldShow(state, id) then
		return false
	end
	local t = Util.now()
	local shown = lastShown[player]
	if shown[id] and t - shown[id] < Onboarding.RepeatSeconds then
		return false
	end
	shown[id] = t
	local lesson = Tutorial.get(id) :: Tutorial.Lesson
	send(player, "Tip", { id = id, seconds = lesson.seconds })
	Analytics.tip(player, "Shown", id)
	if guideAt then
		send(player, "Guide", { at = guideAt })
	end
	if Tutorial.onShown(state, id) then
		save(player, state)
		refreshNew(player)
	end
	return true
end

-- Same tip for a list of players.
function Onboarding.teachAll(players: { Player }, id: string, guideAt: ((Player) -> Vector3?)?)
	for _, player in players do
		Onboarding.teach(player, id, if guideAt then guideAt(player) else nil)
	end
end

function Onboarding.complete(player: Player, id: string)
	local state = states[player]
	if state and Tutorial.complete(state, id) then
		send(player, "TipDone", { id = id })
		Analytics.tip(player, "Done", id)
		Onboarding.clearGuide(player)
		save(player, state)
		refreshNew(player)
	end
end

function Onboarding.clearGuide(player: Player)
	if states[player] then
		send(player, "Guide", {})
	end
end

function Onboarding.tipsOff(player: Player)
	local state = states[player]
	if state and not state.tipsOff then
		state.tipsOff = true
		Analytics.tip(player, "Off")
		send(player, "Guide", {})
		save(player, state)
		refreshNew(player)
	end
end

-- store: the shared PlayerData module (nil = memory only).
function Onboarding.start(s: Store?)
	store = s or Onboarding.memoryStore()
	hud = Remotes.get("Hud")
	local function added(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 5)
			refreshNew(player)
		end)
		Onboarding.load(player)
	end
	Players.PlayerAdded:Connect(added)
	for _, player in Players:GetPlayers() do
		task.spawn(added, player)
	end
	Players.PlayerRemoving:Connect(Onboarding.unload)
	Remotes.get("Input").OnServerEvent:Connect(function(player, action)
		if action == "TipsOff" then
			Onboarding.tipsOff(player)
		elseif action == "TipsReady" then
			Onboarding.clientReady(player)
		end
	end)
end

-- Tests: set up without hooking Players.
function Onboarding._reset(s: Store?)
	states = {}
	lastShown = {}
	pending = {}
	ready = {}
	store = s or Onboarding.memoryStore()
	hud = nil
end

function Onboarding._setHud(remote: RemoteEvent?)
	hud = remote
end

return Onboarding
