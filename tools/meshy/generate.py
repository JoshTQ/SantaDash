#!/usr/bin/env python3
"""Generate one approved model in Meshy from its spec in art/meshy/<Name>.json.

    MESHY_API_KEY=msy_... python3 tools/meshy/generate.py Santa [--preview-only]

Pipeline: Text-to-3D preview (shape) -> refine (colour texture, no PBR) ->
remesh to a Roblox-friendly triangle count -> humanoid auto-rig (if the spec
says "rig": true). Writes into build/meshy/<Name>/:

    preview.png, refined.png   Meshy thumbnails (for the approval PR)
    game.glb                   remeshed, textured model (rotatable preview)
    game.fbx / rigged.fbx      what tools/meshy/upload.py sends to Roblox
    color.png                  base colour texture (becomes MeshPart.TextureID)
    anim_walk.fbx, anim_run.fbx  Meshy's basic animations (rigged models only)
    meshy.json                 task ids, credits used

If the spec has a "meshy" block (task ids from an earlier run, e.g. one a
Claude session made and reviewed), nothing new is generated: the finished
tasks are fetched again, so CI spends no credits on a model already made.
Record one with --record after a run.

No PBR maps: the CI deploy publishes through Open Cloud, which refuses places
containing SurfaceAppearance. Standard library only.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
API = "https://api.meshy.ai/openapi"
KEY = os.environ.get("MESHY_API_KEY")
POLL_SECONDS = 10
GIVE_UP_SECONDS = 30 * 60


def call(method, path, body=None):
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"::error::Meshy {method} {path} failed: {e.code} {e.read().decode()[:500]}")


def wait(path, task_id, label, credits):
    started = time.time()
    while True:
        t = call("GET", f"{path}/{task_id}")
        if t["status"] == "SUCCEEDED":
            used = t.get("consumed_credits", 0) or 0
            credits[label] = used
            print(f"  {label}: done ({used} credits)")
            return t
        if t["status"] in ("FAILED", "CANCELED"):
            sys.exit(f"::error::Meshy {label} {t['status']}: {t.get('task_error')}")
        if time.time() - started > GIVE_UP_SECONDS:
            sys.exit(f"::error::Meshy {label} still {t['status']} after {GIVE_UP_SECONDS // 60} min")
        print(f"  {label}: {t['status']} {t.get('progress', 0)}%")
        time.sleep(POLL_SECONDS)


def save(url, dest):
    if not url:
        return False
    urllib.request.urlretrieve(url, dest)
    print("  saved", os.path.relpath(dest, ROOT))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name", help="spec name, e.g. Santa (art/meshy/Santa.json)")
    ap.add_argument("--preview-only", action="store_true", help="stop after the shape preview")
    ap.add_argument("--from-preview", metavar="TASK_ID",
                    help="keep the shape of an earlier preview task; only re-texture (cheaper re-roll)")
    ap.add_argument("--record", action="store_true",
                    help="after a run, save its task ids in the spec so CI reuses them")
    args = ap.parse_args()
    if not KEY:
        sys.exit("::error::MESHY_API_KEY is not set (repo secret, see tools/meshy/README.md)")
    spec = json.load(open(os.path.join(ROOT, "art", "meshy", args.name + ".json"), encoding="utf-8"))
    out = os.path.join(ROOT, "build", "meshy", args.name)
    os.makedirs(out, exist_ok=True)
    ids, credits = {}, {}
    print(f"== {args.name} ==")
    if spec.get("meshy") and not args.preview_only:
        reuse(spec, out)
        return

    if args.from_preview:
        ids["preview"] = args.from_preview
        p = call("GET", f"/v2/text-to-3d/{ids['preview']}")
    else:
        ids["preview"] = call("POST", "/v2/text-to-3d", {
            "mode": "preview",
            "prompt": spec["shape_prompt"],
            "ai_model": "latest",
            "pose_mode": spec.get("pose_mode", ""),
            "should_remesh": False,
            "target_formats": ["glb"],
            "moderation": True,
        })["result"]
        p = wait("/v2/text-to-3d", ids["preview"], "preview", credits)
    save(p.get("thumbnail_url"), f"{out}/preview.png")

    if not args.preview_only:
        ids["refine"] = call("POST", "/v2/text-to-3d", {
            "mode": "refine",
            "preview_task_id": ids["preview"],
            "texture_prompt": spec["texture_prompt"],
            "enable_pbr": False,
            "texture_resolution": "2k",
            "target_formats": ["glb"],
            "moderation": True,
        })["result"]
        r = wait("/v2/text-to-3d", ids["refine"], "refine", credits)
        save(r.get("thumbnail_url"), f"{out}/refined.png")
        if not save((r.get("texture_urls") or [{}])[0].get("base_color"), f"{out}/color.png"):
            sys.exit("::error::Meshy refine returned no base colour texture")

        ids["remesh"] = call("POST", "/v1/remesh", {
            "input_task_id": ids["refine"],
            "topology": "triangle",
            "target_polycount": spec["polycount"],
            "target_formats": ["glb", "fbx"],
        })["result"]
        m = wait("/v1/remesh", ids["remesh"], f"remesh to {spec['polycount']} tris", credits)
        save(m["model_urls"].get("glb"), f"{out}/game.glb")
        save(m["model_urls"].get("fbx"), f"{out}/game.fbx")

        if spec.get("rig"):
            ids["rig"] = call("POST", "/v1/rigging", {
                "input_task_id": ids["remesh"],
                "height_meters": spec.get("height_meters", 1.7),
            })["result"]
            g = wait("/v1/rigging", ids["rig"], "rig", credits)
            res = g.get("result") or {}
            if not save(res.get("rigged_character_fbx_url"), f"{out}/rigged.fbx"):
                sys.exit("::error::Meshy rigging returned no FBX")
            save(res.get("rigged_character_glb_url"), f"{out}/rigged.glb")
            anims = res.get("basic_animations") or {}
            save(anims.get("walking_fbx_url"), f"{out}/anim_walk.fbx")
            save(anims.get("running_fbx_url"), f"{out}/anim_run.fbx")

    if not args.preview_only and spec.get("animations") and ids.get("rig"):
        ids["animations"] = animations(spec, ids["rig"], out, credits)
    json.dump({"tasks": ids, "credits": credits, "total_credits": sum(credits.values())},
              open(f"{out}/meshy.json", "w"), indent=2)
    print(f"Meshy credits used: {sum(credits.values())}")
    if args.record and not args.preview_only:
        spec["meshy"] = ids
        path = os.path.join(ROOT, "art", "meshy", args.name + ".json")
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(spec, indent=2) + "\n")
        print("  recorded the task ids in", os.path.relpath(path, ROOT))


def reuse(spec, out):
    """Download the results of tasks that already finished (no credits)."""
    ids = spec["meshy"]
    print("  reusing Meshy tasks", json.dumps(ids))
    p = call("GET", f"/v2/text-to-3d/{ids['preview']}")
    save(p.get("thumbnail_url"), f"{out}/preview.png")
    r = call("GET", f"/v2/text-to-3d/{ids['refine']}")
    save(r.get("thumbnail_url"), f"{out}/refined.png")
    if not save((r.get("texture_urls") or [{}])[0].get("base_color"), f"{out}/color.png"):
        sys.exit("::error::Meshy refine task has no base colour texture (expired?); remove the spec's meshy block")
    m = call("GET", f"/v1/remesh/{ids['remesh']}")
    if not save((m.get("model_urls") or {}).get("fbx"), f"{out}/game.fbx"):
        sys.exit("::error::Meshy remesh task has no FBX (expired?); remove the spec's meshy block")
    save(m["model_urls"].get("glb"), f"{out}/game.glb")
    if ids.get("rig"):
        g = call("GET", f"/v1/rigging/{ids['rig']}")
        res = g.get("result") or {}
        save(res.get("rigged_character_fbx_url"), f"{out}/rigged.fbx")
        save(res.get("rigged_character_glb_url"), f"{out}/rigged.glb")
        anims = res.get("basic_animations") or {}
        save(anims.get("walking_fbx_url"), f"{out}/anim_walk.fbx")
        save(anims.get("running_fbx_url"), f"{out}/anim_run.fbx")
    credits = {}
    if spec.get("animations") and ids.get("rig"):
        animations(spec, ids["rig"], out, credits)
    json.dump({"tasks": ids, "credits": credits, "total_credits": sum(credits.values()), "reused": True},
              open(f"{out}/meshy.json", "w"), indent=2)
    print(f"Meshy credits used: {sum(credits.values())} (reused finished tasks)")


def animations(spec, rig_id, out, credits):
    """Meshy animation-library clips on the rig, as one multi-clip GLB (3 credits a clip)."""
    cfg = spec["animations"]
    task = cfg.get("meshy")
    if task:
        a = call("GET", f"/v1/animations/{task}")
    else:
        task = call("POST", "/v1/animations", {"rig_task_id": rig_id, "action_ids": cfg["actions"]})["result"]
        a = wait("/v1/animations", task, f"{len(cfg['actions'])} animations", credits)
    if not save((a.get("result") or {}).get("animation_glb_url"), f"{out}/anims.glb"):
        sys.exit("::error::Meshy animation task has no GLB (expired?); remove animations.meshy from the spec")
    return task


if __name__ == "__main__":
    main()
