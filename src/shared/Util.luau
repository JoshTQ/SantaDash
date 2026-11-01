--[[
	Small helpers shared by server and client.
]]

local Util = {}

-- Server-synchronised clock; every deadline sent to clients uses it.
function Util.now(): number
	return workspace:GetServerTimeNow()
end

-- "0:07" style countdown, rounding up.
function Util.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

function Util.humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function Util.rootOf(player: Player): BasePart?
	local humanoid = Util.humanoidOf(player)
	return humanoid and humanoid.RootPart
end

-- Moves a character without carrying over its velocity.
function Util.teleport(player: Player, target: CFrame)
	local root = Util.rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = target
	end
end

-- Removes the first occurrence of value from an array; returns true if found.
function Util.removeValue(list: { any }, value: any): boolean
	local index = table.find(list, value)
	if index then
		table.remove(list, index)
		return true
	end
	return false
end

-- Picks a key from { {key, weight} } entries. Zero weights are never picked.
function Util.weightedPick(rng: Random, entries: { { any } }): any
	local total = 0
	for _, entry in entries do
		total += entry[2]
	end
	local roll = rng:NextNumber() * total
	for _, entry in entries do
		if entry[2] > 0 then
			roll -= entry[2]
			if roll <= 0 then
				return entry[1]
			end
		end
	end
	for i = #entries, 1, -1 do -- floating point leftovers: last non-zero entry
		if entries[i][2] > 0 then
			return entries[i][1]
		end
	end
	return entries[1][1]
end

return Util
