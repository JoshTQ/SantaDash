-- Approved models are looked up in ServerStorage.Assets and fall back to
-- stand-ins when a model is missing or breaks its contract.
local Assets = load("ServerScriptService.Server.Assets")

local function model(name: string, children: { string }?)
	local m = Instance.new("Model")
	m.Name = name
	for _, child in children or {} do
		local p = Instance.new("Part")
		p.Name = child
		p.Parent = m
	end
	return m
end

local function assetsFolder()
	local folder = Instance.new("Folder")
	folder.Name = "Assets"
	folder.Parent = services.ServerStorage
	return folder
end

describe("Assets.get", function()
	beforeEach(function()
		services.ServerStorage:ClearAllChildren()
	end)

	it("returns nil when there is no Assets folder yet", function()
		expect(Assets.get("Krampus")).toBeNil()
		expect(Assets.folder()).toBeNil()
	end)

	it("returns the named Model", function()
		local folder = assetsFolder()
		local krampus = model("Krampus")
		krampus.Parent = folder
		expect(Assets.get("Krampus")).toBe(krampus)
		expect(Assets.folder()).toBe(folder)
	end)

	it("ignores something with the right name that is not a Model", function()
		local folder = assetsFolder()
		local part = Instance.new("Part")
		part.Name = "Sleigh"
		part.Parent = folder
		expect(Assets.get("Sleigh")).toBeNil()
	end)
end)

describe("Assets.clone", function()
	beforeEach(function()
		services.ServerStorage:ClearAllChildren()
	end)

	it("clones a model that has every required part", function()
		model("ElfA", { "Humanoid", "HumanoidRootPart" }).Parent = assetsFolder()
		local copy = Assets.clone("ElfA", { "Humanoid", "HumanoidRootPart" })
		expect(copy).never.toBeNil()
		expect(copy.Name).toBe("ElfA")
		expect(copy.Parent).toBeNil()
	end)

	it("finds required parts at any depth", function()
		local sleigh = model("Sleigh", { "Body" })
		model("Seats", { "Seat1" }).Parent = sleigh
		sleigh.Parent = assetsFolder()
		expect(Assets.clone("Sleigh", { "Body", "Seat1" })).never.toBeNil()
	end)

	it("falls back to the stand-in when a required part is missing", function()
		model("Krampus", { "Humanoid" }).Parent = assetsFolder()
		expect(Assets.clone("Krampus", { "Humanoid", "Basket" })).toBeNil()
	end)

	it("falls back to the stand-in when the model isn't there", function()
		assetsFolder()
		expect(Assets.clone("Reindeer", {})).toBeNil()
	end)
end)

describe("Assets.mapDressing", function()
	beforeEach(function()
		services.ServerStorage:ClearAllChildren()
	end)

	it("returns nil for maps without dressing", function()
		expect(Assets.mapDressing(nil)).toBeNil()
		expect(Assets.mapDressing("FrozenCanal")).toBeNil()
	end)

	it("returns the map's dressing Model from ServerStorage.Maps", function()
		local maps = Instance.new("Folder")
		maps.Name = "Maps"
		maps.Parent = services.ServerStorage
		local dressing = model("FrozenCanal")
		dressing.Parent = maps
		expect(Assets.mapDressing("FrozenCanal")).toBe(dressing)
	end)
end)
