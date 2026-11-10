#!/usr/bin/env python3
"""Copy status=ready assets (and manifest.json) from _shared/assets into res://assets/,
and rig data (rig.json, anims.json, parts/*.png) from _shared/rigs/ into res://rigs/.
Godot uses .ogg for audio. Run: python3 tools/sync_assets.py"""
import json, shutil, pathlib
from PIL import Image
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

def build_atlas(char_dir: pathlib.Path) -> None:
    """Pack every part image referenced by rig.json / anims.json into one texture.
    One texture per character lets the canvas renderer batch all of its quads into a single draw call."""
    if not (char_dir / "rig.json").exists():
        return
    rig = json.loads((char_dir / "rig.json").read_text())
    anims = json.loads((char_dir / "anims.json").read_text())
    names = {s.get("image", "") for s in rig.get("slots", [])}
    for a in anims.values():
        for sl in a.get("slots", {}).values():
            for k in sl:
                if k.get("image"):
                    names.add(k["image"])
    names = sorted(n for n in names if n and (char_dir / n).exists())
    if not names:
        return
    pad = 2
    images = {n: Image.open(char_dir / n).convert("RGBA") for n in names}
    width = max(512, max(im.width for im in images.values()) + pad * 2)
    x, y, row_h, places = pad, pad, 0, {}
    for n in names:
        im = images[n]
        if x + im.width + pad > width:
            x, y, row_h = pad, y + row_h + pad, 0
        places[n] = [x, y, im.width, im.height]
        x += im.width + pad
        row_h = max(row_h, im.height)
    height = 1
    while height < y + row_h + pad:
        height *= 2
    atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    for n in names:
        atlas.paste(images[n], (places[n][0], places[n][1]))
    atlas.save(char_dir / "atlas.png")
    (char_dir / "atlas.json").write_text(json.dumps(places, ensure_ascii=False))


rigs_src = root.parent / "_shared" / "rigs"
rigs_dst = root / "rigs"
rn = 0
if rigs_src.exists():
    for char_dir in rigs_src.iterdir():
        if not char_dir.is_dir() or char_dir.name.startswith("."):
            continue
        for rel in ["rig.json", "anims.json"]:
            s = char_dir / rel
            if s.exists():
                d = rigs_dst / char_dir.name / rel
                d.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(s, d); rn += 1
        parts_dir = char_dir / "parts"
        if parts_dir.exists():
            out_parts = rigs_dst / char_dir.name / "parts"
            out_parts.mkdir(parents=True, exist_ok=True)
            src_names = {p.name for p in parts_dir.glob("*.png")}
            for old in list(out_parts.glob("*.png")):
                if old.name not in src_names:
                    old.unlink()
                    imp = out_parts / (old.name + ".import")
                    if imp.exists():
                        imp.unlink()
            for p in parts_dir.glob("*.png"):
                shutil.copy2(p, out_parts / p.name); rn += 1
        build_atlas(rigs_dst / char_dir.name)
print(f"synced {n} assets, {rn} rig files; ready={sum(1 for i in m['assets'] if i.get('status')=='ready')}/{len(m['assets'])}")


