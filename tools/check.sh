#!/bin/bash
# Syntax-check every .gd; print only errors. Exit 1 if any.
cd "$(dirname "$0")/.."
fail=0
for f in $(find core view tools -name '*.gd'); do
  out=$(timeout 60 godot --headless --path . --check-only -s "$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR:|at: GDScript" | grep -v "Failed to load script")
  if [ -n "$out" ]; then echo "== $f"; echo "$out"; fail=1; fi
done
[ $fail = 0 ] && echo "CHECK_OK"
exit $fail
