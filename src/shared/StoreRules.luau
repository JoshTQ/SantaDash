--[[
	The store's rules as pure functions, so they are tested without Roblox:
	what a player may see and buy right now, what a purchase grants, and the
	catalog checks that keep the store compliant (Config.Store).

	The server (server/Store.luau) asks canPrompt before every purchase
	prompt and only ever prompts from the server, so a modified client can't
	get around the 3-minute rule or PolicyService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Rarity = require(ReplicatedStorage.Shared.Rarity)

local StoreRules = {}

export type Context = {
	now: number, -- os.time(), UTC
	playSeconds: number, -- total time played (PlayerData)
	owned: { [string]: boolean },
	paidRandomRestricted: boolean, -- PolicyService ArePaidRandomItemsRestricted (true if unknown)
	runServer: boolean, -- this server hosts runs
	saving: boolean, -- the player's data can be saved
}

-- Grants that can never be sold, whatever a catalog entry says.
local FORBIDDEN_GRANTS = { jingle = true, mythic = true, secret = true }
local KNOWN_GRANTS = { coal = true, inventory = true, perk = true, blessing = true, cosmetic = true }
local SACK_TIERS = { BiggerSack5 = 5, BiggerSack3 = 3, BiggerSack2 = 2 }

-- "2026-12-06" -> os.time of that day's 00:00 UTC.
function StoreRules.day(date: string): number
	local y, m, d = string.match(date, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	assert(y, "bad date " .. tostring(date))
	local year, month, dayOfMonth = tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number
	-- Days from the civil date (Howard Hinnant's algorithm): no os.time
	-- timezone surprises.
	local yy = if month <= 2 then year - 1 else year
	local era = (if yy >= 0 then yy else yy - 399) // 400
	local yoe = yy - era * 400
	local mp = (month + 9) % 12
	local doy = (153 * mp + 2) // 5 + dayOfMonth - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return (era * 146097 + doe - 719468) * 86400
end

function StoreRules.item(id: string): any?
	for _, item in Config.Store.Items do
		if item.id == id then
			return item
		end
	end
	return nil
end

function StoreRules.itemByAsset(kind: string, assetId: number): any?
	if assetId == 0 then
		return nil
	end
	for _, item in Config.Store.Items do
		if item.kind == kind and item.assetId == assetId then
			return item
		end
	end
	return nil
end

-- On sale today? (dates are inclusive; Config.Store.IgnoreDates for Staging)
function StoreRules.onSale(item: any, now: number): boolean
	if Config.Store.IgnoreDates then
		return true
	end
	if item.from and now < StoreRules.day(item.from) then
		return false
	end
	if item.to and now >= StoreRules.day(item.to) + 86400 then
		return false
	end
	return true
end

-- Should this item be listed for this player? (reason when not)
function StoreRules.visible(item: any, ctx: Context): (boolean, string?)
	if not item.ready then
		return false, "notReady"
	end
	if not StoreRules.onSale(item, ctx.now) then
		return false, "notOnSale"
	end
	if item.paidRandom and ctx.paidRandomRestricted then
		return false, "restricted"
	end
	if item.runServerOnly and not ctx.runServer then
		return false, "runServerOnly"
	end
	if (item.kind == "Pass" or item.once) and ctx.owned[item.id] then
		return false, "owned"
	end
	if ctx.playSeconds < Config.Store.NoPromptSeconds then
		return false, "tooSoon"
	end
	return true, nil
end

-- May the server prompt this purchase now? Everything visible requires, plus
-- a real asset id and data that can be saved.
function StoreRules.canPrompt(item: any?, ctx: Context): (boolean, string?)
	if not item then
		return false, "unknown"
	end
	local ok, reason = StoreRules.visible(item, ctx)
	if not ok then
		return false, reason
	end
	if not item.assetId or item.assetId == 0 then
		return false, "notCreated"
	end
	if not ctx.saving then
		return false, "notSaving"
	end
	return true, nil
end

-- Applies a purchase to saved data (pure; Store saves it). Returns what the
-- server must still do live: { blessing = true } when a Blessing starts.
function StoreRules.grant(data: { [string]: any }, item: any): { blessing: boolean }
	local grants = item.grants or {}
	if grants.coal then
		data.coal += grants.coal
	end
	for id, count in grants.inventory or {} do
		data.inventory[id] = (data.inventory[id] or 0) + count
	end
	if item.kind == "Pass" or item.once then
		data.owned[item.id] = true
	end
	if grants.cosmetic then
		data.owned[grants.cosmetic] = true
	end
	return { blessing = grants.blessing == true }
end

-- Undoes grant (a receipt whose save failed, so Roblox will retry it).
function StoreRules.revoke(data: { [string]: any }, item: any)
	local grants = item.grants or {}
	if grants.coal then
		data.coal -= grants.coal
	end
	for id, count in grants.inventory or {} do
		data.inventory[id] = math.max(0, (data.inventory[id] or 0) - count)
	end
	if item.kind == "Pass" or item.once then
		data.owned[item.id] = nil
	end
	if grants.cosmetic then
		data.owned[grants.cosmetic] = nil
	end
end

-- Takes one consumable; false if there are none.
function StoreRules.consume(data: { [string]: any }, id: string): boolean
	local count = data.inventory[id] or 0
	if count <= 0 then
		return false
	end
	data.inventory[id] = count - 1
	return true
end

-- Remembers a receipt; false if it was already granted. Keeps the last N.
function StoreRules.recordReceipt(data: { [string]: any }, purchaseId: string, keep: number?): boolean
	for _, id in data.receipts do
		if id == purchaseId then
			return false
		end
	end
	table.insert(data.receipts, purchaseId)
	while #data.receipts > (keep or 50) do
		table.remove(data.receipts, 1)
	end
	return true
end

-- Perk effects --------------------------------------------------------------

function StoreRules.sackCapacity(owned: { [string]: boolean }): number
	local best = 1
	for id, tier in SACK_TIERS do
		if owned[id] and tier > best then
			best = tier
		end
	end
	return Config.Sack.Capacity * best
end

function StoreRules.coalMultiplier(owned: { [string]: boolean }, blessed: boolean?): number
	return (if owned.TwoXLoot then 2 else 1) * (if blessed then 2 else 1)
end

-- The store card's odds lines: base and boosted, for paid random items only.
function StoreRules.oddsFor(item: any): { { name: string, base: string, boosted: string } }?
	if not item.paidRandom then
		return nil
	end
	local base, boosted = Rarity.odds(1), Rarity.odds(item.luck)
	local rows = {}
	for i, odd in base do
		table.insert(rows, {
			name = odd.name,
			base = Rarity.format(odd.percent),
			boosted = Rarity.format(boosted[i].percent),
		})
	end
	return rows
end

-- Catalog checks (run by tests and once at server start). Returns problems.
function StoreRules.validate(items: { any }): { string }
	local problems = {}
	local seen = {}
	local function bad(item, text)
		table.insert(problems, tostring(item.id) .. ": " .. text)
	end
	for _, item in items do
		if seen[item.id] then
			bad(item, "duplicate id")
		end
		seen[item.id] = true
		if item.kind ~= "Pass" and item.kind ~= "Product" then
			bad(item, "kind must be Pass or Product")
		end
		if type(item.price) ~= "number" or item.price <= 0 then
			bad(item, "needs a Robux price")
		end
		if type(item.assetId) ~= "number" then
			bad(item, "assetId must be a number (0 until created)")
		end
		for key, value in item.grants or {} do
			if FORBIDDEN_GRANTS[string.lower(key)] then
				bad(item, "can never grant " .. key)
			elseif not KNOWN_GRANTS[key] then
				bad(item, "unknown grant " .. key)
			end
			if key == "inventory" then
				for id in value do
					if FORBIDDEN_GRANTS[string.lower(id)] or Rarity.EarnedOnly[id] then
						bad(item, "can never grant " .. id)
					end
				end
			end
		end
		if item.paidRandom and not (type(item.luck) == "number" and item.luck > 1) then
			bad(item, "paid random items need a luck multiplier so odds can be shown")
		end
		if item.kind == "Pass" and item.grants and item.grants.inventory then
			bad(item, "passes can't grant consumables")
		end
		if item.from then
			StoreRules.day(item.from)
		end
		if item.to then
			StoreRules.day(item.to)
		end
	end
	return problems
end

return StoreRules
