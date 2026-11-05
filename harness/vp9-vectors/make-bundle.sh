#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Assemble build/vp9-vectors/bundle.tar for the runner job: the dev v4l2codecs plugin (build-plugin.sh), the fluster
# python package (OPi5's fluster 0.7.1 deb, extracted to build/vp9-vectors/fluster-deb), the two VP9 suite JSONs, the
# vectors (fetch-vectors.sh) in fluster's resources layout, and board-fluster.sh. Hard links where possible.
set -euo pipefail
TOP=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd); S=$TOP/harness/vp9-vectors; W=$TOP/build/vp9-vectors; B=$W/bundle
[ -f "$W/out/libgstv4l2codecs.so" ] || { echo "plugin missing: run harness/vp9-vectors/build-plugin.sh"; exit 1; }
[ -d "$W/fluster-deb/usr/lib/python3/dist-packages/fluster" ] || { echo "fluster package missing in $W/fluster-deb"; exit 1; }
rm -rf "${B:?}" "$W/bundle.tar"; mkdir -p "$B/plugins" "$B/pylib" "$B/suites" "$B/resources"
cp "$W/out/libgstv4l2codecs.so" "$B/plugins/"
cp -a "$W/fluster-deb/usr/lib/python3/dist-packages/fluster" "$B/pylib/"
cp "$W/suites/VP9-TEST-VECTORS.json" "$W/suites/VP9-TEST-VECTORS-HIGH.json" "$B/suites/"
python3 -I - "$W/suites" "$W/vec" "$B/resources" <<'PY'
import json, os, sys
suites, vec, res = sys.argv[1:4]
n = 0
for s in ('VP9-TEST-VECTORS', 'VP9-TEST-VECTORS-HIGH'):
    d = json.load(open(os.path.join(suites, s + '.json')))
    for t in d['test_vectors']:
        dst = os.path.join(res, s, t['name']); os.makedirs(dst, exist_ok=True)
        src = os.path.join(vec, t['input_file'])
        if not os.path.exists(src):
            sys.exit('vector missing: ' + src)
        os.link(src, os.path.join(dst, t['input_file'])); n += 1
print('vectors linked:', n)
PY
cp "$S/board-fluster.sh" "$B/"
tar -C "$B" -cf "$W/bundle.tar" .
ls -la "$W/bundle.tar"; echo "bundle: $B"
