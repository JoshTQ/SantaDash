--[[
	Security dogs a full noise meter lets loose (Config.Noise.Alarm, Josh 6 Nov
	2026). They run in from the far end of the street and hunt the nearest
	Santa who isn't safe at the Sleigh Stop; once one sees you it chases
	(GuardDogs / DogBrain: sight, hearing, scent, the pack). A bump works like
	the Christmas Market dogs (DogBump): a corgi knocks a present out of your
	sack, a tin dog bonks you and winds down. They stay until the sleigh leaves.

	Body: the approved DogCorgi / DogTin models (ServerStorage.Assets), else a
	coloured block stand-in.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GuardDogs = require(script.Parent.GuardDogs)
local MapBuilder = require(script.Parent.MapBuilder)
local NoiseAlarm = require(script.Parent.NoiseAlarm)

local A = Config.Noise.Alarm

local AlarmDogs = {}

-- Lets the dogs loose for this stop. Returns their cleanup.
function AlarmDogs.start(run, stop): () -> ()
	local release = stop.krampusSpawn -- the far end of the street
	local specs = {}
	for i, kind in A.Dogs do
		table.insert(specs, {
			kind = kind,
			at = release * CFrame.new(NoiseAlarm.spawnOffset(i, #A.Dogs)),
			hunt = true,
			cooldown = A.Cooldown,
		})
	end
	return GuardDogs.start(run, specs, run.route.model, function(position)
		return MapBuilder.isAboard(stop.deckCFrame, position)
	end)
end

return AlarmDogs
