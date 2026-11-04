--[[
	The lobby -> run place handoff contract (pure, unit tested).

	The lobby place reserves a run server for each crew and teleports the crew
	with TeleportData = Handoff.make(...). The run server reads it from
	player:GetJoinData().TeleportData and only admits members of that crew.
	Reserved servers can only be entered with the access code the lobby holds,
	so the data is a routing hint rather than a security boundary; it is still
	validated because clients can send their own TeleportData elsewhere.
]]

local Config = require(script.Parent.Config)

local Handoff = {}

Handoff.Version = 1
Handoff.Kinds = { Public = true, Party = true, Private = true }

export type Data = {
	v: number,
	crewId: string,
	kind: string, -- "Public" | "Party" | "Private"
	members: { number }, -- UserIds, in seat order
}

function Handoff.make(crewId: string, kind: string, members: { number }): Data
	return { v = Handoff.Version, crewId = crewId, kind = kind, members = table.clone(members) }
end

-- Returns a clean copy of valid data, or nil.
function Handoff.read(raw: any): Data?
	if type(raw) ~= "table" or raw.v ~= Handoff.Version then
		return nil
	end
	if type(raw.crewId) ~= "string" or #raw.crewId == 0 or #raw.crewId > 64 then
		return nil
	end
	if type(raw.kind) ~= "string" or not Handoff.Kinds[raw.kind] then
		return nil
	end
	local members = raw.members
	if type(members) ~= "table" or #members == 0 or #members > Config.Lobby.CrewMax then
		return nil
	end
	local clean = {}
	for i = 1, #members do
		local id = members[i]
		if type(id) ~= "number" or id % 1 ~= 0 then
			return nil
		end
		clean[i] = id
	end
	return { v = raw.v, crewId = raw.crewId, kind = raw.kind, members = clean }
end

-- Same crew and listed as a member.
function Handoff.admits(crew: Data, joined: Data?, userId: number): boolean
	if not joined or joined.crewId ~= crew.crewId then
		return false
	end
	return table.find(crew.members, userId) ~= nil
end

-- A first run leaves once the whole crew is in, or at departAt with whoever
-- made it. A requeued run always waits for its "Next run in 5..." countdown.
function Handoff.shouldDepart(
	arrived: number,
	expected: number,
	t: number,
	departAt: number,
	requeue: boolean
): boolean
	if arrived == 0 then
		return false
	end
	return t >= departAt or (not requeue and arrived >= expected)
end

-- True in a published run place, or in Studio when the place sets the
-- RunPlace attribute on Workspace (to test the run place on its own).
function Handoff.isRunPlace(placeId: number, runPlaceAttribute: any): boolean
	if runPlaceAttribute == true then
		return true
	end
	return Config.Places.Run ~= 0 and placeId == Config.Places.Run
end

return Handoff
