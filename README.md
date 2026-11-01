# Sleigh Heist (Roblox)

Christmas co-op heist: a crew of grumpy naughty Santas robs a street of houses on
Christmas Eve, then escapes on the sleigh. Design source of truth:
`game-design.md` in the project files.

This repo is the **greybox**: plain Parts only, no art. Models go in only after
they are approved through the models gallery.

## Run it

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install`
   (Rojo 7.4, selene, StyLua, pinned in `rokit.toml`).
2. `rojo serve`, then in Studio open an empty Baseplate place, **delete the
   Baseplate**, and connect with the Rojo plugin.
3. Play (or use Test > Clients and Servers with 2-4 players to try a crew).

To build a place file instead: `rojo build -o SleighHeist.rbxl`.

Checks before pushing: `stylua src` and `selene src`.

## What the greybox does

| Piece | Behaviour |
| --- | --- |
| Sleigh Station hub | Spawn, Quick Join pad. A sleigh leaves 10 s after its first rider or when 6 are aboard. Up to 4 runs at once per server. |
| Run | Take-off flight, then 4 stops of 2:00: sneak to 0:45, lights on (Heat), horn at 1:30, sleigh leaves at 2:00 with or without you. |
| Streets | Near / Mid / Far rings (x1 / x1.5 / x2.5 loot). House Cards roll Cosy / Normal / Risky (Stop 1 has no Risky; always one Cosy). Chimneys, ladders, roof labels. |
| Loot | Presents with size-squared value, +25% per house threat. Sack holds 15 and is banked when you leave a stop on the sleigh. |
| Jingle | Start 500, earned per grab. Spend on the Far-ring Vault (1,000, opens for the crew) and Peppermint Rush (1,500, faster). |
| Noise | Shared meter per stop. Grabs and buys add noise, Heat adds more after the lights come on. |
| On foot | Miss the sleigh and follow the snowy path to the next stop; hidden presents on the way. |
| Finale | Stop 4 is Krampus's Lair with the Naughty List. Escaping on the sleigh doubles your loot. |
| Results | 10 s results with best thief and Coal, then the same crew requeues together ("Next run in 5..."). |

All tuning numbers live in `src/shared/Config.luau`.

## Layout

```
src/shared/Config.luau      every tuning number
src/shared/Remotes.luau     RemoteEvents (Hud, LeaveCrew)
src/server/Main.server.luau entry point
src/server/Lobby.luau       Quick Join queue, run slots, requeue
src/server/Run.luau         one crew's run: stops, phases, grabs, buys, noise, results
src/server/MapBuilder.luau  greybox hub, houses, streets, sleigh
src/server/Loot.luau        pure House Card and loot rolls
src/client/Hud.client.luau  timer, Jingle, sack, noise, banners, queue, results
```
