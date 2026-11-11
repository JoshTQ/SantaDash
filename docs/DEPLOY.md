# Deploying Sleigh Heist to Roblox

Everything ships through GitHub Actions (`.github/workflows/deploy.yml`) and
Roblox Open Cloud. After the one-time setup below, you never publish from
Studio again.

```
push to main          tests -> engine tests -> Staging experience (private)
tag v0.1.0            tests -> engine tests -> Staging -> [you approve] -> Live experience
Actions > Deploy >    pick staging or production by hand
  Run workflow
```

Each deploy:

1. runs format, lint and the Lune tests, and builds both environments;
2. runs the in-engine Jest Roblox specs on a private test place (once the
   Jest Roblox PR is merged and step 4 is done);
3. stamps that experience's place ids into `Config.Places` (the repo keeps
   `0`, which means single-server mode for Studio and tests) and adds a
   `Shared.BuildInfo` module with the commit;
4. stops if the place contains anything Open Cloud can't publish
   (SurfaceAppearance, unions, ...);
5. **smoke test**: saves the build as an *unpublished* version of the Lobby
   place, starts a real Roblox server on it, loads every server and shared
   module and checks the place ids. Players never see this version;
6. publishes the **Run place first, then the Lobby**, so a new lobby never
   teleports a crew into an old run build.

## One-time setup (about 30 minutes)

### 1. Decide who owns the game: you or a group

Make this call before creating anything, because it is painful to change:
the experiences, the API key, every audio and model asset, and later the
game passes and developer products must all belong to the same owner, or
the game can't load its sounds and models.

| Owner | Pick it if | Note |
| --- | --- | --- |
| A Roblox group (recommended) | Anyone else may ever help, or you want Robux to go to a group | Make the group first; create the API key from the group's Creator Dashboard |
| Your account | It stays a solo project | Simplest; everything below under your profile |

### 2. Create two experiences, each with a Lobby and a Run place

Open Cloud can update places but can't create them, so do this once in
Studio. Cross-server teleports only work between places of the same
experience, so each experience needs both.

| Experience | Places | Who can play |
| --- | --- | --- |
| **Sleigh Heist (Staging)** | Lobby (start place), Run, EngineTests | Private: you and testers |
| **Sleigh Heist** (the live game) | Lobby (start place), Run | Private until launch day, then Public |

For each experience:

1. Studio > New > Baseplate. Delete the Baseplate. File > Publish to Roblox >
   Create new experience (choose the owner from step 1). This is the
   **Lobby** (start place).
2. View > Asset Manager > Places > right-click > **Add New Place**. Rename it
   **Run**. For Staging, add a third place called **EngineTests**.
3. Home > Game Settings > Security: turn on **Enable Studio Access to API
   Services** (for MemoryStore in Studio playtests).
4. Write down the ids (see "Which id is which" below).

#### Which id is which

"Experience" and "universe" are the same thing on Roblox: one experience id,
plus one place id per place.

| Id | Where to find it |
| --- | --- |
| **Universe id** (= experience id) | create.roblox.com > Creations > click the experience. The number in the URL: `.../experiences/`**`1234567890`**`/overview` |
| **Place id** (one per place) | Same page > **Places** in the left menu > click a place. The number in that URL. Or in Studio: Asset Manager > Places > right-click the place > Copy ID |

### 4. GitHub secret and variables

At **Settings > Secrets and variables > Actions** (repo level, no
environments needed for Staging):

| Tab | Name | Value |
| --- | --- | --- |
| Secrets | `ROBLOX_API_KEY` | the key from step 3 |
| Variables | `ROBLOX_UNIVERSE_ID` | Staging universe id |
| Variables | `ROBLOX_LOBBY_PLACE_ID` | Staging **Lobby** place id |
| Variables | `ROBLOX_RUN_PLACE_ID` | Staging **Run** place id |
| Variables | `ROBLOX_TEST_PLACE_ID` | Staging **EngineTests** place id |
| Variables | `DEPLOY_ENABLED` | `true` |

That's all Staging needs. Deploys stop at Staging until `PRODUCTION_ENABLED`
is set (step 5).

### 5. Later: the live experience

When the live experience exists, add an environment at **Settings >
Environments > New environment** called **production** with:

- Environment variables `ROBLOX_UNIVERSE_ID`, `ROBLOX_LOBBY_PLACE_ID` and
  `ROBLOX_RUN_PLACE_ID` set to the **live** ids. They override the repo
  (Staging) values for the production deploy only.
- **Required reviewers**: add yourself. Every live deploy then waits for you
  to press Approve in the Actions run.
- **Deployment branches and tags**: "Selected branches and tags", add `main`
  and the tag pattern `v*`, so nothing else can reach the live game.

Then add the repo variable `PRODUCTION_ENABLED` = `true`.

