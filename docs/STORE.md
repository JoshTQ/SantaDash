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
| Holiday Bundle (Ugly Jumper suit + 2,500 Coal + Blessing, Dec 6 - Jan 5) | 199 | Art approved; hidden until the suit model is imported |
| Christmas Eve Suit (Midnight Frost, Dec 20 - Jan 5) | 149 | Art approved; hidden until imported |
| Sharky Claus suit (year-round) | 149 | Art approved; hidden until imported |
| Chrome Puffer suit (year-round) | 149 | Art approved; hidden until imported |

## Santa suits

Everyone has Classic Santa for free. The other suits unlock through the store
items above (`grants.cosmetic` = the suit id in `Config.Skins`). The Shop panel
lists every suit at the top: unlocked ones have a **Wear** button, locked ones
say how to get them. Wearing a suit isn't a purchase, so it works from the
first minute.

- The choice is saved as `skin` in PlayerData. A refunded suit falls back to Classic.
- `server/Skins.luau` swaps only Santa's `Body` mesh (all suits share his rig), so
  the clips, sack and Humanoid stay. It works mid-run, with no respawn.
- Each suit adds a trail while moving and a sparkle burst on Cheer
  (`client/SkinEffects.client.luau`). Phones get half the particles.
- A suit whose model isn't in ServerStorage.Assets yet (SantaJumper, SantaFrost,
  SantaShark, SantaChrome) shows as Classic until the Meshy import runs.
- To put a suit on sale: import its model, set `ready = true` and its `assetId`.

## Boots

Josh, 6 Nov 2026: boots are **saved and bought with Coal**, with **Robux
styles that only change the look**. The base pair is **Blade Skates**
(1,500 Coal, `Config.Boots`): faster on ice (36 instead of everyone's 30,
hoops 48 instead of 40) and a gold scratch trail under the blades. They're kept for good and saved as
`owned.SkateBoots`; the pair worn is `boots` in PlayerData.

- The Shop panel has a **Boots** section: Buy for Coal, then Wear / Take off.
  Coal isn't Robux, so the 3-minute rule doesn't apply.
- Boots are one model that goes on top of any suit (`shared/GearAttach.luau`,
  the same code the Lair's warm clothes use). `client/GearFollow.client.luau`
  moves it with Santa's foot bones. No suit needs a boots variation.
- A Robux style (`style = true, base = "SkateBoots"`) is cosmetic only: it
  gives no speed unless you own the Coal boots too. That rules out pay-to-win.
  No styles yet. They're planned after Meshy's credits reset on Dec 5.
- Approved 6 Nov and made in Meshy (`assets/models/SkateBoots.rbxm`:
  LeftBoot and RightBoot, each with `FollowBone`), so the boots are on sale.

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
