-- Body heat, warm gear and where a frozen Santa washes up (Josh's playtest,
-- 6 Nov 2026: swim in the Lair, worry about body heat, buy warm clothes).
local Config = load("ReplicatedStorage.Shared.Config")
local BodyHeat = load("ReplicatedStorage.Shared.BodyHeat")
local Wardrobe = load("ReplicatedStorage.Shared.Wardrobe")
local Swimming = load("ServerScriptService.Server.Swimming")
local SantaMoves = load("ReplicatedStorage.Shared.SantaMoves")
local H = Config.BodyHeat

describe("BodyHeat", function()
	it("drains only while swimming, in SwimSeconds with no gear", function()
		expect(BodyHeat.step(1, H.SwimSeconds / 2, "Swimming", 0)).toBeNear(0.5, 1e-6)
		expect(BodyHeat.step(1, H.SwimSeconds, "Swimming", 0)).toBe(0)
		expect(BodyHeat.step(1, 100, "Swimming", 0)).toBe(0) -- never below 0
		expect(BodyHeat.step(0.5, 1, "Land", 0)).toBeGreaterThan(0.5)
	end)

	it("warm gear stretches swim time; fires warm you faster than land", function()
		expect(BodyHeat.swimSeconds(0.5)).toBe(H.SwimSeconds * 1.5)
		expect(BodyHeat.step(1, H.SwimSeconds, "Swimming", 1)).toBeNear(0.5, 1e-6)
		expect(BodyHeat.swimSeconds(-1)).toBe(H.SwimSeconds)
		local land = BodyHeat.step(0, 1, "Land", 0)
		local fire = BodyHeat.step(0, 1, "Fire", 0)
		expect(fire).toBeGreaterThan(land)
		expect(BodyHeat.step(0.9, 100, "Fire", 0)).toBe(1)
	end)

	it("the HUD value moves in steps and the meter hides when you're warm", function()
		expect(BodyHeat.quantise(0.503)).toBeNear(0.5, 1e-9)
		expect(BodyHeat.quantise(2)).toBe(1)
		expect(BodyHeat.visible(1, false)).toBe(false)
		expect(BodyHeat.visible(0.5, false)).toBe(true)
		expect(BodyHeat.visible(1, true)).toBe(true)
		expect(BodyHeat.label(0.2, false)).toContain("BRRR")
		expect(BodyHeat.label(0.2, true)).toBe("FROZEN SOLID!")
		expect(BodyHeat.label(0.8, false)).toBe("BODY HEAT")
	end)
end)

