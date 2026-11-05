#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Dev build of the v4l2codecs plugin (arm64) from build/vp9-vectors/src (gst-plugins-bad 1.28.6-1ubuntu1 +
# harness/vp9-vectors/patches/0001-0002), rootless (mmdebstrap unshare + qemu-user), same method as
# harness/gst-jpeg/build-dev.sh. Output: build/vp9-vectors/out/libgstv4l2codecs.so + meson/ninja logs.
set -euo pipefail
TOP=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$TOP/build/vp9-vectors
export TMPDIR=${OPIZ2_MEDIA_TMPDIR:-/var/tmp}
rm -rf "${W:?}/out"; mkdir -p "$W/out" "$W/bscripts"
cat > "$W/bscripts/build-in-chroot.sh" <<'EOS'
#!/bin/sh
set -e
cd /build/src
meson setup /build/b -Dauto_features=disabled -Dv4l2codecs=enabled -Dexamples=disabled -Dtests=disabled \
  -Dintrospection=disabled -Dwerror=false > /build/out/meson.log 2>&1 || { tail -30 /build/out/meson.log; exit 1; }
ninja -C /build/b -j8 sys/v4l2codecs/libgstv4l2codecs.so > /build/out/ninja.log 2>&1 || { grep -B2 -A8 "error" /build/out/ninja.log | head -80; exit 1; }
grep -A3 "warning:" /build/out/ninja.log > /build/out/warnings.txt || true
cp /build/b/sys/v4l2codecs/libgstv4l2codecs.so /build/out/
EOS
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
