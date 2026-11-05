# Store and holiday monetisation

Catalog: `Config.Store` in `src/shared/Config.luau`. Rules: `src/shared/StoreRules.luau`.
Server: `src/server/Store.luau`. Saved data: `src/server/PlayerData.luau`
(defaults in `src/shared/PlayerDefaults.luau`). Panel: `src/client/Store.client.luau`
(Shop button, or B).

## Rules the code enforces

| Rule | Where |
| --- | --- |
| No purchase prompt in a player's first 3 minutes of play (total, across sessions and places). Applies to every item, the Starter Sack included. | `StoreRules.visible`; prompts only ever come from the server |
| Jingle, Mythic and Secret are never sold or boosted | `StoreRules.validate` (checked by tests and at server start); `Rarity` keeps Mythic/Secret out of every roll |
| Paid random items (Lucky Sack) show normal and boosted odds before purchase, and are hidden when PolicyService says `ArePaidRandomItemsRestricted` (or the lookup fails) | `StoreRules.oddsFor`, `Store.refreshPolicy` |
| A purchase is granted once per PurchaseId, and `PurchaseGranted` is only returned after the grant is saved | `Store.processReceipt` |
| No purchases when the player's data can't be saved (DataStore down, Studio) | `PlayerData.isPersistent` |
| Holiday items are only on sale between their dates (UTC); shop closes after Jan 5 | `from` / `to` on each item |

## What's live, and what's waiting

| Item | Price | Status |
| --- | --- | --- |
| Starter Sack (1,000 Coal + 2 Instant Break-outs, once) | 25 | Ready |
| 2X Loot (double Coal from runs) | 149 | Ready |
| Bigger Sack 2X / 3X / 5X | 79 / 179 / 449 | Ready |
| Fast Sneak (+3 walk speed in the sneak phase) | 99 | Ready |
| Instant Break-out | 15 | Ready (button on the snatched panel) |
| Santa's Blessing (2X Coal for the whole server, 10 min, buyer named) | 99 | Ready, run servers only |
| Lucky Sack | 29 | Hidden until presents have rarities (Grotto unwrap) |
| Naughty Pass | 399 | Hidden until pass tiers exist |
| VIP Grotto | 299 | Hidden until the Grotto exists; gold sleigh needs art approval |
| Holiday Bundle (Dec 6 - Jan 5) | 199 | Hidden until its suit passes art approval |
| Christmas Eve Suit (Dec 20 - Jan 5) | 149 | Hidden until art approval |

## Going live (Josh)

1. Creator Dashboard > the experience > Monetization: create a **Developer Product** for
   Starter Sack, Instant Break-out, Santa's Blessing (and later Lucky Sack, Holiday Bundle,
   Christmas Eve Suit), and a **Pass** for 2X Loot, Bigger Sack 2X/3X/5X, Fast Sneak.
   Prices as above.
2. Put each id in `assetId` on its item in `Config.Store.Items`. Items with `assetId = 0`
   show as "Soon" and never prompt.
3. Game Settings > Security: **Enable Studio Access to API Services** only if you want saving
   in Studio (and set `Config.PlayerData.SaveInStudio = true`). Live servers always save.
4. To test holiday items early on Staging, set `Config.Store.IgnoreDates = true` there only.
