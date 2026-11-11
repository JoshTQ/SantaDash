--[[
	The Naughty List heist (Josh, 11 Nov 2026: "Naughty book is underwhelming,
	make it more important more challenging. Maybe the lair has PvE?"; he
	picked the List as the x2 and the Cuckoo Watch). Whole runs, headless.
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

local function waitUntil(world, check: () -> boolean, seconds: number?, what: string?)
	local deadline = world.engine.now + (seconds or 300)
	while not check() do
		if world.engine.now > deadline then
			error("timed out waiting for " .. (what or "condition"), 2)
		end
		world.wait(0.25)
	end
end

local function startRun(Run, crew)
	local result = { finished = false }
	local run = Run.new(1, crew, function(_, survivors)
		result.finished = true
		result.survivors = survivors
	end)
	run:start()
	return run, result
end

-- Krampus's Lair, his intro over and Krampus parked out of the way.
local function atLair(world, run, park: boolean?)
	waitUntil(world, function()
		return run.stopIndex == 3 and run.phase == "Sneak" and run.krampus ~= nil and run.list ~= nil
	end, 500, "the Lair")
	if park ~= false then
		run.krampus.stunnedUntil = math.huge
		run.krampus.body.model:PivotTo(
			CFrame.new(run.route.stops[3].deckCFrame.Position + Vector3.new(0, 6, 600))
		)
	end
	return run.route.stops[3]
end

local function sawBanner(engine, player, text: string): boolean
	for _, m in engine:hudMessages(player, "Banner") do
		if string.find(m.data.text, text, 1, true) then
			return true
		end
	end
	return false
end

local function rootOf(player)
	return player.Character:FindFirstChild("HumanoidRootPart")
end

local function toList(engine, run, player)
	engine:teleport(player, run.list.model:GetPivot().Position + Vector3.new(3, 2, 0))
	engine.trigger(run.list.prompt, player)
end

local function aboard(engine, stop, player)
	engine:teleport(player, stop.deckCFrame.Position + Vector3.new(0, 3, 0))
end

local function lastResults(engine, player)
	local results = engine:hudMessages(player, "Results")
	return results[#results] and results[#results].data
end

describe("the Naughty List is the escape bonus", function()
	it("escaping with the List doubles the loot", function()
		local world, engine, Run, players = setup({ "Thief" })
		local santa = players[1]
		world.run(function()
			local run, result = startRun(Run, players)
			local stop = atLair(world, run)
			run.cuckoo = nil -- this test is about the book
			toList(engine, run, santa)
			local st = run.players[santa]
			expect(run.list.carrier).toBe(santa)
			expect(st.carryingList).toBe(true)
			expect(st.sackCount).toBe(0) -- the book isn't in the sack: it hovers over your head
			expect(sawBanner(engine, santa, "Thief stole the Naughty List!")).toBe(true)
			aboard(engine, stop, santa)
			waitUntil(world, function()
				return result.finished
			end, 300, "the run to finish")
			expect(st.escapeMultiplier).toBe(2)
			expect(sawBanner(engine, santa, "You got away with the Naughty List!")).toBe(true)
		end)
		local row = lastResults(engine, santa).rows[1]
		expect(row.escaped).toBe(true)
		expect(row.loot).toBeGreaterThanOrEqual(2 * 250 * 0.8) -- the book's own 250, doubled, at solo 80%
	end)

	it("escaping without it banks the sack at x1", function()
		local world, engine, Run, players = setup({ "Empty" })
		local santa = players[1]
		world.run(function()
			local run, result = startRun(Run, players)
			atLair(world, run)
			local st = run.players[santa]
			waitUntil(world, function()
				return result.finished
			end, 300, "the run to finish")
			expect(st.escapeMultiplier).toBe(1)
			expect(sawBanner(engine, santa, "No Naughty List on the sleigh")).toBe(true)
			-- The Getaway's stamp says so too.
			local scenes = engine:hudMessages(santa, "Cutscene")
			local getaway = scenes[#scenes].data
			expect(getaway.id).toBe("Getaway")
			expect(getaway.swap["LOOT x2"]).toBe("NO LIST, NO x2")
		end)
		expect(lastResults(engine, santa).rows[1].escaped).toBe(true)
	end)

	it("the carrier is Marked: slower, can't hide, and rattles", function()
		local world, engine, Run, players = setup({ "Marked" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			local stop = atLair(world, run)
			run.cuckoo = nil
			toList(engine, run, santa)
			local humanoid = santa.Character:FindFirstChildOfClass("Humanoid")
			expect(humanoid.WalkSpeed).toBe(15)
			engine.trigger(stop.hideSpots[1].prompt, santa)
			expect(run.players[santa].hidden).toBeNil()
			expect(sawBanner(engine, santa, "rattles too much to hide")).toBe(true)
			local before = run.noise
			world.wait(2)
			expect(run.noise).toBeGreaterThan(before)
			expect((run.lastNoisePos - rootOf(santa).Position).Magnitude).toBeLessThan(1)
			-- The book hovers over their head.
			local book = run.list.model:GetPivot().Position
			expect(book.Y).toBeGreaterThan(rootOf(santa).Position.Y + 2)
		end)
	end)

	it("passes to a friend in range, and not to one too far away", function()
		local world, engine, Run, players = setup({ "Passer", "Catcher" })
		local passer, catcher = players[1], players[2]
		world.run(function()
			local run = startRun(Run, players)
			atLair(world, run)
			run.cuckoo = nil
			toList(engine, run, passer)
			local at = rootOf(passer).Position
			engine:teleport(catcher, at + Vector3.new(60, 0, 0))
			run:onInput(passer, "PassList")
			expect(run.list.carrier).toBe(passer)
			expect(sawBanner(engine, passer, "Nobody close enough")).toBe(true)
			engine:teleport(catcher, at + Vector3.new(8, 0, 0))
			run:onInput(passer, "PassList")
			expect(run.list.carrier).toBe(catcher)
			expect(run.players[passer].carryingList).toBe(false)
			expect(run.players[catcher].carryingList).toBe(true)
			expect(sawBanner(engine, catcher, "Passer passed the Naughty List to Catcher!")).toBe(true)
			local carrying = engine:hudMessages(catcher, "List")
			expect(carrying[#carrying].data.carrying).toBe(true)
		end)
	end)

	it("snatched: the List drops, anyone can grab it, and it flies home if nobody does", function()
		local world, engine, Run, players = setup({ "Grabbed", "Helper" })
		local santa, helper = players[1], players[2]
		world.run(function()
			local run = startRun(Run, players)
			atLair(world, run)
			run.cuckoo = nil
			toList(engine, run, santa)
			run:onSnatched(santa)
			expect(run.list.state).toBe("Loose")
			expect(run.list.carrier).toBeNil()
			expect(run.players[santa].carryingList).toBe(false)
			expect(sawBanner(engine, helper, "Krampus snatched Grabbed. The Naughty List fell on the floor!")).toBe(
				true
			)
			engine:teleport(helper, run.list.model:GetPivot().Position + Vector3.new(2, 2, 0))
			engine.trigger(run.list.prompt, helper)
			expect(run.list.carrier).toBe(helper)
			-- Drop it again and walk away: it flies home.
			run.list:drop(false)
			world.wait(world.load("ReplicatedStorage.Shared.Config").NaughtyList.LooseSeconds + 1)
			expect(run.list.state).toBe("Home")
			expect(sawBanner(engine, helper, "flew back to its pedestal")).toBe(true)
			expect((run.list.model:GetPivot().Position - run.list.home.Position).Magnitude).toBeLessThan(0.01)
		end)
	end)

	it("can't get wet: swimming drops it on the lake", function()
		local world, engine, Run, players = setup({ "Swimmer" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			atLair(world, run)
			run.cuckoo = nil
			toList(engine, run, santa)
			santa.Character:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Swimming)
			world.wait(0.5)
			expect(run.list.state).toBe("Loose")
			expect(sawBanner(engine, santa, "can't get wet")).toBe(true)
		end)
	end)

	it("elf bots leave the List for their Santa", function()
		local world, _, Run, players = setup({ "Solo" })
		world.run(function()
			local run = startRun(Run, players)
			atLair(world, run)
			for _, c in run:presentCandidates() do
				expect(c.present.plan.naughtyList).toBeFalsy()
			end
		end)
	end)

	it("a carrier who leaves sends it home", function()
		local world, engine, Run, players = setup({ "Quitter", "Stayer" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			atLair(world, run)
			toList(engine, run, santa)
			run:removePlayer(santa)
			expect(run.list.state).toBe("Home")
			expect(run.list.prompt.Enabled).toBe(true)
		end)
	end)
end)

describe("Cuckoo Watch", function()
	local function denCentre(run)
		local lair = run.route.model:FindFirstChild("LairHouse", true)
		local box = lair:GetBoundingBox()
		return box.Position
	end

	-- Fast-forwards the watch to its next warning.
	local function nextWarning(world, run)
		run.cuckoo.warnAt = world.engine.now + 0.3
		run.cuckoo.warned = false
		run.cuckoo.looking = false
	end

	it("spots a Santa who moves in the den, and summons Krampus to them", function()
		local world, engine, Run, players = setup({ "Fidget" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			atLair(world, run)
			expect(run.cuckoo).never.toBeNil()
			local C = world.load("ReplicatedStorage.Shared.Config").CuckooWatch
			local centre = denCentre(run)
			local floorY = run.list.home.Position.Y
			engine:teleport(santa, Vector3.new(centre.X, floorY + 2, centre.Z))
			nextWarning(world, run)
			waitUntil(world, function()
				return run.cuckoo.looking
			end, 5, "the cuckoo to look")
			expect(sawBanner(engine, santa, "CUCKOO!")).toBe(false)
			local noise = run.noise
			-- Walk while it looks.
			for i = 1, 4 do
				engine:teleport(santa, Vector3.new(centre.X + i * 2, floorY + 2, centre.Z))
				world.wait(0.25)
			end
			expect(sawBanner(engine, santa, "CUCKOO! The clock saw Fidget move!")).toBe(true)
			expect(run.noise).toBeGreaterThanOrEqual(noise + C.SpottedNoise - 0.01)
			expect(run.krampus.magic.summoned).toBe(santa)
			local hud = engine:hudMessages(santa, "Cuckoo")
			local states = {}
			for _, m in hud do
				states[m.data.state] = true
			end
			expect(states.Warn).toBe(true)
			expect(states.Look).toBe(true)
			expect(states.Spotted).toBe(true)
			local lair = run.route.model:FindFirstChild("LairHouse", true)
			expect(lair:GetAttribute("CuckooHold")).toBe(C.LookSeconds)
		end)
	end)

	it("doesn't see a Santa who freezes, or anyone outside the den", function()
		local world, engine, Run, players = setup({ "Statue", "Outside" })
		local statue, outside = players[1], players[2]
		world.run(function()
			local run = startRun(Run, players)
			local stop = atLair(world, run)
			local centre = denCentre(run)
			local floorY = run.list.home.Position.Y
			engine:teleport(statue, Vector3.new(centre.X, floorY + 2, centre.Z))
			nextWarning(world, run)
			waitUntil(world, function()
				return run.cuckoo.looking
			end, 5, "the cuckoo to look")
			for i = 1, 8 do
				engine:teleport(outside, stop.deckCFrame.Position + Vector3.new(i * 2, 3, 0))
				world.wait(0.25)
			end
			expect(sawBanner(engine, statue, "CUCKOO! The clock saw")).toBe(false)
			expect(run.krampus.magic.summoned).toBeNil()
		end)
	end)

	it("Krampus Bell Blinks to the Santa it spotted, whatever his grumpiness", function()
		local world, engine, Run, players = setup({ "Spotted" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			atLair(world, run, false)
			local intro = world.load("ReplicatedStorage.Shared.Cutscenes").get("KrampusArrives")
			if world.load("ReplicatedStorage.Shared.Config").Cutscenes.Enabled and intro then
				world.wait(intro.seconds + 2.5)
			end
			run.cuckoo = nil
			local krampus = run.krampus
			local magic = krampus.magic
			magic.arrivedAt = engine.now -- Grumpy: Bell Blink isn't his yet
			magic.lastCastAt = engine.now -- and he's on cooldown
			krampus.stunnedUntil = 0
			engine:teleport(santa, krampus.body.root.Position + Vector3.new(0, 0, 30))
			magic:summon(santa)
			waitUntil(world, function()
				return magic.lastTrick == "BellBlink"
			end, 3, "the summoned Bell Blink")
		end)
	end)
end)
