#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Fetch the fluster VP9-TEST-VECTORS and VP9-TEST-VECTORS-HIGH vectors on the host (the board has no internet)
# into build/vp9-vectors/vec/ (untrusted data: nothing from there is executed), checking fluster's md5 of each
# source file. Skips files already present with the right md5. Prints "fetched N, bad M" at the end.
set -u
H=/home/aruni/orangepizero2; V=$H/build/vp9-vectors/vec; S=$H/build/vp9-vectors/suites; mkdir -p "$V"
python3 -I - "$S" <<'PY' > "$V/.list"
import json, sys, os
for s in ('VP9-TEST-VECTORS', 'VP9-TEST-VECTORS-HIGH'):
    d = json.load(open(os.path.join(sys.argv[1], s + '.json')))
    for t in d['test_vectors']:
        print(t['input_file'], t['source'], t['source_checksum'])
PY
n=0; bad=0
while read -r f url md5; do
  if [ -f "$V/$f" ] && [ "$(md5sum < "$V/$f" | cut -c1-32)" = "$md5" ]; then continue; fi
  for try in 1 2 3; do curl -sS -L --max-time 300 -o "$V/$f.part" "$url" && break; sleep 5; done
  if [ "$(md5sum < "$V/$f.part" 2>/dev/null | cut -c1-32)" = "$md5" ]; then mv "$V/$f.part" "$V/$f"; n=$((n+1))
  else echo "BAD $f"; rm -f "$V/$f.part"; bad=$((bad+1)); fi
done < "$V/.list"
echo "fetched $n, bad $bad, present $(ls "$V" | grep -v '^\.' | wc -l) of $(wc -l < "$V/.list")"
