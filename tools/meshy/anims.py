#!/usr/bin/env python3
"""Turn Meshy's animation GLB into keyframes Roblox can play on the rig.

    python3 tools/meshy/anims.py Krampus

Reads build/meshy/<Name>/anims.glb (from generate.py) and the spec's
"animations" block, writes build/meshy/<Name>/anims.json for
tools/meshy/anim_rbxm.luau, which builds one KeyframeSequence per clip.

Each pose is the bone's offset from its rest pose in its own space (what
Roblox's Bone.Transform expects): rotation conj(rest) * anim, translation
rotated into the rest frame and scaled from metres to the model's studs.
Horizontal root motion is dropped: the Humanoid does the moving.
Standard library only.
"""
import json
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COMPONENTS = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}
FORMATS = {5126: "f", 5123: "H", 5121: "B"}


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qconj(q):
    return (-q[0], -q[1], -q[2], q[3])


def qrot(q, v):
    x, y, z, w = qmul(qmul(q, (v[0], v[1], v[2], 0.0)), qconj(q))
    return (x, y, z)


def qslerp(a, b, t):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b, dot = tuple(-x for x in b), -dot
    if dot > 0.9995:
        r = tuple(x + (y - x) * t for x, y in zip(a, b))
    else:
        th = math.acos(dot)
        s = math.sin(th)
        wa, wb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
        r = tuple(wa * x + wb * y for x, y in zip(a, b))
    n = math.sqrt(sum(x * x for x in r))
    return tuple(x / n for x in r)


def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen])
    blen = struct.unpack("<I", data[20 + jlen:24 + jlen])[0]
    binary = data[28 + jlen:28 + jlen + blen]

    def accessor(i):
        a = gltf["accessors"][i]
        view = gltf["bufferViews"][a["bufferView"]]
        n = COMPONENTS[a["type"]]
        fmt = FORMATS[a["componentType"]]
        size = struct.calcsize(fmt)
        stride = view.get("byteStride") or n * size
        base = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        out = []
        for k in range(a["count"]):
            vals = struct.unpack_from("<" + fmt * n, binary, base + k * stride)
            out.append(vals if n > 1 else vals[0])
        return out

    return gltf, accessor


def sample(times, values, t, rot):
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    for k in range(1, len(times)):
        if times[k] >= t:
            f = (t - times[k - 1]) / ((times[k] - times[k - 1]) or 1)
            a, b = values[k - 1], values[k]
            return qslerp(a, b, f) if rot else tuple(x + (y - x) * f for x, y in zip(a, b))
    return values[-1]


def main():
    name = sys.argv[1]
    spec = json.load(open(os.path.join(ROOT, "art", "meshy", name + ".json"), encoding="utf-8"))
    cfg = spec["animations"]
    out = os.path.join(ROOT, "build", "meshy", name)
    gltf, accessor = read_glb(os.path.join(out, "anims.glb"))
    nodes = gltf["nodes"]
    joints = set(gltf["skins"][0]["joints"])
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i
    # studs per glTF unit: the model's fitted height over the rig's height
    # (the mesh is in metres), times the scale of the nodes above the skeleton
    # (Meshy's Armature is 0.01: bone offsets are in centimetres).
    scale = spec["assemble"]["mesh"]["fit"]["studs"] / spec.get("height_meters", 1.7)
    above = next((parent.get(j) for j in joints if parent.get(j) not in joints), None)
    while above is not None:
        scale *= nodes[above].get("scale", (1, 1, 1))[1]
        above = parent.get(above)
    fps = cfg.get("fps", 15)
    bones = {}
    for j in joints:
        n = nodes[j]
        p = parent.get(j)
        bones[n["name"]] = {"parent": nodes[p]["name"] if p in joints else None}
    clips = {}
    by_name = {a.get("name"): a for a in gltf["animations"]}
    for game_name, clip_name in cfg["clips"].items():
        anim = by_name.get(clip_name)
        if not anim:
            sys.exit(f"::error::{name}: no clip {clip_name!r} in anims.glb (has {sorted(by_name)})")
        tracks = {}
        duration = 0
        for ch in anim["channels"]:
            node = ch["target"]["node"]
            if node not in joints or ch["target"]["path"] not in ("rotation", "translation"):
                continue
            s = anim["samplers"][ch["sampler"]]
            times = accessor(s["input"])
            duration = max(duration, times[-1])
            tracks.setdefault(node, {})[ch["target"]["path"]] = (times, accessor(s["output"]))
        # "trim": {"<game name>": [start, end]} keeps only that part of a clip
        start, end = (cfg.get("trim") or {}).get(game_name, (0, duration))
        start, end = max(0, start), min(duration, end)
        duration = end - start
        frames = []
        count = max(2, int(round(duration * fps)) + 1)
        for k in range(count):
            t = min(duration, k / fps)
            src = start + t
            poses = {}
            for node, tr in tracks.items():
                n = nodes[node]
                rest_r = tuple(n.get("rotation", (0, 0, 0, 1)))
                rest_t = tuple(n.get("translation", (0, 0, 0)))
                r = sample(*tr["rotation"], src, True) if "rotation" in tr else rest_r
                p = sample(*tr["translation"], src, False) if "translation" in tr else rest_t
                dq = qmul(qconj(rest_r), r)
                dt = qrot(qconj(rest_r), tuple(a - b for a, b in zip(p, rest_t)))
                if bones[n["name"]]["parent"] is None and not cfg.get("root_motion"):
                    # keep the bob, drop the travel (in the parent's frame)
                    world = tuple(a - b for a, b in zip(p, rest_t))
                    dt = qrot(qconj(rest_r), (0.0, world[1], 0.0))
                poses[n["name"]] = [round(v * scale, 4) for v in dt] + [round(v, 5) for v in dq]
            frames.append({"t": round(t, 4), "poses": poses})
        clips[game_name] = {"source": clip_name, "duration": duration,
                            "loop": game_name in cfg.get("loop", []), "frames": frames}
        print(f"  {game_name} <- {clip_name}: {duration:.2f}s, {len(frames)} keyframes, {len(tracks)} bones")
    json.dump({"bones": bones, "clips": clips}, open(os.path.join(out, "anims.json"), "w"))


if __name__ == "__main__":
    main()
