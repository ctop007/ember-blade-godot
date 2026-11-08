#!/bin/bash
# Subset Alibaba PuHuiTi Heavy to the characters used in code + config.
cd "$(dirname "$0")/.."
python3 - <<'PY' > /tmp/jr_chars.txt
import pathlib,string
s=set(string.printable)
s|=set("０１２３４５６７８９％×·—…“”‘’！？，。：；（）《》【】、～·★☆♥↑↓←→")
for p in list(pathlib.Path('.').rglob('*.gd'))+[pathlib.Path('config/game.json')]:
    if '.godot' in p.parts: continue
    s|=set(p.read_text(encoding='utf-8'))
print(''.join(sorted(c for c in s if c not in '\n\r\t')))
PY
/tmp/fontenv/bin/pyftsubset "$HOME/Library/Fonts/Alibaba-PuHuiTi-Heavy.ttf" --text-file=/tmp/jr_chars.txt --output-file=fonts/ui_font.ttf --layout-features='*'
ls -la fonts/ui_font.ttf
