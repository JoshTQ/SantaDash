--[[
	A headless stand-in for the Roblox engine, so modules that need the live
	engine (Run, Krampus, ElfBot, Mover, Lobby, RunHost, Hud) run in Lune.

	It is a model of the engine, not the engine: just enough of it for the
	game's server and client code to run, with simple stand-ins for physics.

	- Instances: a pure-Luau tree with properties, attributes, events (any
	  event name becomes a signal), Clone, PivotTo, GetBoundingBox, IsA.
	- Time: a virtual clock. task.wait / spawn / defer / delay, os.clock,
	  workspace:GetServerTimeNow and RunService.Heartbeat all run on it.
	  Nothing waits in real time, so a 6-minute run takes well under a second.
	- Physics stand-ins: Humanoid:MoveTo walks the root part at WalkSpeed,
	  welds keep welded parts with their Part0, Touched fires when a character
	  root enters a part that has Touched listeners, pathfinding walks straight.
	- Players: engine:addPlayer(name) makes a Player with a character, and
	  fires PlayerAdded. RemoteEvent:FireClient calls are recorded per player.

	Use it through the runner's `headless()` helper, which also gives you a
	`load` that requires game modules into this world.
]]

local roblox = require("@lune/roblox")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local Enum = roblox.Enum

local STEP = 0.1 -- seconds of virtual time per Heartbeat

----------------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

local function newSignal(engine)
	return setmetatable({ engine = engine, handlers = {}, waiting = {} }, Signal)
end

function Signal:Connect(fn)
	local connection = { Connected = true }
	local handlers = self.handlers
	table.insert(handlers, connection)
	connection.fn = fn
	function connection.Disconnect(c)
		c.Connected = false
		local i = table.find(handlers, c)
		if i then
			table.remove(handlers, i)
		end
	end
	return connection
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

