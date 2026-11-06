#!/bin/bash
# Build the four synthetic lossless streams (+ .srcmd5) for afbc-wb into $OUT (default
# kernel-check/vdec-serve/afbc-wb, served to the board, not committed). Each stream is checked
# lossless on the host (software decode == source) before it is kept.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd); OUT=${OUT:-/home/aruni/orangepizero2/kernel-check/vdec-serve/afbc-wb}
W=1024; HH=768; N=${N:-24}; TILE=64
mkdir -p "$OUT"
enc() { # enc <name> <bits> <container> <encoder args...>
  local n=$1 b=$2 c=$3 pf; shift 3; [ $b = 8 ] && pf=yuv420p || pf=yuv420p10le
  python3 -I "$H/mkstreams.py" "$OUT" $n $W $HH $N $b $TILE
  ffmpeg -nostdin -hide_banner -loglevel error -y -f rawvideo -pix_fmt $pf -s ${W}x$HH -r 60 -i "$OUT/$n.yuv" "$@" "$OUT/$n.$c"
  ffmpeg -nostdin -hide_banner -loglevel error -i "$OUT/$n.$c" -f rawvideo -pix_fmt $pf - | cmp - "$OUT/$n.yuv" \
    || { echo "$n: host decode differs from the source (not lossless)"; exit 1; }
  echo "$n.$c: $(stat -c %s "$OUT/$n.$c") bytes, $N frames, lossless ok, sha256 $(sha256sum < "$OUT/$n.$c" | cut -c1-16)"
  rm -f "$OUT/$n.yuv"; }
X265="keyint=12:min-keyint=12:bframes=3:log-level=error"
enc syn-hevc8  8  mkv  -c:v libx265 -x265-params lossless=1:$X265
enc syn-hevc10 10 mkv  -c:v libx265 -profile:v main10 -x265-params lossless=1:$X265
enc syn-vp9p0  8  webm -c:v libvpx-vp9 -lossless 1 -g 12 -row-mt 1
enc syn-vp9p2  10 webm -c:v libvpx-vp9 -profile:v 2 -lossless 1 -g 12 -row-mt 1
ls -la "$OUT"
