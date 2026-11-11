--[[
	Smoke tests: whole runs in a headless world (tests/headless/Engine.luau),
	driven like real players would: stay on the sleigh, wander off, grab
	presents, buy things, hide, get snatched by Krampus and escape.
]]

local function setup(names: { string })
	local world = headless()
	local engine = world.engine
	world.load("ReplicatedStorage.Shared.Remotes").init()
	local players = {}
	for i, name in names do
		players[i] = engine:addPlayer(name)
	end
	return world, engine, world.load("ServerScriptService.Server.Run"), players
end

-- Waits (virtual time) until check() is true.
local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 300)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function startRun(world, Run, crew)
	local result = { finished = false }
	local run = Run.new(1, crew, function(_, survivors)
		result.finished = true
		result.survivors = survivors
	end)
	run:start()
	return run, result
end

local function atStop(world, run, index: number)
	waitUntil(world, function()
		return run.stopIndex == index and run.phase == "Sneak"
	end, 500, "stop " .. index)
end

-- Stop 3 is Krampus's Lair: he is there from its first tick.
local function atLair(world, run)
	atStop(world, run, 3)
	waitUntil(world, function()
		return run.krampus ~= nil
	end, 5, "Krampus")
	return run.krampus
end

local function sawBanner(engine, player, text: string): boolean
	for _, m in engine:hudMessages(player, "Banner") do
		if string.find(m.data.text, text, 1, true) then
			return true
		end
	end
	return false
end

