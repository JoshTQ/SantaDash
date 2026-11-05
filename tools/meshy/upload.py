#!/usr/bin/env python3
"""Upload a Meshy model to Roblox through Open Cloud and download what Roblox
imported, ready for tools/meshy/to_rbxm.luau.

    ROBLOX_API_KEY=... ROBLOX_USER_ID=... python3 tools/meshy/upload.py Santa
    ROBLOX_API_KEY=... ROBLOX_GROUP_ID=... python3 tools/meshy/upload.py Santa
    ... python3 tools/meshy/upload.py Krampus --animations   (after anim_rbxm.luau)

Reads build/meshy/<Name>/ (from generate.py) and:
1. uploads color.png as an Image asset (its id becomes MeshPart.TextureID);
2. uploads rigged.fbx (or game.fbx) as a Model asset: Roblox imports it into
   MeshParts, the only way to get mesh assets made without Studio;
3. downloads that Model asset back as build/meshy/<Name>/imported.rbxm;
4. writes the ids to build/meshy/<Name>/roblox.json.

Upload as the experience's owner (the same user or group as the game), or
the game can't load the meshes. The API key needs Assets Read and Write.
Standard library only.
"""
import gzip
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
API = "https://apis.roblox.com"
KEY = os.environ.get("ROBLOX_API_KEY")
GIVE_UP_SECONDS = 15 * 60  # moderation can take a while
RETRIES = 5
RETRY_SECONDS = 5  # 5, 10, 15, 20, 25 s
RETRY_CODES = (429, 502, 503, 504)


def request(method, url, body=None, content_type=None, raw=False):
    req = urllib.request.Request(url, data=body, method=method)
    if url.startswith(API):
        req.add_header("x-api-key", KEY)
    if content_type:
        req.add_header("Content-Type", content_type)
    # Open Cloud has brief outages (503 "No server is available") and rate
    # limits: retry those with backoff. They mean the request wasn't handled,
    # so a retried POST doesn't create a second asset.
    for attempt in range(RETRIES + 1):
        try:
            with urllib.request.urlopen(req, timeout=120) as res:
                data = res.read()
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:500]
            if e.code in RETRY_CODES and attempt < RETRIES:
                print(f"  {method} {url} -> {e.code}, retrying ({attempt + 1}/{RETRIES})")
                time.sleep(RETRY_SECONDS * (attempt + 1))
                continue
            hint = " (check the key has Assets Read+Write and no IP restriction)" if e.code in (401, 403) else ""
            sys.exit(f"::error::{method} {url} -> {e.code}{hint}\n{detail}")
        except urllib.error.URLError as e:
            if method == "GET" and attempt < RETRIES:
                print(f"  {method} {url} -> {e.reason}, retrying ({attempt + 1}/{RETRIES})")
                time.sleep(RETRY_SECONDS * (attempt + 1))
                continue
            raise
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    return data if raw else json.loads(data or b"{}")


def upload(creator, asset_type, display, path, content_type):
    meta = {
        "assetType": asset_type,
        "displayName": display,
        "description": "Sleigh Heist: " + display + " (generated in Meshy by CI)",
        "creationContext": {"creator": creator},
    }
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        content = f.read()
    if len(content) > 20 * 1024 * 1024:
        sys.exit(f"::error::{os.path.basename(path)} is over Open Cloud's 20 MB limit; lower the spec's polycount")
    body = b"".join([
        f'--{boundary}\r\nContent-Disposition: form-data; name="request"\r\n\r\n'.encode(),
        json.dumps(meta).encode(),
        f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; '
        f'filename="{os.path.basename(path)}"\r\nContent-Type: {content_type}\r\n\r\n'.encode(),
        content,
        f"\r\n--{boundary}--\r\n".encode(),
    ])
    op = request("POST", API + "/assets/v1/assets", body, "multipart/form-data; boundary=" + boundary)
    op_path = op.get("path") or ("operations/" + op["operationId"])
    started = time.time()
    while not op.get("done"):
        if time.time() - started > GIVE_UP_SECONDS:
            sys.exit(f"::error::{asset_type} upload still processing after {GIVE_UP_SECONDS // 60} min: {op_path}")
        time.sleep(5)
        op = request("GET", API + "/assets/v1/" + op_path)
    if "response" not in op:
        sys.exit(f"::error::{asset_type} upload failed: {json.dumps(op.get('error') or op)}")
    asset = op["response"]
    state = (asset.get("moderationResult") or {}).get("moderationState", "unknown")
    print(f"  {asset_type} {display}: asset {asset['assetId']} (moderation: {state})")
    if "REJECTED" in state:
        sys.exit(f"::error::Roblox moderation rejected the {asset_type.lower()} upload")
    return int(asset["assetId"])


