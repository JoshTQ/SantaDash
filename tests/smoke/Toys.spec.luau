--[[
	Toys to fight back (Josh, 11 Nov 2026: "Can we use the toys against them,
	like snow guns etc" ... "Build them"): the Snowball Launcher and Glitter
	Bomb, bought at the toy stand. Whole runs, headless.
]]

local function setup(names: { string })
	local world = headless()
	local engine = world.engine
	world.load("ReplicatedStorage.Shared.Config").MapEvents.Chance = 0
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
	local run = Run.new(1, crew, function() end)
	run:start()
	return run
end

local function sawBanner(engine, player, text: string): boolean
	for _, m in engine:hudMessages(player, "Banner") do
		if string.find(m.data.text, text, 1, true) then
			return true
		end
	end
	return false
end

local function lastToys(engine, player)
	local list = engine:hudMessages(player, "Toys")
	return list[#list] and list[#list].data
end

-- Stands the Santa at `at`, facing `toward`.
local function standAt(player, at: Vector3, toward: Vector3)
	player.Character:PivotTo(CFrame.lookAt(at, Vector3.new(toward.X, at.Y, toward.Z)))
end

local function rootOf(player)
	return player.Character:FindFirstChild("HumanoidRootPart")
end

local function buyKit(engine, run, player)
	local stop = run.route.stops[run.stopIndex]
	run.players[player].jingle = 5000
	engine.trigger(stop.launcherPrompt, player)
	engine.trigger(stop.glitterPrompt, player)
end

describe("the toy stand", function()
	it("sells the launcher, refills, and glitter, at every stop", function()
		local world, engine, Run, players = setup({ "Shopper" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			local Config = world.load("ReplicatedStorage.Shared.Config")
			local L, G = Config.Toys.Launcher, Config.Toys.Glitter
			for _, stop in run.route.stops do
				expect(stop.launcherPrompt).never.toBeNil()
				expect(stop.glitterPrompt).never.toBeNil()
			end
			waitUntil(world, function()
				return run.stopIndex == 1 and run.phase == "Sneak"
			end, 200, "Stop 1")
			local st = run.players[santa]
			local stop = run.route.stops[1]
			st.jingle = L.Cost + L.Refill + G.Cost * 3
			engine.trigger(stop.launcherPrompt, santa)
			expect(st.launcher).toBe(true)
			expect(st.snowballs).toBe(L.Ammo)
			expect(st.jingle).toBe(L.Refill + G.Cost * 3)
			expect(lastToys(engine, santa).snowballs).toBe(L.Ammo)
			-- Full: no charge.
			engine.trigger(stop.launcherPrompt, santa)
			expect(sawBanner(engine, santa, "already full")).toBe(true)
			expect(st.jingle).toBe(L.Refill + G.Cost * 3)
			-- Fire one, then refill for less.
			run:onInput(santa, "Launch")
			expect(st.snowballs).toBe(L.Ammo - 1)
			engine.trigger(stop.launcherPrompt, santa)
			expect(st.snowballs).toBe(L.Ammo)
			expect(st.jingle).toBe(G.Cost * 3)
			-- Glitter, up to Max.
			for _ = 1, 3 do
				engine.trigger(stop.glitterPrompt, santa)
			end
			expect(st.glitters).toBe(G.Max)
			expect(st.jingle).toBe(G.Cost * (3 - G.Max))
			expect(lastToys(engine, santa).glitters).toBe(G.Max)
		end)
	end)

	it("shows the approved toys on the stand, and Santa holds what he buys", function()
		local world, engine, Run, players = setup({ "Holder" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			local Toys = world.load("ServerScriptService.Server.Toys")
			for _, stop in run.route.stops do
				local stand = stop.launcherPrompt.Parent
				expect(stand.Material).toBe(Enum.Material.Wood)
			end
			expect(run.route.model:FindFirstChild("ToyCatapult", true)).never.toBeNil()
			expect(run.route.model:FindFirstChild("ToyGlobe", true)).never.toBeNil()
			waitUntil(world, function()
				return run.stopIndex == 1 and run.phase == "Sneak"
			end, 200, "Stop 1")
			expect(Toys.holding(santa, "Catapult")).toBeNil()
			buyKit(engine, run, santa)
			local catapult = Toys.holding(santa, "Catapult")
			local globe = Toys.holding(santa, "Globe")
			expect(catapult).never.toBeNil()
			expect(globe).never.toBeNil()
			local ball = catapult:FindFirstChild("Snowball", true)
			expect(ball.Transparency).toBe(0)
			expect(ball:GetAttribute("FollowBone")).toBe("RightHand")
			expect(globe:FindFirstChild("Glass", true):GetAttribute("FollowBone")).toBe("LeftHand")
			-- Out of snowballs: the spoon is empty. Out of glitter: the globe goes.
			run.players[santa].snowballs = 1
			run:onInput(santa, "Launch")
			expect(ball.Transparency).toBe(1)
			run:onInput(santa, "Glitter")
			expect(Toys.holding(santa, "Globe")).toBeNil()
			expect(Toys.holding(santa, "Catapult")).never.toBeNil()
			-- Run over: empty hands.
			run:_resetCharacter(santa)
			expect(Toys.holding(santa, "Catapult")).toBeNil()
		end)
	end)

	it("an empty launcher says so, and the cooldown stops spam", function()
		local world, engine, Run, players = setup({ "Spammer" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			waitUntil(world, function()
				return run.stopIndex == 1 and run.phase == "Sneak"
			end, 200, "Stop 1")
			buyKit(engine, run, santa)
			local st = run.players[santa]
			local ammo = st.snowballs
			run:onInput(santa, "Launch")
			run:onInput(santa, "Launch") -- same moment: ignored
			expect(st.snowballs).toBe(ammo - 1)
			st.snowballs = 0
			world.wait(1)
			run:onInput(santa, "Launch")
			expect(sawBanner(engine, santa, "Out of snowballs")).toBe(true)
		end)
	end)
end)

describe("snowballs", function()
	it("knock a guard dog over", function()
		local world, engine, Run, players = setup({ "Pitcher" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			waitUntil(world, function()
				return run.stopIndex == 2 and run.phase == "Sneak" and #(run.dogPacks or {}) > 0
			end, 400, "Stop 2's dogs")
			buyKit(engine, run, santa)
			local Toys = world.load("ServerScriptService.Server.Toys")
			local before = #Toys.targets(run)
			expect(before).toBeGreaterThan(0)
			local dog = Toys.targets(run)[1]
			standAt(santa, dog.position + Vector3.new(0, 0, 15), dog.position)
			run:onInput(santa, "Launch")
			world.wait(0.75)
			local after = 0
			for _, t in Toys.targets(run) do
				if t.kind == "Dog" then
					after += 1
				end
			end
			expect(after).toBe(before - 1) -- the hit dog is down (Stunned)
		end)
	end)

	it("make Krampus flinch, once per cooldown, and never drop his captive", function()
		local world, engine, Run, players = setup({ "Brave", "Caught" })
		local brave, caught = players[1], players[2]
		world.run(function()
			local run = startRun(Run, players)
			waitUntil(world, function()
				return run.stopIndex == 3 and run.phase == "Sneak" and run.krampus ~= nil
			end, 500, "the Lair")
			local Config = world.load("ReplicatedStorage.Shared.Config")
			local L = Config.Toys.Launcher
			run.cuckoo = nil
			buyKit(engine, run, brave)
			local krampus = run.krampus
			krampus.stunnedUntil = 0
			krampus.introUntil = 0
			local at = krampus.body.root.Position
			standAt(brave, at + Vector3.new(0, 0, 30), at)
			run:onInput(brave, "Launch")
			world.wait(0.6)
			local first = krampus.lastFlinchAt
			expect(first).never.toBeNil()
			expect(sawBanner(engine, brave, "Krampus flinched")).toBe(true)
			-- Again straight away: thrown, but he doesn't flinch.
			at = krampus.body.root.Position
			standAt(brave, at + Vector3.new(0, 0, 20), at)
			run:onInput(brave, "Launch")
			world.wait(0.6)
			expect(krampus.lastFlinchAt).toBe(first)
			-- With a captive, after the cooldown: he flinches, the captive stays.
			krampus:_snatch(caught)
			expect(krampus:flinch(first + L.KrampusCooldown + 1)).toBe(true)
			expect(krampus.captive).toBe(caught)
			expect(run.players[caught].captive).toBe(true)
		end)
	end)
end)

describe("Glitter Bombs", function()
	it("make a cloud the cuckoo can't see into, that fades", function()
		local world, engine, Run, players = setup({ "Sparkly" })
		local santa = players[1]
		world.run(function()
			local run = startRun(Run, players)
			waitUntil(world, function()
				return run.stopIndex == 3
					and run.phase == "Sneak"
					and run.krampus ~= nil
					and run.cuckoo ~= nil
			end, 500, "the Lair")
			local Config = world.load("ReplicatedStorage.Shared.Config")
			local G = Config.Toys.Glitter
			run.krampus.stunnedUntil = math.huge
			run.krampus.body.model:PivotTo(
				CFrame.new(run.route.stops[3].deckCFrame.Position + Vector3.new(0, 6, 600))
			)
			buyKit(engine, run, santa)
			local lair = run.route.model:FindFirstChild("LairHouse", true)
			local centre = lair:GetBoundingBox().Position
			local floorY = run.list.home.Position.Y
			local start = Vector3.new(centre.X, floorY + 2, centre.Z)
			standAt(santa, start - Vector3.new(0, 0, G.Throw), start)
			run:onInput(santa, "Glitter")
			expect(run.players[santa].glitters).toBe(0)
			expect(run:inGlitter(start)).toBe(true)
			expect(run.route.model:FindFirstChild("GlitterCloud", true)).never.toBeNil()
			engine:teleport(santa, start)
			-- The cuckoo looks; the Santa wriggles about inside the cloud.
			run.cuckoo.warnAt = engine.now + 0.3
			run.cuckoo.warned = false
			run.cuckoo.looking = false
			waitUntil(world, function()
				return run.cuckoo.looking
			end, 5, "the cuckoo to look")
			for i = 1, 4 do
				engine:teleport(santa, start + Vector3.new(i, 0, 0))
				world.wait(0.25)
			end
			expect(sawBanner(engine, santa, "CUCKOO! The clock saw")).toBe(false)
			world.wait(G.Seconds)
			expect(run:inGlitter(start)).toBe(false)
			expect(run.route.model:FindFirstChild("GlitterCloud", true)).toBeNil()
		end)
	end)
end)
