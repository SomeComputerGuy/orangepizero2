#!/usr/bin/env bash
# Rootless validation build of the Armbian sunxi64 "edge" kernel for Orange Pi Zero2.
# Mirrors what Armbian's framework does (series.conf patches, dt/overlay dirs,
# uwe5622 WiFi driver injection, linux-sunxi64-edge.config) without needing root.
set -euo pipefail

# STAGE=patch  : extract + apply series.conf + copy dt/overlay dirs, then stop (fast patch check)
# STAGE=dtbs   : ... + olddefconfig + all allwinner DTBs/overlays (DT-only changes)
# STAGE=all    : ... + Image + modules + Zero2 DTB + all DTBs/overlays (default)
# DT_CHECK="pat1 pat2": after the build, grep these patterns in the decompiled Zero2 DTB
STAGE="${STAGE:-all}"
KVER="${KVER:-7.3.1}"
ARMBIAN="${ARMBIAN:-/home/aruni/orangepizero2/armbian-build}"
WORK="${WORK:-/home/aruni/orangepizero2/kernel-check/work}"
PATCHROOT="$ARMBIAN/patch/kernel/archive/sunxi-7.3"
UWE_COMMIT="$(grep -oP "uwe5622ver='commit:\K[0-9a-f]+" "$ARMBIAN/lib/functions/compilation/patch/drivers_network.sh")"
JOBS="${JOBS:-$(nproc)}"
# One kernel build at a time (as in the OPi5 project): parallel builds halve each other's speed and two builds
# in one WORK tree corrupt each other. Test kernels are cumulative (harness/AGENT-RULES.md "Builds"): build the
# newest test-cumulative in WORK=kernel-check/work-cumul, not a private tree from an older base.
mkdir -p /home/aruni/orangepizero2/kernel-check/.locks
exec 9>/home/aruni/orangepizero2/kernel-check/.locks/kernel-build.lock
flock -n 9 || { echo "waiting for the kernel build lock (another build is running) ..."; flock 9; }
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
# Always build through ccache (shared dir with Armbian) so rebuilds are incremental.
# CCACHE_DIR left at the default (~/.cache/ccache, shared with the other projects).
MAKE_CC=(); command -v ccache >/dev/null && MAKE_CC=(CC="ccache aarch64-linux-gnu-gcc" HOSTCC="ccache gcc")

mkdir -p "$WORK/dl"
cd "$WORK"

# 1. Fetch kernel
TARBALL="dl/linux-$KVER.tar.xz"
[[ -f $TARBALL ]] || curl -fL -o "$TARBALL" "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-$KVER.tar.xz"
# The source is prepared in a scratch tree (stage/), then synced into the persistent build tree linux-$KVER with
# content checksums: only files whose content changed get a new mtime, so kbuild rebuilds just what the new patches
# touch (same idea as the OPi5 project's read-tree update). Files that the previous run's source had and this one
# lacks are deleted (src-manifest). No manifest yet (first run, or INCREMENTAL=0) means a full re-extract.
INCREMENTAL="${INCREMENTAL:-1}"
rm -rf stage; mkdir stage
tar -C stage -xf "$TARBALL"
cd "stage/linux-$KVER"

# 2a. uwe5622 WiFi driver first: Armbian injects drivers before series.conf (EXTRA_PATCH_FILES_FIRST), so patches.armbian may touch drivers/net/wireless/uwe5622
UWESRC="$WORK/dl/uwe5622"
[[ -d $UWESRC/.git ]] || git clone -q https://github.com/armbian/uwe5622 "$UWESRC"
git -C "$UWESRC" -c advice.detachedHead=false checkout -q "$UWE_COMMIT"
mkdir -p drivers/net/wireless/uwe5622
cp -R "$UWESRC"/{tty-sdio,unisocwcn,unisocwifi,Kconfig,Makefile} drivers/net/wireless/uwe5622/
echo 'obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/' >> drivers/net/wireless/Makefile
sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/uwe5622\/Kconfig"' drivers/net/wireless/Kconfig