describe("Wardrobe rules", function()
	it("sells sets A and D (approved, built from parts), never for Robux", function()
		expect(Config.Wardrobe.Enabled).toBe(true)
		expect(#Wardrobe.onSale()).toBe(4)
		for _, id in Wardrobe.onSale() do
			local item = Wardrobe.item(id)
			expect(item.price > 0).toBe(true)
			expect(item.model).toBeTruthy()
			for _, product in Config.Store.Items do
				expect(product.id).never.toBe(id) -- not in the Robux store
			end
		end
	end)

	it("pieces add up; owning one doesn't block another; no buying twice", function()
		expect(Wardrobe.warmth({})).toBe(0)
		expect(Wardrobe.warmth({ Scarf = true, HotWaterBottle = true })).toBeNear(0.75, 1e-9)
		expect(Wardrobe.warmth({ Nonsense = true })).toBe(0)
		expect(Wardrobe.swimSpeed({ DuckieRing = true })).toBeGreaterThan(0)
		expect(Wardrobe.swimSpeed({ Scarf = true })).toBe(0)
		expect((Wardrobe.canBuy({ Scarf = true }, "Mittens"))).toBe(true)
		local ok, why = Wardrobe.canBuy({ Scarf = true }, "Scarf")
		expect(ok).toBe(false)
		expect(why).toContain("already")
		expect((Wardrobe.canBuy({}, "Nonsense"))).toBe(false)
	end)

	it("the full set lets you swim 2.25x as long", function()
		local all = {}
		for _, id in Wardrobe.onSale() do
			all[id] = true
		end
		expect(BodyHeat.swimSeconds(Wardrobe.warmth(all))).toBeNear(H.SwimSeconds * 2.25, 1e-9)
	end)

	it("encodes owned ids for the character attribute and back", function()
		local s = Wardrobe.encode({ Scarf = true, DuckieRing = true, Mittens = false })
		expect(s).toBe("DuckieRing,Scarf")
		local back = Wardrobe.decode(s)
		expect(back.Scarf).toBe(true)
		expect(back.Mittens).toBeNil()
		expect(next(Wardrobe.decode(nil))).toBeNil()
	end)
end)

describe("Swimming", function()
	local swim = {
		island = Vector3.new(0, 0, 470),
		islandRadius = 58,
		warmRadius = 70,
		bridgeFrom = Vector3.new(0, 0, 294),
		bridgeTo = Vector3.new(0, 0, 416),
	}

	it("washes a frozen Santa up on the nearest of the bridge and the island", function()
		local byBridge = Swimming.shorePoint(swim, Vector3.new(20, 0, 340))
		expect(byBridge.X).toBe(0)
		expect(byBridge.Z).toBeNear(340, 1e-6)
		expect(byBridge.Y).toBe(4)
		local byIsland = Swimming.shorePoint(swim, Vector3.new(100, 0, 470))
		expect(byIsland.X).toBeNear(swim.islandRadius - 4, 1e-6)
		local beyond = Swimming.shorePoint(swim, Vector3.new(0, 0, 200)) -- past the bridge's end
		expect(beyond.Z).toBeNear(294, 1e-6)
	end)

	it("knows swimming, by the fire and plain land apart", function()
		expect(Swimming.where(swim, swim.island, true)).toBe("Swimming")
		expect(Swimming.where(swim, swim.island + Vector3.new(65, 0, 0), false)).toBe("Fire")
		expect(Swimming.where(swim, Vector3.new(0, 0, 300), false)).toBe("Land")
	end)

	it("puts the water under the lake ice", function()
		local lake = Instance.new("Part")
		lake.Size = Vector3.new(300, 0.25, 340)
		lake.CFrame = CFrame.new(0, 0.125, 470)
		local cframe, size = Swimming.waterBlock(lake)
		expect(size.X).toBe(300)
		expect(cframe.Position.Y + size.Y / 2).toBeNear(H.WaterTop, 1e-6)
		expect(Swimming.fillWater(lake)).toBeTruthy() -- no Terrain here: a no-op undo
	end)

	it("Santa paddles with Walk until the Meshy spec has a Swim clip", function()
		expect(SantaMoves.loopFor(0, false, { Walk = true }, true)).toBe("Walk")
		expect(SantaMoves.loopFor(0, false, { Walk = true, Swim = true }, true)).toBe("Swim")
		expect(SantaMoves.loopFor(5, false, { Walk = true, Swim = true }, false)).toBe("Walk")
	end)
end)

describe("WearBuilder", function()
	local WearBuilder = load("ServerScriptService.Server.WearBuilder")
	local BONES = { Spine = true, Hips = true, LeftHand = true, RightHand = true }

	it("builds every piece on sale, around Santa's root, following a bone", function()
		for _, id in Wardrobe.onSale() do
			local m = WearBuilder.build(id)
			expect(m).toBeTruthy()
			expect(m.Name).toBe(Wardrobe.item(id).model)
			expect(m.PrimaryPart.Name).toBe("Root")
			expect(m.PrimaryPart.CFrame.Position.Magnitude).toBeLessThan(1e-6)
			local holders, parts = 0, 0
			for _, d in m:GetDescendants() do
				local bone = d:GetAttribute("FollowBone")
				if bone then
					holders += 1
					expect(BONES[bone]).toBe(true)
				end
				if d:IsA("BasePart") and d ~= m.PrimaryPart then
					parts += 1
					expect(d.CanCollide).toBe(false)
					-- worn on a 5.5-stud Santa whose root is 3 studs over his feet
					local p = d.CFrame.Position
					expect(p.Y).toBeGreaterThan(-3)
					expect(p.Y).toBeLessThan(2.5)
					expect(math.abs(p.X)).toBeLessThan(2.5)
				end
			end
			expect(holders).toBeGreaterThan(0)
			expect(parts).toBeLessThan(30) -- light enough for phones
		end
		expect(WearBuilder.build("Nonsense")).toBeNil()
	end)

	it("mittens are one model with a mitten on each hand, Santa facing -Z", function()
		local m = WearBuilder.build("Mittens")
		local right = m:FindFirstChild("RightMitten")
		local left = m:FindFirstChild("LeftMitten")
		expect(right:GetAttribute("FollowBone")).toBe("RightHand")
		expect(left:GetAttribute("FollowBone")).toBe("LeftHand")
		-- facing -Z, his right is +X
		expect(right:FindFirstChild("Mitten").CFrame.Position.X).toBeGreaterThan(0)
		expect(left:FindFirstChild("Mitten").CFrame.Position.X).toBeLessThan(0)
	end)

	it("the duck and the bottle face the front (-Z)", function()
		local duck = WearBuilder.build("DuckieRing"):FindFirstChild("DuckHead", true)
		expect(duck.CFrame.Position.Z).toBeLessThan(0)
		local bottle = WearBuilder.build("HotWaterBottle"):FindFirstChild("Bottle", true)
		expect(bottle.CFrame.Position.Z).toBeLessThan(0)
	end)
end)
