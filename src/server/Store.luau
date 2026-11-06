--[[
	The Robux store (game-design.md "Monetisation"; catalog in Config.Store,
	rules in shared/StoreRules.luau).

	  * Every purchase prompt comes from the server, after StoreRules.canPrompt:
	    nothing in a player's first 3 minutes, nothing PolicyService restricts,
	    nothing unsaved. The client only asks.
	  * ProcessReceipt grants once per PurchaseId and returns PurchaseGranted
	    only after the grant is saved, so a crash means Roblox retries instead
	    of the player paying for nothing.
	  * Passes are checked with UserOwnsGamePassAsync when a player joins, so
	    passes bought on the website count too.

	Remote "Store" (client -> server): ("Open") for the catalog, ("Buy", id),
	("Equip", suitId) to wear an unlocked Santa suit (server/Skins.luau).
	("BuyBoots", id) buys boots with Coal; ("WearBoots", id or "") puts owned
	boots on or takes them off (server/Boots.luau). Coal, not Robux, so the
	3-minute rule doesn't apply to these.
	Remote "Store" (server -> client): ("Catalog", snapshot), ("Notice", text).
	Instant Break-out is used through the Run's Input remote ("Breakout").
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SkinRules = require(ReplicatedStorage.Shared.SkinRules)
local StoreRules = require(ReplicatedStorage.Shared.StoreRules)
local PlayerData = require(script.Parent.PlayerData)
local Skins = require(script.Parent.Skins)
local Boots = require(script.Parent.Boots)

local Store = {}

local BLESSING_SECONDS = 600

local state = {
	runServer = true,
	restricted = {} :: { [Player]: boolean },
	blessing = nil :: { endsAt: number, by: string }?,
	-- Called with (player) when a granted Instant Break-out should be used now.
	onBreakout = {} :: { (Player) -> boolean },
	started = false,
}

local function remote(): RemoteEvent
	return Remotes.get("Store")
end

local function notice(player: Player, text: string)
	if player.Parent == Players then
		remote():FireClient(player, "Notice", text)
	end
end

local function context(player: Player, data): StoreRules.Context
	return {
		now = os.time(),
		playSeconds = data.playSeconds,
		owned = data.owned,
		-- Unknown counts as restricted: never show paid randomness by mistake.
		paidRandomRestricted = state.restricted[player] ~= false,
		runServer = state.runServer,
		saving = PlayerData.isPersistent(player),
	}
end

-- The owned set used by gameplay (passes and once-only products).
function Store.owned(player: Player): { [string]: boolean }
	local data = PlayerData.get(player)
	return if data then data.owned else {}
end

function Store.isBlessed(): boolean
	return state.blessing ~= nil and os.time() < state.blessing.endsAt
end

function Store.blessing(): { endsAt: number, by: string }?
	return if Store.isBlessed() then state.blessing else nil
end

-- Coal for a finished run: the loot through 2X Loot and Santa's Blessing,
-- credited to saved data. Returns the Coal given.
function Store.creditRun(player: Player, loot: number): number
	local coal = math.floor(
		loot * Config.Coal.PerLootValue * StoreRules.coalMultiplier(Store.owned(player), Store.isBlessed())
	)
	if coal > 0 then
		PlayerData.update(player, function(data)
			data.coal += coal
		end)
	end
	return coal
end

-- Uses one Instant Break-out if the player has one. Returns true if used.
function Store.useBreakout(player: Player): boolean
	local used = false
	PlayerData.update(player, function(data)
		used = StoreRules.consume(data, "InstantBreakout")
	end)
	return used
end

-- What the snatched HUD offers: Break-outs owned, and whether one can be
-- bought right now (all store rules apply). nil = offer nothing.
function Store.breakoutOffer(player: Player): { owned: number, canBuy: boolean }?
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	local owned = data.inventory.InstantBreakout or 0
	local canBuy = (StoreRules.canPrompt(StoreRules.item("InstantBreakout"), context(player, data)))
	if owned <= 0 and not canBuy then
		return nil
	end
	return { owned = owned, canBuy = canBuy }
end

-- Runs register here so a freshly bought Break-out frees the player at once.
function Store.onBreakout(fn: (Player) -> boolean): () -> ()
	table.insert(state.onBreakout, fn)
	return function()
		local i = table.find(state.onBreakout, fn)
		if i then
			table.remove(state.onBreakout, i)
		end
	end
end

-- What the client's store panel shows.
function Store.snapshot(player: Player): any
	local data = PlayerData.get(player)
	if not data then
		return { items = {}, loading = true }
	end
	local ctx = context(player, data)
	local items = {}
	for _, item in Config.Store.Items do
		if StoreRules.visible(item, ctx) then
			table.insert(items, {
				id = item.id,
				name = item.name,
				blurb = item.blurb,
				price = item.price,
				odds = StoreRules.oddsFor(item),
				buyable = (StoreRules.canPrompt(item, ctx)),
			})
		end
	end
	local blessing = Store.blessing()
	return {
		items = items,
		coal = data.coal,
		breakouts = data.inventory.InstantBreakout or 0,
		opensIn = math.max(0, math.ceil(Config.Store.NoPromptSeconds - data.playSeconds)),
		saving = ctx.saving,
		blessing = if blessing then { by = blessing.by, endsAt = blessing.endsAt } else nil,
		skins = Skins.list(player),
		boots = Boots.list(player),
	}
end

function Store.sendCatalog(player: Player)
	if player.Parent == Players then
		remote():FireClient(player, "Catalog", Store.snapshot(player))
	end
end

local REASONS = {
	tooSoon = "The shop opens after a few minutes of play. Go grab some presents!",
	notSaving = "We can't save right now, so the shop is closed. Try again soon!",
	notCreated = "That isn't on sale yet.",
	owned = "You already have that!",
}

-- What a player hears after trying to buy boots with Coal.
local BOOT_NOTICES = {
	ok = "New boots! You'll zoom across the ice.",
	coal = "You need more Coal. Finish a few runs and come back!",
	owned = "You already have those boots!",
	notReady = "Those boots aren't on sale yet.",
	notForCoal = "Those are a Robux style.",
	loading = "Hang on, your Coal is still loading.",
	unknown = "Those boots aren't on sale.",
}

-- Server-side prompt, only when every rule allows it. Returns the reason if not.
function Store.prompt(player: Player, id: string): (boolean, string?)
	local data = PlayerData.get(player)
	if not data then
		return false, "loading"
	end
	local item = StoreRules.item(id)
	local ok, reason = StoreRules.canPrompt(item, context(player, data))
	if not ok then
		notice(player, REASONS[reason :: string] or "That isn't available right now.")
		return false, reason
	end
	local prompted = pcall(function()
		if item.kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, item.assetId)
		else
			MarketplaceService:PromptProductPurchase(player, item.assetId)
		end
	end)
	return prompted, if prompted then nil else "promptFailed"
end

local function startBlessing(buyer: Player)
	state.blessing = { endsAt = os.time() + BLESSING_SECONDS, by = buyer.DisplayName }
	local hud = Remotes.get("Hud")
	hud:FireAllClients("Banner", {
		text = buyer.DisplayName .. "'s Santa's Blessing: 2X loot for everyone for 10 minutes!",
		seconds = 5,
	})
	for _, player in Players:GetPlayers() do
		Store.sendCatalog(player)
	end
end

local function afterGrant(player: Player, item, live)
	if live.blessing then
		startBlessing(player)
	end
	if item.id == "InstantBreakout" then
		for _, fn in state.onBreakout do
			if fn(player) then
				break
			end
		end
	end
	notice(player, "Thanks! " .. item.name .. " is yours.")
	Store.sendCatalog(player)
end

-- MarketplaceService.ProcessReceipt. Exported for tests.
function Store.processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local item = StoreRules.itemByAsset("Product", info.ProductId)
	if not player or not item then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- retried when they're back
	end
	local data = PlayerData.waitFor(player, 10)
	if not data or not PlayerData.isPersistent(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	local fresh, live = false, { blessing = false }
	PlayerData.update(player, function(d)
		fresh = StoreRules.recordReceipt(d, purchaseId)
		if fresh then
			live = StoreRules.grant(d, item)
		end
	end)
	if not PlayerData.saveNow(player) then
		-- Not saved: roll back the grant in memory too, and let Roblox retry.
		if fresh then
			PlayerData.update(player, function(d)
				local i = table.find(d.receipts, purchaseId)
				if i then
					table.remove(d.receipts, i)
				end
				StoreRules.revoke(d, item)
			end)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if fresh then
		afterGrant(player, item, live)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Game passes: owned on Roblox = owned here (bought in game or on the website).
function Store.refreshPasses(player: Player)
	for _, item in Config.Store.Items do
		if item.kind == "Pass" and item.assetId ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, item.assetId)
			end)
			if ok and owns then
				PlayerData.update(player, function(data)
					data.owned[item.id] = true
				end)
			end
		end
	end
