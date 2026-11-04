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
4. Write down the ids. In the Creator Dashboard, open the experience: the
   **universe id** is in the URL (`/dashboard/creations/experiences/<universe id>/overview`).
   Places > each place > the **place id** is in its URL and in the "..." menu
   (Copy Place ID).

Fill in this table as you go:

| | Universe id | Lobby place id | Run place id | EngineTests place id |
| --- | --- | --- | --- | --- |
| Staging | | | | |
| Live | | | | n/a |

### 3. Create the Open Cloud API key

Creator Dashboard > **Open Cloud > API Keys** > **Create API Key** (for a
group-owned game, switch to the group at the top left first).

- **Name**: `github-actions-santadash`
- **Access permissions**, add these API systems, each restricted to *both*
  experiences:

  | API system | Operations | Used for |
  | --- | --- | --- |
  | `universe-places` | Write | Publishing the places |
  | `luau-execution-sessions` | Write (and Read if offered) | Smoke test and engine tests |
  | `universe` | Write | Optional: restarting servers after a deploy |
  | `asset` | Read, Write | Optional: uploading the sounds from CI |

- **Security**: leave **Restrict IP addresses off** (GitHub's runners have no
  fixed IP; a restricted key fails with 401/403).
- **Expiration**: set one (for example 90 days) and a calendar reminder.
  Unused keys expire on their own after 60 days.

Copy the key once it's shown; Roblox won't show it again.

Want production to need a separate key? Create a second key restricted to the
live experience only, and add it as the `ROBLOX_API_KEY` secret on the
`production` environment (step 5); it overrides the repo-wide one there.

### 4. Repo secret and variables (Settings > Secrets and variables > Actions)

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `ROBLOX_API_KEY` | the key from step 3 |
| Variable | `ROBLOX_UNIVERSE_ID` | Staging universe id (for the engine tests) |
| Variable | `ROBLOX_PLACE_ID` | Staging **EngineTests** place id |
| Variable | `DEPLOY_ENABLED` | `true` (only once step 5 is done; until then deploys are skipped and main stays green) |

`ROBLOX_UNIVERSE_ID` and `ROBLOX_PLACE_ID` are the same variables the CI
workflow's engine job uses, so setting them also turns on the in-engine tests
on every pull request.

### 5. Two GitHub environments (Settings > Environments > New environment)

**staging**, with these environment variables:

| Variable | Value |
| --- | --- |
| `UNIVERSE_ID` | Staging universe id |
| `LOBBY_PLACE_ID` | Staging Lobby place id |
| `RUN_PLACE_ID` | Staging Run place id |

**production**, with the same three variables for the live experience, and:

- **Required reviewers**: add yourself. Every live deploy then waits for you
  to press Approve in the Actions run.
- **Deployment branches and tags**: "Selected branches and tags", add `main`
  and the tag pattern `v*`, so nothing else can reach the live game.

Then set `DEPLOY_ENABLED` to `true` (step 4).

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

## Things that break a deploy, and the fix

| Error in the log | Fix |
| --- | --- |
| `401` / `403` on `universes/v1/...` | The key is missing `universe-places` Write on that experience, or has an IP restriction |
| `403` on `luau-execution-session-tasks` | Add `luau-execution-sessions` Write to the key for that experience |
| "contains instances Open Cloud can't publish" | Re-export that model without SurfaceAppearance/unions (colour texture only), or publish that once from Studio |
| "Smoke test: N module(s) failed to load" | A module errors when required in a real server; the log lists which and why |
| "place ids don't match" | The environment's `LOBBY_PLACE_ID` / `RUN_PLACE_ID` are swapped or from another experience |
| "must be set to a numeric id" | An environment variable is missing on that GitHub environment |

## Audio

The sound upload script from the audio PR (`tools/audio/upload.py`) is run by
hand for now: it writes asset ids into `src/shared/Sounds.luau`, which then
needs committing, and Roblox moderates each upload and caps uploads per month
(higher once the owner account is ID-verified). Upload as the same owner as
the experience (step 1): set `ROBLOX_USER_ID` for a game on your account, or
`ROBLOX_GROUP_ID` with a group API key (Assets Read and Write) for a
group-owned game. Otherwise the game can't play the sounds.
