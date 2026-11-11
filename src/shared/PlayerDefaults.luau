--[[
	What a brand-new player's saved data looks like (server/PlayerData.luau).
	Pure, so tests and both places share it. Add new fields here with a
	default; PlayerDefaults.reconcile fills them into older saves.

	Owners: store thread (playSeconds, coal, owned, receipts, inventory),
	tutorial thread (tutorial). skin: shared/SkinRules.luau. boots: shared/BootRules.luau.
]]

local PlayerDefaults = {}

PlayerDefaults.Version = 1

function PlayerDefaults.new()
	return {
		version = PlayerDefaults.Version,
		playSeconds = 0, -- total time played, every session and place (3-minute store rule)
		coal = 0, -- soft currency, earned from runs
		owned = {}, -- [itemId] = true: passes and one-time products granted
		receipts = {}, -- recent ProcessReceipt PurchaseIds, oldest first (capped)
		inventory = {}, -- [itemId] = count: consumables such as InstantBreakout
		skin = "Classic", -- the Santa suit the player wears (Config.Skins)
		boots = "", -- the boots the player wears (Config.Boots id), "" for none
		tutorial = {
			done = {}, -- [lessonId] = true
			tipsOff = false, -- the player's "no more tips" switch
		},
		settings = {
			musicOff = false, -- the HUD's Music button (server/Settings.luau)
		},
	}
end

-- Fills any missing field (deeply) from the defaults, keeping saved values.
-- Returns the same table.
function PlayerDefaults.reconcile(data: { [string]: any }, defaults: { [string]: any }?): { [string]: any }
	local template = defaults or PlayerDefaults.new()
	for key, value in template do
		if data[key] == nil then
			data[key] = value
		elseif type(value) == "table" and type(data[key]) == "table" and next(value) ~= nil then
			PlayerDefaults.reconcile(data[key], value)
		end
	end
	return data
end

return PlayerDefaults
