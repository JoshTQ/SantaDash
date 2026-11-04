local Config = load("ReplicatedStorage.Shared.Config")
local CrewPacker = load("ReplicatedStorage.Shared.CrewPacker")

local MM = Config.Matchmaking
local MAX = Config.Lobby.CrewMax

local nextId = 0
local function ticket(kind: string, size: number, since: number, server: string?)
	nextId += 1
	local members, servers = {}, {}
	for i = 1, size do
		members[i] = nextId * 100 + i
		servers[i] = server or "job-A"
	end
	return { id = "t" .. nextId, kind = kind, members = members, servers = servers, since = since }
end

test("a full crew leaves at once", function()
	local now = 1000
	local tickets = {}
	for i = 1, MAX do
		table.insert(
			tickets,
			ticket("Public", 1, now - 1 + i * 0.01, if i % 2 == 0 then "job-B" else "job-A")
		)
	end
	local crews, keep = CrewPacker.pack(CrewPacker.clean(tickets, now), now)
	expect(#crews).toBe(1)
	expect(#crews[1].members).toBe(MAX)
	expect(#keep).toBe(0)
	expect(crews[1].kind).toBe("Public")
end)

test("a part-full crew waits, then leaves after the public wait", function()
	local now = 1000
	local tickets = { ticket("Public", 1, now - 2), ticket("Public", 1, now - 1) }
	local crews, keep = CrewPacker.pack(CrewPacker.clean(tickets, now), now)
	expect(#crews).toBe(0)
	expect(#keep).toBe(2)
	crews, keep =
		CrewPacker.pack(CrewPacker.clean(tickets, now + MM.PublicWaitSeconds), now + MM.PublicWaitSeconds)
	expect(#crews).toBe(1)
	expect(#crews[1].members).toBe(2)
	expect(#keep).toBe(0)
end)

test("party groups are never split and fill with randoms", function()
	local now = 1000
	local party = ticket("Party", 4, now - MM.PartyFillSeconds)
	local tickets = {
		party,
		ticket("Public", 3, now - 1),
		ticket("Public", 1, now - 0.5),
		ticket("Public", 1, now - 0.4),
	}
	local crews, keep = CrewPacker.pack(CrewPacker.clean(tickets, now), now)
	expect(#crews).toBe(1)
	expect(crews[1].kind).toBe("Party")
	expect(#crews[1].members).toBe(MAX) -- 4 + 1 + 1; the group of 3 didn't fit
	expect(crews[1].members[1]).toBe(party.members[1])
	expect(#keep).toBe(1)
	expect(#keep[1].members).toBe(3)
end)

test("a newer party can leave while an older public rider still waits", function()
	local now = 1000
	local tickets = { ticket("Public", 3, now - 5), ticket("Party", 4, now - MM.PartyFillSeconds) }
	local crews, keep = CrewPacker.pack(CrewPacker.clean(tickets, now), now)
	expect(#crews).toBe(1)
	expect(crews[1].kind).toBe("Party")
	expect(#keep).toBe(1)
end)

test("stale, duplicate and malformed tickets are dropped", function()
	local now = 1000
	local ok = ticket("Public", 1, now)
	local stale = ticket("Public", 1, now - MM.TicketTTLSeconds - 1)
	local bad = ticket("Public", 1, now)
	bad.servers = {}
	local tooBig = ticket("Party", MAX + 1, now)
	local cleaned = CrewPacker.clean({ ok, ok, stale, bad, tooBig, "junk", { id = 5 } }, now)
	expect(#cleaned).toBe(1)
	expect(cleaned[1].id).toBe(ok.id)
end)

test("a rider who hopped off never holds a seat", function()
	local now = 1000
	local solo = ticket("Public", 1, now)
	local party = ticket("Party", 3, now)
	local cancelled = { [solo.members[1]] = solo.id, [party.members[2]] = party.id }
	local cleaned = CrewPacker.clean({ solo, party }, now, cancelled)
	expect(#cleaned).toBe(1)
	expect(cleaned[1].id).toBe(party.id)
	expect(#cleaned[1].members).toBe(2)
	expect(#cleaned[1].servers).toBe(2)
	expect(cleaned[1].members[2]).toBe(party.members[3])
	expect(#party.members).toBe(3) -- the queued ticket itself is not changed
end)

test("an old cancellation does not touch the rider's new ticket", function()
	local now = 1000
	local again = ticket("Public", 1, now)
	local cleaned = CrewPacker.clean({ again }, now, { [again.members[1]] = "an-older-ticket" })
	expect(#cleaned).toBe(1)
end)

test("local fallback keeps groups together", function()
	local crews =
		CrewPacker.fit({ { "a" }, { "p1", "p2", "p3", "p4" }, { "b" }, { "q1", "q2", "q3" }, { "c" } }, MAX)
	expect(#crews).toBe(2)
	expect(#crews[1]).toBe(6) -- a + party of 4 + b
	expect(crews[2][1]).toBe("q1") -- the party of 3 is not split
	expect(#crews[2]).toBe(4)
end)
