#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the Orange Pi Zero2 print-server image. Run as your normal user (compile.sh sudo's itself).
# Ensures armbian-build/userpatches points at this repo's userpatches (git operations in the
# Armbian tree can drop the untracked symlink), then runs the cached build.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
ab="$here/armbian-build"
# Ask for the sudo password once, then keep the credential fresh until this build ends:
# compile.sh relaunches itself under sudo for every variant, and sudo forgets the password after 15 minutes.
if [[ -z ${OPIZ2_SUDO_KEEPALIVE:-} ]]; then
	sudo -v
	export OPIZ2_SUDO_KEEPALIVE=$$
	( while kill -0 "$OPIZ2_SUDO_KEEPALIVE" 2>/dev/null && sudo -n -v; do sleep 60; done ) >/dev/null 2>&1 &
fi
[[ -L $ab/userpatches ]] || { [[ -e $ab/userpatches ]] && { echo "$ab/userpatches exists and is not a symlink" >&2; exit 1; }; ln -s ../userpatches "$ab/userpatches"; }
echo "armbian-build: $(git -C "$ab" rev-parse --abbrev-ref HEAD) $(git -C "$ab" log -1 --format=%h)"
# Our package rebuilds (out/debs-media) first, as this user, for every variant (rootless; a source whose version,
# patches and build recipe are unchanged is skipped, so after the first variant this only checks the stamps):
# gst-plugins-bad/-good and Mesa go into every variant, FFmpeg/mpv into the desktop variant.
"$here/scripts/build-media-debs.sh"
# The desktop also needs two Armbian packages from armbian/external (rootless, stamped like the above).
[[ " $* " == *" OPIZ2_VARIANT=desktop "* || ${OPIZ2_VARIANT:-} == desktop ]] && "$here/scripts/build-armbian-debs.sh"
cd "$ab" && exec ./compile.sh opiz2-printserver "$@"
