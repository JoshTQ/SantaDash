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

test("each lobby server teleports only its own members", function()
	local crew = { members = { 1, 2, 3 }, servers = { "A", "B", "A" } }
	local mine = CrewPacker.localMembers(crew, "A")
	expect(#mine).toBe(2)
	expect(mine[2]).toBe(3)
	expect(#CrewPacker.localMembers(crew, "C")).toBe(0)
end)