# 2. Apply series.conf (active entries only: skip comments and '-'-prefixed disabled lines)
: > "$WORK/patch-failures.txt"
applied=0; failed=0
while read -r p; do
	if patch -p1 -N -s --no-backup-if-mismatch -i "$PATCHROOT/$p" > "$WORK/patch-last.log" 2>&1; then
		applied=$((applied + 1))
	else
		failed=$((failed + 1))
		{ echo "=== $p"; cat "$WORK/patch-last.log"; } >> "$WORK/patch-failures.txt"
	fi
done < <(sed -e 's/#.*//' "$PATCHROOT/series.conf" | awk 'NF && $1 !~ /^-/ {print $1}')
echo "patches applied: $applied, failed: $failed"
[[ $failed -eq 0 ]] || { echo "patch failures (see $WORK/patch-failures.txt):"; grep '^===' "$WORK/patch-failures.txt"; }

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


# 4. Sync the staged source into the persistent tree (unchanged files keep their mtime)
find . \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort > "$WORK/src-manifest.new"
cd "$WORK"
if [[ $INCREMENTAL == 1 && -d linux-$KVER && -f src-manifest ]]; then
	LC_ALL=C comm -23 src-manifest src-manifest.new | (cd "linux-$KVER" && xargs -r -d '\n' rm -f --)
	rsync -rlpc "stage/linux-$KVER/" "linux-$KVER/"
	echo "incremental source update: $(LC_ALL=C comm -23 src-manifest src-manifest.new | wc -l) files removed"
else
	rm -rf "linux-$KVER"; mv "stage/linux-$KVER" "linux-$KVER"; echo "full source tree (no manifest)"
fi
mv src-manifest.new src-manifest; rm -rf stage
cd "linux-$KVER"

[[ $STAGE == patch ]] && { echo "STAGE=patch done (tree in $PWD)"; exit "$failed"; }

# 5. Configure & build
cp "$ARMBIAN/config/kernel/linux-sunxi64-edge.config" .config
make "${MAKE_CC[@]}" olddefconfig > ../olddefconfig.log 2>&1
rc=0
if [[ $STAGE == all ]]; then
	make "${MAKE_CC[@]}" -j"$JOBS" Image modules allwinner/sun50i-h616-orangepi-zero2.dtb > ../build.log 2>&1 || rc=$?
	grep -E ' error:|Error [0-9]' ../build.log || true
	echo "build exit: $rc; C warnings: $(grep -c 'warning:' ../build.log || true)"
	grep 'warning:' ../build.log | sed 's/:[0-9]*:[0-9]*: warning:.*//' | sort | uniq -c | sort -rn | head -20 || true
fi

# 6. All allwinner DTBs + Armbian overlays (.dtbo) + fixup scripts (.scr, needs mkimage from u-boot-tools)
drc=0
make "${MAKE_CC[@]}" -j"$JOBS" dtbs > ../dtbs.log 2>&1 || drc=$?
echo "dtbs exit: $drc; dtc warnings: $(grep -c 'Warning (' ../dtbs.log || true)"
grep -E 'Warning \(|Error|error:' ../dtbs.log | head -30 || true
ls "$DTDIR"/overlay/sun50i-h616-*.dtbo 2>/dev/null | wc -l | sed 's/^/h616 overlays built: /'

# 7. Decompile the Zero2 DTB for inspection (WORK/zero2.dts) and check requested nodes
scripts/dtc/dtc -q -I dtb -O dts -o ../zero2.dts "$DTDIR/sun50i-h616-orangepi-zero2.dtb" 2>../zero2-dtc.log || true
for pat in ${DT_CHECK:-}; do
	if grep -q -- "$pat" ../zero2.dts; then echo "DT_CHECK ok: $pat"; else echo "DT_CHECK MISSING: $pat"; rc=1; fi
done
[[ $drc -eq 0 ]] || rc=$drc
echo "overall exit: $rc"
exit "$rc"
