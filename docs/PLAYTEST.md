# Playtest script (what only real players can test)

CI covers everything a server can check on its own: Lune specs, headless
whole runs, and real physics in the EngineTests place (`tests/engine`). Open
Cloud servers have **no clients**, so these still need a person:

- physics simulated by a player's own client (their character)
- the HUD, touch controls and camera on a real screen
- teleports between the Lobby and Run places

About 20 minutes. Do it on Staging after any change to physics, controls,
the HUD or the map, and once on a phone before launch.

## 0. Studio physics specs (2 min)

Open Cloud test servers don't simulate physics, so the physics specs
(`tests/studio`) run in Studio:

1. `wally install && lune run tools/prepare-engine && rojo build test.project.json -o build/engine-tests.rbxl`
   (or open the EngineTests place, which CI saves on every run).
2. Open it in Studio, press **Run** (F8, server only: physics on, no character).
3. Command bar: `print(require(game.ReplicatedStorage.RunTests)("StudioTests"))`
4. Expect `"success":true`. Paste the Output into the thread if not.

## 1. Studio, 2 players (15 min)

Studio > Test > Clients and Servers > **2 players**, Run place
(Workspace attribute `RunPlace = true`). Shorten the clock while testing:
in the server's command bar, `require(game.ReplicatedStorage.Shared.Config).Run.StopSeconds = 60`.

| # | Do | Expect | Why it isn't automated |
| --- | --- | --- | --- |
| 1 | Both board, take off | Both ride in seats the whole flight, no jitter worse than a little stepping; land standing on the sleigh | Client-owned characters, anchored by the server |
| 2 | Stop 1: walk into a **corgi** with presents in your sack | You're shoved ~6-10 studs away with a small hop; a red present drops; you can grab it back; results screen grabs count doesn't go up for the re-grab | The 4 Nov knockback bug: only a real client shows if the push lands |
| 3 | Walk into a **tin dog** | BONK banner, a small shove, the dog stops for 3 s | Same |
| 4 | Stand on a garden wall or roof above a dog's path | No bumps | Height check |
| 5 | Skate on a canal, fly through a gold **hoop** | Faster on ice (24), much faster for 1.5 s after a hoop (40), back to 16 on snow | FloorMaterial on a client-owned body |
| 6 | Stop 2: stand in the **ice polisher**'s path | WHOOSH, you land by a snowbank | |
| 7 | Stop 3, after the stomp: hop floe to floe; then step into the water and **keep walking** | Splash back onto a floe every time you touch water, including when you keep walking on it (the old bug let you stroll across) | Real jumping and landing |
| 8 | Player 2: get snatched; player 1 rings the bells from behind | Captive rides in the basket, drops behind Krampus, can walk off | |
| 9 | Press reset mid-flight | You respawn seated in the sleigh | |
| 10 | Blizzard (set `Config.MapEvents.Chance = 1` before take-off) | Fog really closes in (you can't see the end of the street), snow falls, it clears after; snowballs splat your crewmate | The 4 Nov fog bug: Atmosphere overrode the fog |
| 11 | Back to hub | Leaves the run, back in the lobby | |

## 2. Phone (5 min)

Studio's Device Emulator (iPhone SE, landscape) first, then a real phone on
Staging.

| # | Check | Expect |
| --- | --- | --- |
| 1 | Top bar in a run | Stats, stop timer and noise meter don't overlap (the HUD scales down) |
| 2 | Thumbstick corner | Nothing of ours under the stick; **Back to hub** is top-left |
| 3 | Jump button corner | During a Blizzard the THROW button sits above the jump button, not on it |
| 4 | Hide in a wardrobe | The TAP button and Come out are both tappable |
| 5 | Frame rate at Stop 1 (market, ~200 bulbs in view) and the Lair | Smooth (Ctrl/Cmd+F5 in Studio; a real phone should feel steady). Note the device if not |
| 6 | Blizzard | Lighter snowfall than on PC, still readable |

## 3. Lobby to Run place (Staging only)

Two accounts on Staging: board the Public sleigh together, both arrive in the
same Run server, play, both come back to the lobby together. The automated
`tests/smoke/CrossServer.spec.luau` fakes MemoryStore and TeleportService;
this is the only check against the real ones.

Log anything odd in the project thread with the step number.
