--[[
	Pure rules for pop-in houses (Config.PopIn, runtime in PopInHouses): which
	filler townhouses open their room and which pack it away, given where the
	Santas are. No Instances, so it runs in unit tests.

	A house opens when a Santa is within OpenRadius of its door. It packs away
	once no Santa has been within CloseRadius for CloseSeconds and nothing (a
	Santa, an elf, a dog, Krampus) is still inside. At most MaxOpen rooms are
	open at once: when that's full, the room idle longest makes way.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local PopInRules = {}

export type House = {
	doorAt: Vector3, -- world position of the front door
	open: boolean,
	lastNear: number, -- last time a Santa was within CloseRadius
	occupied: boolean?, -- something with a Humanoid is inside (runtime sets it)
}

export type Settings = {
	OpenRadius: number,
	CloseRadius: number,
	CloseSeconds: number,
	MaxOpen: number,
}

-- Flat (XZ) distance from `at` to the nearest of `points`.
function PopInRules.nearest(at: Vector3, points: { Vector3 }): number
	local best = math.huge
	for _, p in points do
		local d = Vector3.new(p.X - at.X, 0, p.Z - at.Z).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

-- Can this open room be packed away now?
local function idle(house: House, near: number, t: number, cfg: Settings): boolean
	return near > cfg.CloseRadius and t - house.lastNear >= cfg.CloseSeconds and not house.occupied
end

--[[
	One tick. Updates each house's open/lastNear and returns the indices to
	open and to close (closes first: the caller builds rooms after packing).
]]
function PopInRules.step(
	houses: { House },
	santas: { Vector3 },
	t: number,
	settings: Settings?
): ({ number }, { number })
	local cfg = settings or Config.PopIn :: any
	local opens, closes = {}, {}
	local nearOf = {}
	local openCount = 0
	for i, house in houses do
		local near = PopInRules.nearest(house.doorAt, santas)
		nearOf[i] = near
		if house.open then
			if near <= cfg.CloseRadius then
				house.lastNear = t
			end
			if idle(house, near, t, cfg) then
				house.open = false
				table.insert(closes, i)
			else
				openCount += 1
			end
		end
	end

	-- Closest doors first, so the house a Santa is walking into wins.
	local wanted = {}
	for i, house in houses do
		if not house.open and nearOf[i] <= cfg.OpenRadius then
			table.insert(wanted, i)
		end
	end
	table.sort(wanted, function(a, b)
		return nearOf[a] < nearOf[b]
	end)

	for _, i in wanted do
		if openCount >= cfg.MaxOpen then
			-- Full: the open room nobody's near (idle longest) makes way.
			local victim, oldest = nil, math.huge
			for j, other in houses do
				if other.open and nearOf[j] > cfg.CloseRadius and not other.occupied then
					if other.lastNear < oldest then
						victim, oldest = j, other.lastNear
					end
				end
			end
			if not victim then
				break -- every open room has a Santa by it: this door stays shut for now
			end
			houses[victim].open = false
			table.insert(closes, victim)
			openCount -= 1
		end
		houses[i].open = true
		houses[i].lastNear = t
		openCount += 1
		table.insert(opens, i)
	end
	return opens, closes
end

return PopInRules
