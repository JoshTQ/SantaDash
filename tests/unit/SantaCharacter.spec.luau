-- The Meshy Santa becomes StarterPlayer.StarterCharacter only when it is usable.
local SantaCharacter = load("ServerScriptService.Server.SantaCharacter")
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

local function santa(clips: { string }?, rigType: any?)
	local m = Instance.new("Model")
	m.Name = "Santa"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.Parent = m
	local body = Instance.new("MeshPart")
	body.Name = "Body"
	body.Anchored = true
	body.Parent = m
	m.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = rigType or Enum.HumanoidRigType.R15
	humanoid.Parent = m
	local folder = Instance.new("Folder")
	folder.Name = "Animations"
	for _, clip in clips or { "Idle", "Walk", "Sneak", "Grab", "Cheer" } do
		local a = Instance.new("Animation")
		a.Name = clip
		a.Parent = folder
	end
	folder.Parent = m
	m.Parent = assetsFolder()
	return m
end

local function sack()
	local m = Instance.new("Model")
	m.Name = "SantaSack"
	local p = Instance.new("MeshPart")
	p.Name = "Sack"
	p.Anchored = true
	p.CanCollide = true
	p.Parent = m
	m.PrimaryPart = p
	m.Parent = assetsFolder()
	return m
end

describe("SantaCharacter.problem", function()
	beforeEach(function()
		services.ServerStorage:ClearAllChildren()
	end)

	it("accepts a complete R15 Santa", function()
		expect(SantaCharacter.problem(santa())).toBeNil()
	end)

	it("rejects a missing model, missing parts and missing core clips", function()
		expect(SantaCharacter.problem(nil)).toBe("no Santa model in ServerStorage.Assets")
		local noAnims = santa()
		noAnims.Animations:Destroy()
		expect(SantaCharacter.problem(noAnims)).toBe("Santa has no Animations")
		services.ServerStorage:ClearAllChildren()
		expect(SantaCharacter.problem(santa({ "Idle", "Sneak" }))).toBe("Santa has no Walk animation")
	end)

	it("rejects an R6 humanoid, which would ignore the hip height", function()
		expect(string.find(SantaCharacter.problem(santa(nil, Enum.HumanoidRigType.R6)) or "", "R15")).never.toBeNil()
	end)

	it("is fine without the optional Sneak, Grab and Cheer clips", function()
		expect(SantaCharacter.problem(santa({ "Idle", "Walk" }))).toBeNil()
	end)
end)

describe("SantaCharacter.build / install", function()
	beforeEach(function()
		services.ServerStorage:ClearAllChildren()
		services.StarterPlayer:ClearAllChildren()
	end)

	it("keeps default avatars when there is no Santa", function()
		expect(SantaCharacter.install()).toBe(false)
		expect(services.StarterPlayer:FindFirstChild("StarterCharacter")).toBeNil()
	end)

	it("installs an unanchored, marked StarterCharacter and leaves the template alone", function()
		local template = santa()
		expect(SantaCharacter.install()).toBe(true)
		local character = services.StarterPlayer:FindFirstChild("StarterCharacter")
		expect(character).never.toBeNil()
		expect(character:GetAttribute(SantaMoves.SANTA_ATTRIBUTE)).toBe(true)
		expect(character.HumanoidRootPart.Anchored).toBe(false)
		expect(character.Body.Anchored).toBe(false)
		expect(template.Parent).toBe(services.ServerStorage.Assets)
		expect(template.HumanoidRootPart.Anchored).toBe(true)
	end)

	it("replaces an older StarterCharacter", function()
		local old = Instance.new("Model")
		old.Name = "StarterCharacter"
		old.Parent = services.StarterPlayer
		santa()
		SantaCharacter.install()
		local found = 0
		for _, child in services.StarterPlayer:GetChildren() do
			if child.Name == "StarterCharacter" then
				found += 1
				expect(child ~= old).toBe(true)
			end
		end
		expect(found).toBe(1)
	end)

	it("welds the sack on his back without collisions or mass", function()
		santa()
		sack()
		local character = SantaCharacter.build()
		local bag = character:FindFirstChild("Sack")
		expect(bag).never.toBeNil()
		local part = bag.Sack
		expect(part.Anchored).toBe(false)
		expect(part.CanCollide).toBe(false)
		expect(part.Massless).toBe(true)
		local weld = part:FindFirstChildOfClass("WeldConstraint")
		expect(weld.Part0).toBe(character.HumanoidRootPart)
		expect(weld.Part1).toBe(part)
		-- behind him (+Z) is his back; forward is -Z
		expect(part.CFrame.Position.Z > character.HumanoidRootPart.CFrame.Position.Z).toBe(true)
	end)

	it("goes without a sack if there isn't one", function()
		santa()
		local character = SantaCharacter.build()
		expect(character:FindFirstChild("Sack")).toBeNil()
	end)
end)

describe("SantaCharacter.setSneaking", function()
	it("sets the player attribute the client reads", function()
		local player = Instance.new("Folder") -- stands in for a Player: only attributes are used
		SantaCharacter.setSneaking(player :: any, true)
		expect(player:GetAttribute(SantaMoves.SNEAK_ATTRIBUTE)).toBe(true)
		SantaCharacter.setSneaking(player :: any, false)
		expect(player:GetAttribute(SantaMoves.SNEAK_ATTRIBUTE)).toBe(false)
	end)
end)
