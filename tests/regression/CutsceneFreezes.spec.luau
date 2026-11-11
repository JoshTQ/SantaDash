--[[
	Regression tests for the glitchy cutscenes (Josh, 11 Nov 2026: "The
	cutscenes are glitchy, especially Krampus. Causes game freezes.").

	Root causes, each covered below:
	  1. One cue erroring left CutscenePlayer's "last time" behind, so every
	     earlier cue (music, bells, roar...) fired again on every frame after.
	  2. Krampus and the sleigh only moved on clients at the network rate, so
	     cameras following them juddered. The server now sends each path once
	     (shared/Puppets) and clients pose the same path themselves.
	  3. A bell ring during the KrampusArrives intro spun him mid-walk and cut
	     his hold short while the crew were still watching.
	  4. Krampus's Meshy mesh and texture downloaded the moment he woke (the
	     first frame of his intro). Clients now preload it (shared/Preload).
	  5. play() could yield (WaitForChild) inside the Hud's remote handler.
	  6. Cutscene sounds only came from SoundAssets overrides, never the
	     catalogue ids, so scenes were silent without an override.
]]

local fs = require("@lune/fs")

local Cutscenes = load("ReplicatedStorage.Shared.Cutscenes")
local Puppets = load("ReplicatedStorage.Shared.Puppets")
local Preload = load("ReplicatedStorage.Shared.Preload")
local SleighFlight = load("ReplicatedStorage.Shared.SleighFlight")
local Sounds = load("ReplicatedStorage.Shared.Sounds")

local function near(a: CFrame, b: CFrame): boolean
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = a:GetComponents()
	local _, _, _, s00, s01, s02, s10, s11, s12, s20, s21, s22 = b:GetComponents()
	local rot = math.max(
		math.abs(r00 - s00),
		math.abs(r01 - s01),
		math.abs(r02 - s02),
		math.abs(r10 - s10),
		math.abs(r11 - s11),
		math.abs(r12 - s12),
		math.abs(r20 - s20),
		math.abs(r21 - s21),
		math.abs(r22 - s22)
	)
	return (a.Position - b.Position).Magnitude < 1e-4 and rot < 1e-4
end

