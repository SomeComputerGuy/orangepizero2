#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the netboot flasher (kernel Image + Zero2 DTB + BusyBox initramfs) into $OUT.
# No root needed. Inputs:
#   KERNEL_DEB  linux-image-edge-sunxi64 deb (default: newest in armbian-build/output/debs)
#   DTB_DEB     linux-dtb-edge-sunxi64 deb (default: the one with the same version suffix, else newest)
#   BUSYBOX_DEB busybox-static arm64 deb (default: fetched from ports.ubuntu.com stonking with a
#               private apt config, checked against the signed index by apt)
#   OUT         output dir (default kernel-check/work-flasher/out)
# Output: $OUT/{Image,sun50i-h616-orangepi-zero2.dtb,initrd.img,PROVENANCE}
set -euo pipefail
HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOP="$(dirname "$HARNESS")"
DEBS="$TOP/armbian-build/output/debs"
WORK="${WORK:-$TOP/kernel-check/work-flasher}"
OUT="${OUT:-$WORK/out}"
DTB_NAME=sun50i-h616-orangepi-zero2.dtb
MODULES="dwmac-sun8i" # everything else the flasher needs is built in (MMC_SUNXI, STMMAC_PLATFORM, REALTEK_PHY)

KERNEL_DEB="${KERNEL_DEB:-$(ls -t "$DEBS"/linux-image-edge-sunxi64_*.deb | head -1)}"
if [[ -z ${DTB_DEB:-} ]]; then
	sfx="${KERNEL_DEB##*/linux-image-edge-sunxi64_}"
	DTB_DEB="$DEBS/linux-dtb-edge-sunxi64_$sfx"
	[[ -f $DTB_DEB ]] || DTB_DEB="$(ls -t "$DEBS"/linux-dtb-edge-sunxi64_*.deb | head -1)"
fi

mkdir -p "$WORK" "$OUT"
if [[ -z ${BUSYBOX_DEB:-} ]]; then
	A="$WORK/apt"
	mkdir -p "$A/lists/partial" "$A/cache/archives/partial" "$A/etc/sources.list.d" "$A/etc/preferences.d" "$WORK/dl"
	echo "deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports stonking universe" > "$A/etc/sources.list"
	APT=(-o APT::Architecture=arm64 -o APT::Architectures=arm64 -o Dir::Etc="$A/etc" -o Dir::State::Lists="$A/lists"
		-o Dir::Cache="$A/cache" -o Dir::State::status=/dev/null -o Debug::NoLocking=1)
	if ! ls "$WORK"/dl/busybox-static_*_arm64.deb > /dev/null 2>&1; then
		apt-get "${APT[@]}" update > /dev/null
		(cd "$WORK/dl" && apt-get "${APT[@]}" download busybox-static > /dev/null)
	fi
	BUSYBOX_DEB="$(ls -t "$WORK"/dl/busybox-static_*_arm64.deb | head -1)"
fi

rm -rf "$WORK/x" && mkdir -p "$WORK/x/k" "$WORK/x/d" "$WORK/x/b"
dpkg-deb -x "$KERNEL_DEB" "$WORK/x/k"
dpkg-deb -x "$DTB_DEB" "$WORK/x/d"
dpkg-deb -x "$BUSYBOX_DEB" "$WORK/x/b"
kver="$(ls "$WORK/x/k/lib/modules")"
install -m 0644 "$WORK/x/k/boot/vmlinuz-$kver" "$OUT/Image"
install -m 0644 "$(find "$WORK/x/d" -name "$DTB_NAME" | head -1)" "$OUT/$DTB_NAME"
file -b "$OUT/Image" | grep -q 'ARM64 boot executable Image' || { echo "vmlinuz is not a raw arm64 Image"; exit 1; }

R="$WORK/x/root"
mkdir -p "$R"/{bin,dev,etc,lib/modules,proc,sys,tmp}
install -m 0755 "$WORK/x/b/usr/bin/busybox-static" "$R/bin/busybox"
ln -s busybox "$R/bin/sh"
install -m 0755 "$HARNESS/flasher/init" "$R/init"
install -m 0755 "$HARNESS/flasher/udhcpc.script" "$R/etc/udhcpc.script"
n=0
for m in $MODULES; do
	f="$(find "$WORK/x/k/lib/modules/$kver" -name "$m.ko*" | head -1)"
	[[ -n $f ]] || { echo "module $m not in $KERNEL_DEB"; exit 1; }
	deps="$(grep "/$m.ko[^:]*:" "$WORK/x/k/lib/modules/$kver/modules.dep" | cut -d: -f2)"
	[[ -z ${deps// /} ]] || { echo "module $m has deps ($deps): extend build-flasher.sh"; exit 1; }
	case $f in *.ko) cp "$f" "$R/lib/modules/$(printf %02d $n)-$m.ko" ;; *) echo "compressed module $f: busybox insmod needs plain .ko"; exit 1 ;; esac
	n=$((n + 1))
done
# initramfs: newc cpio, gzip (CONFIG_RD_GZIP=y); device nodes come from devtmpfs
(cd "$R" && find . | LC_ALL=C sort | cpio -o -H newc -R 0:0 --quiet | gzip -9n) > "$OUT/initrd.img"

{
	echo "built $(date -u +%FT%TZ) by harness/flasher/build-flasher.sh"
	echo "kernel $kver from $(basename "$KERNEL_DEB")"
	echo "dtb from $(basename "$DTB_DEB")"
	echo "busybox $(basename "$BUSYBOX_DEB") sha256 $(sha256sum "$BUSYBOX_DEB" | cut -d' ' -f1)"
	echo "busybox binary sha256 $(sha256sum "$R/bin/busybox" | cut -d' ' -f1)"
	(cd "$OUT" && sha256sum Image "$DTB_NAME" initrd.img)
} > "$OUT/PROVENANCE"
cat "$OUT/PROVENANCE"
ls -l "$OUT"
