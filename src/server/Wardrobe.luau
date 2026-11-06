--[[
	The Wardrobe stand: warm gear for Krampus's Lair, bought with Jingle at
	each Sleigh Stop (rules in shared/Wardrobe, items in Config.Wardrobe).
	Josh picked sets A and D (6 Nov 2026): Chunky Scarf, Bobble Mittens,
	Duckie Ring and Hot-Water Bottle. OFF (Config.Wardrobe.Enabled) until he
	approves the 3D art, so the stand here is a greybox rack.

	Each piece is its own model in ServerStorage.Assets (Config item .model),
	pinned to Santa's bones so every suit wears the same one. Owned ids go on
	the character attribute "Wardrobe" so the client can dress Santa.

	  Wardrobe.build(model, at, newPart, addPrompt) -> { [id]: ProximityPrompt }
	  Wardrobe.buy(run, player, id)
	  Wardrobe.dress(player, owned)     sets the attribute (and re-dresses on respawn)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rules = require(ReplicatedStorage.Shared.Wardrobe)
local SoundPlayer = require(ReplicatedStorage.Shared.SoundPlayer)

local Wardrobe = {}

-- A greybox clothes rack with one prompt per piece. `at` is where the stand
-- stands (world CFrame, on the ground).
function Wardrobe.build(model: Instance, at: CFrame, newPart, addPrompt): { [string]: ProximityPrompt }
	local prompts = {}
	if not Rules.enabled() then
		return prompts
	end
	local ids = Rules.onSale()
	local width = math.max(6, #ids * 3)
	local rail = newPart(model, "WardrobeRail", Vector3.new(width, 0.4, 0.4), at * CFrame.new(0, 6, 0))
	rail.Color = Color3.fromRGB(200, 160, 90)
	for _, side in { -1, 1 } do
		newPart(model, "WardrobePost", Vector3.new(0.4, 6, 0.4), at * CFrame.new(side * width / 2, 3, 0))
	end
	for i, id in ids do
		local item = Rules.item(id) :: Rules.Item
		local x = -width / 2 + (i - 0.5) * width / #ids
		local hanger = newPart(model, "WardrobeItem", Vector3.new(2, 2.4, 0.6), at * CFrame.new(x, 4.4, 0))
		hanger.Color = Color3.fromRGB(230, 70, 70)
		hanger:SetAttribute("WardrobeId", id)
		prompts[id] = addPrompt(hanger, "Buy " .. item.price .. " Jingle", item.name, 0.4)
	end
	return prompts
end

-- Puts the owned ids on the character for the client (and GearAttach).
function Wardrobe.dress(player: Player, owned: { [string]: boolean })
	local character = player.Character
	if character then
		local value = Rules.encode(owned)
		character:SetAttribute(Rules.ATTRIBUTE, if value == "" then nil else value)
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
	if not run:_spend(player, item.price) then
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
