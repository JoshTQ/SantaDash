--[[
	The Wardrobe stand: warm gear for Krampus's Lair, bought with Jingle at
	each Sleigh Stop (rules in shared/Wardrobe, items in Config.Wardrobe).
	Josh picked sets A and D and approved them built from parts (6 Nov
	2026): Chunky Scarf, Bobble Mittens, Duckie Ring and Hot-Water Bottle.

	Each piece is its own model (server/WearBuilder, or a model of the same
	name in ServerStorage.Assets) pinned to Santa's bones by shared/GearAttach,
	so every suit wears the same one. Each hanger on the rack shows its piece.
	Owned ids also go on the character attribute "Wardrobe".

	  Wardrobe.build(model, at, newPart, addPrompt) -> { [id]: ProximityPrompt }
	  Wardrobe.buy(run, player, id)
	  Wardrobe.dress(player, owned)     sets the attribute (and re-dresses on respawn)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Wardrobe)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)
local Assets = require(script.Parent.Assets)
local WearBuilder = require(script.Parent.WearBuilder)
local ShopStalls = require(script.Parent.ShopStalls)

local WOOD = Color3.fromRGB(201, 138, 84)
local GOLD = Color3.fromRGB(255, 200, 61)
local DARK = Color3.fromRGB(58, 33, 20)

-- shared/GearAttach comes with the boots work (PR #39). Until it's in, the
-- gear is bought and counted but not shown on Santa.
local okGear, GearAttach = pcall(function()
	return require(ReplicatedStorage.Shared.GearAttach)
end)
if not okGear then
	GearAttach = nil
end

local Wardrobe = {}

-- The model for a piece: an imported one in ServerStorage.Assets wins over
-- the parts build. A fresh copy each call.
function Wardrobe.template(id: string): Model?
	local item = Rules.item(id)
	if not item then
		return nil
	end
	local imported = item.model and Assets.get(item.model)
	if imported then
		return imported:Clone()
	end
	return WearBuilder.build(id)
end

-- Shows a piece on a hanger: anchored, centred `at`.
local function display(parent: Instance, id: string, at: CFrame)
	local piece = Wardrobe.template(id)
	if not piece then
		return
	end
	-- Rough bounds by hand (no GetBoundingBox in the Lune test world).
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") and d ~= piece.PrimaryPart then
			local p, half = d.CFrame.Position, d.Size / 2
			lo, hi = lo:Min(p - half), hi:Max(p + half)
		end
	end
	if lo.X > hi.X then
		piece:Destroy()
		return
	end
	local centre = (lo + hi) / 2
	local delta = at * CFrame.new(0, (hi.Y - lo.Y) / 2, 0) * CFrame.new(-centre)
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CFrame = delta * d.CFrame
		end
	end
	piece.Name = "WardrobeDisplay"
	piece.Parent = parent
end

-- The Wardrobe stall (a giant bobble hat, server/ShopStalls) with the gear
-- hanging on its rail, a price tag under each piece and one prompt per
-- piece. `at` is where the stall stands (world CFrame, on the ground,
-- front facing its -Z).
function Wardrobe.build(model: Instance, at: CFrame, newPart, addPrompt): { [string]: ProximityPrompt }
	local prompts = {}
	if not Rules.enabled() then
		return prompts
	end
	local ids = Rules.onSale()
	local width = math.max(6, #ids * 3)
	local stall, railY, railZ = ShopStalls.wardrobe(model, at, width)
	local counterFront = railZ - 0.4
	for i, id in ids do
		local item = Rules.item(id) :: Rules.Item
		local x = -width / 2 + (i - 0.5) * width / #ids
		local hanger = newPart(
			stall,
			"WardrobeItem",
			Vector3.new(0.25, 0.6, 0.25),
			at * CFrame.new(x, railY - 0.5, railZ),
			WOOD
		)
		hanger.CanCollide = false
		hanger:SetAttribute("WardrobeId", id)
		display(stall, id, at * CFrame.new(x, 3.75, railZ))
		local tag = newPart(
			stall,
			"PriceTag",
			Vector3.new(1.8, 0.8, 0.15),
			at * CFrame.new(x, 2.6, counterFront - 0.1),
			GOLD
		)
		tag.CanCollide = false
		ShopStalls.text(tag, tostring(item.price), GOLD, DARK)
		prompts[id] = addPrompt(hanger, "Buy " .. item.price .. " Jingle", item.name, 0.4)
	end
	return prompts
end

-- Dresses Santa in what he owns (pinned to his bones by GearAttach) and puts
-- the owned ids on the character attribute. Safe to call again after a
-- respawn or a new purchase: each piece is replaced, not doubled.
function Wardrobe.dress(player: Player, owned: { [string]: boolean })
	local character = player.Character
	if not character then
		return
	end
	local value = Rules.encode(owned)
	character:SetAttribute(Rules.ATTRIBUTE, if value == "" then nil else value)
	if not GearAttach then
		return
	end
	for id in Config.Wardrobe.Items do
		if owned[id] then
			local piece = Wardrobe.template(id)
			if piece then
				GearAttach.equip(character :: Model, piece, id)
				piece:Destroy()
			end
		else
			GearAttach.unequip(character :: Model, id)
		end
	end
end

-- Takes every piece off (the run is over).
function Wardrobe.undress(player: Player)
	local character = player.Character
	if not character then
		return
	end
	character:SetAttribute(Rules.ATTRIBUTE, nil)
	if GearAttach then
		for id in Config.Wardrobe.Items do
			GearAttach.unequip(character :: Model, id)
		end
	end
end

-- A Santa buys a piece: Jingle out, worn for the rest of the run.
function Wardrobe.buy(run, player: Player, id: string)
	local st = run.players[player]
	if not st then
		return
	end
	local ok, why = Rules.canBuy(st.wardrobe, id)
	if not ok then
		run:_banner(player, why :: string, 2)
		run:_sfx(player, "Nope")
		return
	end
	local item = Rules.item(id) :: Rules.Item
	if not run:_spend(player, item.price, "Wear" .. id) then
		return
	end
	st.wardrobe[id] = true
	Wardrobe.dress(player, st.wardrobe)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		SoundPlayer.at("Boing", (root :: BasePart).Position)
	end
	run:_sendPlayer(player)
	local seconds = math.floor(Config.BodyHeat.SwimSeconds * (1 + Rules.warmth(st.wardrobe)) + 0.5)
	run:_banner(player, item.name .. "! You can swim for " .. seconds .. " s in Krampus's lake.", 3)
end

return Wardrobe
