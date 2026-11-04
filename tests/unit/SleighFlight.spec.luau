local Config = load("ReplicatedStorage.Shared.Config")
local SleighFlight = load("ReplicatedStorage.Shared.SleighFlight")

local FROM = CFrame.new(-90, 0, 70)
local TO = CFrame.new(160, 0, -40) * CFrame.Angles(0, math.rad(40), 0)
local SECONDS = Config.Run.FlightSeconds
local PEAK = Config.Run.FlightArcHeight

local function at(t)
	return SleighFlight.deckAt(FROM, TO, t, SECONDS, PEAK)
end

test("the flight starts and ends exactly on the decks", function()
	expect((at(0).Position - FROM.Position).Magnitude).toBeLessThan(1e-6)
	expect((at(SECONDS).Position - TO.Position).Magnitude).toBeLessThan(1e-6)
	expect(at(SECONDS).LookVector:Dot(TO.LookVector)).toBeNear(1, 1e-6)
end)

test("it runs along the snow before lifting off (no straight-up launch)", function()
	for t = 0.05, 1.2, 0.05 do
		expect(at(t).Position.Y).toBeNear(0, 1e-6)
	end
	-- and it is moving forward along the ground meanwhile
	expect((at(1.2).Position - FROM.Position).Magnitude).toBeGreaterThan(5)
end)

test("it climbs to cruise height and lands before the end", function()
	local top = 0
	for t = 0, SECONDS, 0.05 do
		top = math.max(top, at(t).Position.Y)
	end
	expect(top).toBeNear(PEAK, 1e-3)
	expect(at(SECONDS - 0.2).Position.Y).toBeNear(0, 1e-6) -- sliding on the runners
end)

test("nose up while climbing, nose down while gliding in", function()
	local climbing, gliding
	for t = 0, SECONDS, 0.02 do
		local s = SleighFlight.progress(t / SECONDS)
		if not climbing and s > 0.3 and s < 0.4 then
			climbing = at(t)
		elseif not gliding and s > 0.8 and s < 0.9 then
			gliding = at(t)
		end
	end
	expect(climbing.LookVector.Y).toBeGreaterThan(0.05)
	expect(gliding.LookVector.Y).toBeLessThan(-0.05)
end)

test("the path is smooth: no frame jumps or flips", function()
	local dt = 1 / 60
	local last = at(0)
	for i = 1, math.floor(SECONDS / dt) do
		local now = at(i * dt)
		expect((now.Position - last.Position).Magnitude).toBeLessThan(3)
		expect(now.LookVector:Dot(last.LookVector)).toBeGreaterThan(0.99)
		expect(now.UpVector.Y).toBeGreaterThan(0.8) -- never rolls or flips over
		last = now
	end
end)

test("it banks into a turn only while airborne", function()
	-- A flight that has to turn left: start facing -Z, end off to the left.
	local from, to = CFrame.new(0, 0, 0), CFrame.new(-150, 0, -80) * CFrame.Angles(0, math.rad(90), 0)
	local maxRoll = 0
	for t = 0, SECONDS, 0.05 do
		local deck = SleighFlight.deckAt(from, to, t, SECONDS, PEAK)
		local roll = deck.RightVector.Y -- > 0: right side up, leaning left
		if deck.Position.Y < 1e-6 then
			expect(math.abs(roll)).toBeLessThan(1e-6)
		end
		maxRoll = math.max(maxRoll, roll)
	end
	expect(maxRoll).toBeGreaterThan(0.05)
	expect(maxRoll).toBeLessThan(math.sin(SleighFlight.MaxBank) + 0.1)
end)

test("progress eases in and out", function()
	expect(SleighFlight.progress(0)).toBe(0)
	expect(SleighFlight.progress(1)).toBeNear(1, 1e-9)
	expect(SleighFlight.progress(0.5)).toBeNear(0.5, 1e-9)
	expect(SleighFlight.progress(0.1)).toBeLessThan(0.1)
end)

test("Takeoff lands on its THUMP: touch-down lines up with 4.6 s", function()
	local u = math.acos(1 - 2 * SleighFlight.TouchDownAt) / math.pi
	expect(u * SECONDS).toBeNear(4.6, 0.05)
end)
