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

return PromptSight
