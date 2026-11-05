#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the cumulative test kernel (harness/AGENT-RULES.md "Builds") and package it for install-kernel.sh.
#   harness/cumul-build.sh c2        -> kernel-check/vdec-serve/{Image.c2,modules-c2.tgz,sun50i-h616-orangepi-zero2.dtb.c2}
# One tree (kernel-check/work-cumul), updated incrementally; build-kernel.sh holds the one-build-at-a-time lock.
set -euo pipefail
tag=${1:?usage: cumul-build.sh <tag, e.g. c2>}
TOP=/home/aruni/orangepizero2; KC=$TOP/kernel-check; WT=$TOP/wt-cumulative; WORK=$KC/work-cumul; SV=$KC/vdec-serve
head=$(git -C "$WT" rev-parse --short=9 HEAD)
[[ -z $(git -C "$WT" status --porcelain) ]] || { echo "wt-cumulative has uncommitted changes"; exit 1; }
echo "== $tag = test-cumulative $head"
ARMBIAN=$WT WORK=$WORK STAGE=all bash "$KC/build-kernel.sh"
K=$WORK/linux-7.3.1; mkdir -p "$SV"; tmp=$(mktemp -d "$WORK/pkg.XXXX")
make -C "$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -s INSTALL_MOD_PATH="$tmp" INSTALL_MOD_STRIP=1 modules_install
tar czf "$SV/modules-$tag.tgz" -C "$tmp/lib/modules" 7.3.1; rm -rf "$tmp"
cp "$K/arch/arm64/boot/Image" "$SV/Image.$tag"
cp "$K/arch/arm64/boot/dts/allwinner/sun50i-h616-orangepi-zero2.dtb" "$SV/sun50i-h616-orangepi-zero2.dtb.$tag"
echo "$tag test-cumulative $head $(date '+%F %T') Image md5 $(md5sum < "$SV/Image.$tag" | cut -c1-32)" | tee -a "$KC/cumulative-kernels.txt"
