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
| 4b | Walk past in front of a dog, then behind one, then tiptoe behind one in the first 45 s | In front: "?" then "!" within about a second, a bark, and it runs you down. Behind: a "?" from your footsteps and it turns to look. Tiptoeing behind it: nothing | Sight, hearing |
| 4c | Get chased, then break line of sight round a stall or house; also try skating up the canal | It runs to where it last saw you, sniffs, follows your trail (not along the ice), gives up after ~5 s. A chasing corgi pants after 4 s: that's your gap | Pathfinding on the real street, raycasts against real walls |
| 4e | Let a dog notice you, then hear you, then see you | Faint yellow "?" as it notices, RED "?" while it comes to look or sniffs round, big red "!" when it chases. A chase that can see you runs straight at you and lunges for the last few studs | The sight ray only reads walls in a real engine (the 11 Nov bug) |
| 4f | Let a corgi bump you with presents in your sack, then have a crewmate run it down | It runs off with a red present in its mouth (slower than you); touching it after a second makes it drop the present to grab back; left alone it drops it after 10 s | Real chasing |
| 4g | Buy a bone at the DOG TREATS tin by the Sleigh Stop sign (200 Jingle), press G toward a dog | The bone lands ~30 studs ahead; dogs within 50 studs trot over and chew for 8 s, ignoring you. Check the BONE button doesn't cover anything on a phone | HUD on touch |
| 4h | Stop 2: walk past the richer houses (Far ring, secret rooms) | A yard dog paces each front garden and won't chase far from home | Pathing in gardens |
| 4i | Get chased, run into a house and shut the front door | The dog comes through the dog flap at the foot of the door (Krampus and elves still can't) | Collision groups only exist in a real engine |
| 4d | After the lights come on | Dogs spot you from much further, the tin dog's head lamp sweeps the street and goes red when it chases | Lighting |
| 5 | Skate on a canal, fly through a gold **hoop** | Faster on ice (24), much faster for 1.5 s after a hoop (40), back to 16 on snow | FloorMaterial on a client-owned body |
| 6 | Stop 2: stand in the **ice polisher**'s path | WHOOSH, you land by a snowbank | |
| 7 | Stop 3, after the stomp: hop the round floes; then drop into the water and **swim** | The lake ice vanishes and leaves water; you swim (no snap back onto a floe), with a BODY HEAT meter under the timer that empties in ~10 s. You can climb out onto a floe, the island's shore ice and the bridge | Terrain water and Roblox's swimming only exist in a real engine |
| 7b | Keep swimming until the meter empties; then stand on the island by the fire pots | FROZEN SOLID: an ice cube for 3 s, then you're on the bridge or the island, slow for 4 s. By the fires the meter refills in about 1.5 s. Krampus walks the shore but never follows you in | |
| 7d | Buy all four warm-gear pieces at the Wardrobe rack by the cocoa machine, then try each suit | Scarf on the neck, mittens on both hands, Duckie Ring round the hips, bottle on the chest, following the animations on every suit (needs the boots PR #39 for the gear to show). Note any suit that needs a nudge in `Config.Gear.SuitNudge` | Bones only move on a real client |
| 7c | Swimming look | Santa paddles with his Walk clip (no Swim clip yet). Note if it looks silly enough to need a Meshy Swim clip | |
| 8 | Player 2: get snatched; player 1 rings the bells from behind | Captive rides in the basket, drops behind Krampus, can walk off | |
| 9 | Press reset mid-flight | You respawn seated in the sleigh | |
| 10 | Blizzard (set `Config.MapEvents.Chance = 1` before take-off) | Fog really closes in (you can't see the end of the street), snow falls, it clears after; snowballs splat your crewmate | The 4 Nov fog bug: Atmosphere overrode the fog |
| 11 | Back to hub | Leaves the run, back in the lobby | |
| 12 | **Playable Santa** (once `assets/models/Santa.rbxm` is in): spawn, stand, walk | You're the Meshy Santa with the sack on your back (not inside him, not floating); idle sways, walk legs match speed, feet on the ground | Bones, hip height and the sack offset (`SantaCharacter.SACK_OFFSET`) only show on a real client |
| 13 | Santa: move during the first 45 s of a stop, then after the lights come on | Tiptoe (Sneak) first, normal walk after | |
| 14 | Santa: grab a present; bank a sack at the sleigh | Bend-over grab; Victory cheer, also seen by the other player | Client-played tracks must replicate |
| 15 | **First-time tips** (fresh account, or Studio): spawn in the workshop | A gold tip card ("Follow the trail to a sleigh!"), a gold trail and ring on the Public bay, and a "First heist!" tag over your Santa that your friend can see | The trail is a client Beam; only a real client shows it |
| 16 | Tips: play the first run | One tip at a time, never over a cutscene: sneak (trail to the nearest door), grab, carry, lights on, horn (trail back to the ring), banked, Lair, Krampus, done. The tag goes after the run | |
| 18 | **Boots**: give yourself Coal in the command bar, buy Blade Skates in the shop, then change suits | Boots stay on both feet, follow the legs when walking and cheering, and fit every suit (watch Chrome Puffer's chunky legs) | Bone-following only shows on a real client. Nudge with `Config.Gear.SuitNudge`. If the toes point backwards, set yaw to 90 in `art/meshy/SkateBoots.json` and re-run the Meshy model workflow (free) |
| 19 | Boots: skate a canal and a hoop, next to a friend without boots | 36 on ice (friend 30) and 48 after a hoop. A gold scratch trail shows only on ice | |
| 17 | Tips: second run on the same account; then press X on a tip on another account | No repeats. X hides the card and trail and no tips come back | Saved only once the store thread's PlayerData is plugged in; until then progress resets when the server restarts |
| 18 | **Run map clarity** (6 Nov playtest fixes): land at Stop 1 and look down the street | A gold "ROB ME · n GIFTS" over each robbable house (through walls), "VAULT · ... Jingle to open" on the vault, front doors already open; the townhouses in between have no doors. Grab a gift: the count drops; empty a house: "EMPTY" in grey | |
| 19 | Skate the street canal, then the main canal | Clearly faster than walking (30 vs 16), Santa leans forward and sways, slow long strides, ice spray at the heels; a friend sees you skate too. Stops the moment you step off the ice | Lean direction: if he leans backwards, flip the sign in SkateLean |
| 20 | Miss the sleigh on purpose at Stop 1 | A gold line from you to the sleigh (and "SLEIGH 230" over it) the whole time, it follows to Stop 2's Sleigh Stop after take-off, orange after the horn, gone once you're aboard | |
| 21 | From Stop 1's far end (past the vault) follow the back lane | Ice all the way: back lane to Stop 2, on to the Lair lake; the raised Lair Lane leads to the castle's back gate, and stays solid after Krampus stomps the lake. Signposts at each junction | |
| 22 | **Lights on: "Who's there?!" checks.** Grab a present at Stop 1, then stay inside a marked house after 0:45 | Within ~16 s the house light flickers orange, a grumble plays and "WHO'S THERE?!" floats over the roof (you get a banner). If you're still inside: white flash, SPOTTED banner, a red present drops on the floor, the NOISE meter jumps and you land outside the front door. Hide in the wardrobe or step out and nothing happens. Houses take turns, not all at once | Note if the warning feels too short on a phone (`Config.LightsCheck.WarnSeconds`) or checks too frequent (`Interval`) |
| 23 | **Naughty List heist** (Josh, 11 Nov). Two players. In the Lair, steal the List | The book hovers over your head with a gold glow and a PASS LIST (Q) button; you walk at 15 and Krampus Bell Blinks to you more. A wardrobe says the List rattles too much to hide | The weld to a client-owned body only shows on a real client |
| 23b | Stand 10 studs from your friend and press Q; then get snatched while carrying; then jump in the lake with it | Your friend catches it. Snatched: it drops on the floor, "Grab" on it. Lake: it bobs for 5 s then flies back to the pedestal | |
| 23c | Escape with it, then play again and escape without it | "LOOT x2" in the Getaway and double loot in the results; without it the Getaway says "NO LIST, NO x2" and loot isn't doubled | |
| 24 | **Cuckoo Watch**: stand in the den after Krampus arrives | About every 12 s: "TICK TOCK... FREEZE!", the cuckoo pops out of the clock, "CUCKOO! DON'T MOVE!". Keep walking: "CUCKOO! The clock saw you move!" and Krampus pops up next to you. Stand still and nothing happens. The doors shut as the look ends | Note if 1.25 s is too short to stop on a phone (`Config.CuckooWatch.WarnSeconds`), and whether the stand-in sounds need real picks |
| 25 | **Gingerbread Mansion** at Stop 2 (right bank, between the Sleigh Stop and the Ice Rink): walk in, climb both flights of stairs and the ladder to the attic | "SEARCH ME · 8 GIFTS" over the roof. The stairs climb without jumping (also on a phone); the gallery rails stop you falling into the hall; the attic truss lets you climb in and out. Krampus-sized doors | Step height and truss climbing only show on a real client |
| 26 | Mansion: hold Search on a few spots, open boxes under the tree, then the piano | Doors, drawers and lids open and glow gold for your friend too; a gift appears in some (bigger upstairs), others puff dust and give +10 Jingle. One tree box wobbles now and then: it's the real one; the rest POP with confetti and noise. The piano PLONKs and fills the noise meter a lot | Sounds are placeholders (GiftPop, DustPuff, PianoPlonk reuse the boing and rustle): note any that feel wrong |

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
| 7 | First-time tip card | Readable, under the stop timer, the X is easy to tap, and it says "Hold the button" rather than "Hold E" |
| 8 | Level of detail: ride the sleigh from Stop 1 to Stop 2 | Stop 1's bulbs and trim fade out behind you and Stop 2 is fully dressed before you land. No hole in the street, no tree popping in right next to you |
| 9 | Level of detail on/off: in the Studio command bar run `workspace:SetAttribute("DetailOff", true)`, then `nil` | With it off the frame rate drops at Stop 1 (that's what the culler saves). If a part you can see up close vanishes with it on, note its name |
| 10 | Respawn or get snatched by Krampus | Nothing missing under your feet when you land (a camera jump brings everything near back that frame) |
| 11 | The Lair lake: swim | The water surface sits just under the floes and the island ice (no gap you can see under them), no frame hitch when the lake fills on landing |
| 12 | **HUD polish (11 Nov)**: first run on a phone, through the Lair | Banners sit in a dark pill under the stop timer; a tip card, the map event chip and the BODY HEAT bar stack under it and never cover each other |
| 13 | Buttons on a phone, then plug in a controller | Phone: "TAP!" and "THROW" with no keyboard keys; controller: "TAP! (A)" and "THROW (R2)" |
| 14 | Grab, get bumped by a corgi, bank, buy cocoa | "+30" floats off the sack row, gold "+5" off Jingle, red "-1" on a knock-out, green "+90" on the banked row, orange "-20" when you spend. A full sack turns the row red with FULL |
| 15 | The horn's last 10 s | The timer throbs, harder in the last 5 s |
| 16 | Tap **Back to hub** once, wait; then twice | Once: "Tap again to leave", back to normal after 3 s, you stay in the run. Twice: you leave |
| 17 | Results with two players | Your own row is gold and "You got +N Coal!" sits above the footer; the fanfare or trombone matches your own result |
| 18 | **Music** button (top-left in the hub, beside Back to hub in a run): tap it, then rejoin | Music stops (sound effects and cutscenes keep playing), the button says Music: OFF, and it's still off after rejoining or teleporting to the run place |
| 19 | Results | "You got +N Coal!" counts up and swells when it lands; under the list: "You grabbed N presents · escaped x2!"; on a first heist also "Spend Coal in the Shop" |
| 20 | Lair: let Krampus get within ~100 studs while you look away from him, then turn round | A red arrow with KRAMPUS! on the screen edge points at him, follows smoothly as you turn, gets brighter as he closes in, and goes the moment he's on screen. Never shows while hiding, snatched or in a cutscene |
| 21 | **Round 2 (11 Nov)**: Lair with 3+ players: Krampus arrives while someone grabs the List and someone gets iced | Up to three banner pills under the timer (newest at the bottom, biggest); "KRAMPUS IS COMING!" stays while crew news comes and goes. The big CUCKOO words sit above the banners, never on them |
| 22 | Watch the take-off, Krampus and getaway cutscenes | No HUD under the letterbox (stats, buttons, tips all hidden); it all comes back the moment the cutscene ends, and a banner sent during it then shows for about 3 s |
| 23 | Hide in a wardrobe, come out, then get Frost Zapped | The ice-cube panel has only TAP!, no "Come out" |
| 24 | Phone: carry the Naughty List; pick up a dog treat | Buttons say PASS LIST and BONE (no Q or G); their banners say "PASS LIST to a friend" / "Throw it with BONE" |
| 25 | Escape the Lair WITHOUT the Naughty List, then with it | Results say "(escaped)" without it (it used to say "escaped x2" either way), "(escaped x2)" with it |

## 3. Lobby to Run place (Staging only)

Two accounts on Staging: board the Public sleigh together, both arrive in the
same Run server, play, both come back to the lobby together. The automated
`tests/smoke/CrossServer.spec.luau` fakes MemoryStore and TeleportService;
this is the only check against the real ones.

Log anything odd in the project thread with the step number.
