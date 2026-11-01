#!/usr/bin/env python3
"""Generate the approved Scruffy Grumpy Santa (and backpack sack) in Meshy.

Pipeline per asset: Text-to-3D preview -> refine (texture) -> remesh to a
Roblox-friendly triangle count -> (Santa only) humanoid auto-rig.
Downloads GLB/FBX files into ./out/<asset>/.

Usage:
    export MESHY_API_KEY=msy_...
    python3 generate_santa.py              # Santa body + sack
    python3 generate_santa.py --only santa # just the body
    python3 generate_santa.py --preview-only   # stop after previews (cheap check)

Standard library only. Prompts are the approved gallery prompts, split into a
shape prompt (preview) and a colour/material prompt (refine). Do not change the
design here without going back through art approval.
"""
import argparse, json, os, sys, time, urllib.request, urllib.error

API = "https://api.meshy.ai/openapi"
KEY = os.environ.get("MESHY_API_KEY")

STYLE = ("Stylized 3D game character, chunky vinyl-toy style, smooth sculpted "
         "rounded forms, soft simple shapes, quirky proportions.")

ASSETS = {
    "santa": {
        "rig": True,
        "pose_mode": "a-pose",
        "polycount": 10000,
        "shape": STYLE + " A scruffy, grumpy Santa Claus: short and round with a big "
            "pot belly, slightly hunched. Big head, furrowed bushy eyebrows, frowning "
            "grumpy face, round nose, messy uneven beard. Suit with a few sewn-on "
            "fabric patches with visible stitching, thick fur trim, belt with a "
            "crooked buckle. Floppy hat tilted sideways with a droopy tip and a "
            "fluffy pompom. Worn boots and mittens. Full body, standing, A-pose, "
            "arms slightly out from the body, hands separate from the belly, "
            "legs slightly apart, single character, no base, no props.",
        "texture": "Bright saturated colours, smooth soft vinyl-toy finish, clean hand-painted "
            "look. Faded red suit with a few darker muted red and brown fabric patches "
            "with visible stitching (patches must not look like presents). Off-white fur "
            "trim, slightly grubby. Black belt with a crooked gold buckle. Rosy round "
            "nose and rosy cheeks, grey-white messy beard and bushy grey eyebrows. "
            "Floppy red hat with off-white fur band and white pompom. Worn brown boots "
            "and brown mittens. No text, no logos.",
    },
    "sack": {
        "rig": False,
        "pose_mode": "",
        "polycount": 4000,
        "shape": "Stylized 3D game accessory, chunky vinyl-toy style, smooth sculpted "
            "rounded forms. A burlap sack worn as a backpack: rounded and full with "
            "smooth sides, two shoulder straps with small rings, wide opening at the "
            "top gathered with thick rope, sewn-on patches, one small hole. Three "
            "wrapped presents with ribbons sticking up out of the top opening only. "
            "Single object, no character, no base.",
        "texture": "Bright saturated colours, smooth soft vinyl-toy finish. Warm tan burlap "
            "with subtle weave, darker muted brown sewn-on patches, worn brown leather "
            "shoulder straps with small brass rings, thick beige rope. Presents: one "
            "blue with white ribbon, one yellow, one purple with yellow ribbon. "
            "No text, no logos.",
    },
}


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"Meshy {method} {path} failed: {e.code} {e.read().decode()[:500]}")


def wait(path, task_id, label):
    while True:
        t = call("GET", f"{path}/{task_id}")
        print(f"  {label}: {t['status']} {t.get('progress', 0)}%", end="\r", flush=True)
        if t["status"] == "SUCCEEDED":
            print(f"\n  {label}: done ({t.get('consumed_credits', '?')} credits)")
            return t
        if t["status"] in ("FAILED", "CANCELED"):
            sys.exit(f"\n  {label} {t['status']}: {t.get('task_error')}")
        time.sleep(10)


def save(url, dest):
    if url:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        urllib.request.urlretrieve(url, dest)
        print("  saved", dest)


def run(name, a, preview_only):
    print(f"\n== {name} ==")
    out = os.path.join("out", name)
    pid = call("POST", "/v2/text-to-3d", {
        "mode": "preview", "prompt": a["shape"], "ai_model": "latest",
        "pose_mode": a["pose_mode"], "should_remesh": False,
        "target_formats": ["glb"], "moderation": True})["result"]
    p = wait("/v2/text-to-3d", pid, "preview")
    save(p.get("thumbnail_url"), f"{out}/preview.png")
    save(p["model_urls"].get("glb"), f"{out}/preview.glb")
    if preview_only:
        return
    rid = call("POST", "/v2/text-to-3d", {
        "mode": "refine", "preview_task_id": pid, "texture_prompt": a["texture"],
        "enable_pbr": True, "texture_resolution": "2k",
        "target_formats": ["glb"], "moderation": True})["result"]
    r = wait("/v2/text-to-3d", rid, "refine")
    save(r.get("thumbnail_url"), f"{out}/refined.png")
    save(r["model_urls"].get("glb"), f"{out}/refined_highpoly.glb")
    mid = call("POST", "/v1/remesh", {
        "input_task_id": rid, "topology": "triangle",
        "target_polycount": a["polycount"], "target_formats": ["glb", "fbx"]})["result"]
    m = wait("/v1/remesh", mid, f"remesh {a['polycount']} tris")
    save(m["model_urls"].get("glb"), f"{out}/{name}_game.glb")
    save(m["model_urls"].get("fbx"), f"{out}/{name}_game.fbx")
    if a["rig"]:
        gid = call("POST", "/v1/rigging", {"input_task_id": mid, "height_meters": 1.5})["result"]
        g = wait("/v1/rigging", gid, "rig")
        res = g.get("result", {})
        save(res.get("rigged_character_glb_url"), f"{out}/{name}_rigged.glb")
        save(res.get("rigged_character_fbx_url"), f"{out}/{name}_rigged.fbx")
        anims = res.get("basic_animations") or {}
        save(anims.get("walking_fbx_url"), f"{out}/anim_walk.fbx")
        save(anims.get("running_fbx_url"), f"{out}/anim_run.fbx")
    json.dump({"preview": pid, "refine": rid, "remesh": mid},
              open(f"{out}/task_ids.json", "w"), indent=2)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=list(ASSETS))
    ap.add_argument("--preview-only", action="store_true")
    args = ap.parse_args()
    if not KEY:
        sys.exit("Set MESHY_API_KEY first (Meshy dashboard > API keys).")
    for k in ([args.only] if args.only else ASSETS):
        run(k, ASSETS[k], args.preview_only)
