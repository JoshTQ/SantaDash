-- Gear worn over any suit (boots, mittens, scarves): built once, it follows
-- Santa's bones, so it fits every suit and survives a suit swap.
local GearAttach = load("ReplicatedStorage.Shared.GearAttach")

local function near(a: CFrame, b: CFrame): boolean
	local d = a:Inverse() * b
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d:GetComponents()
	return d.Position.Magnitude < 1e-3
		and math.abs(r00 - 1) < 1e-3
		and math.abs(r11 - 1) < 1e-3
		and math.abs(r22 - 1) < 1e-3
		and math.abs(r01)
				+ math.abs(r02)
				+ math.abs(r10)
				+ math.abs(r12)
				+ math.abs(r20)
				+ math.abs(r21)
			< 1e-3
end

-- A Santa: root, Body mesh with foot and hand bones.
local function santa(boneNames: { string }?)
	local m = Instance.new("Model")
	m.Name = "Santa"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.CFrame = CFrame.new(10, 3, 5)
	root.Parent = m
	local body = Instance.new("MeshPart")
	body.Name = "Body"
	body.Parent = m
	for _, name in boneNames or { "LeftFoot", "RightFoot", "LeftHand", "RightHand" } do
		local bone = Instance.new("Bone")
		bone.Name = name
		bone.Parent = body
	end
	return m, root
end

local function part(name: string, cf: CFrame, parent: Instance)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Boots: one model, LeftBoot and RightBoot on the foot bones, pivot at the root.
local function boots()
	local m = Instance.new("Model")
	m.Name = "SkateBoots"
	local pivot = part("Root", CFrame.new(0, 0, 0), m)
	m.PrimaryPart = pivot
	local l = part("LeftBoot", CFrame.new(-0.6, -2.6, 0), m)
	l:SetAttribute("FollowBone", "LeftFoot")
	local r = part("RightBoot", CFrame.new(0.6, -2.6, 0), m)
	r:SetAttribute("FollowBone", "RightFoot")
	local weld = Instance.new("WeldConstraint")
	weld.Parent = l
	return m
end

