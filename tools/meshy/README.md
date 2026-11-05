# Meshy → Roblox, automated

After a one-time setup, an approved model goes from prompt to the live game with
one click from you: **merging its PR**.

```
art/meshy/<Name>.json  (approved prompts)
   │  push to main, or Actions > Meshy model > Run workflow
   ▼
Meshy: preview (shape) → refine (colour texture, no PBR) → remesh → auto-rig
   ▼
Open Cloud: upload texture (Image) + FBX (Model) → Roblox imports MeshParts
   ▼
download the import → tools/meshy/to_rbxm.luau → assets/models/<Name>.rbxm
   (TextureID set, SurfaceAppearance/PackageLink stripped, deploy dry-run passes)
   ▼
PR "Approve model: <Name>" with thumbnails and model.glb → you merge → deploy ships it
```

Merging is the final art approval (the strict rule: 3D preview → approval →
gallery and game). Claude builds the rotatable preview from `model.glb` in the
PR and adds the model to the gallery once it's merged.

## One-time setup (about 10 minutes)

| # | Where | What |
| --- | --- | --- |
| 1 | meshy.ai > Settings > API | A Meshy plan with API access (Pro or higher) and an API key |
| 2 | Repo > Settings > Secrets and variables > Actions > Secrets | `MESHY_API_KEY` = that key |
| 3 | Creator Dashboard > Open Cloud > API Keys | On the existing `ROBLOX_API_KEY` key, add the **Assets** API system with **Read and Write** (docs/DEPLOY.md step 3) |
| 4 | Repo > Settings > Secrets and variables > Actions > Variables | `ROBLOX_USER_ID` (your user id) if the game is on your account, or `ROBLOX_GROUP_ID` if a group owns it. Same owner as the experience, or the game can't load the meshes |
| 5 | Repo > Settings > Actions > General | Tick **Allow GitHub Actions to create and approve pull requests** |

## Meshy MCP server (for Claude sessions)

`.mcp.json` at the repo root loads `@meshy-ai/meshy-mcp-server`, so Claude Code
sessions on this repo can call Meshy directly (quick tests, re-rolls, checking
credits). It reads the key from the `MESHY_API_KEY` environment variable; the
key is never committed. CI doesn't use it: the workflow calls the Meshy API
itself with the `MESHY_API_KEY` repo secret.

| Where Claude runs | Where the key goes |
| --- | --- |
| Claude Code on the web / project threads | Cloud environment variable `MESHY_API_KEY` (Project settings > Cloud environment) |
| Claude Code on your computer | `export MESHY_API_KEY=...` in your shell before `claude` |
| Claude Desktop | `claude_desktop_config.json`, `env.MESHY_API_KEY` |

## Day to day

| I want to | Do |
| --- | --- |
| Make a newly approved model | Claude adds `art/meshy/<Name>.json` in a PR; merging it starts the run |
| Make several at once | Run workflow with the names space-separated (`Sleigh Reindeer Krampus`): one job, one approval PR |
| Re-roll a model I didn't like | Remove the spec's `meshy` block, then Run workflow with the name |
| Cheap shape check first | Run workflow with **Shape preview only** (no Roblox upload, no PR) |
| Get the raw FBX/animations | The run's artifacts (`meshy-<Name>-<run>`) |

## Specs

One JSON file per model in `art/meshy/`. The name is the file name and the
model's name in `ServerStorage.Assets`:

| Field | Meaning |
| --- | --- |
| `shape_prompt` | Meshy preview prompt (shape only, ≤ 800 chars) |
| `texture_prompt` | Meshy refine prompt (colours and materials, ≤ 800 chars) |
| `pose_mode` | `a-pose` for characters, `""` for props |
| `polycount` | Remesh target in triangles (Roblox caps a MeshPart at 20K) |
| `rig` / `height_meters` | Humanoid auto-rig (characters only) |
| `meshy` | Task ids of a finished Meshy run (`generate.py <Name> --record`). CI downloads those results instead of generating again, so a model Claude already made and checked costs no extra credits |
| `component` | `true` for a mesh that only exists inside another model (`KrampusBasket`); it gets no `.rbxm` of its own |
| `assemble` | How `to_rbxm.luau` turns the mesh into the part contract the game checks (`src/server/Assets.luau`): turn (`yaw`) and scale (`fit`) the mesh to the stand-in, add the named helper parts (seats, hitch, balls...), attachments, particles, a `humanoid` rig, and `include` component meshes. Positions are studs from the model's pivot, forward is -Z. Full field list at the top of `to_rbxm.luau` |

Meshy's meshes face +Z (characters) or lie along X (the sleigh), so each
spec's `yaw` turns them to the game's -Z forward. `tests/integration/ApprovedModelFiles.spec.luau`
fails if a committed `.rbxm` loses a contract part, which would otherwise
quietly put the greybox stand-in back in the live game.

**Not Meshy models:** the house kit and Krampus's Lair are walk-in buildings
with doors, stairs, fireplaces and hide spots, built per seed. A single Meshy
mesh is a closed shell with no inside, so these stay on the hand-built kit.

`Santa.json` and `SantaSack.json` are the approved 30 Oct 2026 prompts, split
into shape and texture; the design is unchanged. The sack is a separate
accessory so Santa's rig stays clean.

## Known gaps and risks (first real run is the test)

These couldn't be checked without the keys, so watch the first run's log:

| Risk | What happens | Fallback |
| --- | --- | --- |
| Open Cloud's import of a **rigged** FBX may drop the bones | `summary.json` shows `bones: 0` | Fine for props. For Santa, see "Playable Santa" below |
| The asset-delivery download format differs from what `upload.py` expects | The upload step fails with the response in the log | Claude adjusts `download()` |
| Roblox moderation holds the upload | The step waits up to 15 min, then fails | Re-run later |
| Imported scale is off (FBX units) | `summary.json` `sizeStuds` | Scale in the spec/in `to_rbxm.luau` |

**Playable Santa:** players are Roblox Humanoids. Turning a Meshy skeleton into
a character that walks and plays Idle/Sneak/Grab/Cheer animations is a separate
task (StarterCharacter + converting Meshy's animations to Roblox animation
assets, which Open Cloud accepts as `.rbxm`). This pipeline gets the model into
the game; that one makes it the player.
