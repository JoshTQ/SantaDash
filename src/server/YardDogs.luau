--[[
	Yard dogs (Config.DogAI.Yard, Josh 11 Nov 2026: "All of them"): on later
	stops the richer houses (Far ring, or one with a secret room) keep a dog in
	the front garden. It paces across the garden between the house and the
	street, leashed close to home (Yard.Leash), and runs on the same senses as
	every other guard dog (GuardDogs / DogBrain): sight, hearing, scent, Fetch,
	bones and dog flaps.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GuardDogs = require(script.Parent.GuardDogs)
local MapBuilder = require(script.Parent.MapBuilder)

local Y = Config.DogAI.Yard

local YardDogs = {}

-- Does this stop get yard dogs?
function YardDogs.applies(stopIndex: number, kindName: string?): boolean
	if kindName == "Finale" then
		return false -- Krampus's Lair: his clockwork, not dogs
	end
	return table.find(Y.Stops, stopIndex) ~= nil
end

-- The richer houses, best first: a secret room, then the Far ring, then the
-- furthest down the street. At most Yard.Count.
function YardDogs.pick(houses: { any }): { any }
	local list = {}
	for _, house in houses do
		local plan = house.plan or house
		if plan.side ~= 0 and (plan.secret or plan.ring == "Far") then
			table.insert(list, plan)
		end
	end
	table.sort(list, function(a, b)
		if (a.secret == true) ~= (b.secret == true) then
			return a.secret == true
		end
		if (a.ring == "Far") ~= (b.ring == "Far") then
			return a.ring == "Far"
		end
		return a.distance > b.distance
	end)
	while #list > Y.Count do
		table.remove(list)
	end
	return list
end

-- One dog per picked house, pacing its front garden (stop space: +Z runs
-- down the street, houses stand at side * sideOffset facing the road).
function YardDogs.specs(stop, sideOffset: number): { GuardDogs.Spec }
	local specs = {}
	for i, plan in YardDogs.pick(stop.houses) do
		local front = plan.side * (sideOffset - plan.size.Z / 2 - Y.Garden)
		local half = math.max(4, plan.size.X / 2 - 2)
		local a = (stop.origin * CFrame.new(front, 0, plan.distance - half)).Position
		local b = (stop.origin * CFrame.new(front, 0, plan.distance + half)).Position
		local at = a + Vector3.new(0, 3, 0)
		table.insert(specs, {
			kind = if i % 2 == 1 then "DogCorgi" else "DogTin",
			at = CFrame.lookAt(at, at + (b - a)),
			patrol = { a, b },
			startIndex = 2,
			leash = Y.Leash,
			cooldown = Config.Canal.Dogs.CorgiCooldown,
		})
	end
	return specs
end

function YardDogs.start(run, stop): (() -> ())?
	local layout = run.route.map and run.route.map.layout
	local sideOffset = (layout and layout.SideOffset) or Config.Map.SideOffset
	local specs = YardDogs.specs(stop, sideOffset)
	if #specs == 0 then
		return nil
	end
	return GuardDogs.start(run, specs, run.route.model, function(position)
		return MapBuilder.isAboard(stop.deckCFrame, position)
	end, stop)
end

return YardDogs
