--[[
	Drives the Sleigh Station bays built by LobbyMap, on StationClock's
	timetable: a sleigh pulls in, the gate swings open and "BOARDING NOW!"
	lights up, riders step into the board zone and are sat in the sleigh
	(jump to hop off), then the gate shuts and the sleigh flies off.

	Station only moves things and seats riders. What happens to riders is up to
	the handlers Lobby passes in:
	  seated(bay, player)   a rider sat down (Public riders queue right away)
	  unseated(bay, player) a rider hopped off or left
	  depart(bay, riders)   the sleigh is leaving with these riders
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local StationClock = require(ReplicatedStorage.Shared.StationClock)
local Util = require(ReplicatedStorage.Shared.Util)
local Assets = require(script.Parent.Assets)
local MapBuilder = require(script.Parent.MapBuilder)

export type Handlers = {
	seated: (bay: any, player: Player) -> (),
	unseated: (bay: any, player: Player) -> (),
	depart: (bay: any, riders: { Player }) -> (),
}

type BayState = {
	bay: any, -- LobbyMap.Bay
	phase: string?,
	cycle: number,
	sleigh: Model?,
	seats: { Seat },
	riders: { Player },
	gateOpen: boolean,
}

local Station = {}

local TICK = 0.1
local RUN_IN = 70 -- studs behind home where an arriving sleigh appears
local RUN_OUT = 110 -- studs ahead of home where a departing sleigh vanishes
local ARM_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local states: { BayState } = {}
local stateOf: { [Player]: BayState } = {}
local handlers: Handlers

local function ease(a: number): number
	a = math.clamp(a, 0, 1)
	return 1 - (1 - a) ^ 3
end

local function buildSleigh(state: BayState): Model
	local parent = state.bay.zone.Parent
	local seats = {}
	local template = Assets.clone("Sleigh", { "Body", "Seat1", "Hitch" })
	local sleigh: Model
	if template then
		sleigh = MapBuilder.placeSleighTemplate(parent, template, state.bay.home, Assets.get("Reindeer"))
		for i = 1, Config.Lobby.CrewMax do
			local seat = sleigh:FindFirstChild("Seat" .. i, true)
			if seat and seat:IsA("Seat") then
				seat.Disabled = false
				table.insert(seats, seat)
			end
		end
	else
		sleigh = MapBuilder.buildSleigh(parent, state.bay.home)
	end
	if #seats == 0 then
		for i, offset in MapBuilder.SeatOffsets do
			local seat = Instance.new("Seat")
			seat.Name = "Seat" .. i
			seat.Anchored = true
			seat.Size = Vector3.new(2, 1, 2)
			seat.Color = Color3.fromRGB(255, 200, 61)
			seat.CFrame = state.bay.home * offset * CFrame.new(0, -1.5, 0)
			seat.Parent = sleigh
			table.insert(seats, seat)
		end
	end
	sleigh.Name = "StationSleigh"
	state.seats = seats
	return sleigh
end

local function setGate(state: BayState, open: boolean)
	if state.gateOpen == open then
		return
	end
	state.gateOpen = open
	state.bay.gate.CanCollide = not open
	for _, arm in state.bay.arms do
		TweenService:Create(arm.part, ARM_TWEEN, { CFrame = if open then arm.open else arm.closed }):Play()
	end
	for _, label in state.bay.boarding do
		label.Visible = open
	end
	state.bay.boardingSign.Transparency = if open then 0 else 0.6
end

local function removeRider(state: BayState, player: Player, unsit: boolean)
	if not Util.removeValue(state.riders, player) then
		return
	end
	stateOf[player] = nil
	if unsit then
		local humanoid = Util.humanoidOf(player)
		if humanoid then
			humanoid.Sit = false
		end
		for _, seat in state.seats do
			local weld = seat:FindFirstChild("SeatWeld")
			if weld and seat.Occupant == humanoid then
				weld:Destroy()
			end
		end
	end
end

-- Gets a rider off the sleigh (Lobby calls this before moving them).
function Station.release(player: Player)
	local state = stateOf[player]
	if state then
		removeRider(state, player, true)
	end
end

function Station.riderBay(player: Player): any?
	local state = stateOf[player]
	return state and state.bay
end

local function inZone(zone: BasePart, position: Vector3): boolean
	local rel = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Z) <= half.Z and rel.Y > -2 and rel.Y < 8
end

local function freeSeat(state: BayState): Seat?
	for _, seat in state.seats do
		if not seat.Occupant then
			return seat
		end
	end
	return nil
end

local function board(state: BayState)
	for _, player in Players:GetPlayers() do
		if stateOf[player] or #state.riders >= Config.Lobby.CrewMax then
			continue
		end
		local humanoid = Util.humanoidOf(player)
		local root = Util.rootOf(player)
		if
			humanoid
			and root
			and humanoid.Health > 0
			and not humanoid.SeatPart
			and inZone(state.bay.zone, root.Position)
		then
			local seat = freeSeat(state)
			if seat then
				seat:Sit(humanoid)
				table.insert(state.riders, player)
				stateOf[player] = state
				handlers.seated(state.bay, player)
			end
		end
	end
end

-- Riders who jumped off or left are dropped.
local function checkRiders(state: BayState)
	for _, player in table.clone(state.riders) do
		local humanoid = Util.humanoidOf(player)
		local seat = humanoid and humanoid.SeatPart
		if player.Parent ~= Players or not seat or not table.find(state.seats, seat :: any) then
			removeRider(state, player, false)
			handlers.unseated(state.bay, player)
		end
	end
end

local function enter(state: BayState, phase: StationClock.Phase)
	if phase.name == "Arriving" then
		if state.sleigh then
			state.sleigh:Destroy()
		end
		state.sleigh = buildSleigh(state)
	elseif phase.name == "Boarding" then
		setGate(state, true)
	elseif phase.name == "Departing" then
		setGate(state, false)
		handlers.depart(state.bay, table.clone(state.riders))
	elseif phase.name == "Away" then
		-- Anyone still aboard (waiting on a teleport) steps back onto the platform.
		for i, player in table.clone(state.riders) do
			removeRider(state, player, true)
			Util.teleport(
				player,
				CFrame.new(
					state.bay.x + (i - 3.5) * 2,
					Config.LobbyMap.FloorHeight + 3,
					Config.LobbyMap.Platform.Z0 + 2
				)
			)
		end
		if state.sleigh then
			state.sleigh:Destroy()
			state.sleigh = nil
		end
	end
end

local function statusText(phase: StationClock.Phase, t: number): (string, Color3)
	local left = StationClock.clock(phase.endsAt - t)
	if phase.name == "Boarding" then
		return "BOARDING NOW!  " .. left, Color3.fromRGB(255, 200, 61)
	elseif phase.name == "Departing" then
		return "DEPARTED", Color3.fromRGB(232, 52, 63)
	elseif phase.name == "Arriving" then
		return "ARRIVING  " .. left, Color3.fromRGB(120, 200, 255)
	end
	local nextBoard = phase.endsAt + Config.LobbyMap.ArriveSeconds
	return "NEXT SLEIGH  " .. StationClock.clock(nextBoard - t), Color3.fromRGB(200, 205, 230)
end

local MODE = {
	Public = "Anyone can hop on",
	Party = "Your group + randoms",
	Private = "Just your crew",
}

local function update(state: BayState, t: number)
	local bay = state.bay
	local phase = StationClock.phaseAt(bay.kind, bay.number, t)
	if phase.name ~= state.phase or phase.cycle ~= state.cycle then
		state.phase = phase.name
		state.cycle = phase.cycle
		enter(state, phase)
	end

	local sleigh = state.sleigh
	if sleigh then
		local a = (t - phase.startsAt) / (phase.endsAt - phase.startsAt)
		if phase.name == "Arriving" then
			sleigh:PivotTo(bay.home * CFrame.new(0, 0, RUN_IN * (1 - ease(a))))
		elseif phase.name == "Departing" then
			sleigh:PivotTo(bay.home * CFrame.new(0, 12 * a * a, -RUN_OUT * a * a))
		elseif phase.name == "Boarding" then
			sleigh:PivotTo(bay.home)
		end
	end

	if phase.name == "Boarding" then
		checkRiders(state)
		board(state)
	elseif phase.name == "Departing" then
		checkRiders(state)
	end

	local text, colour = statusText(phase, t)
	bay.stats.status.Text = text
	bay.stats.status.TextColor3 = colour
	bay.stats.crew.Text = string.format("CREW %d/%d", #state.riders, Config.Lobby.CrewMax)
	bay.stats.mode.Text = MODE[bay.kind] or ""
	return text
end

function Station.start(hub, h: Handlers)
	handlers = h
	for _, bay in hub.bays do
		local state = { bay = bay, phase = nil, cycle = -1, seats = {}, riders = {}, gateOpen = true }
		setGate(state, false)
		table.insert(states, state)
	end

	Players.PlayerRemoving:Connect(function(player)
		local state = stateOf[player]
		if state then
			removeRider(state, player, false)
			handlers.unseated(state.bay, player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(TICK)
			local t = Util.now()
			local lines = {}
			for _, state in states do
				local ok, text = pcall(update, state, t)
				if ok then
					table.insert(
						lines,
						string.format("BAY %d  %-8s %s", state.bay.number, string.upper(state.bay.kind), text)
					)
				else
					warn("[Station] bay update failed: " .. tostring(text))
				end
			end
			local timetable = table.concat(lines, "\n")
			for _, label in hub.departureBoards do
				label.Text = timetable
			end
		end
	end)
end

return Station
