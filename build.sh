#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the Orange Pi Zero2 print-server image. Run as your normal user (compile.sh sudo's itself).
# Ensures armbian-build/userpatches points at this repo's userpatches (git operations in the
# Armbian tree can drop the untracked symlink), then runs the cached build.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
ab="$here/armbian-build"
[[ -L $ab/userpatches ]] || { [[ -e $ab/userpatches ]] && { echo "$ab/userpatches exists and is not a symlink" >&2; exit 1; }; ln -s ../userpatches "$ab/userpatches"; }
echo "armbian-build: $(git -C "$ab" rev-parse --abbrev-ref HEAD) $(git -C "$ab" log -1 --format=%h)"
# Desktop variant: our FFmpeg/mpv rebuilds (out/debs-media) first, as this user (rootless; skips unchanged sources).
for a in "$@"; do
	if [[ $a == OPIZ2_VARIANT=desktop ]]; then "$here/scripts/build-media-debs.sh"; fi
done
cd "$ab" && exec ./compile.sh opiz2-printserver "$@"
