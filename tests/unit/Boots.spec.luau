-- Boots go on top of whatever suit Santa wears, carry their speeds to the
-- skating loop, and a missing model never takes away paid-for speed.
local Boots = load("ServerScriptService.Server.Boots")
local BootRules = load("ReplicatedStorage.Shared.BootRules")
local PlayerDefaults = load("ReplicatedStorage.Shared.PlayerDefaults")
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

local function rig(name: string)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = m
	local body = Instance.new("MeshPart")
	body.Name = "Body"
	body.Parent = m
	for _, b in { "LeftFoot", "RightFoot" } do
		local bone = Instance.new("Bone")
		bone.Name = b
		bone.Parent = body
	end
	local motor = Instance.new("Motor6D")
	motor.Part0 = root
	motor.Part1 = body
	motor.Parent = body
	return m
end

local function skates()
	local m = Instance.new("Model")
	m.Name = "SkateBoots"
	for _, side in { "Left", "Right" } do
		local p = Instance.new("Part")
		p.Name = side .. "Boot"
		p.Size = Vector3.new(1, 1, 1.4)
		p:SetAttribute("FollowBone", side .. "Foot")
		p.Parent = m
	end
	return m
end

local function owner()
	local data = PlayerDefaults.new()
	data.owned.SkateBoots = true
	data.boots = "SkateBoots"
	return data
end

local function character()
	local c = rig("StarterCharacter")
	c:SetAttribute(SantaMoves.SANTA_ATTRIBUTE, true)
	c.Parent = workspace
	return c
end

describe("Boots.apply", function()
	local boot
	beforeEach(function()
		services.ServerStorage:ClearAllChildren()
		rig("Santa").Parent = assetsFolder()
		rig("SantaShark").Parent = assetsFolder()
		skates().Parent = assetsFolder()
		boot = BootRules.get("SkateBoots")
		boot.ready = true
	end)
	afterEach(function()
		boot.ready = false
	end)

	it("puts one pair on, with speeds and a trail that shows only on ice", function()
		local c = character()
		expect(Boots.apply(c, owner())).toBe("SkateBoots")
		expect(Boots.apply(c, owner())).toBe("SkateBoots") -- again: no second pair
		local gear = c.Gear:GetChildren()
		expect(#gear).toBe(1)
		expect(gear[1]:FindFirstChild("LeftBoot")).never.toBeNil()
		expect(c:GetAttribute("SkateBoots")).toBe("SkateBoots")
		expect(c:GetAttribute("SkateSpeed")).toBe(boot.skateSpeed)
		expect(c:GetAttribute("HoopSpeed")).toBe(boot.hoopSpeed)
		local trail = gear[1].LeftBoot:FindFirstChild("BootTrail")
		expect(trail.Enabled).toBe(false)
		Boots.setOnIce(c, true)
		expect(trail.Enabled).toBe(true)
		Boots.setOnIce(c, false)
		expect(trail.Enabled).toBe(false)
	end)

	it("stays on through a suit change", function()
		local c = character()
		Boots.apply(c, owner())
		Skins.apply(c, "SharkySuit")
		expect(#c.Gear:GetChildren()).toBe(1)
		expect(c.Gear:GetChildren()[1].LeftBoot.GearWeld.Part0).toBe(c.HumanoidRootPart)
	end)

	it("takes them off, and clears the speeds", function()
		local c = character()
		Boots.apply(c, owner())
		local data = owner()
		data.boots = ""
		expect(Boots.apply(c, data)).toBeNil()
		expect(#c.Gear:GetChildren()).toBe(0)
		expect(c:GetAttribute("SkateSpeed")).toBeNil()
		expect(c:GetAttribute("SkateBoots")).toBeNil()
	end)

	it("keeps the paid-for speed even if the model isn't imported", function()
		assetsFolder().SkateBoots:Destroy()
		local c = character()
		expect(Boots.apply(c, owner())).toBeNil()
		expect(c:GetAttribute("SkateSpeed")).toBe(boot.skateSpeed)
	end)
end)
