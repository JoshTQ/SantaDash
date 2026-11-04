local Config = load("ReplicatedStorage.Shared.Config")
local Cutscenes = load("ReplicatedStorage.Shared.Cutscenes")

local FRAMES = {
	anchor = CFrame.new(100, 0, 0),
	follow = CFrame.new(0, 50, 0),
	self = CFrame.new(0, 0, 200),
}

test("all five scenes Josh picked exist", function()
	expect(#Cutscenes.Order).toBe(5)
	for _, id in Cutscenes.Order do
		expect(Cutscenes.get(id)).toBeTruthy()
		expect(Cutscenes.get(id).id).toBe(id)
	end
end)

test("every scene follows the rules (length, keys, pops, cues)", function()
	for _, id in Cutscenes.Order do
		expect(Cutscenes.problem(Cutscenes.get(id), Config.Cutscenes.MaxSeconds)).toBe(nil)
	end
end)

test("no scene runs over 5 seconds", function()
	expect(Config.Cutscenes.MaxSeconds).toBe(5)
	for _, id in Cutscenes.Order do
		expect(Cutscenes.get(id).seconds <= 5).toBeTruthy()
	end
end)

test("first-run cutscene budget stays at or under 15 s", function()
	-- Everyone sees Takeoff, KrampusArrives and Getaway at most once a run.
	local total = 0
	for _, id in { "Takeoff", "KrampusArrives", "Getaway" } do
		total += Cutscenes.get(id).seconds
	end
	expect(total <= 15).toBeTruthy()
end)

test("Takeoff fits inside the first sleigh flight, so it costs no time", function()
	expect(Cutscenes.get("Takeoff").seconds <= Config.Run.FlightSeconds).toBeTruthy()
end)

test("Snatched and LeftBehind only play for the one player", function()
	expect(Cutscenes.get("Snatched").audience).toBe("self")
	expect(Cutscenes.get("LeftBehind").audience).toBe("self")
	expect(Cutscenes.get("KrampusArrives").audience).toBe("all")
end)

test("problem() catches a scene that is too long", function()
	local scene = table.clone(Cutscenes.get("Getaway"))
	scene.seconds = 6
	expect(Cutscenes.problem(scene, 5)).toBeTruthy()
end)

test("problem() catches out-of-order keys and late pops", function()
	local base = Cutscenes.get("Snatched")
	local keys = table.clone(base.keys)
	keys[2], keys[3] = keys[3], keys[2]
	expect(Cutscenes.problem(table.clone(base) :: any, 5)).toBe(nil)
	local swapped = table.clone(base)
	swapped.keys = keys
	expect(Cutscenes.problem(swapped, 5)).toBeTruthy()

	local late = table.clone(base)
	late.pops = { { at = 1.8, hold = 1, text = "late", color = "gold" } }
	expect(Cutscenes.problem(late, 5)).toBeTruthy()

	local badColour = table.clone(base)
	badColour.pops = { { at = 0, hold = 1, text = "x", color = "purple" } }
	expect(Cutscenes.problem(badColour, 5)).toBeTruthy()
end)

test("ease starts at 0, ends at 1 and clamps", function()
	expect(Cutscenes.ease(0)).toBe(0)
	expect(Cutscenes.ease(1)).toBe(1)
	expect(Cutscenes.ease(0.5)).toBeNear(0.5, 1e-9)
	expect(Cutscenes.ease(-3)).toBe(0)
	expect(Cutscenes.ease(7)).toBe(1)
end)

test("keyPair picks the surrounding keys", function()
	local scene = Cutscenes.get("Takeoff")
	local a, b, alpha = Cutscenes.keyPair(scene, 0.6)
	expect(a.at).toBe(0)
	expect(b.at).toBe(1.2)
	expect(alpha).toBeNear(0.5, 1e-9)
	local last, last2, done = Cutscenes.keyPair(scene, 99)
	expect(last.at).toBe(scene.seconds)
	expect(last2.at).toBe(scene.seconds)
	expect(done).toBe(1)
	local first, _, start = Cutscenes.keyPair(scene, -1)
	expect(first.at).toBe(0)
	expect(start).toBe(0)
end)

test("resolve puts offsets in the right space and falls back to the anchor", function()
	local p = { space = "follow", offset = Vector3.new(1, 2, 3) }
	local world = Cutscenes.resolve(p, FRAMES)
	expect(world.X).toBeNear(1, 1e-6)
	expect(world.Y).toBeNear(52, 1e-6)
	-- Krampus despawned / Santa respawning: no follow frame, use the anchor.
	local fallback = Cutscenes.resolve(p, { anchor = FRAMES.anchor })
	expect(fallback.X).toBeNear(101, 1e-6)
end)

test("camera lands exactly on the first and last keys", function()
	for _, id in Cutscenes.Order do
		local scene = Cutscenes.get(id)
		local eye0 = Cutscenes.camera(scene, 0, FRAMES)
		expect((eye0 - Cutscenes.resolve(scene.keys[1].eye, FRAMES)).Magnitude).toBeLessThan(1e-4)
		local eyeEnd, lookEnd = Cutscenes.camera(scene, scene.seconds, FRAMES)
		local lastKey = scene.keys[#scene.keys]
		expect((eyeEnd - Cutscenes.resolve(lastKey.eye, FRAMES)).Magnitude).toBeLessThan(1e-4)
		expect((lookEnd - Cutscenes.resolve(lastKey.look, FRAMES)).Magnitude).toBeLessThan(1e-4)
		-- The camera never sits on the point it looks at (lookAt would break).
		for step = 0, 40 do
			local eye, look = Cutscenes.camera(scene, scene.seconds * step / 40, FRAMES)
			expect((eye - look).Magnitude).toBeGreaterThan(1)
		end
	end
end)

test("field of view eases between keys", function()
	local scene = Cutscenes.get("KrampusArrives")
	local _, _, fovStart = Cutscenes.camera(scene, 0, FRAMES)
	local _, _, fovEnd = Cutscenes.camera(scene, scene.seconds, FRAMES)
	expect(fovStart).toBe(70)
	expect(fovEnd).toBe(50)
end)

test("popAt shows the latest pop and nothing between pops", function()
	local scene = Cutscenes.get("KrampusArrives")
	expect(Cutscenes.popAt(scene, 0.5).text).toBe("jingle... JINGLE...")
	expect(Cutscenes.popAt(scene, 1.5)).toBe(nil)
	expect(Cutscenes.popAt(scene, 2.3).text).toBe("CLONK!")
	expect(Cutscenes.popAt(scene, 3.5).text).toBe("KRAMPUS IS COMING!")
end)

test("cuesBetween fires each cue exactly once across any frame rate", function()
	for _, id in Cutscenes.Order do
		local scene = Cutscenes.get(id)
		for _, dt in { 1 / 60, 1 / 12, 0.7 } do
			local fired, last = 0, -1
			local t = 0
			while last < scene.seconds do
				fired += #Cutscenes.cuesBetween(scene, last, t)
				last = t
				t = math.min(t + dt, scene.seconds)
				if last == scene.seconds then
					break
				end
			end
			expect(fired).toBe(#scene.cues)
		end
	end
end)

test("Krampus tiptoes in from behind and ends on his spawn", function()
	expect(Cutscenes.krampusIntro(0).Position.Z).toBe(16)
	local mid = Cutscenes.krampusIntro(1.65).Position
	expect(mid.Z > 0 and mid.Z < 16).toBeTruthy()
	local done = Cutscenes.krampusIntro(4)
	expect(done.Position.Magnitude).toBeLessThan(1e-6)
end)

test("the getaway sleigh strains low, then climbs and flies forward", function()
	expect(Cutscenes.getawaySleigh(1).Position.Y).toBeLessThan(2)
	local final = Cutscenes.getawaySleigh(4).Position
	expect(final.Y).toBeGreaterThan(60)
	expect(final.Z).toBeLessThan(-100) -- models face -Z
end)

test("Krampus belly-flops short of the deck and ends face down", function()
	local start = CFrame.new(0, 5, 60)
	local deck = Vector3.new(0, 0, 0)
	local before = Cutscenes.krampusFlop(0.5, start, deck)
	expect((before.Position - start.Position).Magnitude).toBeLessThan(1e-6)
	local flopped = Cutscenes.krampusFlop(4, start, deck)
	expect(flopped.Position.Z).toBeNear(8, 1e-4) -- 8 studs short of the deck
	expect(flopped.Position.Y).toBeNear(5, 1e-4) -- back on the ground
	-- Face down: his up vector now points along the ground.
	expect(math.abs(flopped.UpVector.Y)).toBeLessThan(0.05)
	-- Already on the deck: he flops where he stands instead of overshooting.
	local close = Cutscenes.krampusFlop(4, CFrame.new(0, 5, 3), deck)
	expect(close.Position.Z).toBeNear(3, 1e-4)
end)
