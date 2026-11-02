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

describe("weightedPick edge cases", function()
	it("falls back to the last non-zero entry on floating point leftovers", function()
		local overshoot = {
			NextNumber = function()
				return 1.000001
			end,
		}
		expect(Util.weightedPick(overshoot :: any, { { "a", 1 }, { "b", 2 }, { "c", 0 } })).toBe("b")
	end)

	it("returns the first entry when every weight is zero", function()
		expect(Util.weightedPick(Random.new(1), { { "a", 0 }, { "b", 0 } })).toBe("a")
	end)
end)

describe("character helpers", function()
	local function fakePlayer(withHumanoid: boolean)
		local root = { CFrame = CFrame.new(), AssemblyLinearVelocity = Vector3.new(5, 5, 5) }
		local humanoid = { RootPart = root }
		local character = {
			FindFirstChildOfClass = function(_, className)
				return if withHumanoid and className == "Humanoid" then humanoid else nil
			end,
		}
		return { Character = character }, root
	end

	it("finds the humanoid and its root part", function()
		local player, root = fakePlayer(true)
		expect(Util.humanoidOf(player :: any)).never.toBeNil()
		expect(Util.rootOf(player :: any)).toBe(root)
	end)

	it("handles players without a character or humanoid", function()
		expect(Util.humanoidOf({ Character = nil } :: any)).toBeNil()
		expect(Util.rootOf({ Character = nil } :: any)).toBeNil()
		local player = fakePlayer(false)
		expect(Util.rootOf(player :: any)).toBeNil()
		Util.teleport(player :: any, CFrame.new(1, 2, 3)) -- no error, nothing to move
	end)

	it("teleport moves the root and clears its velocity", function()
		local player, root = fakePlayer(true)
		Util.teleport(player :: any, CFrame.new(10, 20, 30))
		expect(root.CFrame.Position.X).toBe(10)
		expect(root.CFrame.Position.Y).toBe(20)
		expect(root.AssemblyLinearVelocity.Magnitude).toBe(0)
	end)
end)