end

function Store.refreshPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- Failed lookups stay restricted (nil), the safe side.
	if ok and type(info) == "table" then
		state.restricted[player] = info.ArePaidRandomItemsRestricted == true
	end
end

local function onPlayer(player: Player)
	Store.refreshPolicy(player)
	if PlayerData.waitFor(player, 30) then
		Store.refreshPasses(player)
	end
end

-- runServer: this server hosts runs (Santa's Blessing is sold only there).
function Store.start(options: { runServer: boolean }?)
	if state.started then
		return
	end
	state.started = true
	state.runServer = if options then options.runServer else true
	local problems = StoreRules.validate(Config.Store.Items)
	for _, problem in SkinRules.validate(Config.Store.Items) do
		table.insert(problems, problem)
	end
	for _, problem in problems do
		warn("[Store] catalog problem:", problem)
	end

	pcall(function()
		MarketplaceService.ProcessReceipt = Store.processReceipt
	end)
	pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
			local item = StoreRules.itemByAsset("Pass", passId)
			if purchased and item then
				PlayerData.update(player, function(data)
					data.owned[item.id] = true
				end)
				task.spawn(PlayerData.saveNow, player)
				afterGrant(player, item, { blessing = false })
			end
		end)
	end)

	remote().OnServerEvent:Connect(function(player, action, id)
		if action == "Open" then
			Store.sendCatalog(player)
		elseif action == "Buy" and type(id) == "string" then
			Store.prompt(player, id)
		elseif action == "Equip" then
			local ok, why = Skins.equip(player, id)
			if ok then
				local skin = SkinRules.get(id)
				notice(player, "You're wearing " .. (if skin then skin.name else "it") .. "!")
			elseif why == "locked" then
				notice(player, "You haven't unlocked that suit yet.")
			end
			Store.sendCatalog(player)
		elseif action == "BuyBoots" then
			local ok, why = Boots.buy(player, id)
			notice(player, BOOT_NOTICES[if ok then "ok" else why or "unknown"] or BOOT_NOTICES.unknown)
			Store.sendCatalog(player)
		elseif action == "WearBoots" then
			Boots.equip(player, id)
			Store.sendCatalog(player)
		end
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayer, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		state.restricted[player] = nil
	end)
end

-- Tests.
function Store._reset()
	state.runServer = true
	state.restricted = {}
	state.blessing = nil
	state.onBreakout = {}
	state.started = false
end

function Store._setRestricted(player: Player, restricted: boolean?)
	state.restricted[player] = restricted
end

return Store
