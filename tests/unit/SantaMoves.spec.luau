-- The playable Santa's animation rules (shared/SantaMoves.luau).
local SantaMoves = load("ReplicatedStorage.Shared.SantaMoves")
local Config = load("ReplicatedStorage.Shared.Config")

local ALL = { Idle = true, Walk = true, Sneak = true, Grab = true, Cheer = true }

describe("SantaMoves.loopFor", function()
	it("idles when standing still, even in the sneak phase", function()
		expect(SantaMoves.loopFor(0, false, ALL)).toBe("Idle")
		expect(SantaMoves.loopFor(0.2, true, ALL)).toBe("Idle")
	end)

	it("walks normally and tiptoes during the sneak phase", function()
		expect(SantaMoves.loopFor(Config.Player.WalkSpeed, false, ALL)).toBe("Walk")
		expect(SantaMoves.loopFor(Config.Player.WalkSpeed, true, ALL)).toBe("Sneak")
	end)

	it("walks if there is no Sneak clip", function()
		expect(SantaMoves.loopFor(10, true, { Idle = true, Walk = true })).toBe("Walk")
	end)
end)

describe("SantaMoves.loopSpeed", function()
	it("plays the walk at normal speed at normal walk speed", function()
		expect(SantaMoves.loopSpeed("Walk", Config.Player.WalkSpeed)).toBe(1)
	end)

	it("speeds up for Peppermint Rush and clamps the extremes", function()
		local rush = Config.Buys.PeppermintRush.WalkSpeed
		expect(SantaMoves.loopSpeed("Walk", rush) > 1).toBe(true)
		expect(SantaMoves.loopSpeed("Walk", 1000)).toBe(1.8)
		expect(SantaMoves.loopSpeed("Sneak", 1)).toBe(0.6)
	end)

	it("never changes the idle", function()
		expect(SantaMoves.loopSpeed("Idle", 40)).toBe(1)
	end)
end)

describe("SantaMoves encode/decode", function()
	it("round-trips a one-shot", function()
		expect(SantaMoves.decode(SantaMoves.encode("Grab", 3))).toBe("Grab")
		expect(SantaMoves.decode(SantaMoves.encode("Cheer", 12))).toBe("Cheer")
	end)

	it("ignores loops, unknown moves and junk", function()
		expect(SantaMoves.decode("Walk#1")).toBeNil()
		expect(SantaMoves.decode("Dance#1")).toBeNil()
		expect(SantaMoves.decode("Grab")).toBeNil()
		expect(SantaMoves.decode(nil)).toBeNil()
		expect(SantaMoves.decode(5)).toBeNil()
	end)
end)

describe("SantaMoves.play", function()
	it("sets a fresh value each time on a Santa, so repeats still fire", function()
		local character = Instance.new("Model")
		character:SetAttribute(SantaMoves.SANTA_ATTRIBUTE, true)
		SantaMoves.play(character, "Grab")
		local first = character:GetAttribute(SantaMoves.MOVE_ATTRIBUTE)
		SantaMoves.play(character, "Grab")
		local second = character:GetAttribute(SantaMoves.MOVE_ATTRIBUTE)
		expect(SantaMoves.decode(first)).toBe("Grab")
		expect(SantaMoves.decode(second)).toBe("Grab")
		expect(first ~= second).toBe(true)
	end)

	it("does nothing to a default avatar, a missing character or an unknown move", function()
		local avatar = Instance.new("Model")
		SantaMoves.play(avatar, "Grab")
		expect(avatar:GetAttribute(SantaMoves.MOVE_ATTRIBUTE)).toBeNil()
		SantaMoves.play(nil, "Cheer")
		local santa = Instance.new("Model")
		santa:SetAttribute(SantaMoves.SANTA_ATTRIBUTE, true)
		SantaMoves.play(santa, "Dance")
		expect(santa:GetAttribute(SantaMoves.MOVE_ATTRIBUTE)).toBeNil()
	end)

	it("has a speed for every one-shot and the clips the spec makes", function()
		local json = readSource("art/meshy/Santa.json")
		for move, opts in SantaMoves.ONE_SHOTS do
			expect(opts.speed > 0).toBe(true)
			expect(string.find(json, '"' .. move .. '"', 1, true) ~= nil).toBe(true)
		end
		for _, loop in SantaMoves.LOOPS do
			expect(string.find(json, '"' .. loop .. '"', 1, true) ~= nil).toBe(true)
		end
	end)
end)