def download(asset_id):
    """Fetch the asset file. Open Cloud answers with a CDN location (JSON) or the bytes."""
    started = time.time()
    while True:
        data = request("GET", f"{API}/asset-delivery-api/v1/assetId/{asset_id}", raw=True)
        try:
            info = json.loads(data)
        except (ValueError, UnicodeDecodeError):
            return data
        location = info.get("location") or ((info.get("locations") or [{}])[0].get("location"))
        if location:
            return request("GET", location, raw=True)
        # Not deliverable yet (usually still in moderation): wait and retry.
        if time.time() - started > GIVE_UP_SECONDS:
            sys.exit(f"::error::Couldn't download model asset {asset_id}: {json.dumps(info)[:500]}")
        print(f"  waiting for asset {asset_id} to become downloadable: {json.dumps(info)[:200]}")
        time.sleep(15)


def upload_animations(creator, name, out):
    """Upload anim_<Clip>.rbxm (tools/meshy/anim_rbxm.luau) as Animation assets."""
    built = json.load(open(f"{out}/anims_built.json"))
    ids = json.load(open(f"{out}/roblox.json"))
    ids["animations"] = {}
    for clip in built:
        ids["animations"][clip] = upload(creator, "Animation", f"{name} {clip}", f"{out}/anim_{clip}.rbxm", "model/x-rbxm")
    json.dump(ids, open(f"{out}/roblox.json", "w"), indent=2)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        sys.exit("usage: upload.py <Name> [--animations]")
    name = args[0]
    user_id, group_id = os.environ.get("ROBLOX_USER_ID"), os.environ.get("ROBLOX_GROUP_ID")
    if not KEY or bool(user_id) == bool(group_id):
        sys.exit("::error::Set ROBLOX_API_KEY and exactly one of ROBLOX_USER_ID or ROBLOX_GROUP_ID")
    creator = {"groupId": str(group_id)} if group_id else {"userId": str(user_id)}
    out = os.path.join(ROOT, "build", "meshy", name)
    if "--animations" in sys.argv:
        print(f"== Uploading {name}'s animations to Roblox ==")
        upload_animations(creator, name, out)
        return
    model = next((p for p in (f"{out}/rigged.fbx", f"{out}/game.fbx") if os.path.isfile(p)), None)
    if not model or not os.path.isfile(f"{out}/color.png"):
        sys.exit(f"::error::Run tools/meshy/generate.py {name} first (needs color.png and an .fbx)")

    print(f"== Uploading {name} to Roblox ==")
    image_id = upload(creator, "Image", f"{name} texture", f"{out}/color.png", "image/png")
    model_id = upload(creator, "Model", name, model, "model/fbx")
    with open(f"{out}/imported.rbxm", "wb") as f:
        f.write(download(model_id))
    json.dump({"modelAssetId": model_id, "imageAssetId": image_id, "source": os.path.basename(model)},
              open(f"{out}/roblox.json", "w"), indent=2)
    print(f"  downloaded build/meshy/{name}/imported.rbxm")


if __name__ == "__main__":
    main()