-- Handlers run in their own threads, as in Roblox, so they may yield.
function Signal:Fire(...)
	for _, c in table.clone(self.handlers) do
		if c.Connected then
			self.engine:spawn(c.fn, ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in waiting do
		self.engine:resume(thread, ...)
	end
end

function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end

----------------------------------------------------------------------------
-- Classes
----------------------------------------------------------------------------

local PARENT_CLASS = {
	Part = "BasePart",
	MeshPart = "BasePart",
	WedgePart = "BasePart",
	CornerWedgePart = "BasePart",
	TrussPart = "BasePart",
	SpawnLocation = "Part",
	Seat = "Part",
	VehicleSeat = "BasePart",
	BasePart = "PVInstance",
	Model = "PVInstance",
	Workspace = "Model",
	PVInstance = "Instance",
	WeldConstraint = "Instance",
	Weld = "JointInstance",
	Motor6D = "JointInstance",
	JointInstance = "Instance",
	PointLight = "Light",
	SpotLight = "Light",
	Light = "Instance",
	ScreenGui = "LayerCollector",
	BillboardGui = "LayerCollector",
	SurfaceGui = "LayerCollector",
	LayerCollector = "GuiBase2d",
	Frame = "GuiObject",
	TextLabel = "GuiObject",
	TextButton = "GuiButton",
	ImageLabel = "GuiObject",
	ImageButton = "GuiButton",
	GuiButton = "GuiObject",
	GuiObject = "GuiBase2d",
	GuiBase2d = "Instance",
	UICorner = "UIComponent",
	UIStroke = "UIComponent",
	UIListLayout = "UIComponent",
	UIPadding = "UIComponent",
	UIComponent = "Instance",
	Player = "Instance",
}

local function isA(className: string, target: string): boolean
	local c: string? = className
	while c do
		if c == target then
			return true
		end
		c = PARENT_CLASS[c]
	end
	return target == "Instance"
end

local DEFAULTS = {
	BasePart = function()
		return {
			Size = Vector3.new(4, 1, 2),
			CFrame = CFrame.new(),
			Anchored = false,
			CanCollide = true,
			CanTouch = true,
			CanQuery = true,
			Transparency = 0,
			Color = Color3.fromRGB(163, 162, 165),
			Massless = false,
			AssemblyLinearVelocity = Vector3.zero,
		}
	end,
	Seat = function()
		return { Disabled = false }
	end,
	VehicleSeat = function()
		return { Disabled = false }
	end,
	Humanoid = function()
		return { WalkSpeed = 16, JumpPower = 50, Health = 100, MaxHealth = 100 }
	end,
	ProximityPrompt = function()
		return {
			Enabled = true,
			HoldDuration = 0,
			MaxActivationDistance = 10,
			RequiresLineOfSight = true,
			ActionText = "",
			ObjectText = "",
		}
	end,
	Light = function()
		return { Enabled = true, Brightness = 1, Range = 8 }
	end,
	Attachment = function()
		return { CFrame = CFrame.new() }
	end,
	GuiObject = function()
		return { Visible = true, Text = "" }
	end,
	LayerCollector = function()
		return { Enabled = true }
	end,
	Model = function()
		return { WorldPivot = CFrame.new() }
	end,
}

local function defaultsFor(className: string)
	local props = {}
	local chain = {}
	local c: string? = className
	while c do
		table.insert(chain, 1, c)
		c = PARENT_CLASS[c]
	end
	for _, name in chain do
		local make = DEFAULTS[name]
		if make then
			for k, v in make() do
				props[k] = v
			end
		end
	end
	return props
end

-- Names that are always events, so reading them never returns a child.
local EVENTS = {
	Touched = true,
	TouchEnded = true,
	Triggered = true,
	TriggerEnded = true,
	PromptShown = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	AncestryChanged = true,
	Destroying = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	OnServerEvent = true,
	OnClientEvent = true,
	Died = true,
	MoveToFinished = true,
	Activated = true,
	MouseButton1Click = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	Heartbeat = true,
	Stepped = true,
	RenderStepped = true,
}

----------------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------------

local Instance = {}
local InstanceMeta = {}

local function isInstance(v): boolean
	return type(v) == "table" and getmetatable(v) == InstanceMeta
end

local function children(self)
	return rawget(self, "_children")
end

local function props(self)
	return rawget(self, "_props")
end

local function newInstance(engine, className: string)
	local self = setmetatable({
		_engine = engine,
		_className = className,
		_props = defaultsFor(className),
		_children = {},
		_attributes = {},
		_signals = {},
		_parent = nil,
		_name = className,
	}, InstanceMeta)
	return self
end

-- Moves a BasePart, keeping Position and CFrame in sync.
local function setCFrame(part, cf)
	props(part).CFrame = cf
end

local getters = {}
local setters = {}

function getters.Name(self)
	return rawget(self, "_name")
end
function setters.Name(self, v)
	rawset(self, "_name", v)
end
function getters.ClassName(self)
	return rawget(self, "_className")
end
function getters.Parent(self)
	return rawget(self, "_parent")
end
function setters.Parent(self, parent)
	local old = rawget(self, "_parent")
	if old == parent then
		return
	end
	if rawget(self, "_destroyed") and parent ~= nil then
		error("The Parent property of " .. rawget(self, "_name") .. " is locked (it was destroyed)", 3)
	end
	if old then
		local list = children(old)
		local i = table.find(list, self)
		if i then
			table.remove(list, i)
		end
		local s = rawget(old, "_signals").ChildRemoved
		if s then
			s:Fire(self)
		end
	end
	rawset(self, "_parent", parent)
	if parent then
		table.insert(children(parent), self)
		local s = rawget(parent, "_signals").ChildAdded
		if s then
			s:Fire(self)
		end
		rawget(self, "_engine"):_onParented(self)
	end
	local s = rawget(self, "_signals").AncestryChanged
	if s then
		s:Fire(self, parent)
	end
end
-- Position is derived from CFrame for parts and attachments; GUI objects
-- have their own (UDim2) Position.
local function hasCFrame(self): boolean
	local class = rawget(self, "_className")
	return isA(class, "BasePart") or class == "Attachment"
end
function getters.Position(self)
	if not hasCFrame(self) then
		return props(self).Position
	end
	local cf = props(self).CFrame
	return if cf then cf.Position else nil
end
function setters.Position(self, v)
	if not hasCFrame(self) then
		props(self).Position = v
		return
	end
	local cf = props(self).CFrame or CFrame.new()
	setCFrame(self, cf - cf.Position + v)
end
function getters.Orientation(self)
	local x, y, z = props(self).CFrame:ToOrientation()
	return Vector3.new(math.deg(x), math.deg(y), math.deg(z))
end
function getters.WorldCFrame(self)
	local parent = rawget(self, "_parent")
	local cf = props(self).CFrame or CFrame.new()
	if parent and isA(rawget(parent, "_className"), "BasePart") then
		return props(parent).CFrame * cf
	end
	return cf
end
function getters.WorldPosition(self)
	return getters.WorldCFrame(self).Position
end
function getters.RootPart(self)
	if rawget(self, "_className") ~= "Humanoid" then
		return props(self).RootPart
	end
	local parent = rawget(self, "_parent")
	return parent and parent:FindFirstChild("HumanoidRootPart")
end
function getters.LocalPlayer(self)
	return props(self).LocalPlayer
end

InstanceMeta.__index = function(self, key)
	local method = Instance[key]
	if method then
		return method
	end
	local getter = getters[key]
	if getter then
		return getter(self)
	end
	local value = props(self)[key]
	if value ~= nil then
		return value
	end
	if EVENTS[key] then
		local signals = rawget(self, "_signals")
		signals[key] = signals[key] or newSignal(rawget(self, "_engine"))
		return signals[key]
	end
	return self:FindFirstChild(key)
end

InstanceMeta.__newindex = function(self, key, value)
	local setter = setters[key]
	if setter then
		setter(self, value)
	else
		props(self)[key] = value
	end
end

InstanceMeta.__tostring = function(self)
	return rawget(self, "_name")
end

function Instance.IsA(self, className: string): boolean
	return isA(rawget(self, "_className"), className)
end

function Instance.GetChildren(self)
	return table.clone(children(self))
end

function Instance.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in children(node) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function Instance.FindFirstChild(self, name: string, recursive: boolean?)
	for _, child in children(self) do
		if rawget(child, "_name") == name then
			return child
		end
	end
	if recursive then
		for _, child in children(self) do
			local found = child:FindFirstChild(name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Instance.FindFirstChildOfClass(self, className: string)
	for _, child in children(self) do
		if rawget(child, "_className") == className then
			return child
		end
	end
	return nil
end

function Instance.FindFirstChildWhichIsA(self, className: string, recursive: boolean?)
	for _, child in children(self) do
		if child:IsA(className) then
			return child
		end
	end
	if recursive then
		for _, child in children(self) do
			local found = child:FindFirstChildWhichIsA(className, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function Instance.FindFirstAncestorOfClass(self, className: string)
	local node = rawget(self, "_parent")
	while node do
		if rawget(node, "_className") == className then
			return node
		end
		node = rawget(node, "_parent")
	end
	return nil
end

function Instance.FindFirstAncestorWhichIsA(self, className: string)
	local node = rawget(self, "_parent")
	while node do
		if node:IsA(className) then
			return node
		end
		node = rawget(node, "_parent")
	end
	return nil
end

function Instance.IsDescendantOf(self, ancestor)
	local node = rawget(self, "_parent")
	while node do
		if node == ancestor then
			return true
		end
		node = rawget(node, "_parent")
	end
	return false
end

function Instance.IsAncestorOf(self, descendant)
	return descendant:IsDescendantOf(self)
end

-- Waits on virtual time; gives up (returns nil) after `timeout` seconds.
function Instance.WaitForChild(self, name: string, timeout: number?)
	local engine = rawget(self, "_engine")
	local deadline = engine.now + (timeout or 5)
	while true do
		local child = self:FindFirstChild(name)
		if child then
			return child
		end
		if engine.now >= deadline or not coroutine.isyieldable() then
			return nil
		end
		engine:wait(STEP)
	end
end

function Instance.GetAttribute(self, name: string)
	return rawget(self, "_attributes")[name]
end

function Instance.SetAttribute(self, name: string, value)
	rawget(self, "_attributes")[name] = value
end

function Instance.GetAttributes(self)
	return table.clone(rawget(self, "_attributes"))
end

function Instance.ClearAllChildren(self)
	for _, child in table.clone(children(self)) do
		child:Destroy()
	end
end

function Instance.Destroy(self)
	local s = rawget(self, "_signals").Destroying
	if s then
		s:Fire()
	end
	for _, child in table.clone(children(self)) do
		child:Destroy()
	end
	self.Parent = nil
	rawset(self, "_destroyed", true)
	for _, signal in rawget(self, "_signals") do
		signal.handlers = {}
	end
end

function Instance.Clone(self)
	local engine = rawget(self, "_engine")
	local map = {}
	local function copy(node)
		local c = newInstance(engine, rawget(node, "_className"))
		map[node] = c
		rawset(c, "_name", rawget(node, "_name"))
		rawset(c, "_props", table.clone(props(node)))
		rawset(c, "_attributes", table.clone(rawget(node, "_attributes")))
		for _, child in children(node) do
			local cc = copy(child)
			rawset(cc, "_parent", c)
			table.insert(children(c), cc)
		end
		return c
	end
	local root = copy(self)
	-- Instance references inside the copied tree point at the copies.
	for _, c in map do
		local p = props(c)
		for k, v in p do
			if isInstance(v) and map[v] then
				p[k] = map[v]
			end
		end
	end
	return root
end

-- BaseParts and Models.
local function partsOf(self)
	local list = {}
	if self:IsA("BasePart") then
		table.insert(list, self)
	end
	for _, d in self:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

function Instance.GetBoundingBox(self)
	local min, max
	for _, part in partsOf(self) do
		local cf, size = props(part).CFrame, props(part).Size
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local p = cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz)
					min = if min then min:Min(p) else p
					max = if max then max:Max(p) else p
				end
			end
		end
	end
	if not min then
		return self:GetPivot(), Vector3.zero
	end
	return CFrame.new((min + max) / 2), max - min
end

function Instance.GetPivot(self)
	if self:IsA("BasePart") then
		return props(self).CFrame
	end
	local primary = props(self).PrimaryPart
	if primary then
		return props(primary).CFrame
	end
	return props(self).WorldPivot or CFrame.new()
end

function Instance.PivotTo(self, target)
	if self:IsA("BasePart") then
		setCFrame(self, target)
		return
	end
	local delta = target * self:GetPivot():Inverse()
	for _, part in partsOf(self) do
		setCFrame(part, delta * props(part).CFrame)
	end
	props(self).WorldPivot = target
end

function Instance.MoveTo(self, goal)
	-- Humanoid:MoveTo: the engine walks the root part each Heartbeat.
	if rawget(self, "_className") == "Humanoid" then
		rawset(self, "_moveGoal", goal)
	else
		self:PivotTo(CFrame.new(goal) * (self:GetPivot() - self:GetPivot().Position))
	end
end

function Instance.SetNetworkOwner() end
function Instance.SetNetworkOwnershipAuto() end
function Instance.BreakJoints() end

function Instance.GetFullName(self)
	local names = {}
	local node = self
	while node do
		table.insert(names, 1, rawget(node, "_name"))
		node = rawget(node, "_parent")
	end
	return table.concat(names, ".")
end

-- Humanoid
function Instance.TakeDamage(self, amount: number)
	props(self).Health = math.max(0, props(self).Health - amount)
	if props(self).Health == 0 then
		self.Died:Fire()
	end
end

-- RemoteEvent / BindableEvent
-- Server -> client: recorded per player, and delivered to OnClientEvent when
-- the player is the world's local player (engine:setLocalPlayer).
function Instance.FireClient(self, player, ...)
	local engine = rawget(self, "_engine")
	engine:_recordClient(player, rawget(self, "_name"), ...)
	if player == engine.localPlayer then
		self.OnClientEvent:Fire(...)
	end
end

function Instance.FireAllClients(self, ...)
	local engine = rawget(self, "_engine")
	for _, player in engine.Players:GetPlayers() do
		self:FireClient(player, ...)
	end
end

function Instance.FireServer(self, ...)
	local engine = rawget(self, "_engine")
	self.OnServerEvent:Fire(engine.localPlayer, ...)
end

function Instance.Fire(self, ...)
	self.Event:Fire(...)
end

----------------------------------------------------------------------------
-- The engine (one per headless world)
----------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

function Engine.new()
	local self = setmetatable({}, Engine)
	self.now = 0
	self.sleeping = {} -- { thread, at, args }
	self.errors = {} -- errors raised inside game threads
	self.warnings = {}
	self.clientLog = {} -- [player] = { { remote, ... } }
	self.teleports = {}
	self.players = {}
	self.nextUserId = 1000
	self.welds = {}
	self.touchParts = {}

	self.DataModel = newInstance(self, "DataModel")
	rawset(self.DataModel, "_name", "Game")
	self.services = {}

	local workspace = self:service("Workspace")
	self.workspace = workspace

	self.Players = self:service("Players")
	local players = self.Players
	props(players).GetPlayers = function()
		local list = {}
		for _, child in children(players) do
			if child:IsA("Player") then
				table.insert(list, child)
			end
		end
		return list
	end
	props(players).GetPlayerFromCharacter = function(_, character)
		for _, p in players:GetPlayers() do
			if props(p).Character == character then
				return p
			end
		end
		return nil
	end
	props(players).GetPlayerByUserId = function(_, userId)
		for _, p in players:GetPlayers() do
			if props(p).UserId == userId then
				return p
			end
		end
		return nil
	end

	local engine = self
	props(workspace).GetServerTimeNow = function()
		return engine.now
	end

	local runService = self:service("RunService")
	self.isServer = true
	props(runService).IsServer = function()
		return engine.isServer
	end
	props(runService).IsClient = function()
		return not engine.isServer
	end
	props(runService).IsStudio = function()
		return false
	end
	self.Heartbeat = runService.Heartbeat

	local pathfinding = self:service("PathfindingService")
	props(pathfinding).CreatePath = function()
		return engine:_newPath()
	end

	local teleport = self:service("TeleportService")
	props(teleport).TeleportAsync = function(_, placeId, players, options)
		table.insert(engine.teleports, { placeId = placeId, players = players, options = options })
		return { PrivateServerId = "reserved-" .. #engine.teleports }
	end
	props(teleport).ReserveServer = function(_, placeId)
		return "reserved-code-" .. tostring(placeId), "reserved-id"
	end

	local cas = self:service("ContextActionService")
	self.boundActions = {}
	props(cas).BindAction = function(_, name, fn, _touch, ...)
		engine.boundActions[name] = fn
	end
	props(cas).UnbindAction = function(_, name)
		engine.boundActions[name] = nil
	end

	-- game:GetService / game.PlaceId / game.JobId
	local dataModel = self.DataModel
	props(dataModel).GetService = function(_, name)
		return engine:service(name)
	end
	props(dataModel).PlaceId = 0
	props(dataModel).JobId = "headless"

	-- task / os stand-ins on virtual time.
	self.task = {
		wait = function(seconds: number?)
			return engine:wait(seconds or 0)
		end,
		spawn = function(fn, ...)
			return engine:spawn(fn, ...)
		end,
		defer = function(fn, ...)
			return engine:delay(0, fn, ...)
		end,
		delay = function(seconds, fn, ...)
			return engine:delay(seconds, fn, ...)
		end,
		cancel = function(thread)
			engine:cancel(thread)
		end,
	}
	self.os = {
		clock = function()
			return engine.now
		end,
		time = function()
			return 1_700_000_000 + math.floor(engine.now)
		end,
		date = os.date,
		difftime = os.difftime,
	}
	self.Instance = {
		new = function(className: string, parent)
			local inst = newInstance(engine, className)
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
	}
	return self
end

function Engine:service(name: string)
	local s = self.services[name]
	if not s then
		s = newInstance(self, name)
		rawset(s, "_name", name)
		self.services[name] = s
		s.Parent = self.DataModel
	end
	return s
end

function Engine.typeof(v)
	if isInstance(v) then
		return "Instance"
	end
	return typeof(v)
end

Engine.isInstance = isInstance

-- Scheduler -------------------------------------------------------------

function Engine:resume(thread, ...)
	if coroutine.status(thread) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		table.insert(self.errors, debug.traceback(thread, tostring(err)))
	end
end

function Engine:spawn(fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	self:resume(thread, ...)
	return thread
end

function Engine:delay(seconds: number, fn, ...)
	local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
	table.insert(self.sleeping, { thread = thread, at = self.now + seconds, args = table.pack(...) })
	return thread
end

function Engine:cancel(thread)
	for i = #self.sleeping, 1, -1 do
		if self.sleeping[i].thread == thread then
			table.remove(self.sleeping, i)
		end
	end
	pcall(coroutine.close, thread)
end

function Engine:wait(seconds: number): number
	local thread = coroutine.running()
	local started = self.now
	table.insert(self.sleeping, { thread = thread, at = self.now + math.max(seconds, 0) })
	coroutine.yield()
	return self.now - started
end

-- One Heartbeat: physics stand-ins, then Heartbeat listeners, then threads
-- whose wait is over.
function Engine:step(dt: number?)
	dt = dt or STEP
	self.now += dt
	self:_physics(dt :: number)
	self.Heartbeat:Fire(dt)
	local due, later = {}, {}
	for _, entry in self.sleeping do
		table.insert(if entry.at <= self.now + 1e-9 then due else later, entry)
	end
	self.sleeping = later
	table.sort(due, function(a, b)
		return a.at < b.at
	end)
	for _, entry in due do
		if entry.args then
			self:resume(entry.thread, table.unpack(entry.args, 1, entry.args.n))
		else
			self:resume(entry.thread, self.now - entry.at)
		end
	end
end

-- Runs fn in a game thread and advances virtual time until it returns.
-- Errors from any game thread fail the call (unless allowErrors).
function Engine:run(fn: () -> (), options: { maxSeconds: number?, allowErrors: boolean? }?)
	local opts = options or {}
	local limit = self.now + (opts.maxSeconds or 900)
	local done, failure = false, nil
	self:spawn(function()
		local ok, err = xpcall(fn, debug.traceback)
		done = true
		if not ok then
			failure = err
		end
	end)
	while not done and self.now < limit do
		self:step()
	end
	if failure then
		error(failure, 0)
	end
	if not done then
		error(
			string.format("headless run didn't finish within %d virtual seconds", opts.maxSeconds or 900),
			0
		)
	end
	if not opts.allowErrors and #self.errors > 0 then
		error("a game thread errored:\n" .. self.errors[1], 0)
	end
end

-- Runs the world for `seconds` of virtual time (call inside engine:run).
function Engine:advance(seconds: number)
	self:wait(seconds)
end

-- Physics stand-ins ------------------------------------------------------

function Engine:_onParented(inst)
	local class = rawget(inst, "_className")
	if class == "WeldConstraint" or class == "Weld" or class == "Motor6D" then
		if not table.find(self.welds, inst) then
			table.insert(self.welds, inst)
		end
	end
end

function Engine:_physics(dt: number)
	-- Humanoids walk toward their MoveTo goal at WalkSpeed (flat, no gravity).
	for _, humanoid in self:_humanoids() do
		local goal = rawget(humanoid, "_moveGoal")
		local root = humanoid.RootPart
		if goal and root and not props(root).Anchored then
			local cf = props(root).CFrame
			local flat = Vector3.new(goal.X - cf.Position.X, 0, goal.Z - cf.Position.Z)
			local stepLength = props(humanoid).WalkSpeed * dt
			if flat.Magnitude <= math.max(stepLength, 0.5) then
				local character = rawget(humanoid, "_parent")
				local target = CFrame.new(goal.X, cf.Position.Y, goal.Z)
				character:PivotTo(target * (cf - cf.Position))
				rawset(humanoid, "_moveGoal", nil)
				humanoid.MoveToFinished:Fire(true)
			else
				local character = rawget(humanoid, "_parent")
				local move = flat.Unit * stepLength
				local facing = CFrame.lookAt(cf.Position + move, cf.Position + move * 2)
				character:PivotTo(facing)
			end
		end
	end

	-- Welds keep Part1 where it was relative to Part0.
	for i = #self.welds, 1, -1 do
		local weld = self.welds[i]
		if rawget(weld, "_destroyed") or not rawget(weld, "_parent") then
			table.remove(self.welds, i)
		else
			local p = props(weld)
			local part0, part1 = p.Part0, p.Part1
			if part0 and part1 and props(part1) then
				local class = rawget(weld, "_className")
				if class == "WeldConstraint" then
					local offset = rawget(weld, "_offset")
					if not offset or rawget(weld, "_pair0") ~= part0 or rawget(weld, "_pair1") ~= part1 then
						offset = props(part0).CFrame:ToObjectSpace(props(part1).CFrame)
						rawset(weld, "_offset", offset)
						rawset(weld, "_pair0", part0)
						rawset(weld, "_pair1", part1)
					end
					if not props(part1).Anchored or props(part0).Anchored then
						setCFrame(part1, props(part0).CFrame * offset)
					end
				else
					local c0 = p.C0 or CFrame.new()
					local c1 = p.C1 or CFrame.new()
					setCFrame(part1, props(part0).CFrame * c0 * c1:Inverse())
				end
			end
		end
	end

	-- Touched: a character root entering a part that has Touched listeners.
	for _, part in self:_touchListeners() do
		local touching = rawget(part, "_touching") or {}
		rawset(part, "_touching", touching)
		for _, player in self.Players:GetPlayers() do
			local character = props(player).Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local inside = self:_overlaps(part, root)
				if inside and not touching[root] then
					touching[root] = true
					part.Touched:Fire(root)
				elseif not inside then
					touching[root] = nil
				end
			end
		end
	end
end

function Engine:_humanoids()
	local list = {}
	for _, d in self.workspace:GetDescendants() do
		if rawget(d, "_className") == "Humanoid" and rawget(d, "_moveGoal") then
			table.insert(list, d)
		end
	end
	return list
end

function Engine:_touchListeners()
	local list = {}
	for _, d in self.workspace:GetDescendants() do
		local s = rawget(d, "_signals").Touched
		if s and #s.handlers > 0 then
			table.insert(list, d)
		end
	end
	return list
end

function Engine:_overlaps(part, root): boolean
	local rel = props(part).CFrame:PointToObjectSpace(props(root).CFrame.Position)
	local half = props(part).Size / 2 + Vector3.new(1, 3, 1)
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

-- Straight-line pathfinding: start, then the goal.
function Engine:_newPath()
	local engine = self
	local path = newInstance(engine, "Path")
	props(path).Status = Enum.PathStatus.NoPath
	props(path).ComputeAsync = function(p, from, to)
		if engine.pathfindingFails then -- set by tests: no route found
			props(p).Status = Enum.PathStatus.NoPath
			return
		end
		props(p).Status = Enum.PathStatus.Success
		rawset(p, "_waypoints", {
			{ Position = from, Action = Enum.PathWaypointAction.Walk },
			{ Position = to, Action = Enum.PathWaypointAction.Walk },
		})
	end
	props(path).GetWaypoints = function(p)
		return rawget(p, "_waypoints") or {}
	end
	return path
end

-- Players ---------------------------------------------------------------

function Engine:_recordClient(player, remote: string, ...)
	local log = self.clientLog[player] or {}
	self.clientLog[player] = log
	table.insert(log, { remote = remote, args = table.pack(...) })
	local sink = self.clientSink
	if sink then
		sink(player, remote, ...)
	end
end

-- Hud messages sent to a player: { { kind, data } }, optionally one kind only.
function Engine:hudMessages(player, kind: string?)
	local out = {}
	for _, entry in self.clientLog[player] or {} do
		if entry.remote == "Hud" and (kind == nil or entry.args[1] == kind) then
			table.insert(out, { kind = entry.args[1], data = entry.args[2] })
		end
	end
	return out
end

local function buildCharacter(engine, player, at)
	local character = engine.Instance.new("Model")
	character.Name = player.Name
	local root = engine.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = at
	root.Parent = character
	local torso = engine.Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2, 2, 1)
	torso.CFrame = at
	torso.Parent = character
	local weld = engine.Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = torso
	weld.Parent = root
	local humanoid = engine.Instance.new("Humanoid")
	humanoid.Parent = character
	character.PrimaryPart = root
	return character
end

-- A player who joined the server, with a character at `at`.
function Engine:addPlayer(name: string, options: { at: CFrame?, joinData: any?, userId: number? }?)
	local opts = options or {}
	self.nextUserId += 1
	local player = newInstance(self, "Player")
	rawset(player, "_name", name)
	local p = props(player)
	p.DisplayName = name
	p.UserId = opts.userId or self.nextUserId
	local engine = self
	local spawnAt = opts.at or CFrame.new(0, 3, 0)
	p.GetJoinData = function()
		return opts.joinData or {}
	end
	p.LoadCharacter = function(plr)
		local old = props(plr).Character
		if old then
			plr.CharacterRemoving:Fire(old)
			old:Destroy()
		end
		local character = buildCharacter(engine, plr, rawget(plr, "_spawnAt") or spawnAt)
		props(plr).Character = character
		character.Parent = engine.workspace
		plr.CharacterAdded:Fire(character)
		return character
	end
	p.Kick = function(plr, message)
		rawset(plr, "_kicked", message or true)
		engine:removePlayer(plr)
	end
	rawset(player, "_spawnAt", spawnAt)
	local gui = newInstance(self, "PlayerGui")
	rawset(gui, "_name", "PlayerGui")
	gui.Parent = player
	table.insert(self.players, player)
	player.Parent = self.Players
	player:LoadCharacter()
	self.Players.PlayerAdded:Fire(player)
	return player
end

-- The player whose client scripts (Hud.client) run in this world.
function Engine:setLocalPlayer(player)
	self.localPlayer = player
	props(self.Players).LocalPlayer = player
end

-- Text of every TextLabel/TextButton in the local player's PlayerGui.
function Engine:guiTexts(): { string }
	local texts = {}
	local gui = self.localPlayer and self.localPlayer:FindFirstChild("PlayerGui")
	for _, d in if gui then gui:GetDescendants() else {} do
		if (d:IsA("GuiObject")) and type(d.Text) == "string" and d.Text ~= "" then
			table.insert(texts, d.Text)
		end
	end
	return texts
end

-- True if some visible label in the local player's GUI contains `text`.
function Engine:guiShows(text: string): boolean
	local gui = self.localPlayer and self.localPlayer:FindFirstChild("PlayerGui")
	for _, d in if gui then gui:GetDescendants() else {} do
		if d:IsA("GuiObject") and type(d.Text) == "string" and string.find(d.Text, text, 1, true) then
			local node = d
			local visible = true
			while node and node ~= gui do
				if props(node).Visible == false or props(node).Enabled == false then
					visible = false
				end
				node = rawget(node, "_parent")
			end
			if visible then
				return true
			end
		end
	end
	return false
end

-- The first GuiButton in the local player's GUI with this text.
function Engine:guiButton(text: string)
	local gui = self.localPlayer and self.localPlayer:FindFirstChild("PlayerGui")
	for _, d in if gui then gui:GetDescendants() else {} do
		if d:IsA("GuiButton") and d.Text == text then
			return d
		end
	end
	return nil
end

function Engine:removePlayer(player)
	self.Players.PlayerRemoving:Fire(player)
	local character = props(player).Character
	if character then
		character:Destroy()
	end
	player.Parent = nil
	local i = table.find(self.players, player)
	if i then
		table.remove(self.players, i)
	end
end

function Engine.rootOf(player)
	local character = props(player).Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

-- Puts a player's character at a position (keeps facing).
function Engine:teleport(player, position: Vector3)
	local character = props(player).Character
	local cf = character:GetPivot()
	character:PivotTo(cf - cf.Position + position)
end

-- Fires a ProximityPrompt for a player, as if they held it.
function Engine.trigger(prompt, player)
	assert(props(prompt).Enabled, "prompt " .. rawget(prompt, "_name") .. " is disabled")
	prompt.Triggered:Fire(player)
end

return Engine
