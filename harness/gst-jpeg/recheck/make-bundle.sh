#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Assemble build/gst-jpeg/bundle-recheck for harness/gst-jpeg/recheck/run-job.sh: the dev plugins from
# build/gst-jpeg/out (harness/gst-jpeg/build-dev.sh of build/gst-jpeg/src branch opiz2 = patches 0101-0107),
# jpegtest, board-test.sh and the vectors of the failing cases of jobs 05 and 06 (from build/gst-jpeg/vec-gaps and
# vec-oddsize, which gaps/gen-vectors.sh and oddsize/gen-vectors.sh wrote).
set -euo pipefail
H=/home/aruni/orangepizero2; W=$H/build/gst-jpeg; B=$W/bundle-recheck
for f in "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$H/harness/jpegtest/jpegtest" \
	"$W/vec-gaps/s420.jpg" "$W/vec-gaps/z4096x4096.jpg" "$W/vec-oddsize/z1921x1081.jpg" "$W/vec-oddsize/mj-z33x17.mkv"; do
	[ -f "$f" ] || { echo "missing: $f"; exit 1; }
done
rm -rf "${B:?}"; mkdir -p "$B/plugins" "$B/vec"
cp "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$B/plugins/"
cp "$H/harness/jpegtest/jpegtest" "$H/harness/gst-jpeg/recheck/board-test.sh" "$B/"
cp "$W/vec-gaps/s420.jpg" "$W/vec-gaps/z4096x4096.jpg" "$B/vec/"
cp "$W"/vec-oddsize/{z17x33-411,z33x17-422,z15x15-444,z1x1,z8x8,z1921x1081}.jpg "$W/vec-oddsize/mj-z33x17.mkv" "$B/vec/"
cat > "$B/vec/cases.txt" <<'EOF'
# NAME W H KIND SPEC   (still: SAMP, hardware path; size: SAMP, must fall back to jpegdec; clip: SEQ of WxH*N)
s420 1920 1080 still 420
z17x33-411 17 33 still 411
z33x17-422 33 17 still 422
z15x15-444 15 15 still 444
z1x1 1 1 still 420
z8x8 8 8 still 420
z4096x4096 4096 4096 size 420
mj-z33x17 0 0 clip 33x17*30
EOF
{
	echo "plugins built from build/gst-jpeg/src $(git -C "$W/src" rev-parse --short HEAD) ($(git -C "$W/src" log -1 --format=%s))"
	echo "patches: $(ls "$H/patches/gstreamer" | grep -o '^01[0-9][0-9]' | tr '\n' ' ')"
	sha256sum "$B"/plugins/*.so | sed "s|$B/||"
} > "$B/BUILD.txt"
(cd "$B/vec" && sha256sum ./*.jpg ./*.mkv > SHA256SUMS)
cat "$B/BUILD.txt"; du -sh "$B"
