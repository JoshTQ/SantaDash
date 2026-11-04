# Meshy run sheet: Scruffy Grumpy Santa (approved 30 Oct 2026)

Design is unchanged from the approved gallery entry. The gallery prompt was 613 chars mixing shape and colour; Meshy builds shape in **Preview** and paints in **Refine**, so it's split into a shape prompt and a texture prompt (full text in `generate_santa.py`, `ASSETS`).

## What changed vs the gallery prompt (wording only)
| # | Change | Why |
|---|---|---|
| 1 | Colours/materials moved to the Refine texture prompt | Preview is untextured; colour words there are wasted or distort shape |
| 2 | Added "hands separate from the belly, legs slightly apart, single character, no base, no props" | Auto-rig fails if arms fuse to the pot belly or legs merge |
| 3 | Dropped "front view, plain background" | 2D image-gen phrasing; no effect in 3D |
| 4 | Patches told to be muted red/brown, "must not look like presents" | Matches the approval note |
| 5 | Backpack sack generated separately, attached as an accessory | Rig stays clean; sack can swell/scale in game |

## Settings
| Step | Setting |
|---|---|
| Preview | Model: latest (Meshy 7.1) · Pose: **A-pose** · Remesh: off · Moderation: on |
| Refine | Texture prompt from script · **PBR: off** (colour map only) · Texture: 2K |
| Remesh | Triangle · **10,000 tris** Santa, **4,000** sack (Roblox caps 20K per MeshPart) |
| Rig (Santa only) | Humanoid auto-rig · height 1.5 m · face must point +Z |

## Option A: API (needs a Meshy API key, paid plan)
```
export MESHY_API_KEY=msy_...
python3 tools/meshy/generate_santa.py --preview-only   # cheap shape check first
python3 tools/meshy/generate_santa.py                  # full run, Santa + sack
```
Outputs land in `out/santa/` and `out/sack/`: thumbnails, `*_game.glb/.fbx`, `*_color.png`, `santa_rigged.fbx`, walk/run anims.

## Option B: by hand in the Meshy web app
1. Text to 3D → paste the Santa **shape** prompt → Model "latest", Pose "A-pose" → generate. Pick the preview where arms clear the belly and the face is grumpy.
2. Texture/Refine → paste the **texture** prompt → PBR **off** → 2K.
3. Remesh → Triangle → 10,000.
4. Animate → Auto-rig (humanoid) → add Idle, Walk, Sneak/crouch walk, Grab/pick up, Cheer presets.
5. Export FBX (rigged) plus the base colour PNG. Don't use "Send to Roblox" (see below).
6. Repeat 1–3 for the sack (no pose, 4,000 tris, no rig).

## Importing into Roblox (deploy rules)
The game is published by CI through Open Cloud, which **refuses places containing SurfaceAppearance, unions or Editable\* instances**, and the deploy wipes anything that exists only in Studio.
1. Studio → Avatar/3D Importer → import `santa_rigged.fbx` (sack: `sack_game.fbx`).
2. Delete any SurfaceAppearance the importer creates. Upload `*_color.png` as a Decal/Image and set it as `MeshPart.TextureID` on each MeshPart.
3. No unions, no EditableMesh/EditableImage.
4. Right-click the model → Save to File → `assets/models/Santa.rbxm` (sack: `assets/models/SantaSack.rbxm`) and commit it. The deploy packs `assets/models/` into `ServerStorage.Assets`.
5. Only commit after the 3D preview is approved.

## After generation
Send the thumbnails back. I build the rotatable preview from the GLB for approval; only then it replaces the stand-in in the models gallery and goes in game.
