#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Rebuild Ubuntu's media and GPU packages for arm64 (Orange Pi Zero2 images) with the patches in patches/<source>/:
#   ffmpeg              V4L2 Request API (stateless decoder) hwaccels: Jernej Skrabec's v4l2request-mpeg4 series
#                       (Kwiboo's hwaccels + VC-1 + MPEG-4) 00xx, shared 01xx, ours 02xx
#                       (desktop variant only)
#   mpv                 v4l2request hwdec + DRM PRIME interop; needs our ffmpeg (desktop variant only)
#   gst-plugins-bad1.0  v4l2codecs/kmssink fixes 00xx (patches/gstreamer) and ours 01xx:
#                       v4l2sljpegdec (cedrus JPEG) and jpegparse sampling-factors caps; 02xx: MPEG-1 D-pictures,
#                       AVS1/AVS+, AVS2, MPEG-4 Part 2, H.263 and Sorenson Spark decoders, their video packet
#                       and GOB positions for cedrus; stateless encoders on single-planar drivers (every variant)
#   gst-plugins-good1.0 shared 00xx: v4l2transform input colorimetry, souphttpsrc HEAD probe race, no colorimetry
#                       probe for compressed OUTPUT formats, v4l2videoenc/v4l2bufferpool error buffers; ours 01xx:
#                       stateful v4l2jpegdec on cedrus: 1:4:0:0 colorimetry, system memory for an ANY peer,
#                       decode errors reported; jpegdec greyscale with sampling factors above 1; souphttpsrc
#                       wakes every waiter; v4l2object leaves caps it can't change alone
#                       (every variant)
#   mesa                our Mesa fork for the Mali-G31 (panfrost/panvk/rusticl fixes, patches/mesa/README.md;
#                       every variant)
#   plymouth            upstream 0001: no spin on an incomplete CSI input sequence; 0002 (upstream MR !523):
#                       plymouthd never blocks reading the terminal (boot hang when PID 1 reads or flushes the
#                       console VT's input; server and desktop variants)
# A build stamp makes sure an unchanged source is not rebuilt.
# Rootless: mmdebstrap --mode=unshare + qemu-user binfmt, no sudo.
# Usage: build-media-debs.sh [--force] [source...]     (default: every source below, in the SOURCES order)
# Output: out/debs-media/*.deb plus a Packages index (a flat apt repository that
#         userpatches/config-opiz2-printserver.conf installs from: every variant takes gst + mesa, the desktop
#         also ffmpeg + mpv). build.sh runs this script before every image build.
#
# patches/<dir>/*.patch are appended to debian/patches/series (upstream code,
# applied by dpkg-source); patches/<dir>/debian/*.patch change the packaging
# itself. <dir> is the source package name, except gstreamer for gst-plugins-bad1.0. The version gets "+opiz2.<rev>", so it sorts above the archive
# version it was built from, and the image pins *+opiz2* versions (etc/apt/preferences.d).
# When Ubuntu updates one of these packages, bump its version below and rebuild.
set -euo pipefail

