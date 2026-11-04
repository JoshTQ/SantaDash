local Config = load("ReplicatedStorage.Shared.Config")
local ElfBrain = load("ServerScriptService.Server.ElfBrain")
local E = Config.ElfBots

test("only solo crews get elf bots", function()
	expect(ElfBrain.wantsBots(1)).toBeTruthy()
	expect(ElfBrain.wantsBots(2)).toBeFalsy()
end)

test("two bots are always one of design A and one of design D", function()
	for seed = 1, 50 do
		local picks = ElfBrain.pickVariants(Random.new(seed), 2)
		expect(#picks).toBe(2)
		expect(picks[1] ~= picks[2]).toBeTruthy()
		for _, name in picks do
			expect(name == "ElfA" or name == "ElfD").toBeTruthy()
		end
	end
end)

test("both designs lead the pair over many runs", function()
	local firsts = {}
	local rng = Random.new(1)
	for _ = 1, 50 do
		firsts[ElfBrain.pickVariants(rng, 2)[1]] = true
	end
	expect(firsts.ElfA).toBeTruthy()
	expect(firsts.ElfD).toBeTruthy()
end)

test("more bots than designs still only uses known designs", function()
	local picks = ElfBrain.pickVariants(Random.new(7), 5)
	expect(#picks).toBe(5)
	for _, name in picks do
		expect(E.StandIn[name] ~= nil).toBeTruthy()
	end
end)

test("bots grab the nearest present within range of their Santa", function()
	local owner = Vector3.new(0, 0, 0)
	local near = { present = "near", position = Vector3.new(5, 0, 0) }
	local far = { present = "far", position = Vector3.new(15, 0, 0) }
	local outOfRange = { present = "out", position = Vector3.new(E.GrabRange + 1, 0, 0) }
	expect(ElfBrain.pickPresent(owner, { far, near, outOfRange }).present).toBe("near")
	expect(ElfBrain.pickPresent(owner, { outOfRange })).toBe(nil)
end)

test("bots stand behind their Santa on alternate sides", function()
	local a, b = ElfBrain.followOffset(1), ElfBrain.followOffset(2)
	expect(a.X * b.X).toBeLessThan(0)
	expect(a.Z).toBeGreaterThan(0)
	expect(b.Z).toBeGreaterThan(0)
end)