### 6. First deploy

1. Actions > **Deploy** > Run workflow > target `staging`. The run summary
   shows the place versions it published.
2. Play Staging with two accounts (or a friend): join the Lobby, Quick Join a
   sleigh together, and check you both land in the same Run server and come
   back to the lobby after the results. Open Cloud can't test teleports or
   real players, so this check stays manual.
3. When happy, tag a release: `git tag v0.1.0 && git push origin v0.1.0` (or
   Run workflow > `production`). Approve the `production` step when asked.

### 7. Launch-day checklist for the live experience (Creator Dashboard)

These are one-off settings Open Cloud doesn't cover:

- Experience Questionnaire (maturity / content labels): required before it
  can go public.
- Name, description, icon and thumbnails; genre; supported devices
  (phone/tablet matter for this audience).
- Access: Public on launch day.
- Places > Run: leave it as a non-start place. Players who somehow join it
  directly are sent back to the Lobby by `RunHost`.

## Day to day

| I want to | Do |
| --- | --- |
| Ship to testers | Merge to `main` |
| Ship to players | Push a `v*` tag, approve the production step |
| Push a hotfix to live now | Actions > Deploy > Run workflow > production, tick **Restart live servers** if old servers must go |
| Roll back | Creator Dashboard > the place > Version History > restore the previous version, for **Run and Lobby** both. Or re-run an older successful Deploy run |
| Test a build without publishing | `lune run tools/deploy staging --dry-run` (no key needed), then open `build/SleighHeist-staging.rbxl` |
| Add an approved model | Export it from Studio as `.rbxm` into `assets/models/` (see the README there) |

**Restarting servers** (`--restart`, the "Restart live servers" box) is the
same as "Restart servers for updates" in the Creator Dashboard: players
mid-run get disconnected, so production only does it when you tick the box.
Staging always does. Without it, old servers keep running the old build until
they empty, and new players get the new one. Because old lobbies can still
teleport crews into new run servers for a while, keep the lobby-to-run
handoff (`Shared/Handoff.luau`) backwards compatible, or restart.

## Watching for crashes and errors

Every server counts what goes wrong (`src/server/Telemetry.luau`) and sends
the counts to Roblox once a minute. Nothing to set up: open **Creator
Dashboard > the experience > Analytics > Custom Events**.

| Event | What it means |
| --- | --- |
| `ServerError` | A server script errored. Split by a short signature, e.g. `Run:#: attempt to index nil` |
| `ClientError` | A player's script errored (max 20 reports per player per server) |
| `Warning` | Any warning in server output, e.g. `[Matchmaker] could not queue` |
| `TeleportRetried` / `TeleportFailed` | A teleport needed another try / gave up (the rider went back to the hub) |
| `MatchCrewFormed` | A crew left for a run server, split by kind and size (`Public 6`) |
| `MatchLocalFallback` | Riders waited too long and ran on the lobby server instead (MemoryStore trouble) |
| `MatchQueueFailed` / `MatchCrewRetry` / `MatchReserveFailed` | MemoryStore or reserving a run server failed |
| `RunBuildFailed` | A run server couldn't build its route |

CustomField01 is the detail (the signature or reason), CustomField02 is
`Lobby` or `Run`. No player names, ids or chat are sent. Roblox's own
**Error Report** page in the dashboard also lists raw script errors.

Where players drop off (first-game funnel, runs, Coal and Jingle, tips) is
separate: see [ANALYTICS.md](ANALYTICS.md).

## Things that break a deploy, and the fix

| Error in the log | Fix |
| --- | --- |
| `401` / `403` on `universes/v1/...` | The key is missing `universe-places` Write on that experience, or has an IP restriction |
| `403` on `luau-execution-session-tasks` | Add `luau-execution-sessions` Write to the key for that experience |
| "contains instances Open Cloud can't publish" | Re-export that model without SurfaceAppearance/unions (colour texture only), or publish that once from Studio |
| "Smoke test: N module(s) failed to load" | A module errors when required in a real server; the log lists which and why |
| "place ids don't match" | `ROBLOX_LOBBY_PLACE_ID` / `ROBLOX_RUN_PLACE_ID` are swapped or from another experience |
| "must be set to a numeric id" | A variable from step 4 (or the production environment) is missing |

## Audio

The sound upload script from the audio PR (`tools/audio/upload.py`) is run by
hand for now: it writes asset ids into `src/shared/Sounds.luau`, which then
needs committing, and Roblox moderates each upload and caps uploads per month
(higher once the owner account is ID-verified). Upload as the same owner as
the experience (step 1): set `ROBLOX_USER_ID` for a game on your account, or
`ROBLOX_GROUP_ID` with a group API key (Assets Read and Write) for a
group-owned game. Otherwise the game can't play the sounds.