# --- build recipe begin (this block and the mmdebstrap call below are part of every source's build stamp)
if [ "${1:-}" = --in-chroot ]; then
  # Runs inside the build chroot (as the unshared root user): fetch, patch, build.
  src=$2 ver=$3 rev=$4 jobs=$5 pdir_name=${6:-$2} build=${7:-any} debfrom=${8:-}
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /build/debs && cd /build
  apt-get update -q
  if [ -n "$debfrom" ]; then
    # A newer upstream release than the archive's: debian/ comes from the archive source package $debfrom,
    # the source from the tarballs listed in /tmp/opiz2-upstream/MANIFEST ("file directory" per line)
    apt-get source -q --only-source "$src=$debfrom"
    old=$(find . -maxdepth 1 -mindepth 1 -type d -name "${src}-*" | head -1)
    dir=./$src-${ver%%-*}
    mkdir "$dir"
    while read -r tb sub; do
      mkdir -p "$dir/$sub"
      tar -C "$dir/$sub" --strip-components=1 -xf "/tmp/opiz2-upstream/$tb"
    done < /tmp/opiz2-upstream/MANIFEST
    mv "$old/debian" "$dir/"
    rm -rf "$old"
  else
    apt-get source -q --only-source "$src=$ver"
    dir=$(find . -maxdepth 1 -mindepth 1 -type d -name "${src}-*" | head -1)
  fi
  cd "$dir"
  mkdir -p debian/patches; touch debian/patches/series
  for p in /tmp/opiz2-patches/*.patch; do
    [ -e "$p" ] || continue
    cp "$p" "debian/patches/opiz2-$(basename "$p")"
    echo "opiz2-$(basename "$p")" >> debian/patches/series
  done
  for p in /tmp/opiz2-patches/debian/*.patch; do
    [ -e "$p" ] || continue
    patch -p1 --no-backup-if-mismatch < "$p"
  done
  {
    echo "$src ($ver+opiz2.$rev) $(dpkg-parsechangelog -S Distribution); urgency=medium"
    echo
    echo "  * Orange Pi Zero2 (H616) rebuild with the orangepizero2 build's patches/$pdir_name:"
    for p in /tmp/opiz2-patches/*.patch /tmp/opiz2-patches/debian/*.patch; do
      [ -e "$p" ] || continue
      echo "    - $(sed -n 's/^Subject: \(\[PATCH[^]]*\] \)\{0,1\}//p' "$p" | head -1)"
    done
    echo
    echo " -- Arun Iyengar <aiyengar1990@gmail.com>  $(date -R)"
    echo
    cat debian/changelog
  } > debian/changelog.new
  mv debian/changelog.new debian/changelog
  # any: the arm64 packages (-B); all: an Architecture: all source (-A)
  if [ "$build" = all ]; then bd=--indep-only bt=-A; else bd=--arch-only bt=-B; fi
  apt-get build-dep -q -y $bd -Pnocheck ./
  # ccache (installed and seeded by the host side, see below): compilers of this
  # name in /usr/lib/ccache come first in PATH. Sources are always unpacked at
  # /build, so hits carry over between runs. Cache size is capped to keep the
  # copy in/out cheap.
  if [ -d /usr/lib/ccache ] && [ -d /build/opiz2-media-ccache ]; then
    export PATH=/usr/lib/ccache:$PATH CCACHE_DIR=/build/opiz2-media-ccache CCACHE_BASEDIR=/build CCACHE_MAXSIZE=3G
  fi
  DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$jobs" \
    dpkg-buildpackage $bt -us -uc -Pnocheck
  mv ../*.deb /build/debs/
  exit 0
fi
# --- build recipe end

[ "$(id -u)" -ne 0 ] || { echo "run as your normal user (rootless build)"; exit 1; }
SELF=$(readlink -f "$0")
TOP=$(cd "$(dirname "$SELF")/.." && pwd)
REPO=$TOP/out/debs-media
WORK=$TOP/build/media
SUITE=stonking
MIRROR=http://ports.ubuntu.com/ubuntu-ports
COMPONENTS="main restricted universe multiverse"
# mmdebstrap's chroot lives in $TMPDIR: the full ffmpeg build needs ~20 GB there. /tmp is a shared tmpfs on
# this host, so default to /var/tmp (disk, world-traversable for the unshared root).
export TMPDIR=${OPIZ2_MEDIA_TMPDIR:-/var/tmp}
JOBS=${MEDIA_JOBS:-10}         # the host is shared; qemu-user runs one CPU per job
# Archive version each patch set was made for, and our revision of it
declare -A VERSION=(
  [ffmpeg]=7:8.1.2-2ubuntu2
  [mpv]=0.41.0-2ubuntu5
  [gst-plugins-bad1.0]=1.28.6-1ubuntu1
  [gst-plugins-good1.0]=1.28.7-1ubuntu0.1
  [mesa]=26.3.0-0ubuntu1
  [plymouth]=24.004.60+git20250831.4a3c171d-0ubuntu10
)
declare -A REV=([ffmpeg]=15 [mpv]=1 [gst-plugins-bad1.0]=5 [gst-plugins-good1.0]=7 [mesa]=2 [plymouth]=1)
# Sources built from a newer upstream release than the archive has: the archive source package whose debian/
# directory is used (patches/<dir>/debian/*.patch adapt it), and the upstream tarballs unpacked in place of its
# source ("file sha256 directory url" per tarball; directory relative to the source tree)
declare -A DEBIAN_FROM=([mesa]=26.2.4-1ubuntu1)
declare -A UPSTREAM=([mesa]="mesa-26.3.0.tar.xz 91d729aa68bb89e4ec857841300bbe922bcb3e52b1f97566ca83930d3b28343a . https://archive.mesa3d.org/mesa-26.3.0.tar.xz
venus-protocol-v1.1.3.tar.gz c5a362ca28e0a35042db1baeadaf9183500b216841e49d72714b80bae50b4445 subprojects/venus-protocol-1.1.3 https://gitlab.freedesktop.org/virgl/venus-protocol/-/archive/v1.1.3/venus-protocol-v1.1.3.tar.gz")
DL=$TOP/build/media-dl         # download cache of the upstream tarballs
declare -A PDIR=([ffmpeg]=ffmpeg [mpv]=mpv [gst-plugins-bad1.0]=gstreamer [gst-plugins-good1.0]=gst-plugins-good1.0 [mesa]=mesa [plymouth]=plymouth)
# Architecture: all sources (built with -A); the rest build their arm64 packages
declare -A BUILD=()
# Extra archive pockets a source needs (its VERSION is only there, e.g. a security update); they are added to that
# source's build chroot only and are part of its build stamp, so sources without them keep their stamps
declare -A POCKETS=([gst-plugins-good1.0]="$SUITE-updates $SUITE-security")

FORCE=0
if [ "${1:-}" = --force ]; then FORCE=1; shift; fi
if [ $# -gt 0 ]; then
  SOURCES=("$@")
else
  SOURCES=(ffmpeg mpv gst-plugins-bad1.0 gst-plugins-good1.0 mesa plymouth)
fi

# apt cache: apt-cacher-ng on 127.0.0.1:3142 is used if it is listening
# (OPIZ2_APT_PROXY=http://host:port overrides, OPIZ2_APT_PROXY=none disables). Only
# http is proxied; https sources go direct. The option lands in the build chroot's
# /etc/apt/apt.conf.d/99mmdebstrap (the chroot is thrown away).
APT_PROXY=${OPIZ2_APT_PROXY:-}
if [ -z "$APT_PROXY" ] && (exec 3<>/dev/tcp/127.0.0.1/3142) 2>/dev/null; then
  APT_PROXY=http://127.0.0.1:3142
fi
APT_PROXY_OPTS=()
if [ -n "$APT_PROXY" ] && [ "$APT_PROXY" != none ]; then
  APT_PROXY_OPTS=(--aptopt="Acquire::http::Proxy \"$APT_PROXY\"" --aptopt='Acquire::https::Proxy "DIRECT"')
  echo "apt cache: using $APT_PROXY"
else
  echo "apt cache: not used (nothing on 127.0.0.1:3142, or OPIZ2_APT_PROXY=none)"
fi

# ccache for the compiles inside the chroot (OPIZ2_MEDIA_CCACHE=0 disables). The
# cache lives on the host in $CCACHE_HOST and is copied into each build chroot and
# synced back out afterwards (bind mounts aren't permitted in the user namespace).
# The synced-out copy replaces the host cache, so evicted entries don't pile up; a
# failed build doesn't sync its cache back. Only the cache is exchanged: nothing
# of it ends up in the debs.
CCACHE_HOST=$HOME/.cache/opiz2-media-ccache   # basename must stay opiz2-media-ccache
CCACHE_OPTS=() CCACHE_SYNC=()
if [ "${OPIZ2_MEDIA_CCACHE:-1}" != 0 ]; then
  rm -rf "${CCACHE_HOST:?}.new"
  mkdir -p "$CCACHE_HOST"
  CCACHE_OPTS=(--include=ccache
    --customize-hook='mkdir -p "$1/build"'
    --customize-hook="copy-in '$CCACHE_HOST' /build")
  CCACHE_SYNC=(--customize-hook="sync-out /build/opiz2-media-ccache '$CCACHE_HOST.new'")
  echo "ccache: build chroot uses $CCACHE_HOST"
else
  echo "ccache: not used (OPI5_MEDIA_CCACHE=0)"
fi
mkdir -p "$REPO" "$WORK"
# Build stamp: version, revision, every patch file and this script's build recipe (the marked blocks: the in-chroot
# build and the mmdebstrap call). An unchanged source is not rebuilt; comments and the source list elsewhere in
# this script do not count.
stamp_of() {
  { echo "${VERSION[$1]} ${REV[$1]}${DEBIAN_FROM[$1]:+ ${DEBIAN_FROM[$1]} ${UPSTREAM[$1]}}${POCKETS[$1]:+ pockets ${POCKETS[$1]}}"; sed -n '/^ *# --- build recipe begin/,/^ *# --- build recipe end/p' "$SELF" | sha256sum;
    (cd "$TOP/patches/${PDIR[$1]}" && find . -type f -print0 | sort -z | xargs -0 sha256sum); } | sha256sum | cut -c1-16
}
index_repo() {
  (cd "$REPO" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null)
}
index_repo
# apt runs as the unshared root (a subordinate uid), which can't read $HOME, so
# the local repository is served from a world-readable copy
STAGE=$(mktemp -d /tmp/opiz2-media-repo.XXXXXX)   # small; the chroot sees it at the same path
UPSTAGE=$(mktemp -d "${TMPDIR:-/var/tmp}/opiz2-upstream.XXXXXX")   # upstream tarballs (~100 MB for mesa), not on the tmpfs
trap 'rm -rf "$STAGE" "$UPSTAGE"' EXIT
chmod 755 "$STAGE"

for src in "${SOURCES[@]}"; do
  [ -n "${VERSION[$src]:-}" ] || { echo "unknown source package $src"; exit 1; }
  pdir=$TOP/patches/${PDIR[$src]}
  [ -d "$pdir" ] || { echo "missing $pdir"; exit 1; }
  ver=${VERSION[$src]} rev=${REV[$src]}
  st=$(stamp_of "$src")
  if [ "$FORCE" = 0 ] && [ "$(cat "$REPO/.stamp-$src" 2>/dev/null)" = "$st" ] &&
     ls "$REPO"/*_"${ver#*:}+opiz2.${rev}"_*.deb > /dev/null 2>&1; then
    echo "==> $src $ver+opiz2.$rev: up to date (stamp $st), not rebuilt"
    continue
  fi
  # A fresh work directory per run: an interrupted run's mmdebstrap may still finish
  # and sync its debs out later
  w=$(mktemp -d "$WORK/$src.XXXXXX")
  echo "==> $src $ver+opiz2.$rev (log: $w/build.log)"
  rm -f "$STAGE"/*
  cp "$REPO"/Packages "$STAGE"/
  for d in "$REPO"/*.deb; do if [ -e "$d" ]; then cp "$d" "$STAGE"/; fi; done
  chmod -R a+rX "$STAGE"
  # Upstream tarballs (sha256-checked, cached in $DL), copied into the chroot as /tmp/opiz2-upstream
  rm -rf "$UPSTAGE"; mkdir -p "$UPSTAGE" "$DL"
  if [ -n "${UPSTREAM[$src]:-}" ]; then
    while read -r tb sum sub url; do
      [ -n "$tb" ] || continue
      if ! echo "$sum  $DL/$tb" | sha256sum -c --quiet 2>/dev/null; then
        curl -fsSL -o "$DL/$tb.part" "$url" && mv "$DL/$tb.part" "$DL/$tb"
        echo "$sum  $DL/$tb" | sha256sum -c --quiet || { echo "$tb: sha256 mismatch"; exit 1; }
      fi
      cp "$DL/$tb" "$UPSTAGE/"
      echo "$tb $sub" >> "$UPSTAGE/MANIFEST"
    done <<< "${UPSTREAM[$src]}"
  fi
  chmod -R a+rX "$UPSTAGE"
  EXTRA_APT=()
  for pk in ${POCKETS[$src]:-}; do EXTRA_APT+=("deb $MIRROR $pk $COMPONENTS" "deb-src $MIRROR $pk $COMPONENTS"); done
  # --- build recipe begin
  # The local repository is a file:// mirror, so mpv's build-deps resolve to our
  # libav*-dev rather than Ubuntu's. The outer apt reads it at $STAGE on the host,
  # apt inside the chroot at the same path in the chroot (copy-in; bind mounts
  # aren't permitted in the user namespace).
  mmdebstrap --mode=unshare --arch=arm64 --variant=buildd \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    --aptopt='APT::Install-Recommends "false"' \
    --dpkgopt=force-unsafe-io \
    "${APT_PROXY_OPTS[@]}" \
    --include=ca-certificates \
    --setup-hook="mkdir -p \"\$1/tmp\"" \
    --setup-hook="copy-in '$STAGE' /tmp" \
    --customize-hook="copy-in '$pdir' /tmp" \
    --customize-hook="mv \"\$1/tmp/${PDIR[$src]}\" \"\$1/tmp/opiz2-patches\"" \
    --customize-hook="copy-in '$SELF' /tmp" \
    --customize-hook="copy-in '$UPSTAGE' /tmp" \
    --customize-hook="mv \"\$1/tmp/$(basename "$UPSTAGE")\" \"\$1/tmp/opiz2-upstream\"" \
    "${CCACHE_OPTS[@]}" \
    --customize-hook="chroot \"\$1\" /bin/bash /tmp/$(basename "$SELF") --in-chroot '$src' '$ver' '$rev' '$JOBS' '${PDIR[$src]}' '${BUILD[$src]:-any}' '${DEBIAN_FROM[$src]:-}'" \
    --customize-hook="sync-out /build/debs '$w/debs'" \
    "${CCACHE_SYNC[@]}" \
    "$SUITE" /dev/null \
    "deb $MIRROR $SUITE $COMPONENTS" \
    "deb-src $MIRROR $SUITE $COMPONENTS" \
    "${EXTRA_APT[@]}" \
    "deb [trusted=yes] file://$STAGE ./" \
    > "$w/build.log" 2>&1 || { echo "$src failed; see $w/build.log"; tail -20 "$w/build.log"; exit 1; }
  # --- build recipe end
  if [ -d "$CCACHE_HOST.new" ]; then rm -rf "$CCACHE_HOST"; mv "$CCACHE_HOST.new" "$CCACHE_HOST"; fi
  # Replace the previous build of this source in the repository
  for d in "$REPO"/*.deb; do
    [ -e "$d" ] || continue
    s=$(dpkg-deb -f "$d" Source); s=${s%% *}
    [ -n "$s" ] || s=$(dpkg-deb -f "$d" Package)
    if [ "$s" = "$src" ]; then rm -f "$d"; fi
  done
  mv "$w"/debs/*.deb "$REPO/"
  rm -rf "$w"
  chmod 644 "$REPO"/*.deb
  index_repo
  echo "$st" > "$REPO/.stamp-$src"
  ls -1 "$REPO" | grep -c '\.deb$' | xargs echo "    repository now has debs:"
done
echo "Done: $REPO"
