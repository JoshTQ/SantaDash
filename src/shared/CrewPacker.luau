--[[
	Packs matchmaking tickets into crews (pure, unit tested).

	A ticket is one Public rider or one Party group, as it sits in the shared
	MemoryStore queue. Groups are never split. Oldest tickets are served first:
	a crew starts from the oldest ticket and is topped up first-fit with newer
	ones. A crew leaves when it is full, or part-full once its oldest ticket has
	waited its kind's wait time (bots fill the empty seats in the run place).
	Everything not in a leaving crew goes back in the queue unchanged.
]]

local Config = require(script.Parent.Config)

export type Ticket = {
	id: string, -- unique per ticket
	kind: string, -- "Public" | "Party"
	members: { number }, -- UserIds
	servers: { string }, -- JobId of the lobby server holding each member
	since: number, -- unix seconds when queued
}

export type Crew = {
	kind: string, -- "Party" if it holds a Party group, else "Public"
	members: { number },
	servers: { string },
	tickets: { Ticket },
}

local CrewPacker = {}

local function waitFor(ticket: Ticket): number
	local mm = Config.Matchmaking
	return if ticket.kind == "Party" then mm.PartyFillSeconds else mm.PublicWaitSeconds
end

-- Valid, unexpired tickets only (queue data may be stale or malformed).
function CrewPacker.clean(raw: { any }, now: number): { Ticket }
	local out, seen = {}, {}
	for _, t in raw do
		if type(t) ~= "table" or type(t.id) ~= "string" or seen[t.id] then
			continue
		end
		if (t.kind ~= "Public" and t.kind ~= "Party") or type(t.since) ~= "number" then
			continue
		end
		if type(t.members) ~= "table" or type(t.servers) ~= "table" then
			continue
		end
		local n = #t.members
		if n == 0 or n > Config.Lobby.CrewMax or #t.servers ~= n then
			continue
		end
		if now - t.since > Config.Matchmaking.TicketTTLSeconds then
			continue
		end
		seen[t.id] = true
		table.insert(out, t)
	end
	table.sort(out, function(a, b)
		if a.since == b.since then
			return a.id < b.id
		end
		return a.since < b.since
	end)
	return out
end

-- Returns crews that should leave now, and the tickets to put back.
function CrewPacker.pack(tickets: { Ticket }, now: number): ({ Crew }, { Ticket })
	local max = Config.Lobby.CrewMax
	local pool = table.clone(tickets) -- oldest first (see clean)
	local leaving: { Crew } = {}
	local keep: { Ticket } = {}

	while #pool > 0 do
		local first = table.remove(pool, 1)
		local crew = { first }
		local size = #first.members
		local i = 1
		while i <= #pool and size < max do
			local t = pool[i]
			if size + #t.members <= max then
				table.insert(crew, t)
				size += #t.members
				table.remove(pool, i)
			else
				i += 1
			end
		end
		if size >= max or now - first.since >= waitFor(first) then
			local out: Crew = { kind = "Public", members = {}, servers = {}, tickets = crew }
			for _, t in crew do
				if t.kind == "Party" then
					out.kind = "Party"
				end
				for k, userId in t.members do
					table.insert(out.members, userId)
					table.insert(out.servers, t.servers[k])
				end
			end
			table.insert(leaving, out)
		else
			-- Not ready yet: these tickets wait for more riders. Keep packing the
			-- rest, since a newer Party group can be ready sooner (shorter wait).
			for _, t in crew do
				table.insert(keep, t)
			end
		end
	end
	table.sort(keep, function(a, b)
		return a.since < b.since
	end)
	return leaving, keep
end

-- Members of a crew that live on this lobby server, in seat order.
function CrewPacker.localMembers(
	crew: { members: { number }, servers: { string } },
	jobId: string
): { number }
	local out = {}
	for i, userId in crew.members do
		if crew.servers[i] == jobId then
			table.insert(out, userId)
		end
	end
	return out
end

return CrewPacker
