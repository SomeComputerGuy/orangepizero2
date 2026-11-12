#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build every image variant back to back (minimal, server, desktop) with the same arguments.
# Usage: ./build-all.sh OPIZ2_WIFI_REGDOM=US
# Stops at the first failing variant. Kernel/U-Boot/BSP artifacts are cached, so the second build reuses them.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# Ask for the sudo password once, then keep the credential fresh until this build ends:
# compile.sh relaunches itself under sudo for every variant, and sudo forgets the password after 15 minutes.
if [[ -z ${OPIZ2_SUDO_KEEPALIVE:-} ]]; then
	sudo -v
	export OPIZ2_SUDO_KEEPALIVE=$$
	( while kill -0 "$OPIZ2_SUDO_KEEPALIVE" 2>/dev/null && sudo -n -v; do sleep 60; done ) >/dev/null 2>&1 &
fi
for v in minimal server desktop; do
	echo "=== building OPIZ2_VARIANT=$v ==="
	"$here/build.sh" OPIZ2_VARIANT="$v" "$@"
done
echo "=== all variants built: $(ls -1t "$here"/armbian-build/output/images/*.img.xz 2>/dev/null | head -3 | tr '\n' ' ')"
