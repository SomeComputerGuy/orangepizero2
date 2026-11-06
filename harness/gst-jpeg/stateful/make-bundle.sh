#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Assemble build/gst-jpeg/bundle-stateful for harness/gst-jpeg/stateful/run-job.sh: the dev plugins of the recheck
# (build/gst-jpeg/out, patches 0101-0107: v4l2sljpegdec, jpegparse), board-test.sh, the 16-aligned JPEG vectors
# (z1920x1088.jpg, mjmix.mkv, mjmix-up.mkv from build/gst-jpeg/vec-oddsize) and a stateless regression clip
# (h264-640x480.mkv: 30 frames, libx264 high profile with B-frames) with its reference md5 (host ffmpeg, I420).
set -euo pipefail
H=/home/aruni/orangepizero2; W=$H/build/gst-jpeg; B=$W/bundle-stateful; V=$W/vec-oddsize
for f in "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$V/z1920x1088.jpg" "$V/mjmix.mkv" "$V/mjmix-up.mkv"; do
	[ -f "$f" ] || { echo "missing: $f"; exit 1; }
done
rm -rf "${B:?}"; mkdir -p "$B/plugins" "$B/vec"
cp "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$B/plugins/"
cp "$H/harness/gst-jpeg/stateful/board-test.sh" "$B/"
cp "$V/z1920x1088.jpg" "$V/mjmix.mkv" "$V/mjmix-up.mkv" "$B/vec/"
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=s=640x480:r=30 -frames:v 30 -c:v libx264 \
	-profile:v high -bf 2 -pix_fmt yuv420p -g 15 "$B/vec/h264-640x480.mkv"
ffmpeg -nostdin -hide_banner -loglevel error -i "$B/vec/h264-640x480.mkv" -f rawvideo -pix_fmt yuv420p - | \
	md5sum | cut -c1-32 > "$B/vec/h264-640x480.i420.md5"
{
	echo "plugins built from build/gst-jpeg/src $(git -C "$W/src" rev-parse --short HEAD) ($(git -C "$W/src" log -1 --format=%s))"
	sha256sum "$B"/plugins/*.so | sed "s|$B/||"
} > "$B/BUILD.txt"
(cd "$B/vec" && sha256sum ./*.jpg ./*.mkv > SHA256SUMS)
cat "$B/BUILD.txt"; du -sh "$B"
