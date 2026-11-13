--[[
	Line of sight for in-house prompts (Josh, 13 Nov 2026: "you can interact
	with gifts through walls, outside of the house"). Map prompts are built
	with RequiresLineOfSight off, because Roblox casts that ray from the
	camera, and with Invisicam the camera is often outside the house while
	your Santa is inside. client/PromptSight casts from your Santa's head
	instead and switches the prompt off (for you only) while a wall is in the
	way. These are the pure rules; the client does the raycasts.
]]

local PromptSight = {}

-- Seconds between checks, and how far (studs) past a prompt's reach to bother.
PromptSight.Interval = 0.15
PromptSight.Margin = 6
-- A ray that stops within this (studs) of the target's skin still counts
-- as seeing it: it clipped the table or shelf the gift sits on.
PromptSight.Slack = 0.75
-- Things you reach past, not through: a hit inside one of these models is
-- skipped and the ray carries on.
PromptSight.SeeThrough = { Tree = true, Present = true }
-- The prompt's own model is skipped too when it has at most this many
-- children (a present: box, ribbon, bow), never when it's a whole house.
PromptSight.SmallModel = 8
-- At most this many skipped hits per check.
PromptSight.MaxSkips = 4

local ACTIONS = { Grab = true, Search = true, Steal = true, Hide = true }

-- Whether a prompt needs your Santa to see it: gifts, search spots, hiding
-- spots, tree boxes and the Naughty List. Doors, chimneys and buys don't.
function PromptSight.applies(actionText: string, parentName: string): boolean
	if ACTIONS[actionText] then
		return true
	end
	return actionText == "Open" and parentName == "TreeBox"
end

-- The server's check is looser (Josh's crew on laggy phones: never refuse a
-- fair grab): it also tries from points this far round the head, since the
-- server sees a Santa a little behind where they really are.
PromptSight.ServerNudge = 1.5

-- Is the target blocked, given where the ray hit (nil = nothing in the way)?
function PromptSight.blocked(hit: Vector3?, target: Vector3, targetSize: Vector3): boolean
	if not hit then
		return false
	end
	-- Its thinnest side, so a thin trigger flush to a wall (the secret
	-- bookcase) can't be reached from the far side of that wall.
	local thin = math.min(targetSize.X, targetSize.Y, targetSize.Z)
	local reach = thin / 2 + PromptSight.Slack
	return (hit - target).Magnitude > reach
end

local function seeThroughModel(part: Instance): Instance?
	local node = part.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and PromptSight.SeeThrough[node.Name] then
			return node
		end
		node = node.Parent
	end
	return nil
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
params.RespectCanCollide = true

-- Can a Santa whose head is at `from` see the prompt's part? Skips the
-- character, the part, its small model (ribbon, bow), trees and presents.
function PromptSight.sees(from: Vector3, target: BasePart, character: Instance?): boolean
	local goal = target.Position
	local skip: { Instance } = { target }
	if character then
		table.insert(skip, character)
	end
	local model = target.Parent
	if model and model:IsA("Model") and #model:GetChildren() <= PromptSight.SmallModel then
		table.insert(skip, model) -- the present's ribbon and bow, not a whole house
	end
	for _ = 0, PromptSight.MaxSkips do
		params.FilterDescendantsInstances = skip
		local result = workspace:Raycast(from, goal - from, params)
		if not result then
			return true
		end
		local through = seeThroughModel(result.Instance)
		if not through then
			return not PromptSight.blocked(result.Position, goal, target.Size)
		end
		table.insert(skip, through)
	end
	return true
end

-- The server's check before a grab, search or hide goes through: true when
-- any of the head, the root or a point ServerNudge round the head sees it.
function PromptSight.serverAllows(character: Model?, prompt: ProximityPrompt): boolean
	local target = prompt.Parent
	if not character or not target or not target:IsA("BasePart") then
		return true
	end
	if not PromptSight.applies(prompt.ActionText, target.Name) then
		return true
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head or not head:IsA("BasePart") then
		return true
	end
	local at = head.Position
	local n = PromptSight.ServerNudge
	local root = character:FindFirstChild("HumanoidRootPart")
	local froms = { at, Vector3.new(at.X + n, at.Y, at.Z), Vector3.new(at.X - n, at.Y, at.Z) }
	table.insert(froms, Vector3.new(at.X, at.Y, at.Z + n))
	table.insert(froms, Vector3.new(at.X, at.Y, at.Z - n))
	if root and root:IsA("BasePart") then
		table.insert(froms, root.Position)
	end
	for _, from in froms do
		if PromptSight.sees(from, target, character) then
			return true
		end
	end
	return false
end

return PromptSight
