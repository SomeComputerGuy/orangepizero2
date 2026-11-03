#!/bin/bash
# Cross-build Jernej's FFmpeg fork (v4l2request-mpeg4) for the Zero2 on the host (ccache).
# Sysroot: libdrm/libudev headers+libs copied from the board, kernel uapi from our work-vdec tree.
set -euo pipefail
B=/home/aruni/orangepizero2/kernel-check/ffmpeg-afbc
SRC=${SRC:-$B/src/ffmpeg}; OUT=${OUT:-$B/build}; S=$B/sysroot; PFX=${PFX:-$B/install}
mkdir -p "$OUT"; cd "$OUT"
cat > pkgconf.sh <<P
#!/bin/sh
PKG_CONFIG_SYSROOT_DIR=$S PKG_CONFIG_LIBDIR=$S/usr/lib/aarch64-linux-gnu/pkgconfig exec pkg-config "\$@"
P
chmod +x pkgconf.sh
"$SRC/configure" --prefix=/opt/ffv4l2 --enable-cross-compile --arch=aarch64 --target-os=linux \
  --cross-prefix=aarch64-linux-gnu- --cc="ccache aarch64-linux-gnu-gcc" --cxx="ccache aarch64-linux-gnu-g++" \
  --pkg-config="$OUT/pkgconf.sh" \
  --extra-cflags="-I$S/kuapi/include" \
  --extra-ldflags="-L$S/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$S/usr/lib/aarch64-linux-gnu -Wl,--allow-shlib-undefined" \
  --disable-autodetect --disable-doc --disable-debug --enable-static --disable-shared \
  --enable-libdrm --enable-libudev --enable-v4l2-request --enable-network \
  > configure.out 2>&1 || { tail -30 configure.out; tail -40 ffbuild/config.log; exit 1; }
grep -iE "v4l2|drm|udev" configure.out | head -20
make -j"$(nproc)" > make.out 2>&1 || { tail -40 make.out; exit 1; }
make install DESTDIR="$PFX" > install.out 2>&1
ls -la "$PFX/opt/ffv4l2/bin"
