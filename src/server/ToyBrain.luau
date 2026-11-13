--[[
	Pure rules for the Lair toys (Config.Toys): the Snowball Launcher's soft
	auto-aim, Krampus's flinch cooldown and Glitter Bomb clouds. No Instances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local T = Config.Toys

local ToyBrain = {}

export type Target = { position: Vector3, kind: string, hit: (seconds: number) -> ()? }
export type Cloud = { position: Vector3, untilT: number }

-- The nearest target within Range and AimCone of where the Santa faces
-- (on the floor plan), or nil: the snowball then flies straight ahead.
function ToyBrain.aim(from: Vector3, look: Vector3, targets: { Target }): Target?
	local L = T.Launcher
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 1e-3 then
		return nil
	end
	facing = facing.Unit
	local minCos = math.cos(math.rad(L.AimCone))
	local best, bestDistance = nil, L.Range
	for _, target in targets do
		local offset = Vector3.new(target.position.X - from.X, 0, target.position.Z - from.Z)
		local d = offset.Magnitude
		if d <= bestDistance and (d < 1e-3 or facing:Dot(offset.Unit) >= minCos) then
			best, bestDistance = target, d
		end
	end
	return best
end

-- Seconds the snowball takes to get there.
function ToyBrain.flightSeconds(from: Vector3, to: Vector3): number
	return (to - from).Magnitude / T.Launcher.Speed
end

-- Krampus flinches only once per KrampusCooldown, whoever throws.
function ToyBrain.canFlinch(lastFlinchAt: number?, t: number): boolean
	return lastFlinchAt == nil or t - lastFlinchAt >= T.Launcher.KrampusCooldown
end

-- Inside any live glitter cloud (flat distance, a little height either way).
function ToyBrain.inCloud(clouds: { Cloud }, at: Vector3, t: number): boolean
	local r = T.Glitter.Radius
	for _, c in clouds do
		if t < c.untilT then
			local flat = Vector3.new(at.X - c.position.X, 0, at.Z - c.position.Z).Magnitude
			if flat <= r and math.abs(at.Y - c.position.Y) <= r then
				return true
			end
		end
	end
	return false
end

-- Drops clouds that have faded.
function ToyBrain.prune(clouds: { Cloud }, t: number)
	for i = #clouds, 1, -1 do
		if t >= clouds[i].untilT then
			table.remove(clouds, i)
		end
	end
end

return ToyBrain
