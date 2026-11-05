#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Quick static aarch64 cross build of an FFmpeg v4l2-request tree for board tests (copied prefix, no install).
# Usage: harness/ffmpeg/dev-build.sh <ffmpeg-src> <build-dir> [extra configure args]
# Output: <build-dir>/ffmpeg, ffprobe (static, only libdrm/libudev from the sysroot). Rerun = incremental (ccache).
# Kernel uAPI headers with our downstream controls (AVS2, AVS, MPEG-1 flags): kernel-check/ffmpeg-deb/kuapi
# (make headers_install of the integration kernel tree).
set -euo pipefail
here=$(cd "$(dirname "$0")/../.." && pwd)
src=$(realpath "${1:?src}"); b=${2:?build}; shift 2
sys=$here/kernel-check/ffmpeg-afbc/sysroot
kuapi=${KUAPI:-$here/kernel-check/ffmpeg-deb/kuapi/include}
mkdir -p "$b"; b=$(realpath "$b")
cat > "$b/pkgconf.sh" <<PC
#!/bin/sh
PKG_CONFIG_SYSROOT_DIR=$sys PKG_CONFIG_LIBDIR=$sys/usr/lib/aarch64-linux-gnu/pkgconfig exec pkg-config "\$@"
PC
chmod +x "$b/pkgconf.sh"
cd "$b"
if [[ ! -f ffbuild/config.mak || "$src/configure" -nt ffbuild/config.mak || -n "${RECONF:-}" ]]; then
	"$src/configure" --prefix=/opt/ffv4l2 --enable-cross-compile --arch=aarch64 --target-os=linux \
		--cross-prefix=aarch64-linux-gnu- --cc='ccache aarch64-linux-gnu-gcc' --cxx='ccache aarch64-linux-gnu-g++' \
		--pkg-config="$b/pkgconf.sh" --extra-cflags="-I$kuapi" \
		--extra-ldflags="-L$sys/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$sys/usr/lib/aarch64-linux-gnu -Wl,--allow-shlib-undefined" \
		--disable-autodetect --disable-doc --disable-debug --enable-static --disable-shared \
		--enable-libdrm --enable-libudev --enable-v4l2-request --enable-network --enable-gpl "$@" > configure.log
fi
make -j"$(nproc)" ffmpeg ffprobe > make.log 2>&1 || { tail -30 make.log; exit 1; }
grep -E "warning:" make.log | grep -E "v4l2_request|avs|cavs|mpeg12|mpeg4" || true
ls -la "$b/ffmpeg" "$b/ffprobe"
