#!/usr/bin/env bash
# Rootless validation build of the Armbian sunxi64 "edge" kernel for Orange Pi Zero2.
# Mirrors what Armbian's framework does (series.conf patches, dt/overlay dirs,
# uwe5622 WiFi driver injection, linux-sunxi64-edge.config) without needing root.
set -euo pipefail

KVER="${KVER:-7.3.1}"
ARMBIAN="${ARMBIAN:-/home/aruni/orangepizero2/armbian-build}"
WORK="${WORK:-/home/aruni/orangepizero2/kernel-check/work}"
PATCHROOT="$ARMBIAN/patch/kernel/archive/sunxi-7.3"
UWE_COMMIT="$(grep -oP "uwe5622ver='commit:\K[0-9a-f]+" "$ARMBIAN/lib/functions/compilation/patch/drivers_network.sh")"
JOBS="${JOBS:-$(nproc)}"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
# Always build through ccache (shared dir with Armbian) so rebuilds are incremental.
# CCACHE_DIR left at the default (~/.cache/ccache, shared with the other projects).
MAKE_CC=(); command -v ccache >/dev/null && MAKE_CC=(CC="ccache aarch64-linux-gnu-gcc" HOSTCC="ccache gcc")

mkdir -p "$WORK/dl"
cd "$WORK"

# 1. Fetch kernel
TARBALL="dl/linux-$KVER.tar.xz"
[[ -f $TARBALL ]] || curl -fL -o "$TARBALL" "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$KVER.tar.xz"
rm -rf "linux-$KVER"
tar -xf "$TARBALL"
cd "linux-$KVER"

# 2. Apply series.conf (active entries only: skip comments and '-'-prefixed disabled lines)
: > ../patch-failures.txt
applied=0; failed=0
while read -r p; do
	if patch -p1 -N -s --no-backup-if-mismatch -i "$PATCHROOT/$p" > ../patch-last.log 2>&1; then
		applied=$((applied + 1))
	else
		failed=$((failed + 1))
		{ echo "=== $p"; cat ../patch-last.log; } >> ../patch-failures.txt
	fi
done < <(sed -e 's/#.*//' "$PATCHROOT/series.conf" | awk 'NF && $1 !~ /^-/ {print $1}')
echo "patches applied: $applied, failed: $failed"

# 3. Copy bare DT and overlay dirs, add new dts to Makefile (Armbian auto-patch-dt-makefile)
DTDIR=arch/arm64/boot/dts/allwinner
cp -a "$PATCHROOT/dt_64/." "$DTDIR/" 2>/dev/null || true
mkdir -p "$DTDIR/overlay"
cp -a "$PATCHROOT/overlay_64/." "$DTDIR/overlay/" 2>/dev/null || true
for f in "$DTDIR"/*.dts; do
	b="$(basename "${f%.dts}").dtb"
	grep -q "$b" "$DTDIR/Makefile" || echo "dtb-\$(CONFIG_ARCH_SUNXI) += $b" >> "$DTDIR/Makefile"
done
if [[ -f $DTDIR/overlay/Makefile ]] && ! grep -q 'subdir-y.*overlay' "$DTDIR/Makefile"; then
	echo 'subdir-y += overlay' >> "$DTDIR/Makefile"
fi

# 4. uwe5622 WiFi driver (same steps as driver_uwe5622 in drivers_network.sh)
UWESRC="$WORK/dl/uwe5622"
[[ -d $UWESRC/.git ]] || git clone -q https://github.com/armbian/uwe5622 "$UWESRC"
git -C "$UWESRC" -c advice.detachedHead=false checkout -q "$UWE_COMMIT"
mkdir -p drivers/net/wireless/uwe5622
cp -R "$UWESRC"/{tty-sdio,unisocwcn,unisocwifi,Kconfig,Makefile} drivers/net/wireless/uwe5622/
echo 'obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/' >> drivers/net/wireless/Makefile
sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/uwe5622\/Kconfig"' drivers/net/wireless/Kconfig

# 5. Configure & build
cp "$ARMBIAN/config/kernel/linux-sunxi64-edge.config" .config
make "${MAKE_CC[@]}" olddefconfig > ../olddefconfig.log 2>&1
# dtbs needs mkimage (u-boot-tools) for overlay fixup .scr files; build only the Zero2 DTB here.
rc=0
make "${MAKE_CC[@]}" -j"$JOBS" Image modules allwinner/sun50i-h616-orangepi-zero2.dtb > ../build.log 2>&1 || rc=$?
grep -E ' error:|Error [0-9]' ../build.log || true
echo "build exit: $rc"
exit "$rc"
