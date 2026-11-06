--[[
	Wardrobe rules (warm gear for Krampus's Lair, bought with Jingle at each
	Sleigh Stop). Items live in Config.Wardrobe.Items keyed by id:
	  { name, price, warmth?, swimSpeed?, model?, enabled }
	Each piece is its own model pinned to Santa's bones (client/WearFollow),
	so it fits every suit. Warmth and swim speed add up.
	Owned ids are per run (never saved, never sold for Robux). The server
	(server/Wardrobe) sets the character attribute "Wardrobe" to the owned ids,
	comma separated, so client scripts can dress Santa.
]]

local Config = require(script.Parent.Config)

local Wardrobe = {}

Wardrobe.ATTRIBUTE = "Wardrobe"

export type Item = {
	name: string,
	price: number,
	warmth: number?,
	swimSpeed: number?,
	model: string?,
	enabled: boolean?,
}

function Wardrobe.enabled(): boolean
	return Config.Wardrobe.Enabled == true
end

-- The item with this id, if it exists and is switched on.
function Wardrobe.item(id: string): Item?
	local item = Config.Wardrobe.Items[id]
	if item and item.enabled ~= false then
		return item
	end
	return nil
end

-- Items on sale, in stand order.
function Wardrobe.onSale(): { string }
	local list = {}
	for _, id in Config.Wardrobe.Order do
		if Wardrobe.item(id) then
			table.insert(list, id)
		end
	end
	return list
end

-- Warmth from what you own: pieces add up.
function Wardrobe.warmth(owned: { [string]: boolean }?): number
	local total = 0
	for id in owned or {} do
		local item = Wardrobe.item(id)
		if item then
			total += item.warmth or 0
		end
	end
	return total
end

-- Extra WalkSpeed while swimming from what you own.
function Wardrobe.swimSpeed(owned: { [string]: boolean }?): number
	local total = 0
	for id in owned or {} do
		local item = Wardrobe.item(id)
		if item then
			total += item.swimSpeed or 0
		end
	end
	return total
end

-- Can a Santa owning `owned` buy `id`? Returns ok and, if not, why.
function Wardrobe.canBuy(owned: { [string]: boolean }, id: string): (boolean, string?)
	local item = Wardrobe.item(id)
	if not item then
		return false, "Not for sale"
	end
	if owned[id] then
		return false, "You already have the " .. item.name
	end
	return true, nil
end

-- "A,B" for the character attribute (sorted, so it's stable).
function Wardrobe.encode(owned: { [string]: boolean }): string
	local ids = {}
	for id, yes in owned do
		if yes then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

function Wardrobe.decode(value: any): { [string]: boolean }
	local owned = {}
	if type(value) == "string" then
		for id in string.gmatch(value, "[^,]+") do
			owned[id] = true
		end
	end
	return owned
end

return Wardrobe
