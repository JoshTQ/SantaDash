--[[
	Which Santa suits a player may wear (Config.Skins). Pure: the server
	(server/Skins.luau) and tests share it.

	A suit is unlocked when it's free or the player's saved owned table has
	its id (a store item's grants.cosmetic). A saved choice that's no longer
	owned (a refunded suit) falls back to the default.
]]

local Config = require(script.Parent.Config)

local SkinRules = {}

export type Skin = {
	id: string,
	name: string,
	free: boolean?,
	model: string?,
	howTo: string?,
	trail: { Color3 }?,
	cheer: { colors: { Color3 }, count: number }?,
}

function SkinRules.get(id: any): Skin?
	if type(id) ~= "string" then
		return nil
	end
	for _, skin in Config.Skins.List do
		if skin.id == id then
			return skin
		end
	end
	return nil
end

function SkinRules.owns(owned: { [string]: boolean }?, id: any): boolean
	local skin = SkinRules.get(id)
	if not skin then
		return false
	end
	return skin.free == true or (owned ~= nil and owned[skin.id] == true)
end

-- The suit this player wears now: their choice if they still own it.
function SkinRules.current(data: { skin: string?, owned: { [string]: boolean }? }?): string
	local choice = data and data.skin
	if choice and SkinRules.owns(data and data.owned, choice) then
		return choice
	end
	return Config.Skins.Default
end

-- Puts the suit on (in data); returns false and why when they can't.
function SkinRules.equip(data: { skin: string?, owned: { [string]: boolean }? }, id: any): (boolean, string?)
	if not SkinRules.get(id) then
		return false, "unknown"
	end
	if not SkinRules.owns(data.owned, id) then
		return false, "locked"
	end
	data.skin = id
	return true, nil
end

-- What the suit picker shows: every suit, owned or not, and which is on.
function SkinRules.list(data: { skin: string?, owned: { [string]: boolean }? }?): { any }
	local wearing = SkinRules.current(data)
	local out = {}
	for _, skin in Config.Skins.List do
		local unlocked = SkinRules.owns(data and data.owned, skin.id)
		table.insert(out, {
			id = skin.id,
			name = skin.name,
			unlocked = unlocked,
			equipped = skin.id == wearing,
			howTo = if unlocked then nil else skin.howTo,
		})
	end
	return out
end

-- Catalog problems (each suit's unlock must exist), for Store.start's check.
function SkinRules.validate(items: { any }): { string }
	local problems = {}
	local granted = {}
	for _, item in items do
		if item.grants and item.grants.cosmetic then
			granted[item.grants.cosmetic] = true
		end
	end
	local seen = {}
	for _, skin in Config.Skins.List do
		if seen[skin.id] then
			table.insert(problems, "duplicate suit " .. skin.id)
		end
		seen[skin.id] = true
		if not skin.free and not granted[skin.id] then
			table.insert(problems, "no store item unlocks suit " .. skin.id)
		end
		if not skin.free and not skin.model then
			table.insert(problems, "suit " .. skin.id .. " has no model")
		end
	end
	if not SkinRules.owns({}, Config.Skins.Default) then
		table.insert(problems, "the default suit must be free")
	end
	return problems
end

return SkinRules
