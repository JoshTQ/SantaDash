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
| `DogCorgi`, `DogTin` | `Humanoid`, `HumanoidRootPart` (anchored and moved along the patrol) | Block dogs |
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
- **Events:** `events = { { kind, weight } }` lists the random map events the
  map can roll (`src/server/MapEvents.luau`, numbers and off switches in
  `Config.MapEvents`). One roll per run (60%), never in a Krampus stop, warned
  8 s ahead and always over before the horn; `MapEventBrain` holds the rules.
- **Frozen Canal Town** (`Maps/FrozenCanal`, `server/CanalTown`, launch map):
  each street is a frozen canal (skate = WalkSpeed 24 on Ice, boost hoops 40)
  with pavements, front gardens, picket fences, hedges and bollard barriers
  with ICE gaps; a main canal with hoops joins the stops along the on-foot
  path. Stop 1 Christmas Market with security dogs (`DogCorgi` rams you and
  knocks a present out to grab back, `DogTin` bonks then winds down 3 s);
  Stop 2 Ice Rink Square with the ice polisher (scoops you into a snowbank);
  Stop 3 the Lair on a lake island with the bell bridge, and 8 s in Krampus
  stomps the lake into floes (fall in = SPLOOSH back onto a floe).
  `CanalTown.breakZone(part)` breaks any `IceZone` part into floes (Thin Ice
  uses it on `CrackZone` canal pieces). Stalls, hoops, rink, floes and the
  bridge are greybox until the canal kit is approved.
- **Dressing:** an approved Model in `ServerStorage.Maps.<dressing>` with
  `StopDressing` (cloned at every stop) and `RouteDressing` (once). Art only.

## Sounds

Every sound has a key in `src/shared/Sounds.luau` (51 keys, ranked in three
tiers). To give a key real audio, either:

- drop a `Sound` named after the key into `ReplicatedStorage.SoundAssets` in
  Studio (its SoundId, Volume and PlaybackSpeed are kept; the 3D range comes
  from the catalogue), or
- set its `id` in `Sounds.luau` to a Roblox audio asset id.

**Ready-made audio:** `assets/audio/<Key>.ogg` has an original cartoon sound
for every key, made from code by `tools/audio/synth.py` (re-run it to
regenerate). Upload them one of two ways:

- `ROBLOX_API_KEY=... ROBLOX_USER_ID=... python3 tools/audio/upload.py` (or `ROBLOX_GROUP_ID=...` if a group owns the experience; upload as the experience owner)
  uploads each file with Open Cloud (key needs Assets read/write) and writes
  the new ids into `Sounds.luau`. Re-running skips keys that have an id.
- Or in Studio: Asset Manager > Bulk Import the .ogg files, insert each one,
  and drop the Sounds into `ReplicatedStorage.SoundAssets` (names already match).

Roblox moderates audio uploads and caps how many you can upload a month, so
do Tier 1 first.

Keys with neither are silent (Studio prints one warning each with what to
search for), so the game runs before every sound is picked. Use the Creator
Store's Audio tab filtered to the **Roblox** creator so the audio is free and
licensed. World sounds (snoring parents, dogs, Krampus's bells, presents,
doors) are 3D and played by the server; music, the sleigh countdown, the
Krampus heartbeat and UI sounds are 2D on each client (`Audio.client.luau`).
Mix levels are in `Config.Audio` (kept under 1 for phone speakers).

## Lobby and run places (cross-server matchmaking)

The same build runs in two places. The **lobby place** queues crews and
teleports each one into its own reserved server of the **run place**, which
plays runs back to back for that crew and sends leavers back to the lobby.
`src/shared/Handoff.luau` is the contract between them: the lobby teleports
with `TeleportData = Handoff.make(crewId, kind, memberUserIds)`; the run server
only admits members of that crew and starts when they are all in, or after
`Config.Places.ArrivalTimeoutSeconds`.

### The Sleigh Station (lobby)

You spawn inside the Naughty Workshop, walk out past the top crews podium,
giant weekly present and Most Wanted wall, and follow the present path to a
signpost that forks to three bays: **Public** (anyone), **Party** (your group,
topped up with randoms) and **Private** (just your crew). Each bay runs a
timetable (`StationClock`): a sleigh pulls in, the gate opens under a
"BOARDING NOW!" sign, you step into the glowing zone to sit down (jump to hop
off), then the gate shuts and the sleigh leaves. Layout numbers are in
`Config.LobbyMap`, timings in `Config.Matchmaking` and `Config.LobbyMap`.

