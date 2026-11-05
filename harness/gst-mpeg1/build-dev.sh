#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Dev build of the v4l2codecs plugin (arm64) from build/gst-mpeg1/src (git worktree of build/gst-jpeg/src, branch mpeg1 =
# dd1d605 + patches/gstreamer 0001-0017, 0101-0107, 0201), rootless (mmdebstrap unshare + qemu-user), the method of
# harness/gst-jpeg/build-dev.sh. 0015 changes libgstcodecs (gst-libs/gst/codecs), so the patched
# libgstcodecs-1.0.so.0 is shipped too and loaded with LD_LIBRARY_PATH on the board.
# Output: build/gst-mpeg1/out/{libgstv4l2codecs.so,libgstjpegformat.so,libgstcodecs-1.0.so.0} + meson/ninja logs.
set -euo pipefail
TOP=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$TOP/build/gst-mpeg1
export TMPDIR=${OPIZ2_MEDIA_TMPDIR:-/var/tmp}
rm -rf "${W:?}/out"; mkdir -p "$W/out" "$W/bscripts"
cat > "$W/bscripts/build-in-chroot.sh" <<'EOF'
#!/bin/sh
set -e
cd /build/src
meson setup /build/b -Dauto_features=disabled -Dv4l2codecs=enabled -Djpegformat=enabled -Dexamples=disabled -Dtests=disabled \
  -Dintrospection=disabled -Dwerror=false > /build/out/meson.log 2>&1 || { tail -30 /build/out/meson.log; exit 1; }
ninja -C /build/b -j8 sys/v4l2codecs/libgstv4l2codecs.so gst/jpegformat/libgstjpegformat.so > /build/out/ninja.log 2>&1 || { grep -B2 -A8 "error" /build/out/ninja.log | head -80; exit 1; }
grep -A3 "warning:" /build/out/ninja.log > /build/out/warnings.txt || true
cp /build/b/sys/v4l2codecs/libgstv4l2codecs.so /build/b/gst/jpegformat/libgstjpegformat.so /build/out/
cp -L /build/b/gst-libs/gst/codecs/libgstcodecs-1.0.so.0 /build/out/libgstcodecs-1.0.so.0
EOF
PROXY=()
if (exec 3<>/dev/tcp/127.0.0.1/3142) 2>/dev/null; then
  PROXY=(--aptopt='Acquire::http::Proxy "http://127.0.0.1:3142"')
fi
mmdebstrap --mode=unshare --variant=buildd --arch=arm64 "${PROXY[@]}" \
  --include=meson,ninja-build,pkgconf,libgstreamer1.0-dev,libgstreamer-plugins-base1.0-dev,libgudev-1.0-dev,libudev-dev,libdrm-dev,liborc-0.4-dev,python3 \
  --customize-hook='mkdir -p "$1/build/src" "$1/build/out" "$1/build/scripts"' \
  --customize-hook="sync-in $W/src /build/src" \
  --customize-hook="sync-in $W/bscripts /build/scripts" \
  --customize-hook='chroot "$1" sh /build/scripts/build-in-chroot.sh' \
  --customize-hook="sync-out /build/out $W/out" \
  stonking /dev/null 'deb http://ports.ubuntu.com/ubuntu-ports stonking main universe' > "$W/mmdebstrap.log" 2>&1 \
  || { tail -40 "$W/mmdebstrap.log"; exit 1; }
ls -la "$W/out"
