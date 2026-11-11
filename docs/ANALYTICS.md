# Player analytics: where players drop off

The game sends Roblox's own analytics events (AnalyticsService), so there is
nothing to sign up for. Everything shows in the **Creator Hub**: open
<https://create.roblox.com/dashboard/creations>, pick Sleigh Heist, then
**Analytics** in the left menu.

- Code: `src/server/Analytics.luau` sends the events. `src/shared/Funnels.luau`
  holds the steps and labels.
- Crash and error counts are separate (`Telemetry.luau`). See
  [DEPLOY.md](DEPLOY.md#watching-for-crashes-and-errors).

## Checking it works (do this first after a deploy)

1. Roblox only records events from **published servers**. Studio sends
   nothing. Play the published staging game on a phone or a second account.
2. Open **Analytics > Funnels** (or Economy, or Custom Events) and press
   **View Events** at the top. It lists events almost live.
3. Charts fill in about **24 hours** later.

Your own account joined before analytics existed, so it never enters the
first-game funnel (see "Who counts as new"). To see the onboarding steps
yourself, play once on a brand-new alt account.

To watch events in Studio without sending them, set
`Config.Analytics.PrintInStudio = true`. Each event then prints in Output as
`[Analytics] ...`.

## 1. First game (Analytics > Funnels > Onboarding)

This is the main drop-off chart. Each new player is counted once, and every
step is on the path every new player has to walk, in this order:

| Step | Name | Logged when |
| --- | --- | --- |
| 1 | Joined the game | Their save loads for the first time |
| 2 | Loaded in | Their game has loaded (the tips script is running) |
| 3 | Sat in a sleigh | They sit in any station sleigh |
| 4 | Crew found | Their crew leaves for a run (teleport, or a same-server run) |
| 5 | First run started | The take-off cutscene starts |
| 6 | Landed at Stop 1 | The sleigh lands at Stop 1 |
| 7 | Landed at Stop 2 | Same for Stop 2 |
| 8 | Reached Krampus's Lair | Same for the Lair |
| 9 | First heist finished | The results screen shows |
| 10 | Second run started | They start another run (any session) |

How to read the biggest drops:

- **2 to 3**: they loaded in but never sat in a sleigh. The lobby is confusing,
  or the Board tip and trail aren't working.
- **3 to 4**: they sat down but no crew left. This is the queue wait (see
  `CrewWait` and `LeftLobby` below).
- **5 to 6**: they left during the take-off cutscene or the first flight. If
  this drop is big, look at the cutscene freezes first.
- **9 to 10**: they finished one heist and didn't play again. This is the
  core fun check.

Who counts as new: a player whose save has under
`Config.Analytics.NewPlayerSeconds` (2 minutes) of play time the first time
analytics sees it. Everyone else is marked as having played before and never
enters this funnel, so old testers don't skew it. Progress is saved
(`data.analytics.onboarding`), so the funnel carries on across the lobby and
run places and across sessions. Roblox counts a step that was skipped as
done, which is why optional things like grabbing a present are custom
events, not steps.

**Never renumber or reorder these steps after launch.** Roblox stores the
numbers. Add new steps only at the end.

## 2. Every visit and every run (Analytics > Funnels)

These funnels count every visit and every run. Use them to compare new
players with veterans. Roblox lets you filter by step 1's fields only, so
step 1 carries the useful splits.

| Funnel | Steps | Step 1 fields (filters) |
| --- | --- | --- |
| **Lobby** | Loaded into the lobby, Sat in a sleigh, Crew found | 01: `First game` / `Played before` |
| **Run** | Run started, Landed at Stop 1, Landed at Stop 2, Reached Krampus's Lair, Run finished | 01: `1st run`, `2nd run`, `3-5 runs`, `6-20 runs`, `21+ runs`; 02: map; 03: `Solo` / `Crew of N` |
| **Shop** | Opened the store, Purchase prompt shown, Bought | 01: experience; 02: time played (`Under 3 min`, `3-10 min`, ...); 03: `Lobby` / `Run` |

A Break-out prompt from inside a run starts a Shop visit at step 2.

## 3. Coal and Jingle (Analytics > Economy)

| Currency | In (sources) | Out (sinks) |
| --- | --- | --- |
| **Coal** (saved) | `RunReward` (Gameplay), Robux packs such as `StarterSack` (IAP) | Boots by id, e.g. `BladeSkates` (Shop) |
| **Jingle** (one run only) | `Presents`, `NaughtyList`, `SecretRoom` (Gameplay) | `PeppermintRush` (Shop), `VaultDoor` (Gameplay), wardrobe gear such as `WearScarf` (Shop) |

Jingle from presents is added up and sent once per stop, so the event
counts stay well inside the rate limit.

## 4. Custom events (Analytics > Custom Events)

| Event | Value | Fields (01 / 02 / 03) |
| --- | --- | --- |
| `TipShown` | 1 | tip id (`Board`, `Sneak`, ...) / `Lobby` or `Run` |
| `TipDone` | 1 | tip id (only action tips: `Board`, `Grab`) / place |
| `TipsOff` | 1 | the tip that was showing when they pressed X / place |
| `LeftLobby` | 1 | `Exploring`, `Sitting in a sleigh`, `Queued for a crew`, `Crew leaving` / experience / time in the lobby |
| `CrewWait` | seconds from sitting in a sleigh to the crew leaving | wait bucket (`Under 10 s`, `10-30 s`, ...) / experience |
| `LeftRun` | 1 | where, e.g. `Takeoff`, `Stop 1: Sneak`, `Lair: Horn` / experience / `Quit the game` or `Left the crew` |
| `RunEnd` | 1 | `Escaped` or `Missed the last sleigh` / runs bucket / map |
| `Purchase` | Robux price | item id / time played / place |
| `FirstPurchase` | Robux price | item id / time played / runs bucket (once per player) |

Experience is `First game`, `Played before`, or `Unknown` (their save
hadn't loaded yet).

Good first charts:

- `LeftRun` split by field 01, filtered to `First game`. This shows the exact
  moment new players quit.
- `TipsOff` split by field 01. This shows which tip annoys players.
- `CrewWait` average value. If it goes over about 30 s, the queue is too
  slow.

Roblox also tracks retention (D1 and D7), session length and Robux revenue
by itself, under **Analytics > Engagement** and **Monetization**.

## 5. Inside a run (Analytics > Custom Events)

Each player gets a short report every time the sleigh leaves a stop.
"Stop" is `Stop 1`, `Stop 2` or `Lair`. "Experience" is `First game`,
`Played before` or `Unknown`.

| Event | Value | Fields (01 / 02 / 03) | Sent |
| --- | --- | --- | --- |
| `StopGrabs` | presents grabbed this stop (0 counts too) | stop / experience / `Aboard` or `Missed` | every stop |
| `StopLoot` | loot value banked this stop | stop / experience / crew | when they made the sleigh |
| `MissedSleigh` | 1 | stop / experience / `Had loot` or `Empty sack` | when they missed it |
| `FirstGrab` | seconds from landing to their first present | stop / experience / bucket | once a stop |
| `Spotted` | times grown-ups caught them in a house | stop / experience / crew | if it happened |
| `DogBump` | times a dog bumped them | stop / experience / crew | if it happened |
| `Hid` | times they hid in a wardrobe | stop / experience / crew | if it happened |
| `Frozen` | times they froze solid in Krampus's lake | stop / experience / crew | if it happened |
| `Snatched` | times Krampus caught them | stop / experience / crew | if it happened |
| `Freed` | seconds Krampus held them | `Wiggled free`, `Bells rung`, `Break-out` or `Krampus let go` / stop / experience | each release |
| `SecretFound` | 1 | secret kind / stop / experience | each find |
| `NaughtyListGrab` | 1 | experience / crew | each grab |
| `RunLoot` | final loot value | runs bucket / crew / `Escaped` or `Missed the last sleigh` | at the results |
| `Quit` | seconds on this server | `Lobby` or `Run` / experience / runs on this server | when they leave the game (not on a teleport) |

These are sent once per crew, so they count runs, not players:

| Event | Fields (01 / 02 / 03) |
| --- | --- |
| `NoiseAlarm` | stop / the phase when the meter filled (`Sneak`, `LightsOn`, `Horn`) / crew |
| `KrampusArrived` | stop / `On time` or `Too noisy` / crew |
| `MapEvent` | stop / event kind (e.g. `Blizzard`) / crew |

Questions these answer:

- **Is Stop 1 too hard for new players?** Look at `MissedSleigh` and
  `StopGrabs` at `Stop 1` for `First game`. Many misses or 0 grabs means it
  is.
- **Is Krampus fair?** Look at `Freed` split by field 01, and its average
  value. If most players only get free with `Krampus let go`, the wiggle is
  too hard or friends can't find the bells.
- **Do players find things?** Compare `SecretFound` with the number of runs.
  Also look at the average value of `FirstGrab`. Over about 20 s means the
  first stop is confusing.

## 6. How smoothly it runs (Analytics > Custom Events)

Each player's game measures its own frame rate and freezes
(`client/ClientStats.client.luau`) and reports them to the server. A
stutter is a frame over 0.25 s. A freeze is a frame over 1 s.

| Event | Value | Fields (01 / 02 / 03) |
| --- | --- | --- |
| `Device` | 1 | `Phone`, `Tablet`, `Computer`, `Console`, `VR` / experience / place |
| `LoadTime` | seconds until their game was running | bucket / device / experience |
| `CutscenePerf` | longest frame in ms during that cutscene | cutscene id (`KrampusArrives`, `Takeoff`, ...) / fps bucket / device |
| `CutsceneFreeze` | freezes during it | cutscene id / device / experience |
| `CutsceneSkipped` | seconds watched | cutscene id / experience |
| `Fps` | average fps over a minute of play | area (`Lobby`, `Stop 1`, `Lair`, `Flight`, ...) / device / fps bucket |
| `Freeze` | freezes in that minute | area / device / experience |

The server times its own frames too. Any frame over 0.5 s is counted as the
`ServerHitch` telemetry event, tagged with the cutscene that was playing,
for example `KrampusArrives 1-2 s`.

**Krampus cutscene freezes:** open `CutsceneFreeze` and `CutscenePerf`,
split by field 01, and filter to `KrampusArrives`.
- If only phones show it, the client can't keep up. The fix is lighter
  effects on phones.
- If `ServerHitch` also shows `KrampusArrives`, the server stalls while
  Krampus spawns. The fix is to build his model before the cutscene starts.

## Limits and privacy

- Roblox allows 120 + 20 x players events a minute across the whole game.
  Each server keeps to `PerMinuteBase` (10) + `PerMinutePerPlayer` (15) a
  minute, averaged over 5 minutes (`WindowSeconds`). This leaves room for
  the burst at the start of a run. Anything over that is dropped and
  counted as the `AnalyticsDropped` telemetry event, so the game is never
  throttled. A normal solo first run stays under it (a test checks this).
- Fields are a few fixed labels. Roblox folds anything past 8,000 distinct
  values into "Other". No names, user ids or chat text are ever sent.
- There are 4 funnels out of Roblox's 10, and about 50 custom event names
  out of 100, including the telemetry ones. Prefer a new field value over
  a new event name.
