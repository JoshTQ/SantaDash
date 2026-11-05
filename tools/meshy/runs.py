#!/usr/bin/env python3
"""Print the Meshy runs a set of models needs: each model, plus the component
specs its "assemble.include" pulls in (e.g. Krampus -> KrampusBasket).

    python3 tools/meshy/runs.py Krampus Sleigh   ->   Krampus KrampusBasket Sleigh
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
runs = []
for name in sys.argv[1:]:
    spec = json.load(open(os.path.join(ROOT, "art", "meshy", name + ".json"), encoding="utf-8"))
    if spec.get("component"):
        sys.exit(f"::error::{name} is a component; run the model that includes it")
    for n in [name] + [i["from"] for i in (spec.get("assemble") or {}).get("include", {}).values()]:
        if n not in runs:
            runs.append(n)
print(" ".join(runs))
