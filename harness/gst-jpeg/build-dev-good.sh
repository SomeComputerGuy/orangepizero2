#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Dev build of gst-plugins-good's video4linux2 plugin (arm64: v4l2jpegdec and the other stateful v4l2 elements)
# from build/gst-jpeg/good/src (1.28.7 + patches/gst-plugins-good1.0), rootless (mmdebstrap unshare + qemu-user),
# same method as build-dev.sh. Output: build/gst-jpeg/good/out/libgstvideo4linux2.so + meson/ninja logs.
set -euo pipefail
TOP=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
W=$TOP/build/gst-jpeg/good
export TMPDIR=${OPIZ2_MEDIA_TMPDIR:-/var/tmp}
rm -rf "${W:?}/out"; mkdir -p "$W/out" "$W/bscripts"
cat > "$W/bscripts/build-in-chroot.sh" <<'EOS'
#!/bin/sh
set -e
cd /build/src
meson setup /build/b -Dauto_features=disabled -Dv4l2=enabled -Dv4l2-gudev=enabled -Dexamples=disabled -Dtests=disabled \
  -Dnls=disabled -Dwerror=false > /build/out/meson.log 2>&1 || { tail -30 /build/out/meson.log; exit 1; }
ninja -C /build/b -j8 sys/v4l2/libgstvideo4linux2.so > /build/out/ninja.log 2>&1 || { grep -B2 -A8 "error" /build/out/ninja.log | head -80; exit 1; }
grep -A3 "warning:" /build/out/ninja.log > /build/out/warnings.txt || true
cp /build/b/sys/v4l2/libgstvideo4linux2.so /build/out/
EOS
PROXY=()
if (exec 3<>/dev/tcp/127.0.0.1/3142) 2>/dev/null; then
  PROXY=(--aptopt='Acquire::http::Proxy "http://127.0.0.1:3142"')
fi
mmdebstrap --mode=unshare --variant=buildd --arch=arm64 "${PROXY[@]}" \
  --include=meson,ninja-build,pkgconf,libgstreamer1.0-dev,libgstreamer-plugins-base1.0-dev,libgudev-1.0-dev,libudev-dev,python3 \
  --customize-hook='mkdir -p "$1/build/src" "$1/build/out" "$1/build/scripts"' \
  --customize-hook="sync-in $W/src /build/src" \
  --customize-hook="sync-in $W/bscripts /build/scripts" \
  --customize-hook='chroot "$1" sh -c "dpkg-query -W libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev > /build/out/versions.txt"' \
  --customize-hook='chroot "$1" sh /build/scripts/build-in-chroot.sh' \
  --customize-hook="sync-out /build/out $W/out" \
  stonking /dev/null 'deb http://ports.ubuntu.com/ubuntu-ports stonking main universe' > "$W/mmdebstrap.log" 2>&1 \
  || { tail -40 "$W/mmdebstrap.log"; exit 1; }
ls -la "$W/out"
