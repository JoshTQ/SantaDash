--[[
	Regression tests for decisions Josh has signed off. Each one checks the
	behaviour, not only the number, so a tuning or refactor change that
	silently undoes one of his calls fails here. To change one on purpose,
	update this file in the same PR and say so in the PR description.

	Add a test here whenever Josh makes a call, and whenever a bug is fixed
	(name the bug in the test so it can't come back unnoticed).
]]

local Config = load("ReplicatedStorage.Shared.Config")
local Loot = load("ServerScriptService.Server.Loot")
local KrampusBrain = load("ServerScriptService.Server.KrampusBrain")
local ElfBrain = load("ServerScriptService.Server.ElfBrain")
local MapBuilder = load("ServerScriptService.Server.MapBuilder")
local Handoff = load("ReplicatedStorage.Shared.Handoff")

describe("15 Nov launch slice", function()
	it("is two house stops then Krampus's Lair, 2:00 each", function()
		expect(Config.Run.StopKinds).toEqual({ "Street", "Street", "Finale" })
		expect(Config.Run.StopSeconds).toBe(120)
		expect(Config.StopKinds.Finale.EndHouse).toBe("Lair")
	end)

	it("keeps a short run: about 6 minutes of stops", function()
		local total = #Config.Run.StopKinds * Config.Run.StopSeconds
		expect(total).toBeLessThanOrEqual(6 * 60)
	end)
end)

describe("Krampus first appears at Stop 3 (Josh, 1 Nov)", function()
	it("never arrives at Stops 1 or 2, however late or noisy", function()
		for stop = 1, 2 do
			expect(KrampusBrain.shouldArrive(stop, "Street", 9999, true)).toBeFalsy()
		end
	end)

	it("is always home in the Lair at Stop 3", function()
		expect(KrampusBrain.shouldArrive(3, "Finale", 0, false)).toBeTruthy()
	end)

	it("keeps the Stop 1 tease off until Josh approves it", function()
		expect(Config.Krampus.TeaseEnabled).toBe(false)
		expect(KrampusBrain.shouldTease(1, 9999)).toBeFalsy()
	end)
end)

describe("wiggling free takes 15 taps, solo or in a crew (Josh, 1 Nov)", function()
	it("needs 15 taps", function()
		expect(KrampusBrain.wiggleNeeded()).toBe(15)
	end)
end)

describe("the Sleigh Stop (Josh, 1 Nov)", function()
	local deck = CFrame.new(100, 0, 50)

	it("counts anyone inside the 17-stud clearing as aboard", function()
		expect(Config.Map.SleighStopRadius).toBe(17)
		expect(MapBuilder.isAboard(deck, deck.Position + Vector3.new(16, 0, 0))).toBeTruthy()
		expect(MapBuilder.isAboard(deck, deck.Position + Vector3.new(18, 0, 0))).toBeFalsy()
	end)

	it("is a Krampus safe zone: he never targets a Santa standing in it", function()
		local inside = deck.Position + Vector3.new(5, 0, 5)
		local candidate = {
			player = "santa",
			position = inside,
			hidden = false,
			captive = false,
			aboard = MapBuilder.isAboard(deck, inside),
		}
		expect(KrampusBrain.pickTarget(inside + Vector3.new(2, 0, 0), { candidate }, 0)).toBeNil()
	end)
end)

describe("banking and the final sleigh (Josh, 1 Nov)", function()
	local function stateWith(sackValue: number, banked: number)
		local st = Loot.newPlayerState()
		st.banked = banked
		st.sackValue = sackValue
		st.sackCount = 1
		return st
	end

	it("banks the sack whenever you leave a stop on board", function()
		local st = stateWith(100, 0)
		Loot.bank(st)
		expect(st.banked).toBe(100)
		expect(st.sackValue).toBe(0)
	end)

	it("missing the final sleigh keeps banked loot plus half the unbanked sack", function()
		local st = stateWith(100, 300)
		Loot.bankMissed(st)
		expect(Loot.finalLoot(st)).toBe(350)
	end)

	it("escaping the Lair doubles your loot", function()
		local st = stateWith(100, 300)
		Loot.bank(st, Config.StopKinds.Finale.EscapeMultiplier)
		expect(Loot.finalLoot(st)).toBe(800)
	end)
end)

describe("solo elf bots (Josh, 1 Nov)", function()
	it("join only solo runs", function()
		expect(ElfBrain.wantsBots(1)).toBeTruthy()
		expect(ElfBrain.wantsBots(2)).toBeFalsy()
	end)

	it("are always one Tin Elf (A) and one Gingerbread Helper (D)", function()
		local rng = Random.new(7)
		for _ = 1, 50 do
			local picks = ElfBrain.pickVariants(rng, 2)
			table.sort(picks)
			expect(picks).toEqual({ "ElfA", "ElfD" })
		end
	end)

	it("pay 80% loot so playing with friends is better", function()
		expect(Config.ElfBots.SoloLootMultiplier).toBe(0.8)
	end)
end)

describe("cross-server matchmaking (Josh, 1 Nov)", function()
	it("runs in one server while the run place isn't published (ID 0)", function()
		local saved = Config.Places.Run
		Config.Places.Run = 0
		expect(Handoff.isRunPlace(0, nil)).toBeFalsy()
		expect(Handoff.isRunPlace(123, nil)).toBeFalsy()
		Config.Places.Run = saved
	end)

	it("lets Studio test the run place with Workspace.RunPlace = true", function()
		expect(Handoff.isRunPlace(0, true)).toBeTruthy()
	end)
end)

describe("crews", function()
	it("hold up to 6 Santas, which is also the sleigh's seat count", function()
		expect(Config.Lobby.CrewMax).toBe(6)
		expect(#MapBuilder.SeatOffsets).toBeGreaterThanOrEqual(Config.Lobby.CrewMax)
	end)
end)

-- The same calls, checked in whole runs (headless world).
describe("in a real run", function()
	local function runWith(names)
		local world = headless()
		local engine = world.engine
		world.load("ReplicatedStorage.Shared.Remotes").init()
		local Run = world.load("ServerScriptService.Server.Run")
		local players = {}
		for i, name in names do
			players[i] = engine:addPlayer(name)
		end
		return world, engine, Run, players
	end

	it("Krampus never shows up at Stops 1-2, even with the noise meter full", function()
		local world, _, Run, players = runWith({ "Loud" })
		world.run(function()
			local run = Run.new(1, players, function() end)
			run:start()
			while run.stopIndex < 3 do
				if run.stopIndex >= 1 and run.phase ~= "Flight" then
					run:_addNoise(1000)
				end
				expect(run.krampus).toBeNil()
				world.wait(1)
			end
			run.ended = true
		end)
	end)

	it("Krampus never snatches a Santa standing in the Sleigh Stop clearing", function()
		local world, engine, Run, players = runWith({ "Safe" })
		local santa = players[1]
		world.run(function()
			local run = Run.new(1, players, function() end)
			run:start()
			while not run.krampus do
				world.wait(0.5)
			end
			local deck = run.route.stops[3].deckCFrame
			-- Standing on the ground inside the clearing, not on the sleigh.
			engine:teleport(santa, (deck * CFrame.new(12, 0, 0)).Position)
			local krampus = run.krampus
			krampus.body.model:PivotTo(deck * CFrame.new(0, 0, 25))
			for _ = 1, 60 do
				world.wait(0.5)
				expect(run.players[santa].captive).toBe(false)
			end
			run.ended = true
		end)
	end)

	-- Josh, 11 Nov 2026: escaping doubles only with the Naughty List aboard.
	it(
		"missing the final sleigh keeps half the sack, escaping with the List doubles, in the results",
		function()
			local world, engine, Run, players = runWith({ "Escapes", "Misses" })
			local escapes, misses = players[1], players[2]
			local done = false
			world.run(function()
				local run = Run.new(1, players, function()
					done = true
				end)
				run:start()
				while not run.krampus do
					world.wait(0.5)
				end
				run.krampus.stunnedUntil = math.huge
				run.cuckoo = nil
				for _, p in players do
					local st = run.players[p]
					st.banked = 300
					st.sackValue = 100
					st.sackCount = 1
				end
				run.list:take(escapes)
				engine:teleport(escapes, run.route.stops[3].deckCFrame.Position + Vector3.new(0, 3, 0))
				engine:teleport(misses, run.route.stops[3].deckCFrame.Position + Vector3.new(0, 0, 200))
				while not done do
					world.wait(1)
				end
			end)
			local results = engine:hudMessages(escapes, "Results")
			local rows = results[#results].data.rows
			local loot = {}
			for _, row in rows do
				loot[row.name] = row.loot
			end
			expect(loot.Escapes).toBe((300 + 100 + 250) * 2) -- the List itself is worth 250
			expect(loot.Misses).toBe(300 + 50)
		end
	)
end)

describe("lights on has a consequence (Josh, 6 Nov 2026)", function()
	it(
		"lit houses check for Santas on street stops, never in Krampus's Lair, and spotting costs a present",
		function()
			local world = headless()
			local Config = world.load("ReplicatedStorage.Shared.Config")
			local LightsCheck = world.load("ServerScriptService.Server.LightsCheck")
			expect(Config.LightsCheck.Enabled).toBe(true)
			expect(LightsCheck.applies("Street")).toBe(true)
			expect(LightsCheck.applies("Finale")).toBe(false)
			expect(Config.LightsCheck.Noise > 0).toBeTruthy()
			expect(Config.LightsCheck.WarnSeconds >= 2).toBeTruthy() -- always time to hide or get out
		end
	)
end)

describe("Krampus's magic tricks (Josh, 6 Nov: Top 3 + Grumpy Meter)", function()
	local M = Config.Krampus.Magic
	it("is on, with Frost Zap, Frost Stomp and Bell Blink unlocking over the Lair", function()
		expect(M.Enabled).toBe(true)
		expect(M.Grumpy.Tricks[1]).toEqual({ "FrostZap" })
		expect(table.find(M.Grumpy.Tricks[2], "FrostStomp")).never.toBeNil()
		expect(table.find(M.Grumpy.Tricks[3], "BellBlink")).never.toBeNil()
	end)
	it("never zaps point blank, so a teammate always has time to smash the ice", function()
		local secondsToReach = (M.FrostZap.MinRange - Config.Krampus.CatchRange) / M.Grumpy.Speed[3]
		expect(secondsToReach > 1).toBe(true)
	end)
	it("is slower than a Santa until Furious, and Peppermint Rush always outruns him", function()
		expect(M.Grumpy.Speed[1] < Config.Player.WalkSpeed).toBe(true)
		expect(M.Grumpy.Speed[3] < Config.Buys.PeppermintRush.WalkSpeed).toBe(true)
	end)
end)
