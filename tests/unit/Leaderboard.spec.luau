-- Weekly leaderboard rules (shared/Leaderboard) and the server module that
-- saves runs and draws the boards (server/Leaderboards), on a fake DataStore.
local Config = load("ReplicatedStorage.Shared.Config")
local Leaderboard = load("ReplicatedStorage.Shared.Leaderboard")
local Leaderboards = load("ServerScriptService.Server.Leaderboards")
local LobbyMap = load("ServerScriptService.Server.LobbyMap")

-- Thursday 12 Nov 2026 13:00 UTC
local NOW = 1794488400

-- An in-memory DataStoreService: ordered stores only, with switchable faults.
local function fakeService()
	local svc = { stores = {}, failNext = 0, down = false, calls = 0 }
	local function maybeFail()
		svc.calls += 1
		if svc.down then
			error("DataStore is down")
		end
		if svc.failNext > 0 then
			svc.failNext -= 1
			error("hiccup")
		end
	end
	function svc.GetOrderedDataStore(_, name)
		svc.stores[name] = svc.stores[name] or {}
		local data = svc.stores[name]
		return {
			UpdateAsync = function(_, key, fn)
				maybeFail()
				local v = fn(data[key])
				if v ~= nil then
					data[key] = v
				end
			end,
			IncrementAsync = function(_, key, delta)
				maybeFail()
				data[key] = (data[key] or 0) + delta
			end,
			GetSortedAsync = function(_, ascending, n)
				maybeFail()
				local rows = {}
				for k, v in data do
					table.insert(rows, { key = k, value = v })
				end
				table.sort(rows, function(a, b)
					return if ascending then a.value < b.value else a.value > b.value
				end)
				return {
					GetCurrentPage = function()
						return table.move(rows, 1, math.min(n, #rows), 1, {})
					end,
				}
			end,
		}
	end
	return svc
end

local function setup()
	local svc = fakeService()
	Config.Leaderboards.RetrySeconds = 0
	Leaderboards.useService(svc)
	Leaderboards.useClock(function()
		return NOW
	end)
	local looked = {}
	Leaderboards.useNames(function(ids)
		local out = {}
		for _, id in ids do
			table.insert(looked, id)
			out[id] = "Santa" .. id
		end
		return out
	end)
	return svc, looked
end

local function week(base)
	return base .. "/" .. Leaderboard.weekKey(NOW)
end

describe("Leaderboard weeks", function()
	it("starts each week on Monday 00:00 UTC", function()
		expect(Leaderboard.weekKey(NOW)).toBe("2026-11-09")
		-- Sunday 15 Nov 23:59:59 is still the same week; a second later is the next
		local mondayNext = 1794787200 -- Mon 16 Nov 00:00 UTC
		expect(Leaderboard.weekKey(mondayNext - 1)).toBe("2026-11-09")
		expect(Leaderboard.weekKey(mondayNext)).toBe("2026-11-16")
		expect(Leaderboard.secondsLeft(mondayNext - 1)).toBe(1)
		expect(Leaderboard.secondsLeft(mondayNext)).toBe(7 * 86400)
	end)

	it("says when the boards reset", function()
		expect(Leaderboard.resetText(3 * 86400 + 4 * 3600 + 5)).toBe("Resets in 3d 4h")
		expect(Leaderboard.resetText(5 * 3600 + 59)).toBe("Resets in 5h")
		expect(Leaderboard.resetText(11 * 60 + 1)).toBe("Resets in 12m")
		expect(Leaderboard.resetText(1)).toBe("Resets in 1m")
	end)
end)

describe("Leaderboard crew keys", function()
	it("is the same crew in any order, and decodes back to the UserIds", function()
		local a = Leaderboard.crewKey({ 9000000001, 42, 1234567 })
		expect(a).toBe(Leaderboard.crewKey({ 42, 1234567, 9000000001 }))
		expect(Leaderboard.crewIds(a :: string)).toEqual({ 42, 1234567, 9000000001 })
	end)

	it("fits a full crew of big UserIds in a 50-character DataStore key", function()
		local ids = {}
		for i = 1, Config.Lobby.CrewMax do
			table.insert(ids, 99999999999 - i)
		end
		local key = Leaderboard.crewKey(ids) :: string
		expect(#key <= 50).toBeTruthy()
		expect(string.find(key, "^[%w]+$") ~= nil).toBeTruthy()
		table.sort(ids)
		expect(Leaderboard.crewIds(key)).toEqual(ids)
	end)

	it("drops bots, duplicates and empty crews", function()
		expect(Leaderboard.crewKey({})).toBe(nil)
		expect(Leaderboard.crewKey({ -1, 0 })).toBe(nil) -- Studio test players
		expect(Leaderboard.crewKey({ 7, 7 })).toBe(Leaderboard.crewKey({ 7 }))
		expect(Leaderboard.crewIds("bad")).toEqual({})
		expect(Leaderboard.crewIds("!!!!!!!")).toEqual({})
	end)
end)

describe("Leaderboard text", function()
	it("shortens big hauls", function()
		expect(Leaderboard.short(950)).toBe("950")
		expect(Leaderboard.short(1000)).toBe("1K")
		expect(Leaderboard.short(12345)).toBe("12.3K")
		expect(Leaderboard.short(250000)).toBe("250K")
		expect(Leaderboard.short(2500000)).toBe("2.5M")
	end)

	it("lists crew names and cuts long crews", function()
		expect(Leaderboard.crewNames({})).toBe("?")
		expect(Leaderboard.crewNames({ "Bob" })).toBe("Bob")
		expect(Leaderboard.crewNames({ "Bob", "Ann" })).toBe("Bob & Ann")
		expect(Leaderboard.crewNames({ "Bob", "Ann", "Cy" })).toBe("Bob, Ann & Cy")
		expect(Leaderboard.crewNames({ "A", "B", "C", "D", "E", "F" })).toBe("A, B +4")
	end)

	it("keeps a crew's best run, not its last", function()
		expect(Leaderboard.bestHaul(nil, 120.7)).toBe(120)
		expect(Leaderboard.bestHaul(500, 120)).toBe(500)
		expect(Leaderboard.bestHaul(500, 900)).toBe(900)
	end)
end)

describe("Leaderboards.record", function()
	it("saves the crew's haul and each Santa's loot in this week's stores", function()
		local svc = setup()
		expect(Leaderboards.record({ { 11, 300 }, { 22, 200 } })).toBe(true)
		local key = Leaderboard.crewKey({ 11, 22 }) :: string
		expect(svc.stores[week("TopCrews_v1")][key]).toBe(500)
		expect(svc.stores[week("MostWanted_v1")]["11"]).toBe(300)
		expect(svc.stores[week("MostWanted_v1")]["22"]).toBe(200)
	end)

	it("keeps the best crew run but adds up every Santa's loot", function()
		local svc = setup()
		Leaderboards.record({ { 11, 300 }, { 22, 200 } })
		Leaderboards.record({ { 22, 50 }, { 11, 50 } }) -- same crew, worse run
		local key = Leaderboard.crewKey({ 11, 22 }) :: string
		expect(svc.stores[week("TopCrews_v1")][key]).toBe(500)
		expect(svc.stores[week("MostWanted_v1")]["11"]).toBe(350)
	end)

	it("skips runs where nobody got away with anything", function()
		local svc = setup()
		expect(Leaderboards.record({ { 11, 0 }, { 22, 0 } })).toBe(false)
		expect(Leaderboards.record({})).toBe(false)
		expect(svc.calls).toBe(0)
	end)

	it("doesn't put a Santa with no loot on the wall, but keeps them in the crew", function()
		local svc = setup()
		Leaderboards.record({ { 11, 300 }, { 22, 0 } })
		expect(svc.stores[week("MostWanted_v1")]["22"]).toBe(nil)
		expect(svc.stores[week("TopCrews_v1")][Leaderboard.crewKey({ 11, 22 }) :: string]).toBe(300)
	end)

	it("retries a DataStore hiccup", function()
		local svc = setup()
		svc.failNext = 1
		expect(Leaderboards.record({ { 11, 300 } })).toBe(true)
		expect(svc.stores[week("MostWanted_v1")]["11"]).toBe(300)
	end)

	it("gives up after WriteAttempts when the DataStore is down", function()
		local svc = setup()
		svc.down = true
		expect(Leaderboards.record({ { 11, 300 } })).toBe(false)
		expect(svc.calls).toBe(Config.Leaderboards.WriteAttempts * 2)
	end)
end)

describe("Leaderboards.fetch and render", function()
	it("reads the top crews and Santas, best first", function()
		setup()
		Leaderboards.record({ { 1, 100 } })
		Leaderboards.record({ { 2, 400 }, { 3, 100 } })
		Leaderboards.record({ { 4, 900 } })
		Leaderboards.record({ { 5, 10 } })
		local board = Leaderboards.fetch() :: any
		expect(#board.crews).toBe(Config.Leaderboards.TopCrews)
		expect(board.crews[1]).toEqual({ ids = { 4 }, haul = 900 })
		expect(board.crews[2]).toEqual({ ids = { 2, 3 }, haul = 500 })
		expect(board.wanted[1]).toEqual({ userId = 4, haul = 900 })
		expect(board.wanted[2]).toEqual({ userId = 2, haul = 400 })
		expect(#board.wanted).toBe(5)
	end)

	it("returns nil when the DataStore can't be read", function()
		local svc = setup()
		svc.down = true
		expect(Leaderboards.fetch()).toBe(nil)
	end)

	it("draws crews, posters and the biggest haul on the lobby", function()
		setup()
		Leaderboards.record({ { 2, 9000 }, { 3, 3500 } })
		Leaderboards.record({ { 4, 900 } })
		local hub = LobbyMap.build(newFolder())
		local s = hub.showOff
		local board = Leaderboards.refresh(s)
		expect(board ~= nil).toBeTruthy()
		expect(s.crewRows[1].Visible).toBe(true)
		expect(s.crewRows[1].Text).toBe("1.  Santa2 & Santa3  ·  12.5K")
		expect(s.crewRows[2].Text).toBe("2.  Santa4  ·  900")
		expect(s.crewRows[3].Visible).toBe(false)
		expect(s.crewEmpty.Visible).toBe(false)
		expect(s.crewReset.Text).toBe("Resets in 3d 11h")
		expect(s.biggestHaul[1].Text).toBe("THIS WEEK'S BIGGEST HAUL: 12.5K")
		expect(#s.biggestHaul).toBe(2)
		expect(#s.wanted).toBe(Config.Leaderboards.MostWanted)
		expect(s.wanted[1].title.Text).toBe("WANTED #1")
		expect(s.wanted[1].name.Text).toBe("Santa2")
		expect(s.wanted[1].haul.Text).toBe("9K loot")
		expect(s.wanted[1].photo.Image).toBe(Leaderboard.headshot(2))
		expect(s.wanted[1].photo.Visible).toBe(true)
		expect(s.wanted[3].name.Text).toBe("Santa4")
		expect(s.wanted[4].name.Text).toBe("???")
		expect(s.wanted[4].haul.Text).toBe("Could be you!")
		expect(s.wanted[4].photo.Visible).toBe(false)
	end)

	it("looks each name up once, then uses the cache", function()
		local _, looked = setup()
		Leaderboards.record({ { 2, 100 }, { 3, 50 } })
		local hub = LobbyMap.build(newFolder())
		Leaderboards.refresh(hub.showOff)
		Leaderboards.refresh(hub.showOff)
		table.sort(looked)
		expect(looked).toEqual({ 2, 3 })
	end)

	it("shows an empty board as an invitation, and an outage as a snow day", function()
		local svc = setup()
		local hub = LobbyMap.build(newFolder())
		Leaderboards.refresh(hub.showOff)
		expect(hub.showOff.crewEmpty.Visible).toBe(true)
		expect(hub.showOff.crewEmpty.Text).toBe("Rob the most presents to stand up here!")
		expect(hub.showOff.biggestHaul[1].Text).toBe("THIS WEEK'S BIGGEST HAUL")
		svc.down = true
		Leaderboards.refresh(hub.showOff)
		expect(hub.showOff.crewEmpty.Text).toBe("Leaderboard is having a snow day. Back soon!")
		expect(hub.showOff.wanted[1].name.Text).toBe("???")
	end)

	it("a new week starts with empty boards", function()
		setup()
		Leaderboards.record({ { 2, 100 } })
		Leaderboards.useClock(function()
			return NOW + 7 * 86400
		end)
		local board = Leaderboards.fetch() :: any
		expect(#board.crews).toBe(0)
		expect(#board.wanted).toBe(0)
	end)
end)
