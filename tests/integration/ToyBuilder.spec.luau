-- The approved toys (Josh, 13 Nov 2026: "Do it" on the 3D preview of the
-- Candy Cane Catapult and Shaken Snow Globe), built from parts.
local ToyBuilder = load("ServerScriptService.Server.ToyBuilder")

local function partsOf(model)
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

describe("ToyBuilder", function()
	test("both toys stay small: phones carry one per Santa", function()
		expect(#partsOf(ToyBuilder.gear("Catapult"))).toBeLessThanOrEqual(17) -- 16 + the hidden Root
		expect(#partsOf(ToyBuilder.gear("Globe"))).toBeLessThanOrEqual(9)
		expect(ToyBuilder.gear("Nope")).toBeNil()
	end)

	test("held: the catapult in the right hand, the globe in the left, no collisions", function()
		for id, bone in { Catapult = "RightHand", Globe = "LeftHand" } do
			local m = ToyBuilder.gear(id)
			expect(m.Name).toBe(ToyBuilder.MODELS[id])
			expect(m.PrimaryPart.Name).toBe("Root")
			expect(m:FindFirstChild("Toy"):GetAttribute("FollowBone")).toBe(bone)
			for _, p in partsOf(m) do
				expect(p.CanCollide).toBe(false)
				if p.Name ~= "Root" then
					local side = p.CFrame.Position.X
					if bone == "RightHand" then
						expect(side).toBeGreaterThan(0.5)
					else
						expect(side).toBeLessThan(-0.5)
					end
				end
			end
		end
	end)

	test("the catapult fires forward (-Z) and has a snowball in its spoon", function()
		local m = ToyBuilder.gear("Catapult")
		local spoon, cuff = m:FindFirstChild("Spoon", true), m:FindFirstChild("Cuff", true)
		expect(spoon.CFrame.Position.Z).toBeLessThan(cuff.CFrame.Position.Z - 0.5)
		expect(m:FindFirstChild("Snowball", true)).never.toBeNil()
	end)

	test("the globe has a see-through glass with glitter inside", function()
		local m = ToyBuilder.gear("Globe")
		local glass = m:FindFirstChild("Glass", true)
		expect(glass.Transparency).toBeGreaterThan(0.3)
		expect(glass:FindFirstChild("Glitter"):FindFirstChildOfClass("ParticleEmitter")).never.toBeNil()
	end)

	test("on the stand they sit on the table, bigger", function()
		local folder = Instance.new("Folder")
		local m = ToyBuilder.display("Globe", folder, CFrame.new(0, 2, 0))
		expect(m.Parent).toBe(folder)
		for _, p in partsOf(m) do
			expect(p.Anchored).toBe(true)
			local r = p.CFrame
			local halfY = math.abs(r.RightVector.Y) * p.Size.X / 2
				+ math.abs(r.UpVector.Y) * p.Size.Y / 2
				+ math.abs(r.LookVector.Y) * p.Size.Z / 2
			expect(r.Position.Y - halfY).toBeGreaterThan(1.9)
		end
		local held = m:FindFirstChild("Glass", true).Size.X
		expect(held).toBeGreaterThan(ToyBuilder.gear("Globe"):FindFirstChild("Glass", true).Size.X)
	end)
end)
