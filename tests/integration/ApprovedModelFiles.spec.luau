--[[
	Every committed model in assets/models/ (what the deploy puts in
	ServerStorage.Assets) keeps the part contract its system checks for
	(src/server/Assets.luau). A model that breaks it would silently fall back
	to the greybox stand-in in the live game, so it fails here instead.
	Also: nothing Open Cloud refuses to publish, and every mesh is textured.
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local DIR = "assets/models"

-- name -> { primary = PrimaryPart name?, parts = required descendants }
local CONTRACTS = {
	Santa = {
		primary = "HumanoidRootPart",
		parts = { "Humanoid", "HumanoidRootPart", "Body", "Animations" },
		clips = { "Idle", "Walk", "Sneak", "Grab", "Cheer" }, -- shared/SantaMoves.luau
	},
	SantaSack = { primary = "Sack", parts = { "Sack" } },
	SkateBoots = { primary = "Root", parts = { "Root", "LeftBoot", "RightBoot" }, follow = true },
	Krampus = {
		primary = "HumanoidRootPart",
		parts = { "Humanoid", "HumanoidRootPart", "Basket" },
		clips = { "Idle", "Scheme", "Tiptoe", "Sniff", "Snatch", "Dizzy" }, -- KrampusBrain.clipFor
	},
	Sleigh = {
		primary = "Body",
		parts = { "Body", "Seat1", "Seat2", "Seat3", "Seat4", "Seat5", "Seat6", "Hitch", "Horn", "Lantern" },
	},
	Reindeer = { primary = "Body", parts = { "Body" } },
	CocoaMachine = { primary = "Body", parts = { "Body", "BuyPrompt" } },
	ElfA = {
		primary = "HumanoidRootPart",
		parts = { "Humanoid", "HumanoidRootPart" },
		clips = { "Idle", "Follow", "Grab" },
	},
	ElfD = {
		primary = "HumanoidRootPart",
		parts = { "Humanoid", "HumanoidRootPart" },
		clips = { "Idle", "Follow", "Grab" },
	},
	DogCorgi = { primary = "HumanoidRootPart", parts = { "Humanoid", "HumanoidRootPart" } },
	DogTin = { primary = "HumanoidRootPart", parts = { "Humanoid", "HumanoidRootPart" } },
	VaultDoor = { primary = "Frame", parts = { "Frame", "Door", "Dial", "PricePlate" } },
	Present = { primary = "Box", parts = { "Box" } },
	PresentTall = { primary = "Box", parts = { "Box" } },
	PresentLong = { primary = "Box", parts = { "Box" } },
	NaughtyList = { primary = "Book", parts = { "Book", "Chain", "Lock" } },
	SnowPile = {
		primary = "Drift",
		parts = { "Drift", "Ball1", "Ball2", "Ball3", "Ball4", "Ball5", "Glow", "Sparkles" },
	},
}

local UNPUBLISHABLE = {
	"SurfaceAppearance",
	"PartOperation",
	"EditableImage",
	"EditableMesh",
	"BaseWrap",
	"PackageLink",
}

-- Top-level models plus one level of variant folders (assets/models/Presents/*.rbxm).
local files = {}
local paths = {}
if fs.isDir(DIR) then
	for _, file in fs.readDir(DIR) do
		local name = string.match(file, "^(%w+)%.rbxm$")
		if name then
			table.insert(files, name)
			paths[name] = DIR .. "/" .. file
		elseif fs.isDir(DIR .. "/" .. file) then
			for _, inner in fs.readDir(DIR .. "/" .. file) do
				local variant = string.match(inner, "^(%w+)%.rbxm$")
				if variant then
					table.insert(files, variant)
					paths[variant] = DIR .. "/" .. file .. "/" .. inner
				end
			end
		end
	end
end
table.sort(files)

local function load(name: string)
	local roots = roblox.deserializeModel(fs.readFile(paths[name]))
	return roots
end

describe("assets/models", function()
	it("only holds .rbxm files named like Assets entries", function()
		for _, file in fs.isDir(DIR) and fs.readDir(DIR) or {} do
			if file ~= "README.md" and not fs.isDir(DIR .. "/" .. file) then
				expect(string.match(file, "^%w+%.rbxm$")).toBe(file)
			end
		end
	end)

	for _, name in files do
		describe(name, function()
			it("is one Model named after its file, with a PrimaryPart", function()
				local roots = load(name)
				expect(#roots).toBe(1)
				expect(roots[1].ClassName).toBe("Model")
				expect(roots[1].Name).toBe(name)
				expect(roots[1].PrimaryPart).never.toBeNil()
			end)

			it("has nothing Open Cloud can't publish, and textured meshes", function()
				local model = load(name)[1]
				for _, d in model:GetDescendants() do
					for _, className in UNPUBLISHABLE do
						expect(d:IsA(className) and d:GetFullName() or nil).toBeNil()
					end
					if d:IsA("MeshPart") then
						-- Lune stores TextureID as the newer TextureContent property.
						local ok, texture = pcall(function()
							return tostring(d.TextureContent)
						end)
						expect(ok and string.match(texture, "rbxassetid://%d+") ~= nil).toBe(true)
					end
				end
			end)

			local contract = CONTRACTS[name]
			if contract then
				it("keeps the part contract the game checks", function()
					local model = load(name)[1]
					for _, part in contract.parts do
						expect(model:FindFirstChild(part, true) and part).toBe(part)
					end
					expect(model.PrimaryPart.Name).toBe(contract.primary)
				end)

				if contract.follow then
					it("is gear: each boot follows a foot bone", function()
						local model = load(name)[1]
						expect(model.LeftBoot:GetAttribute("FollowBone")).toBe("LeftFoot")
						expect(model.RightBoot:GetAttribute("FollowBone")).toBe("RightFoot")
					end)
				end

				it("names its animations after the clips the game plays", function()
					local model = load(name)[1]
					local folder = model:FindFirstChild("Animations")
					for _, animation in folder and folder:GetChildren() or {} do
						expect(animation.ClassName).toBe("Animation")
						expect(table.find(contract.clips or {}, animation.Name) and animation.Name).toBe(
							animation.Name
						)
					end
				end)
			end
		end)
	end
end)
