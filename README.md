# Sleigh Heist (Roblox)

Christmas co-op heist: a crew of grumpy naughty Santas robs a street of houses on
Christmas Eve, then escapes on the sleigh. Design source of truth:
`game-design.md` in the project files.

This repo is the **greybox**: plain Parts only. Models go in only after they are
approved through the models gallery. Each approved model is dropped into
`ServerStorage.Assets` under its name and the game uses it instead of the
stand-in (a model missing a required part is skipped with a warning):

| Asset | Required parts | Stand-in until then |
| --- | --- | --- |
| `Krampus` | `Humanoid`, `HumanoidRootPart`, `Basket` | Blocks in the Shaggy Goat Grump colours |
| `Sleigh` | PrimaryPart `Body`, `Seat1`-`Seat6`, `Horn`, `Lantern`, `Hitch` | Red block sleigh |
| `Reindeer` | PrimaryPart `Body`, `Head`, four legs on Motor6Ds | None (two hitched in front of the sleigh) |
| `ElfA`, `ElfD` | `Humanoid`, `HumanoidRootPart` | Green and red block elves |
| `House` (any number, or an `Assets.Houses` folder) | `Floor`, `TypeSign`, `ChimneyTop`, `Fireplace`, `Wardrobe`, `FrontDoor` > `Door`, `PresentSpawn1`-`8`; attribute `Style` | Block houses. Any style anywhere; the Far ring prefers `Style = "alpine"` |
| `KrampusLair` | `Floor`, `ListPedestal`, `KrampusSpawn`, `HideSpot1`-`2` | Block Lair |
| `VaultDoor` | `Frame`, `Door` (hinged on its left edge) | Gold block door |
| `CocoaMachine` | `Body`, `BuyPrompt` attachment | Brown block |
| `Present` (any number, or an `Assets.Presents` folder) | `Box` (recoloured per present), `Ribbon`, `Bow` | Box with ribbons; scaled so the Box's longest side matches the present's size |
| `NaughtyList` | a PrimaryPart (the `Book`) | Gold scroll |

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
| Run | Take-off flight to each stop's Sleigh Stop (a clearing on the ground; inside it when the sleigh leaves = aboard), then 3 stops of 2:00 (two house stops, then Krampus's Lair): sneak to 0:45, lights on (Heat), horn at 1:30, sleigh leaves at 2:00 with or without you. |
| Streets | Near and Far rings (x1 / x2.5 loot); the Mid ring is configured but off for launch. House Cards roll Cosy / Normal / Risky (Stop 1 has no Risky; always one Cosy). Chimneys, ladders, wardrobes, roof labels. |
| Loot | Presents with size-squared value, +25% per house threat. Sack holds 15 and is banked when you leave a stop on the sleigh. |
| Jingle | Start 500, earned per grab. Spend on the Far-ring Vault (1,000, opens for the crew) and Peppermint Rush (1,500, faster). |
| Noise | Shared meter per stop. Grabs and buys add noise, Heat adds more after the lights come on. |
| Krampus | From Stop 3 (always in his Lair): hunts the nearest Santa he can sense, snatches them into his basket (perks lost), carries them around. Ring the bells behind him to make him spin and drop them; or tap 15 times to wiggle free. Hide in a wardrobe and tap to hold your breath while he's near, or you gasp and give yourself away. |
| Elf bots | Solo runs get 2 elf bots, always one of design A and one of design D. They follow you, fetch presents near you into your sack (not from a locked vault) and hop to you after chimneys and flights. Solo runs pay 80% loot so playing with friends is better. |
| On foot | Miss the sleigh and follow the snowy path to the next stop; hidden presents on the way. |
| Finale | Krampus's Lair holds the Naughty List. Escaping on the sleigh doubles your loot; missing it keeps only half of your unbanked sack. |
| Results | 10 s results with best thief and Coal, then the same crew requeues together ("Next run in 5..."). |

All tuning numbers live in `src/shared/Config.luau`.

## Maps

Each run picks a map from `Maps.Rotation` (never the one the crew just
played, when there is a choice). A map is a pure definition in
`src/shared/Maps/` (palette, layout, features, set dressing); gameplay is
always built procedurally from it, so every map gets houses, presents,
Krampus and the sleigh. `Maps/SnowyStreet.luau` is the reference shape.

