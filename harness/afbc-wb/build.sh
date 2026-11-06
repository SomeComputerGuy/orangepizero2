#!/bin/bash
# Cross-build afbc-wb for the Zero2 against the static FFmpeg of kernel-check/ffmpeg-afbc (as afbc-kms-play/build.sh).
# The FFmpeg install tree must be current: run `make install DESTDIR=$B/install` in $B/build after an FFmpeg rebuild
# (2026-11-03: a stale install silently dropped the V4L2REQUEST_PIXFMT override; refreshed again 2026-11-06).
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
B=${FFB:-/home/aruni/orangepizero2/kernel-check/ffmpeg-afbc}
S=$B/sysroot; I=$B/install; OUT=${OUT:-$H/out}
for l in libavcodec libavformat libavutil; do
  [ "$I/opt/ffv4l2/lib/$l.a" -nt "$B/build/$l/$l.a" ] || cmp -s "$I/opt/ffv4l2/lib/$l.a" "$B/build/$l/$l.a" \
    || { echo "stale FFmpeg install: $l.a differs from the build tree (make install DESTDIR=$I in $B/build)"; exit 1; }
done
mkdir -p "$OUT"
export PKG_CONFIG_SYSROOT_DIR=$I PKG_CONFIG_LIBDIR=$I/opt/ffv4l2/lib/pkgconfig
FF_CFLAGS=$(pkg-config --cflags libavformat libavcodec libavutil)
FF_LIBS=$(pkg-config --static --libs libavformat libavcodec libswresample libavutil)
ccache aarch64-linux-gnu-gcc -O2 -g -Wall -Wextra -Wno-unused-parameter -std=gnu11 \
	$FF_CFLAGS -I"$S/usr/include" -I"$S/usr/include/libdrm" -I"$S/kuapi/include" \
	-o "$OUT/afbc-wb" "$H/afbc-wb.c" \
	$FF_LIBS -L"$S/usr/lib/aarch64-linux-gnu" -Wl,-rpath-link,"$S/usr/lib/aarch64-linux-gnu" \
	-Wl,--allow-shlib-undefined -ldrm -ludev -lpthread -lm
aarch64-linux-gnu-readelf -d "$OUT/afbc-wb" | grep NEEDED
ls -la "$OUT/afbc-wb"
sha256sum "$OUT/afbc-wb"
