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
local LobbyMap = require(script.Parent.LobbyMap)
local MapBuilder = require(script.Parent.MapBuilder)

export type Handlers = {
	seated: (bay: LobbyMap.Bay, player: Player) -> (),
	unseated: (bay: LobbyMap.Bay, player: Player) -> (),
	depart: (bay: LobbyMap.Bay, riders: { Player }) -> (),
}

type BayState = {
	bay: LobbyMap.Bay,
	phase: string?,
	cycle: number,
	sleigh: Model, -- built once, parked out of sight between cycles
	seats: { Seat },
	riders: { Player },
	gateOpen: boolean,
}

local Station = {}

local TICK = 0.1
local RUN_IN = 70 -- studs behind home where an arriving sleigh appears
local RUN_OUT = 110 -- studs ahead of home where a departing sleigh vanishes
local PARKED = CFrame.new(0, -300, 0) -- out of sight under the map between cycles
local ARM_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local states: { BayState } = {}
local stateOf: { [Player]: BayState } = {}
local handlers: Handlers
local shown: { [TextLabel]: string } = {} -- last text written per label

local function ease(a: number): number
	a = math.clamp(a, 0, 1)
	return 1 - (1 - a) ^ 3
end

-- One sleigh per bay, reused every cycle.
local function buildSleigh(bay: LobbyMap.Bay): (Model, { Seat })
	local parent = bay.zone.Parent
	local template = Assets.clone("Sleigh", { "Body", "Seat1", "Hitch" })
	local sleigh: Model
	local seats = {}
	if template then
		sleigh = MapBuilder.placeSleighTemplate(parent, template, bay.home, Assets.get("Reindeer"), true)
		for _, d in sleigh:GetDescendants() do
			if d:IsA("Seat") then
				table.insert(seats, d)
			end
		end
	else
		sleigh = MapBuilder.buildSleigh(parent, bay.home)
		seats = MapBuilder.addSeats(sleigh)
	end
	sleigh.Name = "StationSleigh"
	return sleigh, seats
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

-- Skips writes that would not change the label (most ticks).
local function write(label: TextLabel, text: string)
	if shown[label] ~= text then
		shown[label] = text
		label.Text = text
	end
end

local function enter(state: BayState, phase: StationClock.Phase)
	if phase.name == "Boarding" then
		state.sleigh:PivotTo(state.bay.home)
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
		state.sleigh:PivotTo(PARKED)
	end
end

local function statusText(phase: StationClock.Phase, t: number): (string, Color3)
	local left = Util.clock(phase.endsAt - t)
	if phase.name == "Boarding" then
		return "BOARDING NOW!  " .. left, Color3.fromRGB(255, 200, 61)
	elseif phase.name == "Departing" then
		return "DEPARTED", Color3.fromRGB(232, 52, 63)
	elseif phase.name == "Arriving" then
		return "ARRIVING  " .. left, Color3.fromRGB(120, 200, 255)
	end
	local nextBoard = phase.endsAt + Config.LobbyMap.ArriveSeconds
	return "NEXT SLEIGH  " .. Util.clock(nextBoard - t), Color3.fromRGB(200, 205, 230)
end

local function update(state: BayState, t: number)
	local bay = state.bay
	local phase = StationClock.phaseAt(bay.kind, bay.number, t)
	if phase.name ~= state.phase or phase.cycle ~= state.cycle then
		state.phase = phase.name
		state.cycle = phase.cycle
		enter(state, phase)
	end

	local a = (t - phase.startsAt) / (phase.endsAt - phase.startsAt)
	if phase.name == "Arriving" then
		state.sleigh:PivotTo(bay.home * CFrame.new(0, 0, RUN_IN * (1 - ease(a))))
	elseif phase.name == "Departing" then
		state.sleigh:PivotTo(bay.home * CFrame.new(0, 12 * a * a, -RUN_OUT * a * a))
	end

	if phase.name == "Boarding" then
		checkRiders(state)
		board(state)
	elseif phase.name == "Departing" then
		checkRiders(state)
	end

	local text, colour = statusText(phase, t)
	write(bay.stats.status, text)
	bay.stats.status.TextColor3 = colour
	write(bay.stats.crew, string.format("CREW %d/%d", #state.riders, Config.Lobby.CrewMax))
	return text
end

function Station.start(hub: LobbyMap.Hub, h: Handlers)
	handlers = h
	for _, bay in hub.bays do
		local sleigh, seats = buildSleigh(bay)
		sleigh:PivotTo(PARKED)
		local state: BayState = {
			bay = bay,
			phase = nil,
			cycle = -1,
			sleigh = sleigh,
			seats = seats,
			riders = {},
			gateOpen = true,
		}
		setGate(state, false)
		table.insert(states, state)
	end

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
				write(label, timetable)
			end
		end
	end)
end

return Station
