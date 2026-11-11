--[[
	When a Party or Private sleigh's riders go into the queue (pure, unit tested).

	Riders join the queue the moment they sit down (Josh, 11 Nov 2026), but a
	Party or Private group must not be split: queueing the first friend on
	their own would send them off before their mates climb in. So the group
	is held together, already "in the queue" on their screens, and handed to
	the matchmaker as soon as one of these is true:

	  Full     the sleigh has a whole crew
	  Friends  two or more riders, every rider has a Roblox friend aboard, and
	           none of them has a friend in the lobby who isn't aboard yet
	  Quiet    nobody has climbed in for Config.Lobby.GatherSeconds
	  (the sleigh taking off flushes the group too; Lobby handles that)

	Generic over the rider type so tests can use plain strings.
]]

local Config = require(script.Parent.Config)

local PartyGather = {}

export type Reason = "Full" | "Friends" | "Quiet"

-- riders: the group aboard. lastBoardAt: when the newest rider sat down.
-- lobby: players in the lobby who could still climb in (not aboard, not
-- queued, not in a run). areFriends(a, b): Roblox friends.
function PartyGather.ready<T>(
	riders: { T },
	lastBoardAt: number,
	now: number,
	lobby: { T },
	areFriends: (T, T) -> boolean
): Reason?
	if #riders == 0 then
		return nil
	end
	if #riders >= Config.Lobby.CrewMax then
		return "Full"
	end
	if now - lastBoardAt >= Config.Lobby.GatherSeconds then
		return "Quiet"
	end
	if #riders < 2 then
		return nil
	end
	for _, rider in riders do
		local hasFriend = false
		for _, other in riders do
			if other ~= rider and areFriends(rider, other) then
				hasFriend = true
				break
			end
		end
		if not hasFriend then
			return nil -- may be waiting for someone who isn't a Roblox friend
		end
		for _, other in lobby do
			if areFriends(rider, other) then
				return nil -- a friend is still on the way
			end
		end
	end
	return "Friends"
end

return PartyGather
