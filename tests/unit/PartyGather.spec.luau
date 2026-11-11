local Config = load("ReplicatedStorage.Shared.Config")
local PartyGather = load("ReplicatedStorage.Shared.PartyGather")

-- Friendships as pairs of names.
local function friends(pairs: { { string } })
	local set = {}
	for _, pair in pairs do
		set[pair[1] .. "|" .. pair[2]] = true
		set[pair[2] .. "|" .. pair[1]] = true
	end
	return function(a, b)
		return set[a .. "|" .. b] == true
	end
end

local NOBODY = friends({})
local GATHER = Config.Lobby.GatherSeconds

describe("PartyGather.ready", function()
	it("never sends an empty sleigh", function()
		expect(PartyGather.ready({}, 0, 1000, {}, NOBODY)).toBeNil()
	end)

	it("holds a lone rider for GatherSeconds, then sends them", function()
		expect(PartyGather.ready({ "Ann" }, 0, GATHER - 0.1, {}, NOBODY)).toBeNil()
		expect(PartyGather.ready({ "Ann" }, 0, GATHER, {}, NOBODY)).toBe("Quiet")
	end)

	it("every new rider restarts the wait", function()
		-- Ann sat at 0, Bo at 4: not quiet until 4 + GatherSeconds.
		expect(PartyGather.ready({ "Ann", "Bo" }, 4, GATHER + 1, {}, NOBODY)).toBeNil()
		expect(PartyGather.ready({ "Ann", "Bo" }, 4, GATHER + 4, {}, NOBODY)).toBe("Quiet")
	end)

	it("sends a full sleigh at once", function()
		local riders = {}
		for i = 1, Config.Lobby.CrewMax do
			riders[i] = "P" .. i
		end
		expect(PartyGather.ready(riders, 0, 0, { "Outside" }, NOBODY)).toBe("Full")
	end)

	it("sends friends at once when every friend in the lobby is aboard", function()
		local areFriends = friends({ { "Ann", "Amy" } })
		expect(PartyGather.ready({ "Ann", "Amy" }, 0, 0.5, { "Stranger" }, areFriends)).toBe("Friends")
	end)

	it("waits while a rider's friend is still in the lobby", function()
		local areFriends = friends({ { "Ann", "Amy" }, { "Amy", "Bo" } })
		expect(PartyGather.ready({ "Ann", "Amy" }, 0, 0.5, { "Bo" }, areFriends)).toBeNil()
		expect(PartyGather.ready({ "Ann", "Amy", "Bo" }, 1, 1.5, {}, areFriends)).toBe("Friends")
	end)

	it("waits if any rider has no friend aboard (they may be waiting for a non-friend)", function()
		local areFriends = friends({ { "Ann", "Amy" } })
		expect(PartyGather.ready({ "Ann", "Amy", "Sam" }, 0, 0.5, {}, areFriends)).toBeNil()
		expect(PartyGather.ready({ "Ann", "Amy", "Sam" }, 0, GATHER, {}, areFriends)).toBe("Quiet")
	end)

	it("a lone rider with no friends around still waits (friends of friends may come)", function()
		expect(PartyGather.ready({ "Ann" }, 0, 0.5, {}, NOBODY)).toBeNil()
	end)

	it("a friend still in the lobby can't hold the sleigh past GatherSeconds", function()
		local areFriends = friends({ { "Ann", "Amy" }, { "Ann", "Bo" } })
		expect(PartyGather.ready({ "Ann", "Amy" }, 0, GATHER, { "Bo" }, areFriends)).toBe("Quiet")
	end)
end)
