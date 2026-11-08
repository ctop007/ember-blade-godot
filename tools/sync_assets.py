#!/usr/bin/env python3
"""Copy status=ready assets (and manifest.json) from _shared/assets into res://assets/.
Godot uses .ogg for audio. Run: python3 tools/sync_assets.py"""
import json, shutil, pathlib
root = pathlib.Path(__file__).resolve().parent.parent
src = root.parent / "_shared" / "assets"
dst = root / "assets"
dst.mkdir(exist_ok=True)
m = json.loads((src / "manifest.json").read_text())
# No human voice lines in any build (user requirement): never copy voice assets.
EXCLUDE = ("audio/sfx/ult_voice",)
m["assets"] = [i for i in m["assets"] if not i["path"].startswith(EXCLUDE)]
(dst / "manifest.json").write_text(json.dumps(m, ensure_ascii=False, indent=1))
n = 0
for it in m["assets"]:
    if it.get("status") != "ready" or it["path"].startswith(EXCLUDE):
        continue
    files = [f for f in it.get("files", [it["path"]]) if not f.endswith(".mp3")]
    for f in files:
        s = src / f
        if not s.exists():
            print("missing", f); continue
        d = dst / f
        d.parent.mkdir(parents=True, exist_ok=True)
        if not d.exists() or d.stat().st_mtime < s.stat().st_mtime:
            shutil.copy2(s, d); n += 1
print(f"synced {n} files; ready={sum(1 for i in m['assets'] if i.get('status')=='ready')}/{len(m['assets'])}")
