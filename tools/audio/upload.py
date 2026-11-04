"""
Uploads the generated sounds (assets/audio/*.ogg) to Roblox with Open Cloud
and writes each new asset id into src/shared/Sounds.luau.

    ROBLOX_API_KEY=... ROBLOX_USER_ID=... python3 tools/audio/upload.py [Key ...]

The API key needs the "Assets: Write" (and Read) permission for your account.
Keys that already have an id other than 0 in Sounds.luau are skipped, so it is
safe to re-run after a failure. Pass keys to (re)upload only those.

Roblox moderates every audio upload and limits how many you can upload a
month (more if your account is ID-verified), so upload the Tier 1 keys first.
"""

import json
import os
import re
import sys
import time
import urllib.request
import uuid

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO = os.path.join(ROOT, "assets", "audio")
SOUNDS = os.path.join(ROOT, "src", "shared", "Sounds.luau")
API = "https://apis.roblox.com/assets/v1"


def request(method, url, key, body=None, content_type=None):
    req = urllib.request.Request(url, data=body, method=method)
    req.add_header("x-api-key", key)
    if content_type:
        req.add_header("Content-Type", content_type)
    with urllib.request.urlopen(req) as res:
        return json.loads(res.read() or b"{}")


def upload(key, user_id, name, path):
    meta = {
        "assetType": "Audio",
        "displayName": "SleighHeist " + name,
        "description": "Sleigh Heist sound effect: " + name,
        "creationContext": {"creator": {"userId": str(user_id)}},
    }
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        audio = f.read()
    body = b"".join(
        [
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n".encode(),
            json.dumps(meta).encode(),
            f"\r\n--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{name}.ogg\"\r\nContent-Type: audio/ogg\r\n\r\n".encode(),
            audio,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )
    op = request("POST", API + "/assets", key, body, "multipart/form-data; boundary=" + boundary)
    op_path = op.get("path") or ("operations/" + op["operationId"])
    for _ in range(60):  # moderation can take a little while
        if op.get("done"):
            break
        time.sleep(2)
        op = request("GET", API + "/" + op_path, key)
    if not op.get("done"):
        raise RuntimeError("upload still processing; re-run later")
    return int(op["response"]["assetId"])


def main():
    key = os.environ.get("ROBLOX_API_KEY")
    user_id = os.environ.get("ROBLOX_USER_ID")
    if not key or not user_id:
        sys.exit("Set ROBLOX_API_KEY and ROBLOX_USER_ID first (see the top of this file).")
    source = open(SOUNDS, encoding="utf-8").read()
    wanted = sys.argv[1:]
    names = wanted or sorted(f[:-4] for f in os.listdir(AUDIO) if f.endswith(".ogg"))
    for name in names:
        if not wanted and not re.search(r"\t" + re.escape(name) + r" = \{\s*id = 0\b", source):
            print(f"skip   {name} (already has an id)")
            continue
        try:
            asset_id = upload(key, user_id, name, os.path.join(AUDIO, name + ".ogg"))
        except Exception as e:  # keep going; re-run picks up the rest
            print(f"FAILED {name}: {e}")
            continue
        source = re.sub(r"(\t" + re.escape(name) + r" = \{\s*id = )\d+", lambda m: m.group(1) + str(asset_id), source, count=1)
        with open(SOUNDS, "w", encoding="utf-8") as f:
            f.write(source)
        print(f"ok     {name} -> {asset_id}")


if __name__ == "__main__":
    main()
