#!/bin/bash
# Cross-build kms-wb for the Zero2 against the board sysroot copies of libdrm (same sysroot as afbc-kms-play/build.sh).
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
S=${SYSROOT:-/home/aruni/orangepizero2/kernel-check/ffmpeg-afbc/sysroot}; OUT=${OUT:-$H/out}
mkdir -p "$OUT"
ccache aarch64-linux-gnu-gcc -O2 -g -Wall -Wextra -Wno-unused-parameter -std=gnu11 \
	-I"$S/usr/include" -I"$S/usr/include/libdrm" -I"$S/kuapi/include" \
	-o "$OUT/kms-wb" "$H/kms-wb.c" \
	-L"$S/usr/lib/aarch64-linux-gnu" -Wl,-rpath-link,"$S/usr/lib/aarch64-linux-gnu" -ldrm
aarch64-linux-gnu-readelf -d "$OUT/kms-wb" | grep NEEDED
ls -la "$OUT/kms-wb"; sha256sum "$OUT/kms-wb"
