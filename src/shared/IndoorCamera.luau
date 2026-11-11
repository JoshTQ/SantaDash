--[[
	Indoor camera rules (Josh, 11 Nov 2026: "hard for a player to control [in
	houses], and the camera is janky"). Roblox's default camera zooms in hard
	whenever a wall gets between it and the Santa, then springs back out: in a
	small room that's a constant jitter. client/IndoorCamera fixes it two ways:

	- Walls between the camera and your Santa fade out (Invisicam) instead of
	  shoving the camera into your back.
	- Under a roof with walls close round you, the camera can't zoom out past
	  MaxZoomInside, so it never ends up outside the house looking at a wall.

	Pure: the client does the raycasts and passes the hits in.
]]

local IndoorCamera = {}

IndoorCamera.MaxZoomInside = 13 -- studs: over the shoulder in the roomiest pop-in room
IndoorCamera.CeilingRange = 18 -- a roof or ceiling this close above means "maybe inside"
IndoorCamera.WallRange = 22 -- ... and walls this close on at least WallsNeeded of 4 sides
IndoorCamera.WallsNeeded = 2
IndoorCamera.EnterSeconds = 0.2 -- inside this long before the zoom limit kicks in
IndoorCamera.LeaveSeconds = 0.6 -- outside this long before it lifts (doorways don't flicker it)

-- Inside a house? ceiling: distance to whatever's above (nil if nothing),
-- walls: distances to the nearest wall in 4 directions (nil = nothing in range).
function IndoorCamera.inside(ceiling: number?, walls: { number? }): boolean
	if not ceiling or ceiling > IndoorCamera.CeilingRange then
		return false
	end
	local near = 0
	for i = 1, 4 do
		local d = walls[i]
		if d and d <= IndoorCamera.WallRange then
			near += 1
		end
	end
	return near >= IndoorCamera.WallsNeeded
end

export type State = { indoors: boolean, since: number }

function IndoorCamera.newState(): State
	return { indoors = false, since = 0 }
end

--[[
	Hysteresis: feeds this frame's raw `inside` and the time, returns the
	settled indoors flag (it only flips once the raw value has held for
	EnterSeconds / LeaveSeconds). `since` tracks when the raw value last
	disagreed with the settled one.
]]
function IndoorCamera.step(state: State, inside: boolean, t: number): boolean
	if inside == state.indoors then
		state.since = t
		return state.indoors
	end
	local wait = if inside then IndoorCamera.EnterSeconds else IndoorCamera.LeaveSeconds
	if t - state.since >= wait then
		state.indoors = inside
		state.since = t
	end
	return state.indoors
end

-- The camera's max zoom: clamped inside, the player's own outside.
function IndoorCamera.maxZoom(indoors: boolean, outdoorMax: number): number
	return if indoors then math.min(IndoorCamera.MaxZoomInside, outdoorMax) else outdoorMax
end

return IndoorCamera
