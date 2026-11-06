#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Assemble build/gst-jpeg/bundle-stateful for harness/gst-jpeg/stateful/run-job.sh: the dev plugins of the recheck
# (build/gst-jpeg/out, patches 0101-0107: v4l2sljpegdec, jpegparse), the dev video4linux2 plugin (build/gst-jpeg/good/out,
# gst-plugins-good 1.28.7 + patches/gst-plugins-good1.0 0101-0102: v4l2jpegdec; harness/gst-jpeg/build-dev-good.sh),
# board-test.sh, the 16-aligned JPEG vectors (z1920x1088.jpg, mjmix.mkv, mjmix-up.mkv from build/gst-jpeg/vec-oddsize),
# a stateless regression clip (h264-640x480.mkv: 30 frames, libx264 high profile with B-frames) and a stateless
# resolution-change stream (h264mix.h264: 15 frames 640x480 then 15 frames 320x240, Annex B) with their reference
# md5s (host ffmpeg, I420; h264mix: the two parts decoded separately, concatenated).
set -euo pipefail
H=/home/aruni/orangepizero2; W=$H/build/gst-jpeg; B=$W/bundle-stateful; V=$W/vec-oddsize
G=$W/good/out
for f in "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$G/libgstvideo4linux2.so" "$V/z1920x1088.jpg" "$V/mjmix.mkv" "$V/mjmix-up.mkv"; do
	[ -f "$f" ] || { echo "missing: $f"; exit 1; }
done
rm -rf "${B:?}"; mkdir -p "$B/plugins" "$B/vec"
cp "$W/out/libgstv4l2codecs.so" "$W/out/libgstjpegformat.so" "$G/libgstvideo4linux2.so" "$B/plugins/"
cp "$H/harness/gst-jpeg/stateful/board-test.sh" "$B/"
cp "$V/z1920x1088.jpg" "$V/mjmix.mkv" "$V/mjmix-up.mkv" "$B/vec/"
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=s=640x480:r=30 -frames:v 30 -c:v libx264 \
	-profile:v high -bf 2 -pix_fmt yuv420p -g 15 "$B/vec/h264-640x480.mkv"
ffmpeg -nostdin -hide_banner -loglevel error -i "$B/vec/h264-640x480.mkv" -f rawvideo -pix_fmt yuv420p - | \
	md5sum | cut -c1-32 > "$B/vec/h264-640x480.i420.md5"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=s=640x480:r=30 -frames:v 15 -c:v libx264 \
	-profile:v high -bf 2 -pix_fmt yuv420p -g 15 -f h264 "$T/a.h264"
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i testsrc2=s=320x240:r=30 -frames:v 15 -c:v libx264 \
	-profile:v high -bf 2 -pix_fmt yuv420p -g 15 -f h264 "$T/b.h264"
cat "$T/a.h264" "$T/b.h264" > "$B/vec/h264mix.h264"
for p in a b; do ffmpeg -nostdin -hide_banner -loglevel error -i "$T/$p.h264" -f rawvideo -pix_fmt yuv420p -; done | \
	md5sum | cut -c1-32 > "$B/vec/h264mix.i420.md5"
{
	echo "plugins built from build/gst-jpeg/src $(git -C "$W/src" rev-parse --short HEAD) ($(git -C "$W/src" log -1 --format=%s))"
	echo "libgstvideo4linux2.so built from build/gst-jpeg/good/src $(git -C "$W/good/src" rev-parse --short HEAD) ($(git -C "$W/good/src" log -1 --format=%s))"
	sha256sum "$B"/plugins/*.so | sed "s|$B/||"
} > "$B/BUILD.txt"
(cd "$B/vec" && sha256sum ./*.jpg ./*.mkv ./*.h264 > SHA256SUMS)
cat "$B/BUILD.txt"; du -sh "$B"