local function lastResults(engine, player)
	local results = engine:hudMessages(player, "Results")
	return results[#results] and results[#results].data
end

local function rowFor(rows, name)
	for _, row in rows do
		if row.name == name then
			return row
		end
	end
	return nil
end

describe("a solo run", function()
	it("plays all three stops, banks the loot and escapes the Lair", function()
		local world, engine, Run, players = setup({ "Solo" })
		local santa = players[1]
		world.run(function()
			local run, result = startRun(world, Run, { santa })
			atStop(world, run, 1)
			local grabs = 0
			for _, present in run.route.stops[1].presents do
				if not present.taken and not present.inVault and grabs < 3 then
					engine.trigger(present.prompt, santa)
					grabs += 1
				end
			end
			expect(run.players[santa].sackCount).toBeGreaterThanOrEqual(3)
			waitUntil(world, function()
				return result.finished
			end, 600, "the run to finish")
			expect(result.survivors).toEqual({ santa })
		end)

		local results = lastResults(engine, santa)
		expect(results).never.toBeNil()
		local row = results.rows[1]
		expect(row.escaped).toBe(true)
		expect(row.grabs).toBeGreaterThanOrEqual(3)
		expect(row.loot).toBeGreaterThan(0)
		expect(#engine:hudMessages(santa, "RunEnd")).toBe(1)
		for _, w in engine.warnings do
			expect(w).never.toContain("crashed")
		end
	end)

	it("brings one Tin Elf and one Gingerbread Helper that follow and fetch presents", function()
		local world, engine, Run, players = setup({ "Solo" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, { santa })
			atStop(world, run, 1)
			expect(#run.elves).toBe(2)
			local variants = { run.elves[1].variant, run.elves[2].variant }
			table.sort(variants)
			expect(variants).toEqual({ "ElfA", "ElfD" })
			-- Walk into the street, next to some presents, and let the elves work.
			local stop = run.route.stops[1]
			local target
			for _, present in stop.presents do
				if not present.inVault then
					target = present.model:GetPivot().Position
					break
				end
			end
			engine:teleport(santa, target + Vector3.new(0, 3, 0))
			world.wait(60) -- into the lights-on phase, when elves fetch
			expect(run.players[santa].sackCount).toBeGreaterThan(0)
			for _, elf in run.elves do
				local elfAt = elf.body.root.Position
				expect((elfAt - engine.rootOf(santa).Position).Magnitude).toBeLessThan(40)
			end
		end)
	end)
end)

describe("a crew run", function()
	it("leaves a Santa behind who misses the sleigh, and halves their sack in the finale", function()
		local world, engine, Run, players = setup({ "Stays", "Wanders" })
		local stays, wanders = players[1], players[2]
		world.run(function()
			local run, result = startRun(world, Run, { stays, wanders })
			atStop(world, run, 1)
			expect(#run.elves).toBe(0) -- bots are for solo runs
			engine:teleport(wanders, run.route.stops[1].deckCFrame.Position + Vector3.new(0, 0, 150))
			atStop(world, run, 2)
			expect(sawBanner(engine, wanders, "You missed the sleigh!")).toBe(true)
			expect(sawBanner(engine, stays, "You missed the sleigh!")).toBe(false)
			-- The sleigh flew without them: they are nowhere near the Stop 2 sleigh.
			local deck2 = run.route.stops[2].deckCFrame
			expect((engine.rootOf(wanders).Position - deck2.Position).Magnitude).toBeGreaterThan(50)
			-- They catch up on foot, grab a present at the finale, and miss the last sleigh.
			engine:teleport(wanders, deck2.Position + Vector3.new(0, 3, 0))
			atLair(world, run)
			local st = run.players[wanders]
			st.sackValue = 100
			st.sackCount = 1
			engine:teleport(wanders, run.route.stops[3].deckCFrame.Position + Vector3.new(0, 0, 200))
			run.krampus.stunnedUntil = math.huge -- keep him home for this test
			waitUntil(world, function()
				return result.finished
			end, 600, "the run to finish")
		end)
		local rows = lastResults(engine, stays).rows
		expect(rowFor(rows, "Stays").escaped).toBe(true)
		expect(rowFor(rows, "Wanders").escaped).toBe(false)
		expect(sawBanner(engine, wanders, "You missed the last sleigh! Half your sack fell out.")).toBe(true)
	end)

	it("ends early when everyone leaves", function()
		local world, engine, Run, players = setup({ "A", "B" })
		world.run(function()
			local run, result = startRun(world, Run, players)
			atStop(world, run, 1)
			run:removePlayer(players[1])
			engine:removePlayer(players[2])
			run:removePlayer(players[2])
			waitUntil(world, function()
				return result.finished
			end, 30, "the run to end")
			expect(#result.survivors).toBe(0)
			expect(run.route.model.Parent).toBeNil()
		end)
	end)
end)

describe("buying and moving around a stop", function()
	it("opens the vault for the crew and gives Peppermint Rush, once, if you have the Jingle", function()
		local world, engine, Run, players = setup({ "Rich", "Poor" })
		local rich, poor = players[1], players[2]
		world.run(function()
			local run = startRun(world, Run, players)
			atStop(world, run, 1)
			local stop = run.route.stops[1]
			engine.trigger(stop.vaultPrompt, poor) -- 500 Jingle is not enough
			expect(stop.vaultPrompt.Enabled).toBe(true)
			expect(sawBanner(engine, poor, "Need 500 more Jingle")).toBe(true)
			run.players[rich].jingle = 5000
			engine.trigger(stop.vaultPrompt, rich)
			expect(stop.vaultPrompt.Enabled).toBe(false)
			expect(stop.vaultDoor.CanCollide).toBe(false)

			engine.trigger(stop.cocoaPrompt, rich)
			expect(run.players[rich].perks.PeppermintRush).toBe(true)
			local humanoid = rich.Character:FindFirstChildOfClass("Humanoid")
			expect(humanoid.WalkSpeed).toBe(22)
			local jingle = run.players[rich].jingle
			engine.trigger(stop.cocoaPrompt, rich) -- already have it
			expect(run.players[rich].jingle).toBe(jingle)
			expect(run.noise).toBeGreaterThan(0)
		end)
	end)

	it("tells every client where the sleigh is waiting, so the gold guide line can point there", function()
		local world, engine, Run, players = setup({ "Lost" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, players)
			atStop(world, run, 2)
			local stop = run.route.stops[2]
			local found = false
			for _, m in engine:hudMessages(santa, "Stop") do
				if m.data.stop == 2 and m.data.phase ~= "Flight" then
					expect(m.data.sleighAt).toBe(stop.deckCFrame.Position)
					found = true
				elseif m.data.phase == "Flight" then
					expect(m.data.sleighAt).toBeNil()
				end
			end
			expect(found).toBe(true)
		end)
	end)

	it("takes you down a chimney and back up, and swings doors", function()
		local world, engine, Run, players = setup({ "Climber" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, players)
			atStop(world, run, 1)
			local stop = run.route.stops[1]
			local chimney = stop.chimneys[1]
			expect(chimney).never.toBeNil()
			engine.trigger(chimney.down, santa)
			expect((engine.rootOf(santa).Position - chimney.inside.Position).Magnitude).toBeLessThan(0.1)
			engine.trigger(chimney.up, santa)
			expect((engine.rootOf(santa).Position - chimney.roof.Position).Magnitude).toBeLessThan(0.1)
			for _, door in stop.doors do
				expect(door.open).toBe(true) -- doors start open
				engine.trigger(door.prompt, santa)
				expect(door.open).toBe(false)
				engine.trigger(door.prompt, santa)
				expect(door.open).toBe(true)
			end
		end)
	end)
end)

describe("Krampus in his Lair", function()
	local function toLair(world, engine, run, crew)
		atLair(world, run)
		local spawn = run.route.stops[3].krampusSpawn.Position
		for i, player in crew do
			engine:teleport(player, spawn + Vector3.new(i * 2, 0, 12))
		end
	end

	it("snatches a Santa off the sleigh, who wiggles free with 15 taps", function()
		local world, engine, Run, players = setup({ "Snatched", "Friend" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, players)
			toLair(world, engine, run, { santa })
			waitUntil(world, function()
				return run.players[santa].captive
			end, 60, "Krampus to snatch someone")
			expect(#engine:hudMessages(santa, "Captive")).toBeGreaterThan(0)
			for _ = 1, 15 do
				run:onInput(santa, "Tap")
				world.wait(0.25)
			end
			expect(run.players[santa].captive).toBe(false)
			expect(sawBanner(engine, santa, "Snatched wiggled free!")).toBe(true)
		end)
	end)

	it("drops his captive when a friend rings the bells behind him", function()
		local world, engine, Run, players = setup({ "Snatched", "Ringer" })
		local santa, ringer = players[1], players[2]
		world.run(function()
			local run = startRun(world, Run, players)
			toLair(world, engine, run, { santa })
			waitUntil(world, function()
				return run.players[santa].captive
			end, 60, "Krampus to snatch someone")
			local krampus = run.krampus
			krampus.stunnedUntil = math.huge -- hold still so the ringer can line up
			engine:teleport(ringer, (krampus.body.root.CFrame * CFrame.new(0, 0, 4)).Position)
			engine.trigger(krampus.body.bellPrompt, ringer)
			expect(run.players[santa].captive).toBe(false)
			expect(sawBanner(engine, santa, "Ringer rang the bells! Krampus dropped Snatched!")).toBe(true)
		end)
	end)

	it("can't see a Santa hiding in a wardrobe, but they gasp when their breath runs out", function()
		local world, engine, Run, players = setup({ "Hider" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, players)
			atLair(world, run)
			local stop = run.route.stops[3]
			local spot = stop.hideSpots[1]
			expect(spot).never.toBeNil()
			engine.trigger(spot.prompt, santa)
			expect(run.players[santa].hidden).toBe(spot)
			run:onInput(santa, "Tap")
			-- Let his KrampusArrives intro finish first: it drives his pivot.
			local intro = world.load("ReplicatedStorage.Shared.Cutscenes").get("KrampusArrives")
			if world.load("ReplicatedStorage.Shared.Config").Cutscenes.Enabled and intro then
				world.wait(intro.seconds + 0.25)
			end
			-- Park Krampus next to the wardrobe.
			local krampus = run.krampus
			krampus.stunnedUntil = math.huge
			krampus.body.model:PivotTo(spot.inside * CFrame.new(0, 0, 4))
			waitUntil(world, function()
				return run.players[santa].hidden == nil
			end, 30, "the hider to gasp")
			expect(run.noise).toBeGreaterThan(0)
			expect(sawBanner(engine, santa, "Hider gasped for air!")).toBe(true)
		end)
	end)
end)

-- Magic tricks (Josh, 6 Nov 2026: Frost Zap, Frost Stomp, Bell Blink + the Grumpy Meter).
describe("Krampus's magic tricks", function()
	local function rootOf(player)
		return player.Character:FindFirstChild("HumanoidRootPart")
	end
	local function humanoidOf(player)
		return player.Character:FindFirstChildOfClass("Humanoid")
	end
	-- Lair, intro over, Krampus parked and ready to cast at `level`.
	local function ready(world, engine, run, level)
		atLair(world, run)
		local intro = world.load("ReplicatedStorage.Shared.Cutscenes").get("KrampusArrives")
		if world.load("ReplicatedStorage.Shared.Config").Cutscenes.Enabled and intro then
			world.wait(intro.seconds + 0.25)
		end
		local krampus = run.krampus
		local magic = krampus.magic
		krampus.stunnedUntil = 0
		magic.arrivedAt = engine.now - 1000 -- Furious by the clock...
		magic.bellRings = 0
		magic.lastCastAt = -math.huge
		-- ...unless a level is asked for: rewind the clock to it.
		local M = world.load("ReplicatedStorage.Shared.Config").Krampus.Magic
		if level then
			magic.arrivedAt = engine.now - M.Grumpy.At[level] - M.FirstCastAfter - 0.5
		end
		return krampus, magic, M
	end

	local function inFront(krampus, studs)
		local root = krampus.body.root
		return (root.CFrame * CFrame.new(0, 0, -studs)).Position
	end

	it("Frost Zap freezes a Santa into an ice cube, and a friend smashes them out", function()
		local world, engine, Run, players = setup({ "Iced", "Smasher" })
		local santa, friend = players[1], players[2]
		world.run(function()
			local run = startRun(world, Run, players)
			local krampus, magic = ready(world, engine, run, 1)
			engine:teleport(friend, krampus.body.root.Position + Vector3.new(0, 0, 400)) -- out of the way
			engine:teleport(santa, inFront(krampus, 45))
			waitUntil(world, function()
				return run.players[santa].iced == true
			end, 10, "the Frost Zap to hit")
			expect(run:_free(santa)).toBeNil()
			expect(sawBanner(engine, santa, "Iced is an ice cube! Smash them out!")).toBe(true)
			krampus.stunnedUntil = math.huge -- hold him so the smash is the test
			local cube = magic.cubes[santa].part
			engine:teleport(friend, cube.Position + Vector3.new(4, 0, 0))
			local prompt = cube:FindFirstChildOfClass("ProximityPrompt")
			for _ = 1, 3 do
				engine.trigger(prompt, friend)
			end
			expect(run.players[santa].iced).toBe(false)
			expect(sawBanner(engine, santa, "Smasher smashed Iced out of the ice!")).toBe(true)
			expect(rootOf(santa).Anchored).toBe(false)
		end)
	end)

	it("a frozen Santa can tap their way out, and the cube melts on its own", function()
		local world, engine, Run, players = setup({ "Cracker" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, players)
			local krampus, magic, M = ready(world, engine, run, 1)
			krampus.stunnedUntil = math.huge
			magic:freeze(santa)
			for _ = 1, M.FrostZap.CrackTaps do
				run:onInput(santa, "Tap")
				world.wait(0.2)
			end
			expect(run.players[santa].iced).toBe(false)
			magic:freeze(santa)
			world.wait(M.FrostZap.FrozenSeconds + 0.5)
			expect(run.players[santa].iced).toBe(false)
		end)
	end)

	it("he scoops up an ice cube, ice and all", function()
		local world, engine, Run, players = setup({ "Scooped" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, players)
			local krampus, magic = ready(world, engine, run, 1)
			engine:teleport(santa, inFront(krampus, 4))
			magic:freeze(santa)
			waitUntil(world, function()
				return run.players[santa].captive
			end, 5, "the snatch")
			expect(run.players[santa].iced).toBe(false)
			expect(magic.cubes[santa]).toBeNil()
		end)
	end)

	it("Frost Stomp skids a Santa on the ground, but not one who jumps it", function()
		local world, engine, Run, players = setup({ "Skidder", "Jumper" })
		local santa, jumper = players[1], players[2]
		world.run(function()
			local run = startRun(world, Run, players)
			local krampus = ready(world, engine, run, 2)
			engine:teleport(santa, inFront(krampus, 12))
			engine:teleport(jumper, (krampus.body.root.CFrame * CFrame.new(12, 0, 0)).Position)
			jumper.Character:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Freefall)
			waitUntil(world, function()
				return (run.players[santa].skidUntil or 0) > engine.now
			end, 5, "the frost ring")
			expect(humanoidOf(santa).WalkSpeed < 16).toBe(true)
			expect(run.players[jumper].skidUntil).toBeNil()
		end)
	end)

	it("Bell Blink pops him out beside a Santa who ran away", function()
		local world, engine, Run, players = setup({ "Runner" })
		local santa = players[1]
		world.run(function()
			local run = startRun(world, Run, players)
			local krampus = ready(world, engine, run, 3)
			engine:teleport(santa, inFront(krampus, 80))
			world.wait(2.5)
			local gap = (krampus.body.root.Position - rootOf(santa).Position).Magnitude
			expect(gap < 20).toBe(true)
			expect(sawBanner(engine, santa, "Krampus popped up right next to you!")).toBe(true)
		end)
	end)

	it("ringing his bells cancels a trick and makes him grumpier", function()
		local world, engine, Run, players = setup({ "Target", "Ringer" })
		local santa, ringer = players[1], players[2]
		world.run(function()
			local run = startRun(world, Run, players)
			local krampus, magic = ready(world, engine, run, 1)
			engine:teleport(santa, inFront(krampus, 40))
			waitUntil(world, function()
				return magic.casting ~= nil
			end, 5, "a wind-up")
			engine:teleport(ringer, (krampus.body.root.CFrame * CFrame.new(0, 0, 4)).Position)
			engine.trigger(krampus.body.bellPrompt, ringer)
			expect(magic.casting).toBeNil()
			expect(magic.bellRings).toBe(1)
			world.wait(3)
			expect(run.players[santa].iced).never.toBe(true)
		end)
	end)
end)
