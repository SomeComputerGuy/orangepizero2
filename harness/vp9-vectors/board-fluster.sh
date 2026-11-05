#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side of the VP9 vectors job: board-fluster.sh DIR CHUNK
#   DIR holds plugins/libgstv4l2codecs.so (dev build), pylib/fluster, suites/*.json, resources/<suite>/<vector>/<file>.
#   CHUNK: pre = pre-flight, the one known-good vector vp90-2-00-quantizer-00.webm (plus a direct gst-launch run
#                with GST_DEBUG=2 into out/pre.gst.txt, so a failure says why),
#          c1 = vp90-2-00/01 (quantizer, sharpness, 71), c2 = vp90-2-02/03 (sizes, 137),
#          c3 = vp90-2-05 .. vp90-2-14 (tiles, show-existing, key-frame resize, 59),
#          c5 = vp90-2-15 .. vp90-2-22 + vp91 (inter-frame resize, svc, profile 1, 38), c4 = VP9-TEST-VECTORS-HIGH (6).
#          u1 = inter-frame resize: svc_1280x720_3 (upsize) + the 26 downsize vectors (21-resize_inter x24, 05, 18) (27),
#          u2 = profile-0 regression subset, one or two vectors per feature group (25). u1/u2 = job vp9-upsize.
# The dev plugin is loaded from a private plugin path (the system libgstv4l2codecs.so is left out), nothing is
# installed. Output: DIR/out/CHUNK.md (fluster summary, plain text: OK/KO/ER/TO/NS per vector), DIR/out/CHUNK.log,
# DIR/out/CHUNK.rc. Every fluster line is also printed to stdout with a timestamp (the host's stall watchdog watches
# stdout). The last line printed is ROUND-DONE.
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
stamp() { while IFS= read -r l; do printf '%s %s\n' "$(date +%T)" "$l"; done; }
# selector words: prefixes to include (none = all); a word starting with ! is a prefix to exclude
case $C in
	pre) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-00-quantizer-00.webm' ;;
	c1) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-00- vp90-2-01-' ;;
	c2) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-02- vp90-2-03-' ;;
	c3) SUITE=VP9-TEST-VECTORS; SEL='!vp90-2-00- !vp90-2-01- !vp90-2-02- !vp90-2-03- !vp90-2-15- !vp90-2-16- !vp90-2-17- !vp90-2-18- !vp90-2-19- !vp90-2-2 !vp91-' ;;
	c5) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-15- vp90-2-16- vp90-2-17- vp90-2-18- vp90-2-19- vp90-2-2 vp91-' ;;
	c4) SUITE=VP9-TEST-VECTORS-HIGH; SEL='' ;;
	u1) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-22-svc_1280x720_3 vp90-2-21- vp90-2-05-resize vp90-2-18-resize' ;;
	u2) SUITE=VP9-TEST-VECTORS; SEL='vp90-2-00-quantizer-00. vp90-2-00-quantizer-63. vp90-2-01-sharpness-1. vp90-2-02-size-08x08.
	    vp90-2-02-size-66x66. vp90-2-02-size-lf-1920x1080. vp90-2-03-size-226x226. vp90-2-03-deltaq. vp90-2-06-bilinear.
	    vp90-2-07-frame_parallel. vp90-2-08-tile-4x4. vp90-2-08-tile_1x8_frame_parallel. vp90-2-09-aq2. vp90-2-09-lf_deltas.
	    vp90-2-10-show-existing-frame. vp90-2-11-size-351x287. vp90-2-12-droppable_1. vp90-2-14-resize-fp-tiles-1-16.
	    vp90-2-14-resize-10frames-fp-tiles-1-2-4-8. vp90-2-15-segkey. vp90-2-16-intra-only. vp90-2-17-show-existing-frame.
	    vp90-2-19-skip. vp90-2-20-big_superframe-01. vp90-2-22-svc_1280x720_1.' ;;
	*) echo "unknown chunk $C"; echo ROUND-DONE; exit 1 ;;
esac
# shellcheck disable=SC2086
python3 -I - "$D/suites/$SUITE.json" $SEL > "$O/$C.list" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); words = sys.argv[2:]
inc = [w for w in words if not w.startswith('!')]; exc = [w[1:] for w in words if w.startswith('!')]
for t in d['test_vectors']:
    n = t['name']
    if (not inc or any(n.startswith(p) for p in inc)) and not any(n.startswith(p) for p in exc):
        print(n)
PY
echo "chunk $C: $SUITE, $(wc -l < "$O/$C.list") vectors" | tee "$O/$C.log"
if [ "$C" = pre ]; then # direct run of the same pipeline fluster uses, with GStreamer warnings, for diagnosis
	V=$D/resources/VP9-TEST-VECTORS/vp90-2-00-quantizer-00.webm/vp90-2-00-quantizer-00.webm
	GST_DEBUG=2 timeout 60 gst-launch-1.0 --no-fault filesrc location="$V" ! parsebin ! v4l2slvp9dec ! video/x-raw \
		! videoconvert dither=none ! video/x-raw,format=I420 ! videocodectestsink -m > "$O/pre.gst.txt" 2>&1
	echo "direct gst-launch rc=$? $(grep -c 'checksum=' "$O/pre.gst.txt") checksum lines" | tee -a "$O/$C.log"
fi
rm -rf "$D/tmpout"; mkdir -p "$D/tmpout"
# shellcheck disable=SC2046
python3 -I -u -c "import sys; sys.path.insert(0, '$D/pylib'); from fluster.main import fluster_main; sys.exit(fluster_main())" \
	-tsd "$D/suites" -r "$D/resources" -o "$D/tmpout" -ne \
	run -d GStreamer-VP9-V4L2SL-Gst1.0 -ts "$SUITE" -tv $(cat "$O/$C.list") -j1 -t 90 -s -so "$O/$C.md" 2>&1 \
	| tee -a "$O/$C.log" | grep --line-buffered -E "^\[|^Ran |^FAIL:|^ERROR:" | stamp
rc=$(sed -n 's/^Ran \([0-9]*\)\/\([0-9]*\) tests.*/\1 \2/p' "$O/$C.log" | tail -1)
[ -n "$rc" ] && [ -f "$O/$C.md" ] && echo "rc=0" > "$O/$C.rc" || echo "rc=1" > "$O/$C.rc"
echo "fluster: ran $rc (ok total); $(cat "$O/$C.rc")"
rm -rf "$D/tmpout"
dmesg | grep -iE 'cedrus|timed out|iommu|fault|oops|warning' | tail -40 > "$O/$C.dmesg" 2>&1
echo ROUND-DONE
