#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build every image variant back to back (minimal, then server) with the same arguments.
# Usage: ./build-all.sh OPIZ2_WIFI_REGDOM=US
# Stops at the first failing variant. Kernel/U-Boot/BSP artifacts are cached, so the second build reuses them.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
for v in minimal server; do
	echo "=== building OPIZ2_VARIANT=$v ==="
	"$here/build.sh" OPIZ2_VARIANT="$v" "$@"
done
echo "=== all variants built: $(ls -1t "$here"/armbian-build/output/images/*.img.xz 2>/dev/null | head -2 | tr '\n' ' ')"