- **Layout:** street slots, widths and spacing override `Config`. `StopOrigins`
  puts each stop anywhere (curves, opposite banks); `EndHouseAt` places a stop
  kind's Vault or Lair (e.g. the Lair on an island).
- **Features:** `src/server/MapFeatures.luau` entries with `build` (Instances,
  no events) and `start` (runtime behaviour per stop, returns a cleanup).
- **Dressing:** an approved Model in `ServerStorage.Maps.<dressing>` with
  `StopDressing` (cloned at every stop) and `RouteDressing` (once). Art only.

## Lobby and run places (cross-server matchmaking)

The same build runs in two places. The **lobby place** queues crews and
teleports each one into its own reserved server of the **run place**, which
plays runs back to back for that crew and sends leavers back to the lobby.
`src/shared/Handoff.luau` is the contract between them: the lobby teleports
with `TeleportData = Handoff.make(crewId, kind, memberUserIds)`; the run server
only admits members of that crew and starts when they are all in, or after
`Config.Places.ArrivalTimeoutSeconds`.

Until both places are published and their IDs are set in `Config.Places`,
everything runs in one server (the local `Lobby` runs the routes itself). To
test the run place on its own in Studio, set a `RunPlace = true` attribute on
Workspace; players with no TeleportData then join as a test crew.

## Tests

| Layer | What | How |
| --- | --- | --- |
| Unit | Pure rules: House Card rolls, stop plans, values, banking, results, Krampus decisions (arrival, targeting, bells, breath, wiggle), elf bot decisions (design mix, present picks), lobby-to-run handoff (validation, admission, departure), map registry and rotation, Config invariants | `lune run tests/runner` |
| Integration | MapBuilder builds real Instances (Lune's Roblox library) from real plans: counts, prompts, sleigh on the ground at the Sleigh Stop, no overlapping houses, approved house kit / Lair / vault door (with stand-in models), Krampus and elf rigs, sleigh seats, vault presents, map palette/layout/features/stop origins, every map in the rotation | same command |
| Static | Format, lint, place build | `stylua --check src tests`, `selene src`, `rojo build` |
| E2E | Not automated yet; see below | Studio playtest |

CI (`.github/workflows/ci.yml`) runs all of the above on every pull request.
Filter tests by file name: `lune run tests/runner Loot`.

The test runner loads modules straight from `src/` with a fake `game`/`script`/
`require`, so keep rule code in pure modules (`Loot`, `KrampusBrain`, `ElfBrain`, `Handoff`, `Util`)
and keep `MapBuilder` free of events. Code that needs the live engine (`Run`,
`Lobby`, `Krampus` and `ElfBot` movement, physics, pathfinding, remotes) is covered by the
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
src/shared/Cutscenes.luau     the five short cutscenes: timing, camera keys, text pops, gags
src/shared/Util.luau          clock, character helpers, weighted pick
src/server/Main.server.luau   entry point
src/server/Lobby.luau         Quick Join queue, run slots, requeue (single-server mode)
src/server/RunHost.luau       run place: receive a crew, run back to back, return leavers
src/shared/Handoff.luau       lobby -> run place TeleportData contract
src/shared/Maps/              map definitions and the rotation
src/server/MapFeatures.luau   map-specific builders and per-stop runtime hooks
src/server/Run.luau           one crew's run: stops, phases, grabs, buys, noise, hiding, results
src/server/Krampus.luau       Krampus movement, snatch, carry, bells, wiggle
src/server/KrampusBrain.luau  pure Krampus decisions
src/server/ElfBot.luau        solo elf bots: follow, fetch presents, catch up
src/server/ElfBrain.luau      pure elf bot decisions
src/server/Mover.luau         pathfinding for Krampus and elf bots
src/server/Assets.luau        approved models from ServerStorage.Assets
src/server/HouseKit.luau      houses, Lair and vault door from the approved models
src/server/MapBuilder.luau    greybox hub, houses, streets, sleigh, Krampus and elf stand-ins
src/server/Loot.luau          pure House Card rolls, stop plans, loot and results
src/client/Hud.client.luau    timer, Jingle, sack, noise, bells, breath, wiggle, queue, results
src/client/CutscenePlayer.luau plays a cutscene locally: letterbox, camera, pops, Skip
tests/runner.luau             Lune test runner
tests/unit, tests/integration specs
```
