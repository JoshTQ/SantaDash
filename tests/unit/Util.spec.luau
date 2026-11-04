local Util = load("ReplicatedStorage.Shared.Util")

test("weightedPick never returns a zero-weight entry", function()
	local rng = Random.new(9)
	for _ = 1, 500 do
		expect(Util.weightedPick(rng, { { "a", 0 }, { "b", 1 }, { "c", 0 } })).toBe("b")
	end
end)

test("weightedPick roughly follows the weights", function()
	local rng = Random.new(10)
	local hits = 0
	for _ = 1, 2000 do
		if Util.weightedPick(rng, { { "x", 3 }, { "y", 1 } }) == "x" then
			hits += 1
		end
	end
	expect(hits / 2000).toBeNear(0.75, 0.05)
end)

test("removeValue removes the first match only", function()
	local list = { 1, 2, 3, 2 }
	expect(Util.removeValue(list, 2)).toBeTruthy()
	expect(table.concat(list, ",")).toBe("1,3,2")
	expect(Util.removeValue(list, 9)).toBeFalsy()
end)
