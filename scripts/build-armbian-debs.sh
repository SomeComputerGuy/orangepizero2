#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the Armbian packages that armbian-config's desktop install (configng common.yaml, every DE) takes from
# apt.armbian.com, which this image does not use (SKIP_ARMBIAN_REPO=yes: no stonking suite there):
#   armbian-firstrun-gui                         graphical first-run wizard (Rust/Slint on DRM/KMS); it writes
#                                                the PRESET_* answers for armbian-firstlogin
#   network-manager-config-connectivity-armbian  NetworkManager connectivity check (captive portals)
# Both come from armbian/external (build/<package>/, Armbian's own packaging) at the commit below, built for arm64
# in a stonking chroot. Rootless: mmdebstrap --mode=unshare + qemu-user binfmt, no sudo.
# Usage: build-armbian-debs.sh [--force]
# Output: out/debs-armbian/*.deb; userpatches/config-opiz2-printserver.conf installs them before the desktop.
# A build stamp (commit + build recipe) skips an unchanged build. To update: change EXTERNAL_COMMIT.
set -euo pipefail

# --- build recipe begin
if [ "${1:-}" = --in-chroot ]; then
  jobs=$2
  export DEBIAN_FRONTEND=noninteractive CARGO_BUILD_JOBS=$jobs
  apt-get update -q
  cd /tmp/opiz2-external
  # armbian/external generates this package's changelog from VERSION; do the same (native, version = VERSION)
  d=network-manager-config-connectivity-armbian
  echo '3.0 (native)' > $d/debian/source/format
  printf '%s (%s) unstable; urgency=medium\n\n  * Built from armbian/external %s.\n\n -- Armbian <info@armbian.com>  %s\n' \
    $d "$(cat $d/VERSION)" "$(cat COMMIT)" "$(date -R)" > $d/debian/changelog
  for d in network-manager-config-connectivity-armbian armbian-firstrun-gui; do
    (cd $d && apt-get build-dep -q -y ./ && DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$jobs" dpkg-buildpackage -b -us -uc)
  done
  mkdir -p /build/debs && mv ./*.deb /build/debs/
  exit 0
fi
# --- build recipe end

[ "$(id -u)" -ne 0 ] || { echo "run as your normal user (rootless build)"; exit 1; }
EXTERNAL_REPO=https://github.com/armbian/external.git
EXTERNAL_COMMIT=92d366eb162b28552b4440816334dac52c2516db   # 2026-11-12: firstrun-gui 0.1.1, connectivity 1.1
PACKAGES=(armbian-firstrun-gui network-manager-config-connectivity-armbian)
SELF=$(readlink -f "$0")
TOP=$(cd "$(dirname "$SELF")/.." && pwd)
REPO=$TOP/out/debs-armbian
SRC=$TOP/build/armbian-external
SUITE=stonking
MIRROR=http://ports.ubuntu.com/ubuntu-ports
export TMPDIR=${OPIZ2_MEDIA_TMPDIR:-/var/tmp}   # disk, world-traversable for the unshared root
JOBS=${MEDIA_JOBS:-10}
FORCE=0
[ "${1:-}" = --force ] && FORCE=1

st=$({ echo "$EXTERNAL_COMMIT"; sed -n '/^# --- build recipe begin/,/^# --- build recipe end/p' "$SELF"; } | sha256sum | cut -c1-16)
have_all() { for p in "${PACKAGES[@]}"; do ls "$REPO/${p}"_*.deb > /dev/null 2>&1 || return 1; done; }
if [ "$FORCE" = 0 ] && [ "$(cat "$REPO/.stamp" 2>/dev/null)" = "$st" ] && have_all; then
  echo "==> armbian/external debs: up to date (stamp $st), not rebuilt"
  exit 0
fi

# apt cache as in build-media-debs.sh: apt-cacher-ng on 127.0.0.1:3142 if listening (OPIZ2_APT_PROXY overrides/none)
APT_PROXY=${OPIZ2_APT_PROXY:-}
if [ -z "$APT_PROXY" ] && (exec 3<>/dev/tcp/127.0.0.1/3142) 2>/dev/null; then APT_PROXY=http://127.0.0.1:3142; fi
APT_PROXY_OPTS=()
if [ -n "$APT_PROXY" ] && [ "$APT_PROXY" != none ]; then
  APT_PROXY_OPTS=(--aptopt="Acquire::http::Proxy \"$APT_PROXY\"" --aptopt='Acquire::https::Proxy "DIRECT"')
fi

# Source: only the two package directories of armbian/external, at the pinned commit
if [ ! -d "$SRC/.git" ]; then
  rm -rf "$SRC"
  git clone -q --filter=blob:none --no-checkout "$EXTERNAL_REPO" "$SRC"
fi
git -C "$SRC" sparse-checkout set "${PACKAGES[@]/#/build/}"
git -C "$SRC" cat-file -e "$EXTERNAL_COMMIT^{commit}" 2>/dev/null || git -C "$SRC" fetch -q origin
git -C "$SRC" -c advice.detachedHead=false checkout -q --force "$EXTERNAL_COMMIT"

STAGE=$(mktemp -d "$TMPDIR/opiz2-external.XXXXXX")
w=$(mktemp -d "$TMPDIR/opiz2-external-out.XXXXXX")
trap 'rm -rf "$STAGE" "$w"' EXIT
mkdir "$STAGE/opiz2-external"
for p in "${PACKAGES[@]}"; do cp -r "$SRC/build/$p" "$STAGE/opiz2-external/"; done
echo "$EXTERNAL_COMMIT" > "$STAGE/opiz2-external/COMMIT"
chmod -R a+rX "$STAGE"

echo "==> building ${PACKAGES[*]} from armbian/external ${EXTERNAL_COMMIT:0:12} (arm64, $SUITE)"
# --- build recipe begin (mmdebstrap)
mmdebstrap --mode=unshare --arch=arm64 --variant=buildd \
  --aptopt='APT::Install-Recommends "false"' \
  "${APT_PROXY_OPTS[@]}" \
  --include=ca-certificates,debhelper \
  --setup-hook='mkdir -p "$1/tmp"' \
  --customize-hook="copy-in '$STAGE/opiz2-external' /tmp" \
  --customize-hook="copy-in '$SELF' /tmp" \
  --customize-hook="chroot \"\$1\" /bin/bash /tmp/$(basename "$SELF") --in-chroot '$JOBS'" \
  --customize-hook="sync-out /build/debs '$w/debs'" \
  "$SUITE" /dev/null "deb $MIRROR $SUITE main universe"
# --- build recipe end (mmdebstrap)

mkdir -p "$REPO"
rm -f "$REPO"/*.deb
cp "$w"/debs/*.deb "$REPO/"
have_all || { echo "build finished without every package: $(ls "$REPO")"; exit 1; }
echo "$st" > "$REPO/.stamp"
ls -l "$REPO"
