#!/usr/bin/env bash
# Fast sunxi-7.3 series.conf apply check for an armbian-build git rev (mirrors kernel-check/build-kernel.sh
# STAGE=patch: uwe5622 injected first, then active series.conf entries with patch -p1 -N).
# Usage: kseries-check.sh <rev> [label]   -> prints "applied N failed M" + failing patch names
set -uo pipefail
REV=$1; LABEL=${2:-$1}
A=/home/aruni/orangepizero2/armbian-build
K=/home/aruni/orangepizero2/kernel-check/prprep/ktree/linux-7.3.1
UWE=/home/aruni/orangepizero2/kernel-check/work/dl/uwe5622
T=$(mktemp -d /tmp/kscheck.XXXX)
git -C "$A" archive "$REV" patch/kernel/archive/sunxi-7.3 lib/functions/compilation/patch/drivers_network.sh | tar -x -C "$T"
P=$T/patch/kernel/archive/sunxi-7.3
uwe=$(grep -oP "uwe5622ver='commit:\K[0-9a-f]+" "$T/lib/functions/compilation/patch/drivers_network.sh")
cd "$K" && git reset -q --hard && git clean -fdxq
git -C "$UWE" cat-file -e "$uwe^{commit}" 2>/dev/null || git -C "$UWE" fetch -q origin
mkdir -p drivers/net/wireless/uwe5622
git -C "$UWE" archive "$uwe" tty-sdio unisocwcn unisocwifi Kconfig Makefile | tar -x -C drivers/net/wireless/uwe5622
echo 'obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/' >> drivers/net/wireless/Makefile
sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/uwe5622\/Kconfig"' drivers/net/wireless/Kconfig
applied=0; failed=0; fails=""
while read -r p; do
	if patch -p1 -N -s --no-backup-if-mismatch -i "$P/$p" > /dev/null 2>&1; then applied=$((applied+1)); else failed=$((failed+1)); fails="$fails $p"; fi
done < <(sed -e 's/#.*//' "$P/series.conf" | awk 'NF && $1 !~ /^-/ {print $1}')
echo "$LABEL: uwe=${uwe:0:12} applied $applied failed $failed${fails:+ ->$fails}"
rm -rf "$T"