describe("GearAttach", function()
	it("puts a copy of the gear in the character's Gear folder, massless and welded to the root", function()
		local char, root = santa()
		local model = boots()
		local copy = GearAttach.equip(char, model) :: Model
		expect(copy).never.toBeNil()
		expect(copy.Parent.Name).toBe("Gear")
		expect(copy.Parent.Parent).toBe(char)
		expect(model.Parent).toBeNil() -- the asset itself is untouched
		local left = copy:FindFirstChild("LeftBoot") :: BasePart
		expect(left.Anchored).toBe(false)
		expect(left.Massless).toBe(true)
		expect(left.CanCollide).toBe(false)
		expect(left:FindFirstChildOfClass("WeldConstraint")).toBeNil() -- old joints stripped
		local weld = left:FindFirstChild("GearWeld") :: Weld
		expect(weld.Part0).toBe(root)
		expect(weld.Part1).toBe(left)
		expect(near(weld.C0, CFrame.new(-0.6, -2.6, 0))).toBe(true)
		expect(near(left.CFrame, root.CFrame * CFrame.new(-0.6, -2.6, 0))).toBe(true)
		expect(left:GetAttribute("FollowBone")).toBe("LeftFoot")
		expect(near(left:GetAttribute("GearRest"), CFrame.new(-0.6, -2.6, 0))).toBe(true)
	end)

	it("replaces gear with the same id and lists what's worn", function()
		local char = santa()
		GearAttach.equip(char, boots())
		GearAttach.equip(char, boots())
		local scarf = Instance.new("Model")
		scarf.Name = "WearScarf"
		part("Scarf", CFrame.new(0, 1, 0), scarf)
		GearAttach.equip(char, scarf)
		expect(#char.Gear:GetChildren()).toBe(2)
		local worn = GearAttach.worn(char)
		expect(worn[1]).toBe("SkateBoots")
		expect(worn[2]).toBe("WearScarf")
		expect(GearAttach.unequip(char, "SkateBoots")).toBe(true)
		expect(GearAttach.unequip(char, "SkateBoots")).toBe(false)
		expect(#GearAttach.worn(char)).toBe(1)
	end)

	it("needs a root, and unequip with no gear is a no-op", function()
		local m = Instance.new("Model")
		expect(GearAttach.equip(m, boots())).toBeNil()
		expect(GearAttach.unequip(m, "SkateBoots")).toBe(false)
		expect(#GearAttach.worn(m)).toBe(0)
	end)

	it("lets mittens be one model with a child model per hand", function()
		local char = santa()
		local mittens = Instance.new("Model")
		mittens.Name = "WearMittens"
		for _, side in { "Left", "Right" } do
			local hand = Instance.new("Model")
			hand.Name = side
			hand:SetAttribute("FollowBone", side .. "Hand")
			part(side .. "Cuff", CFrame.new(0, 0, 0), hand)
			part(side .. "Thumb", CFrame.new(0, 0.3, 0), hand)
			hand.Parent = mittens
		end
		local copy = GearAttach.equip(char, mittens) :: Model
		local thumb = copy:FindFirstChild("Right"):FindFirstChild("RightThumb")
		expect(thumb:GetAttribute("FollowBone")).toBe("RightHand")
		expect(copy:FindFirstChild("Left"):FindFirstChild("LeftCuff"):GetAttribute("FollowBone")).toBe(
			"LeftHand"
		)
	end)

	it("keeps parts in place inside a holder that has an explicit Offset", function()
		local char = santa()
		local gear = Instance.new("Model")
		gear.Name = "WearHat"
		local holder = Instance.new("Model")
		holder:SetAttribute("FollowBone", "Head")
		holder:SetAttribute("Offset", CFrame.new(0, 1, 0))
		local base = part("Base", CFrame.new(5, 5, 5), holder)
		holder.PrimaryPart = base
		local bobble = part("Bobble", CFrame.new(5, 6, 5), holder)
		holder.Parent = gear
		GearAttach.equip(char, gear)
		expect(near(base:GetAttribute("GearOffset") or CFrame.new(99, 0, 0), CFrame.new(99, 0, 0))).toBe(true) -- the asset isn't changed
		local copy = char.Gear.WearHat
		local cb = copy:FindFirstChildOfClass("Model"):FindFirstChild("Base")
		local cbo = copy:FindFirstChildOfClass("Model"):FindFirstChild("Bobble")
		expect(near(cb:GetAttribute("GearOffset"), CFrame.new(0, 1, 0))).toBe(true)
		expect(near(cbo:GetAttribute("GearOffset"), CFrame.new(0, 2, 0))).toBe(true)
		expect(bobble.Parent).toBe(holder)
	end)

	it("finds bones by name or alias, case-insensitively, only inside the Body", function()
		local char = santa({ "leftankle", "mixamorig:RightFoot" })
		expect(GearAttach.findBone(char, "LeftFoot").Name).toBe("leftankle")
		expect(GearAttach.findBone(char, "RightFoot").Name).toBe("mixamorig:RightFoot")
		expect(GearAttach.findBone(char, "Head")).toBeNil()
		expect(GearAttach.findBone(Instance.new("Model"), "LeftFoot")).toBeNil()
		local names = GearAttach.boneNames("LeftFoot")
		expect(names[1]).toBe("LeftFoot")
		expect(#GearAttach.boneNames("Tail")).toBe(1)
	end)

	it("finds the nearest FollowBone at or above a part", function()
		local m = Instance.new("Model")
		m:SetAttribute("FollowBone", "Hips")
		local inner = Instance.new("Model")
		inner:SetAttribute("FollowBone", "LeftFoot")
		inner.Parent = m
		local a = part("A", CFrame.new(), inner)
		local b = part("B", CFrame.new(), m)
		expect((GearAttach.boneFor(a, m))).toBe("LeftFoot")
		expect((GearAttach.boneFor(b, m))).toBe("Hips")
		local plain = Instance.new("Model")
		expect((GearAttach.boneFor(part("C", CFrame.new(), plain), plain))).toBeNil()
	end)

	it("moves a piece with its bone: offset from the bind pose, then the animated pose", function()
		local root = CFrame.new(10, 3, 5) * CFrame.Angles(0, math.rad(90), 0)
		local restBone = CFrame.new(-0.5, -2.5, 0) -- root space, at rest
		local restC0 = CFrame.new(-0.6, -2.6, 0.1) -- the boot, root space, at rest
		local offset = GearAttach.partOffset(restBone, restC0)
		-- At rest, the weld puts the boot right where it was modelled.
		expect(near(GearAttach.weldC0(root, root * restBone, offset), restC0)).toBe(true)
		-- Kick the foot forward: the boot goes with it.
		local kicked = root * restBone * CFrame.new(0, 0, -1) * CFrame.Angles(math.rad(30), 0, 0)
		local c0 = GearAttach.weldC0(root, kicked, offset)
		expect(near(root * c0, kicked * offset)).toBe(true)
		-- An explicit offset wins over the bind pose.
		expect(near(GearAttach.partOffset(restBone, restC0, CFrame.new(1, 2, 3)), CFrame.new(1, 2, 3))).toBe(
			true
		)
	end)

	it("nudges only the suits and bones Config lists", function()
		expect(near(GearAttach.nudge("ChromeSuit", "LeftFoot"), CFrame.new())).toBe(true)
		expect(near(GearAttach.nudge(nil, nil), CFrame.new())).toBe(true)
	end)
end)
