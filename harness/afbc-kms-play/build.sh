#!/bin/bash
# Cross-build afbc-kms-play for the Zero2 against the static FFmpeg from
# harness/research/vdec-perf/build-ffmpeg.sh (Jernej's v4l2request-mpeg4 fork,
# a56a208b + V4L2REQUEST_PIXFMT override). FFmpeg is linked statically;
# libdrm, libudev and glibc come from the board (sysroot copies), exactly like
# the ffmpeg binary built by that script.
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
B=${FFB:-/home/aruni/orangepizero2/kernel-check/ffmpeg-afbc}
S=$B/sysroot; I=$B/install; OUT=${OUT:-$H/out}
mkdir -p "$OUT"
export PKG_CONFIG_SYSROOT_DIR=$I PKG_CONFIG_LIBDIR=$I/opt/ffv4l2/lib/pkgconfig
FF_CFLAGS=$(pkg-config --cflags libavformat libavcodec libavutil)
FF_LIBS=$(pkg-config --static --libs libavformat libavcodec libswresample libavutil)
ccache aarch64-linux-gnu-gcc -O2 -g -Wall -Wextra -Wno-unused-parameter -std=gnu11 \
	$FF_CFLAGS -I"$S/usr/include" -I"$S/usr/include/libdrm" -I"$S/kuapi/include" \
	-o "$OUT/afbc-kms-play" "$H/afbc-kms-play.c" \
	$FF_LIBS -L"$S/usr/lib/aarch64-linux-gnu" -Wl,-rpath-link,"$S/usr/lib/aarch64-linux-gnu" \
	-Wl,--allow-shlib-undefined -ldrm -ludev -lpthread -lm
aarch64-linux-gnu-readelf -d "$OUT/afbc-kms-play" | grep NEEDED
ls -la "$OUT/afbc-kms-play"
sha256sum "$OUT/afbc-kms-play"
