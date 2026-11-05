#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side of the VP9 vectors job: board-fluster.sh DIR CHUNK
#   DIR holds plugins/libgstv4l2codecs.so (dev build), pylib/fluster, suites/*.json, resources/<suite>/<vector>/<file>.
#   CHUNK: c1 = vp90-2-00/01 (quantizer, sharpness), c2 = vp90-2-02/03 (sizes), c3 = the rest of VP9-TEST-VECTORS,
#          c4 = VP9-TEST-VECTORS-HIGH.
# The dev plugin is loaded from a private plugin path (the system libgstv4l2codecs.so is left out), nothing is
# installed. Output: DIR/out/CHUNK.md (fluster summary, plain text), DIR/out/CHUNK.log, DIR/out/CHUNK.rc. The last
# line printed is ROUND-DONE.
set -u
D=$1; C=$2; O=$D/out; mkdir -p "$O"
SYS=/usr/lib/aarch64-linux-gnu/gstreamer-1.0
P=$D/pdir; rm -rf "$P"; mkdir -p "$P"
for f in "$SYS"/*.so; do
	case $(basename "$f") in libgstv4l2codecs.so) ;; *) ln -s "$f" "$P/";; esac
done
cp "$D"/plugins/*.so "$P/"
export GST_PLUGIN_SYSTEM_PATH=$P GST_REGISTRY=$D/registry.bin
rm -f "$GST_REGISTRY"
{
	uname -rv; gst-launch-1.0 --version | head -2
	for e in v4l2slvp9dec parsebin matroskademux ivfparse vp9parse videoconvert videocodectestsink; do
		gst-inspect-1.0 "$e" >/dev/null 2>&1 && echo "element $e: present" || echo "element $e: MISSING"
	done
	gst-inspect-1.0 --plugin v4l2codecs 2>/dev/null | grep -E 'Filename|Version' | head -2
	ls -l /dev/video* 2>/dev/null
} > "$O/env.txt" 2>&1
case $C in
	c1) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-00- vp90-2-01-' ;;
	c2) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-02- vp90-2-03-' ;;
	c3) SUITE=VP9-TEST-VECTORS; SEL='!vp90-2-00- vp90-2-01- vp90-2-02- vp90-2-03-' ;;
	c4) SUITE=VP9-TEST-VECTORS-HIGH; SEL='' ;;
	*) echo "unknown chunk $C"; echo ROUND-DONE; exit 1 ;;
esac
python3 -I - "$D/suites/$SUITE.json" $SEL > "$O/$C.list" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); sel = sys.argv[2:]
inv = bool(sel) and sel[0].startswith('!')
if inv: sel[0] = sel[0][1:]
for t in d['test_vectors']:
    hit = not sel or any(t['name'].startswith(p) for p in sel)
    if hit != inv: print(t['name'])
PY
echo "chunk $C: $SUITE, $(wc -l < "$O/$C.list") vectors" | tee "$O/$C.log"
rm -rf "$D/tmpout"; mkdir -p "$D/tmpout"
# shellcheck disable=SC2046
python3 -I -c "import sys; sys.path.insert(0, '$D/pylib'); from fluster.main import fluster_main; sys.exit(fluster_main())" \
	-tsd "$D/suites" -r "$D/resources" -o "$D/tmpout" -ne \
	run -d GStreamer-VP9-V4L2SL-Gst1.0 -ts "$SUITE" -tv $(cat "$O/$C.list") -j1 -t 90 -s -so "$O/$C.md" >> "$O/$C.log" 2>&1
echo "rc=$?" | tee "$O/$C.rc"
rm -rf "$D/tmpout"
dmesg | grep -iE 'cedrus|timed out|iommu|fault|oops|warning' | tail -40 > "$O/$C.dmesg" 2>&1
echo ROUND-DONE
