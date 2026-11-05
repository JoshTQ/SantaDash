-- Wearing a suit swaps only Santa's "Body" mesh: the Humanoid, root, clips
-- and sack stay, the new body sits on the same Motor6D, and a missing suit
-- model keeps the classic look.
local Skins = load("ServerScriptService.Server.Skins")
local SantaMoves = load("ReplicatedStorage.Shared.SantaMoves")

local function assetsFolder()
	local folder = services.ServerStorage:FindFirstChild("Assets")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Assets"
		folder.Parent = services.ServerStorage
	end
	return folder
end

-- A model with a root and a Body mesh, like an imported Santa or suit.
local function rig(name: string, tag: string)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = m
	local body = Instance.new("MeshPart")
	body.Name = "Body"
	body:SetAttribute("Tag", tag)
	body.Parent = m
	local bone = Instance.new("Bone")
	bone.Name = "Spine"
	bone.Parent = body
	local motor = Instance.new("Motor6D")
	motor.Name = "Root"
	motor.Part0 = root
	motor.Part1 = body
	motor.C0 = CFrame.new(0, -0.5, 0)
	motor.Parent = body
	return m
end

local function character()
	local c = rig("StarterCharacter", "classic")
	c:SetAttribute(SantaMoves.SANTA_ATTRIBUTE, true)
	c:SetAttribute(SantaMoves.SKIN_ATTRIBUTE, "Classic")
	local animations = Instance.new("Folder")
	animations.Name = "Animations"
	animations.Parent = c
	c.Parent = workspace
	return c
end

describe("Skins.apply", function()
	beforeEach(function()
		services.ServerStorage:ClearAllChildren()
		rig("Santa", "classic").Parent = assetsFolder()
		rig("SantaShark", "shark").Parent = assetsFolder()
	end)

	it("swaps in the suit's body on the same motor, keeping the rest", function()
		local c = character()
		local root = c.HumanoidRootPart
		expect(Skins.apply(c, "SharkySuit")).toBe("SharkySuit")
		local body = c:FindFirstChild("Body")
		expect(body:GetAttribute("Tag")).toBe("shark")
		expect(body:FindFirstChild("Spine")).never.toBeNil()
		local motors = {}
		for _, d in body:GetChildren() do
			if d:IsA("Motor6D") then
				table.insert(motors, d)
			end
		end
		expect(#motors).toBe(1)
		expect(motors[1].Part0).toBe(root)
		expect(motors[1].C0).toEqual(CFrame.new(0, -0.5, 0))
		expect(c:FindFirstChild("Animations")).never.toBeNil()
		expect(c:GetAttribute(SantaMoves.SKIN_ATTRIBUTE)).toBe("SharkySuit")
		local count = 0
		for _, child in c:GetChildren() do
			if child.Name == "Body" then
				count += 1
			end
		end
		expect(count).toBe(1)
	end)

	it("adds the suit's trail, and Classic takes it off again", function()
		local c = character()
		Skins.apply(c, "SharkySuit")
		expect(c.HumanoidRootPart:FindFirstChild("SkinTrail")).never.toBeNil()
		expect(Skins.apply(c, "Classic")).toBe("Classic")
		expect(c.Body:GetAttribute("Tag")).toBe("classic")
		expect(c.HumanoidRootPart:FindFirstChild("SkinTrail")).toBeNil()
	end)

	it("keeps the classic look when the suit's model isn't imported yet", function()
		local c = character()
		expect(Skins.apply(c, "ChromeSuit")).toBe("Classic")
		expect(c.Body:GetAttribute("Tag")).toBe("classic")
	end)

	it("does nothing to a default Roblox avatar", function()
		local c = character()
		c:SetAttribute(SantaMoves.SANTA_ATTRIBUTE, nil)
		expect(Skins.apply(c, "SharkySuit")).toBeNil()
		expect(c.Body:GetAttribute("Tag")).toBe("classic")
	end)

	it("doesn't rebuild the body when the suit is already on", function()
		local c = character()
		Skins.apply(c, "SharkySuit")
		local body = c.Body
		Skins.apply(c, "SharkySuit")
		expect(c.Body).toBe(body)
	end)
end)
