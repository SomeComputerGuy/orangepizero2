#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Assemble build/gst-mpeg1/bundle for harness/gst-mpeg1/run-job.sh: the dev plugins and the patched libgstcodecs from
# build/gst-mpeg1/out (harness/gst-mpeg1/build-dev.sh), board-test.sh and the test streams from kernel-check/legacy-serve.
set -euo pipefail
H=/home/aruni/orangepizero2; W=$H/build/gst-mpeg1; B=$W/bundle; SV=$H/kernel-check/legacy-serve/mpeg2
for f in "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$W/out/libgstcodecs-1.0.so.0"; do [ -f "$f" ] || { echo "missing: $f"; exit 1; }; done
rm -rf "${B:?}"; mkdir -p "$B/plugins" "$B/lib" "$B/vec"
cp "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$B/plugins/"
cp "$W/out/libgstcodecs-1.0.so.0" "$B/lib/"
cp "$H/harness/gst-mpeg1/board-test.sh" "$B/"; chmod +x "$B/board-test.sh"
cp "$SV/ccm1.mpg" "$B/vec/ccm1"
for n in tcela-18 tcela-16 tcela-19 tcela-15 mcp10ccett; do cp "$SV/$n.bits" "$B/vec/$n"; done
cp "$SV/MEI.stream16.long" "$SV/MEI.stream16v2" "$B/vec/"
{ echo "plugins built from build/gst-mpeg1/src $(git -C "$W/src" rev-parse --short HEAD) ($(git -C "$W/src" log -1 --format=%s))"
  (cd "$W/out" && sha256sum *.so *.so.0); (cd "$B/vec" && sha256sum *); } > "$B/BUILD.txt"
du -sh "$B"; cat "$B/BUILD.txt" | head -5
