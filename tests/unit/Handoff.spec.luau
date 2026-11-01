local Config = load("ReplicatedStorage.Shared.Config")
local Handoff = load("ReplicatedStorage.Shared.Handoff")

local function crew()
	return Handoff.make("crew-1", "Party", { 101, 202 })
end

test("data made by the lobby reads back unchanged", function()
	local data = Handoff.read(crew())
	expect(data.crewId).toBe("crew-1")
	expect(data.kind).toBe("Party")
	expect(#data.members).toBe(2)
	expect(data.members[2]).toBe(202)
end)

test("bad or missing data is rejected", function()
	expect(Handoff.read(nil)).toBe(nil)
	expect(Handoff.read("crew-1")).toBe(nil)
	local wrongVersion = crew()
	wrongVersion.v = 99
	expect(Handoff.read(wrongVersion)).toBe(nil)
	expect(Handoff.read(Handoff.make("crew-1", "Secret", { 1 }))).toBe(nil)
	expect(Handoff.read(Handoff.make("", "Public", { 1 }))).toBe(nil)
	expect(Handoff.read(Handoff.make("crew-1", "Public", {}))).toBe(nil)
	expect(Handoff.read(Handoff.make("crew-1", "Public", { 1.5 }))).toBe(nil)
	local tooMany = {}
	for i = 1, Config.Lobby.CrewMax + 1 do
		tooMany[i] = i
	end
	expect(Handoff.read(Handoff.make("crew-1", "Public", tooMany))).toBe(nil)
end)

test("only members of this server's crew are admitted", function()
	local c = crew()
	expect(Handoff.admits(c, crew(), 101)).toBeTruthy()
	expect(Handoff.admits(c, crew(), 999)).toBeFalsy()
	expect(Handoff.admits(c, Handoff.make("crew-2", "Party", { 101 }), 101)).toBeFalsy()
	expect(Handoff.admits(c, nil, 101)).toBeFalsy()
end)

test("a first run leaves when the whole crew is in, or at the timeout", function()
	expect(Handoff.shouldDepart(0, 2, 100, 0, false)).toBeFalsy()
	expect(Handoff.shouldDepart(1, 2, 0, 15, false)).toBeFalsy()
	expect(Handoff.shouldDepart(2, 2, 0, 15, false)).toBeTruthy()
	expect(Handoff.shouldDepart(1, 2, 15, 15, false)).toBeTruthy()
end)

test("a requeued run always waits for its countdown", function()
	expect(Handoff.shouldDepart(2, 2, 0, 5, true)).toBeFalsy()
	expect(Handoff.shouldDepart(2, 2, 5, 5, true)).toBeTruthy()
end)

test("Studio (place 0) is the lobby unless the RunPlace attribute is set", function()
	expect(Handoff.isRunPlace(0, nil)).toBeFalsy()
	expect(Handoff.isRunPlace(123, true)).toBeTruthy()
end)
