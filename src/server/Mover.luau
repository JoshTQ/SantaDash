--[[
	Path-following for server-driven Humanoids (Krampus, elf bots). Call
	moveTo(goal) every tick; it re-paths when the goal moves or the path is old,
	and walks straight at the goal when no path exists.
]]

local PathfindingService = game:GetService("PathfindingService")

local Mover = {}
Mover.__index = Mover

local WAYPOINT_REACHED = 4
local GOAL_MOVED = 6

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function Mover.new(humanoid: Humanoid, root: BasePart, agent: { [string]: any }, repathSeconds: number)
	local self = setmetatable({}, Mover)
	self.humanoid = humanoid
	self.root = root
	self.path = PathfindingService:CreatePath(agent)
	self.repathSeconds = repathSeconds
	self.waypoints = nil :: { PathWaypoint }?
	self.waypointIndex = 0
	self.goal = nil :: Vector3?
	self.pathAt = 0
	return self
end

function Mover:moveTo(goal: Vector3)
	local root = self.root
	local t = os.clock()
	if not self.goal or (self.goal - goal).Magnitude > GOAL_MOVED or t - self.pathAt > self.repathSeconds then
		self.goal = goal
		self.pathAt = t
		local ok = pcall(function()
			self.path:ComputeAsync(root.Position, goal)
		end)
		if ok and self.path.Status == Enum.PathStatus.Success then
			self.waypoints = self.path:GetWaypoints()
			self.waypointIndex = 2
		else
			self.waypoints = nil
		end
	end
	local waypoints = self.waypoints
	if not waypoints then
		self.humanoid:MoveTo(goal) -- no path: walk straight at it
		return
	end
	local waypoint = waypoints[self.waypointIndex]
	while waypoint and flatDistance(waypoint.Position, root.Position) < WAYPOINT_REACHED do
		self.waypointIndex += 1
		waypoint = waypoints[self.waypointIndex]
	end
	self.humanoid:MoveTo(if waypoint then waypoint.Position else goal)
end

function Mover:stop()
	self.humanoid:MoveTo(self.root.Position)
end

-- Teleports the body and forgets the old path.
function Mover:teleport(cframe: CFrame)
	self.root.AssemblyLinearVelocity = Vector3.zero
	self.root.CFrame = cframe
	self.goal = nil
	self.waypoints = nil
end

return Mover
