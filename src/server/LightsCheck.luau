--[[
	Rules for the "Who's there?!" checks (Config.LightsCheck): once the lights
	are on, each lit house checks itself now and then and spots any Santa
	inside who isn't hiding. Pure, so Lune can test it; HouseChecks does the
	lights, sounds and bonks.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local L = Config.LightsCheck

local LightsCheck = {}

-- Do the houses on this stop check themselves? Krampus's Lair has nobody home.
function LightsCheck.applies(kindName: string?): boolean
	return L.Enabled and kindName ~= "Finale"
end

-- When house `index` of `count` first flashes, for lights on at `lightsAt`:
-- spread across one Interval so the street doesn't flash all at once.
function LightsCheck.firstCheckAt(lightsAt: number, index: number, count: number): number
	local spread = if count > 0 then (index - 1) / count * L.Interval else 0
	return lightsAt + L.FirstDelay + L.WarnSeconds + spread
end

-- The next flash after one at `previous`. `roll` is 0-1 (Random:NextNumber()).
function LightsCheck.nextCheckAt(previous: number, roll: number): number
	return previous + L.Interval + (roll * 2 - 1) * L.Jitter
end

-- Is the warning showing for a flash due at `checkAt`?
function LightsCheck.warning(t: number, checkAt: number): boolean
	return t >= checkAt - L.WarnSeconds and t < checkAt
end

-- Is `position` inside the box (a house's bounding box), Margin in from the walls?
function LightsCheck.inside(box: CFrame, size: Vector3, position: Vector3): boolean
	local p = box:PointToObjectSpace(position)
	local m = L.Margin
	return math.abs(p.X) <= size.X / 2 - m and math.abs(p.Z) <= size.Z / 2 - m and math.abs(p.Y) <= size.Y / 2
end

export type Santa = { player: any, position: Vector3, hidden: boolean, captive: boolean }

-- The Santas a flash in this house spots: inside, not hiding, not snatched.
function LightsCheck.spotted(box: CFrame, size: Vector3, santas: { Santa }): { any }
	local caught = {}
	for _, santa in santas do
		if not santa.hidden and not santa.captive and LightsCheck.inside(box, size, santa.position) then
			table.insert(caught, santa.player)
		end
	end
	return caught
end

-- Where a spotted Santa lands: ExitDistance outside the house's box (its
-- bounding box), facing away from it. Through the wall nearest the front
-- door at `door` (the door is in the front wall), at the door's height. With
-- no door, through the wall that faces `front`, a few studs above the floor.
function LightsCheck.exitCFrame(box: CFrame, size: Vector3, door: Vector3?, front: Vector3): CFrame
	local half = size / 2
	local p = if door then box:PointToObjectSpace(door) else Vector3.new(0, -half.Y + 3, 0)
	local axis, sign
	if door then
		-- The face the door is closest to.
		local gapX, gapZ = half.X - math.abs(p.X), half.Z - math.abs(p.Z)
		if gapX < gapZ then
			axis, sign = "X", if p.X >= 0 then 1 else -1
		else
			axis, sign = "Z", if p.Z >= 0 then 1 else -1
		end
	else
		local f = box:VectorToObjectSpace(front)
		if math.abs(f.X) > math.abs(f.Z) then
			axis, sign = "X", if f.X >= 0 then 1 else -1
		else
			axis, sign = "Z", if f.Z >= 0 then 1 else -1
		end
	end
	local out, at
	if axis == "X" then
		out = Vector3.new(sign, 0, 0)
		at = Vector3.new(sign * (half.X + L.ExitDistance), p.Y, p.Z)
	else
		out = Vector3.new(0, 0, sign)
		at = Vector3.new(p.X, p.Y, sign * (half.Z + L.ExitDistance))
	end
	local world = box:PointToWorldSpace(at)
	local dir = box:VectorToWorldSpace(out)
	return CFrame.lookAt(world, world + dir)
end

return LightsCheck