describe("cutscene cues (freeze: every cue re-fired each frame)", function()
	it("a cue that errors never stops the others, and nothing fires twice", function()
		local scene = Cutscenes.get("KrampusArrives")
		local fired = {}
		local last = -1
		-- 60 fps through the whole scene, with the hats gag erroring every time.
		for frame = 0, scene.seconds * 60 do
			local t = frame / 60
			local errors
			last, errors = Cutscenes.fireCues(scene, last, t, function(cue)
				fired[cue] = (fired[cue] or 0) + 1
				if cue.kind == "hatsOff" then
					error("hat handle isn't Archivable")
				end
			end)
			for _, err in errors do
				expect(string.find(err, "hatsOff", 1, true)).toBeTruthy()
			end
		end
		for _, cue in scene.cues do
			expect(fired[cue]).toBe(1)
		end
	end)

	it("returns the time to resume from, never going backwards", function()
		local scene = Cutscenes.get("Getaway")
		local nextFrom = Cutscenes.fireCues(scene, 3, 2, function() end)
		expect(nextFrom).toBe(3)
		local count = 0
		local _, errors = Cutscenes.fireCues(scene, -1, scene.seconds, function()
			count += 1
		end)
		expect(count).toBe(#scene.cues)
		expect(#errors).toBe(0)
	end)
end)

describe("puppets (judder: Krampus and the sleigh stepped at the network rate)", function()
	local spawn = CFrame.new(40, 6, -120) * CFrame.Angles(0, math.rad(35), 0)
	local fromDeck = CFrame.new(0, 2, 0)
	local toDeck = CFrame.new(300, 2, -500) * CFrame.Angles(0, math.rad(-20), 0)

	it("clients pose Krampus's intro exactly where the server puts him", function()
		local puppet = { path = "krampusIntro", base = spawn, seconds = 4 }
		for t = 0, 4, 0.05 do
			expect(near(Puppets.poseAt(puppet, t), spawn * Cutscenes.krampusIntro(t))).toBe(true)
		end
		-- After the end he holds the final pose (no snap back behind the gate).
		expect(near(Puppets.poseAt(puppet, 9), spawn * Cutscenes.krampusIntro(4))).toBe(true)
		expect(near(Puppets.poseAt(puppet, -1), spawn * Cutscenes.krampusIntro(0))).toBe(true)
	end)

	it("clients pose the belly-flop, the getaway sleigh and every flight the same way", function()
		local deck = Vector3.new(0, 0, 0)
		local start = CFrame.new(0, 5, 60)
		local flop = { path = "krampusFlop", base = start, deck = deck, seconds = 5 }
		local getaway = { path = "getawaySleigh", base = toDeck, seconds = 5 }
		local flight = { path = "flight", base = fromDeck, to = toDeck, peak = 40, seconds = 7 }
		for t = 0, 5, 0.1 do
			expect(near(Puppets.poseAt(flop, t), Cutscenes.krampusFlop(t, start, deck))).toBe(true)
			expect(near(Puppets.poseAt(getaway, t), toDeck * Cutscenes.getawaySleigh(t))).toBe(true)
			expect(near(Puppets.poseAt(flight, t), SleighFlight.deckAt(fromDeck, toDeck, t, 7, 40))).toBe(
				true
			)
		end
	end)

	it("a rider's seat offset rides along with the deck", function()
		local seat = CFrame.new(2, 3, 1)
		local flight =
			{ path = "flight", base = fromDeck, to = toDeck, peak = 40, seconds = 7, offset = seat }
		for t = 0, 7, 0.5 do
			expect(near(Puppets.poseAt(flight, t), SleighFlight.deckAt(fromDeck, toDeck, t, 7, 40) * seat)).toBe(
				true
			)
		end
	end)

	it("bad puppets are rejected instead of erroring every frame", function()
		expect(Puppets.problem({ path = "krampusIntro", base = spawn, seconds = 4 })).toBe(nil)
		expect(Puppets.problem({ path = "moonwalk", base = spawn, seconds = 4 })).toBeTruthy()
		expect(Puppets.problem({ path = "krampusIntro", seconds = 4 })).toBeTruthy()
		expect(Puppets.problem({ path = "krampusIntro", base = spawn, seconds = 0 })).toBeTruthy()
		expect(Puppets.problem({ path = "flight", base = spawn, seconds = 4 })).toBeTruthy()
		expect(Puppets.problem({ path = "krampusFlop", base = spawn, seconds = 4 })).toBeTruthy()
		expect(Puppets.problem({ path = "getawaySleigh", base = spawn, seconds = 4, offset = 3 })).toBeTruthy()
		expect(Puppets.problem("nope" :: any)).toBeTruthy()
	end)
end)

describe("Krampus's intro in a run", function()
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

	local function waitUntil(world, check: () -> boolean, seconds: number, what: string)
		local deadline = world.engine.now + seconds
		while not check() do
			if world.engine.now > deadline then
				error("timed out waiting for " .. what, 2)
			end
			world.wait(0.25)
		end
	end

	local function atLair(world, run)
		waitUntil(world, function()
			return run.krampus ~= nil
		end, 600, "Krampus")
		return run.krampus
	end

	it("sends the crew his path on the same clock as the cutscene", function()
		local world, engine, Run, players = setup({ "A", "B" })
		world.run(function()
			local run = Run.new(1, players, function() end)
			run:start()
			local krampus = atLair(world, run)
			for _, player in players do
				local cutscene, puppet
				for _, m in engine:hudMessages(player, "Cutscene") do
					if m.data.id == "KrampusArrives" then
						cutscene = m.data
					end
				end
				for _, m in engine:hudMessages(player, "Puppets") do
					for _, p in m.data.puppets do
						if p.path == "krampusIntro" then
							puppet = { data = m.data, puppet = p }
						end
					end
				end
				expect(cutscene).never.toBeNil()
				expect(puppet).never.toBeNil()
				expect(puppet.puppet.target).toBe(krampus.body.model)
				expect(cutscene.follow).toBe(krampus.body.model)
				expect(math.abs(puppet.data.startedAt - cutscene.startedAt)).toBeLessThan(0.05)
				expect(puppet.puppet.seconds).toBe(Cutscenes.get("KrampusArrives").seconds)
				expect(Puppets.problem(puppet.puppet)).toBe(nil)
			end
			run.ended = true
		end, { allowErrors = true })
	end)

	it("can't be rung during the intro, and a ring never shortens his hold", function()
		local world, engine, Run, players = setup({ "A" })
		local a = players[1]
		world.run(function()
			local run = Run.new(1, players, function() end)
			run:start()
			local krampus = atLair(world, run)
			local hold = krampus.stunnedUntil
			expect(krampus.body.bellPrompt.Enabled).toBe(false)
			-- Even if a ring gets through (a prompt fired just before), it's ignored.
			engine:teleport(a, (krampus.body.root.CFrame * CFrame.new(0, 0, 4)).Position)
			krampus:_ringBells(a)
			expect(krampus.stunnedUntil).toBe(hold)
			expect(krampus.lastBellAt).toBe(-math.huge)

			world.wait(Cutscenes.get("KrampusArrives").seconds + 0.3)
			expect(krampus.body.bellPrompt.Enabled).toBe(true)
			-- He ends his walk exactly on his spawn, where the clients' copy ends too.
			local spawn = run.route.stops[run.stopIndex].krampusSpawn
			expect((krampus.body.model:GetPivot().Position - spawn.Position).Magnitude).toBeLessThan(0.01)

			-- A ring in the grace after the intro still can't cut the hold short.
			krampus.stunnedUntil = world.engine.now + 60
			local long = krampus.stunnedUntil
			engine:teleport(a, (krampus.body.root.CFrame * CFrame.new(0, 0, 4)).Position)
			krampus:_ringBells(a)
			expect(krampus.lastBellAt > -math.huge).toBe(true) -- the ring counted
			expect(krampus.stunnedUntil).toBe(long)
			run.ended = true
		end, { allowErrors = true })
	end)

	it("every flight sends the sleigh and each rider's seat, and lands on the path's end", function()
		local world, engine, Run, players = setup({ "A", "B" })
		world.run(function()
			local run = Run.new(1, players, function() end)
			run:start()
			world.wait(0.5) -- in the take-off flight
			local messages = engine:hudMessages(players[1], "Puppets")
			expect(#messages).toBe(1)
			local data = messages[1].data
			expect(#data.puppets).toBe(1 + #players) -- the sleigh + both riders
			expect(data.puppets[1].target).toBe(run.route.sleigh)
			expect(data.puppets[1].path).toBe("flight")
			local riders = {}
			for i = 2, #data.puppets do
				local p = data.puppets[i]
				expect(typeof(p.offset)).toBe("CFrame")
				riders[p.target] = true
			end
			for _, player in players do
				expect(riders[player.Character.HumanoidRootPart]).toBe(true)
			end
			waitUntil(world, function()
				return run.stopIndex >= 1
			end, 60, "Stop 1")
			local landed = Puppets.poseAt(data.puppets[1], data.puppets[1].seconds)
			expect((run.route.sleigh:GetPivot().Position - landed.Position).Magnitude).toBeLessThan(0.01)
			run.ended = true
		end, { allowErrors = true })
	end)
end)

describe("preloading (freeze: Krampus's mesh downloaded as he woke)", function()
	it("collects every mesh, texture and sound id once", function()
		local model = Instance.new("Model")
		local a = Instance.new("SpecialMesh")
		a.MeshId = "rbxassetid://111"
		a.TextureId = "rbxassetid://222"
		a.Parent = model
		local decal = Instance.new("Decal")
		decal.Texture = "rbxassetid://222" -- the same texture again
		decal.Parent = model
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://333"
		sound.Parent = decal
		local ids = Preload.contentIds(model)
		expect(#ids).toBe(3)
		expect(table.find(ids, "rbxassetid://111")).toBeTruthy()
		expect(table.find(ids, "rbxassetid://222")).toBeTruthy()
		expect(table.find(ids, "rbxassetid://333")).toBeTruthy()
		expect(#Preload.contentIds(Instance.new("Model"))).toBe(0)
	end)

	it("round-trips the ids through the attribute string", function()
		local ids = { "rbxassetid://1", "rbxassetid://22", "rbxassetid://333" }
		expect(Preload.decode(Preload.encode(ids))).toEqual(ids)
		expect(#Preload.decode(nil)).toBe(0)
		expect(#Preload.decode("")).toBe(0)
	end)

	it("preloads Krampus and every cutscene sound that has audio", function()
		expect(table.find(Preload.LateModels, "Krampus")).toBeTruthy()
		local ids = Preload.soundIds(Sounds.Defs)
		for _, id in Cutscenes.Order do
			for _, cue in Cutscenes.get(id).cues do
				if cue.kind == "sfx" and Sounds.Defs[cue.key].id > 0 then
					expect(table.find(ids, "rbxassetid://" .. Sounds.Defs[cue.key].id)).toBeTruthy()
				end
			end
		end
		local folder = Instance.new("Folder")
		local keep = Instance.new("Sound")
		keep.Name = "CutsceneRoar"
		keep.Parent = folder
		local skip = Instance.new("Sound")
		skip.Name = "Footstep"
		skip.Parent = folder
		local found = Preload.sounds(folder)
		expect(#found).toBe(1)
		expect(found[1]).toBe(keep)
		expect(#Preload.sounds(nil)).toBe(0)
	end)
end)

describe("the client cutscene player", function()
	local source = fs.readFile("src/client/CutscenePlayer.luau")

	it("never yields while starting a scene", function()
		-- play() runs inside the Hud's remote handler; a WaitForChild there
		-- held the scene back. Only the PlayerGui fallback may wait.
		local _, waits = string.gsub(source, "WaitForChild%(", "")
		local _, guiWaits = string.gsub(source, 'WaitForChild%("PlayerGui"%)', "")
		local _, moduleWaits = string.gsub(source, 'WaitForChild%("PuppetPlayer"%)', "")
		expect(waits - guiWaits - moduleWaits).toBe(0)
	end)

	it("plays cutscene sounds through SoundPlayer (catalogue ids, not only overrides)", function()
		expect(string.find(source, "SoundPlayer.make(", 1, true)).toBeTruthy()
	end)

	it("follows puppeted models and stops cleanly if a frame errors", function()
		expect(string.find(source, "PuppetPlayer.poseOf(", 1, true)).toBeTruthy()
		expect(string.find(source, "Cutscenes.fireCues(", 1, true)).toBeTruthy()
		expect(string.find(source, "pcall(frame)", 1, true)).toBeTruthy()
	end)
end)
