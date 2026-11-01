# Sleigh Heist (Roblox)

Christmas co-op heist: a crew of grumpy naughty Santas robs a street of houses on
Christmas Eve, then escapes on the sleigh. Design source of truth:
`game-design.md` in the project files.

This repo is the **greybox**: plain Parts only. Models go in only after they are
approved through the models gallery. Krampus is a block stand-in in the approved
Shaggy Goat Grump colours; drop a Model named `Krampus` (with a `Humanoid`, a
`HumanoidRootPart` and a part named `Basket`) into `ServerStorage.Assets` and the
game uses it instead.

## Run it

1. Install the toolchain with [Rokit](https://github.com/rojo-rbx/rokit): `rokit install`
   (Rojo, selene, StyLua and Lune, pinned in `rokit.toml`).
2. `rojo serve`, then in Studio open an empty Baseplate place, **delete the
   Baseplate**, and connect with the Rojo plugin.
3. Play (or use Test > Clients and Servers with 2-4 players to try a crew).

To build a place file instead: `rojo build -o SleighHeist.rbxl`.

## What the greybox does (15 Nov launch slice)

| Piece | Behaviour |
| --- | --- |
| Sleigh Station hub | Spawn, Quick Join pad. A sleigh leaves 10 s after its first rider or when 6 are aboard. Up to 4 runs at once per server. |
| Run | Take-off flight, then 3 stops of 2:00 (two house stops, then Krampus's Lair): sneak to 0:45, lights on (Heat), horn at 1:30, sleigh leaves at 2:00 with or without you. |
| Streets | Near and Far rings (x1 / x2.5 loot); the Mid ring is configured but off for launch. House Cards roll Cosy / Normal / Risky (Stop 1 has no Risky; always one Cosy). Chimneys, ladders, wardrobes, roof labels. |
| Loot | Presents with size-squared value, +25% per house threat. Sack holds 15 and is banked when you leave a stop on the sleigh. |
| Jingle | Start 500, earned per grab. Spend on the Far-ring Vault (1,000, opens for the crew) and Peppermint Rush (1,500, faster). |
| Noise | Shared meter per stop. Grabs and buys add noise, Heat adds more after the lights come on. |
| Krampus | From Stop 3 (always in his Lair): hunts the nearest Santa he can sense, snatches them into his basket (perks lost), carries them around. Ring the bells behind him to make him spin and drop them; or tap 15 times to wiggle free. Hide in a wardrobe and tap to hold your breath while he's near, or you gasp and give yourself away. |
| On foot | Miss the sleigh and follow the snowy path to the next stop; hidden presents on the way. |
| Finale | Krampus's Lair holds the Naughty List. Escaping on the sleigh doubles your loot; missing it keeps only half of your unbanked sack. |
| Results | 10 s results with best thief and Coal, then the same crew requeues together ("Next run in 5..."). |

All tuning numbers live in `src/shared/Config.luau`.

## Tests

| Layer | What | How |
| --- | --- | --- |
| Unit | Pure rules: House Card rolls, stop plans, values, banking, results, Krampus decisions (arrival, targeting, bells, breath, wiggle), Config invariants | `lune run tests/runner` |
| Integration | MapBuilder builds real Instances (Lune's Roblox library) from real plans: counts, prompts, sleigh on the roof, no overlapping houses, Krampus rig | same command |
| Static | Format, lint, place build | `stylua --check src tests`, `selene src`, `rojo build` |
| E2E | Not automated yet; see below | Studio playtest |

CI (`.github/workflows/ci.yml`) runs all of the above on every pull request.
Filter tests by file name: `lune run tests/runner Loot`.

The test runner loads modules straight from `src/` with a fake `game`/`script`/
`require`, so keep rule code in pure modules (`Loot`, `KrampusBrain`, `Util`)
and keep `MapBuilder` free of events. Code that needs the live engine (`Run`,
`Lobby`, `Krampus` movement, physics, pathfinding, remotes) is covered by the
playtest checklist until E2E is set up.

**E2E plan:** Roblox Open Cloud's Luau Execution API runs a script inside a
real headless server for a published place. A CI job would publish the built
place to a private test universe, then run a script that starts a run with
the server's own logic and asserts on it (route built, Krampus pathfinds into a
house, phases advance on time). It needs a test universe and place ID and an
Open Cloud API key stored as a repo secret. Multi-player behaviour (bells,
rescues, the sleigh carrying riders) still needs Studio's Test > Clients and
Servers.

## Layout

```
src/shared/Config.luau        every tuning number
src/shared/Remotes.luau       RemoteEvents (Hud, LeaveCrew, Input)
src/shared/Util.luau          clock, character helpers, weighted pick
src/server/Main.server.luau   entry point
src/server/Lobby.luau         Quick Join queue, run slots, requeue
src/server/Run.luau           one crew's run: stops, phases, grabs, buys, noise, hiding, results
src/server/Krampus.luau       Krampus movement, snatch, carry, bells, wiggle
src/server/KrampusBrain.luau  pure Krampus decisions
src/server/MapBuilder.luau    greybox hub, houses, streets, sleigh, Krampus stand-in
src/server/Loot.luau          pure House Card rolls, stop plans, loot and results
src/client/Hud.client.luau    timer, Jingle, sack, noise, bells, breath, wiggle, queue, results
tests/runner.luau             Lune test runner
tests/unit, tests/integration specs
```