Cross-server (`Matchmaker`): Public riders queue in a shared MemoryStore queue
as soon as they sit; a Party sleigh queues its group when it leaves; any lobby
server packs crews (`CrewPacker`), reserves a run server, and announces it over
MessagingService so each lobby server teleports its own riders. Private sleighs
reserve a server straight away. If no crew forms within
`Config.Matchmaking.LocalFallbackSeconds` (queue down), riders run in the
lobby server instead.

**Place setup (once):** in one experience, create the lobby place (start
place) and a second run place, publish this build to both, put their IDs in
`Config.Places.Lobby` / `Config.Places.Run`, and turn on Studio Access to API
Services (MemoryStore). Teleports only work in a published game, so test
cross-server matchmaking with real servers, not Studio.

Until both places are published and their IDs are set in `Config.Places`,
everything runs in one server (the local `Lobby` runs the routes itself). To
test the run place on its own in Studio, set a `RunPlace = true` attribute on
Workspace; players with no TeleportData then join as a test crew.

## Tests

`lune run tests/runner` runs every spec (about 5 seconds); add `--coverage`
for the report. Filter by file name: `lune run tests/runner Loot`.

| Layer | Folder | What |
| --- | --- | --- |
| Unit | `tests/unit` | Pure rules: House Card rolls, stop plans, values, banking, results, Krampus and elf bot decisions, the lobby-to-run handoff, crew packing, station timetable, maps, map event rolls and timing, Assets lookups, Config invariants |
| Integration | `tests/integration` | MapBuilder, LobbyMap and the house kit build real Instances (Lune's Roblox library): counts, prompts, the Sleigh Stop, no overlapping houses, approved house / Lair / vault door / presents |
| Smoke | `tests/smoke` | Whole runs in a **headless world**: solo and crew runs, elf bots, buys, chimneys, doors, Krampus (snatch, wiggle, bells, hiding, gasps), every approved model, the HUD, edge cases and failures, and **matchmaking** (Quick Join, full sleighs, leaving, requeue, a busy server; the run place handoff, arrival timeout, strangers, back-to-back runs) |
| Regression | `tests/regression/DesignCalls.spec.luau` | Every call Josh has signed off, as unit checks and in whole runs. Add a test here for each new call and each bug fix |
| Static | | `stylua --check src tests`, `selene src`, `rojo build` |
| In-engine | `tests/engine` | Jest Roblox in a real Roblox server: approved sleigh, cocoa machine and set dressing placement, remotes, server clock, and a whole empty-crew run. CI `engine` job (Open Cloud); see below |
| Manual | | Feel, real physics, multi-player networking: Studio playtest |

CI (`.github/workflows/ci.yml`) runs all of it on every pull request.

Specs use a Jest-compatible subset (`describe`, `it`/`test`, `beforeEach`,
`afterEach`, `expect(x).toBe / toEqual / toContain / toThrow / never...`).
Services that aren't `src/` folders (`ServerStorage`, ...) are real empty
Instances; fill them through the `services` helper.

### Headless worlds

`tests/headless/Engine.luau` is a small model of the Roblox engine, so code
that needs the live engine runs in Lune too. `local world = headless()` gives
a world with its own Instances, players and module cache, with `src/` mounted
the way Rojo would (`world.load("ServerScriptService.Server.Run")`,
`world.runScript("ServerScriptService.Server.Main")`).

- **Virtual time:** `task.wait`, `os.clock`, `GetServerTimeNow` and Heartbeat run
  on a clock that only moves inside `world.run(fn)`; a 6-minute run takes a
  fraction of a second. In specs, wait with `world.wait(seconds)`.
- **Players:** `engine:addPlayer(name, { userId, joinData })`,
  `engine:teleport(player, position)`, `engine.trigger(prompt, player)`,
  `engine:hudMessages(player, kind)` (everything the server sent to the HUD).
- **Physics stand-ins:** Humanoid:MoveTo walks at WalkSpeed, welds follow,
  Touched fires when a character enters a part, pathfinding walks straight
  (`engine.pathfindingFails = true` tests the fallback).
- **Client:** `engine:setLocalPlayer(p)` and `world.runScript(...Hud)` run the
  HUD against the real server; `engine:guiShows(text)`, `engine:guiButton(text)`.
- `math.random` is seeded per world, so runs repeat exactly.

It is a model, not the engine: it can't catch real physics, rendering or
networking bugs, so Studio playtests still matter.

### Coverage

```
cargo build --release --manifest-path tools/luau-cov/Cargo.toml   # once
lune run tests/runner --coverage
```

`tools/luau-cov` adds line and function probes to every module under `src/`
(on the same line, so error line numbers don't move); the runner counts them
and writes `coverage/index.html` (per-file table, then each file's source with
covered lines green and missed lines red), `coverage/lcov.info` (for Codecov or
the VS Code Coverage Gutters extension) and `coverage/summary.md`. CI posts the
table to the job summary and uploads the report as the `coverage-report`
artifact. The 90% floor is advisory (a warning, not a failure, before launch).

### In-engine tests (Jest Roblox + Open Cloud)

Code that needs the live engine is tested with
[Jest Roblox](https://github.com/Roblox/jest-roblox) inside a real headless
Roblox server, through Open Cloud Luau Execution. The CI `engine` job:

1. `wally install` (Jest Roblox into `DevPackages/`)
2. `lune run tools/prepare-engine --coverage` copies `src/` to
   `build/engine-src/` with coverage probes
3. `rojo build test.project.json` builds the test place (`src/server` goes in
   `ServerStorage` so `Main` doesn't start a lobby)
4. `lune run tools/ocale build/engine-tests.rbxl --coverage` saves it as a new
   version of the test place, runs `ReplicatedStorage.RunTests` there, prints
   the Jest output, and merges the engine hit counts into the coverage report

Engine specs require everything from `JestGlobals` and use Jest's matchers
(`expect(x).never.toBeNil()`, `toBeCloseTo`, ...). The job is advisory until
after launch.

**One-time setup:**

1. Create a private test experience on Roblox (it never needs to be
   public). Note its universe ID and place ID.
2. Create an Open Cloud API key (Creator Dashboard > Open Cloud > API Keys)
   for that experience with `universe-places:write` and
   `luau-execution-sessions:write`.
3. In the GitHub repo settings, add the secret `ROBLOX_API_KEY`, and the
   variables `ROBLOX_UNIVERSE_ID` and `ROBLOX_TEST_PLACE_ID` (the EngineTests
   place; the deploy setup in docs/DEPLOY.md uses the same names).

Until then, the job only checks that the test place builds. To run the engine
specs by hand, build the test place, open it in Studio, and run
`print(require(game.ReplicatedStorage.RunTests)())` in the command bar.

## Layout

```
src/shared/Config.luau        every tuning number
src/shared/Remotes.luau       RemoteEvents (Hud, LeaveCrew, Input)
src/shared/Util.luau          clock, character helpers, weighted pick
src/shared/Sounds.luau        sound catalogue and pure cue rules (leave warning, noise, heartbeat)
src/shared/SoundPlayer.luau   plays catalogue sounds (3D on server, 2D on client)
src/server/Main.server.luau   entry point
src/server/Lobby.luau         what happens when a station sleigh leaves; same-server runs (fallback)
src/server/LobbyMap.luau      Sleigh Station lobby: workshop, show-off yard, present path, bays
src/server/Station.luau       bay timetable: sleighs, gates, boarding signs, seating
src/server/Matchmaker.luau    cross-server queue, reserved run servers, teleports
src/shared/CrewPacker.luau    pure crew packing from queue tickets
src/shared/StationClock.luau  pure bay timetable
src/server/RunHost.luau       run place: receive a crew, run back to back, return leavers
src/shared/Handoff.luau       lobby -> run place TeleportData contract
src/shared/Maps/              map definitions and the rotation
src/server/MapFeatures.luau   map-specific builders and per-stop runtime hooks
src/server/MapEvents.luau     random map events (Blizzard); rules in MapEventBrain
src/server/Run.luau           one crew's run: stops, phases, grabs, buys, noise, hiding, results
src/server/Krampus.luau       Krampus movement, snatch, carry, bells, wiggle
src/server/KrampusBrain.luau  pure Krampus decisions
src/server/ElfBot.luau        solo elf bots: follow, fetch presents, catch up
src/server/ElfBrain.luau      pure elf bot decisions
src/server/Mover.luau         pathfinding for Krampus and elf bots
src/server/Assets.luau        approved models from ServerStorage.Assets
src/server/HouseKit.luau      houses, Lair and vault door from the approved models
src/server/MapBuilder.luau    greybox houses, streets, sleigh, Krampus and elf stand-ins
src/server/Parts.luau         shared anchored-part helper for the builders
src/server/Loot.luau          pure House Card rolls, stop plans, loot and results
src/client/Hud.client.luau    timer, Jingle, sack, noise, bells, breath, wiggle, queue, results
src/client/Audio.client.luau  music, sleigh countdown, Krampus heartbeat, loot and UI sounds
tests/runner.luau             Lune test runner (tests/coverage.luau: coverage reports)
tests/unit, tests/integration, tests/regression   Lune specs
tests/engine                  Jest Roblox specs (in-engine tier)
tools/luau-cov                coverage instrumenter (Rust)
tools/prepare-engine.luau     builds src for the test place
tools/ocale.luau              runs the engine specs in Open Cloud
```
