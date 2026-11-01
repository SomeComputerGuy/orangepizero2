#!/usr/bin/env bash
# Rootless validation build of the Armbian sunxi64 U-Boot for Orange Pi Zero2 (H616).
# Mirrors what Armbian's framework does for the board (patch/u-boot/<BOOTPATCHDIR>
# top-level + board_<BOARD>/ patches applied in LC_ALL=C name order, defconfig,
# BOOTDELAY/LOCALVERSION tweaks, BL31 from TF-A, binman image) without needing root.
#
# Caching (rule #1): the U-Boot and TF-A clones under $WORK are reused; U-Boot builds
# out-of-tree in $WORK/build so the source can be reset+repatched cheaply while the
# object dir stays incremental; everything compiles through ccache. TF-A's bl31.bin is
# built once and reused (ATF_REBUILD=1 forces).
#
# STAGE=patch : reset tree + apply patches, then stop (fast patch check)
# STAGE=all   : ... + defconfig + build u-boot-sunxi-with-spl.bin (default)
# CFG_CHECK="CONFIG_A=y CONFIG_B" : after configuring, grep these in .config
# ARMBIAN     : tree whose patch/u-boot/<BOOTPATCHDIR> is used (default: wt-uboot worktree)
set -euo pipefail

STAGE="${STAGE:-all}"
BOARD="${BOARD:-orangepizero2}"
BOOTCONFIG="${BOOTCONFIG:-orangepi_zero2_defconfig}"
UBOOT_TAG="${UBOOT_TAG:-v2026.10}"
BOOTPATCHDIR="${BOOTPATCHDIR:-v2026.10-sunxi64}"
ATF_TAG="${ATF_TAG:-lts-v2.14.11}"
ATF_PLAT="${ATF_PLAT:-sun50i_h616}"
BOOTDELAY="${BOOTDELAY:-1}"
ARMBIAN="${ARMBIAN:-/home/aruni/orangepizero2/wt-uboot}"
WORK="${WORK:-/home/aruni/orangepizero2/kernel-check/work-uboot}"
CACHE="${CACHE:-/home/aruni/orangepizero2/armbian-build/cache}"
JOBS="${JOBS:-$(nproc)}"
PATCHROOT="$ARMBIAN/patch/u-boot/$BOOTPATCHDIR"
export CROSS_COMPILE=aarch64-linux-gnu-
MAKE_CC=(); command -v ccache > /dev/null && MAKE_CC=(CC="ccache aarch64-linux-gnu-gcc" HOSTCC="ccache gcc")

mkdir -p "$WORK"
cd "$WORK"

# 1. Sources (shallow clones; prefer Armbian's local bare/worktree caches, fall back to network).
# The cache is root-owned, so override git's safe.directory check only for the clone.
if [[ ! -d u-boot/.git ]]; then
	git -c safe.directory='*' clone -q --depth 1 -b "$UBOOT_TAG" "file://$CACHE/git-bare/u-boot" u-boot 2> /dev/null ||
		git clone -q --depth 1 -b "$UBOOT_TAG" https://github.com/u-boot/u-boot u-boot
fi
if [[ ! -d arm-trusted-firmware/.git ]]; then
	git -c safe.directory='*' clone -q --depth 1 "file://$CACHE/sources/arm-trusted-firmware/$ATF_TAG" arm-trusted-firmware 2> /dev/null ||
		git clone -q --depth 1 -b "$ATF_TAG" https://github.com/ARM-software/arm-trusted-firmware arm-trusted-firmware
fi

# 2. BL31 (cached)
BL31="$WORK/arm-trusted-firmware/build/$ATF_PLAT/debug/bl31.bin"
if [[ ! -f $BL31 || -n ${ATF_REBUILD:-} ]]; then
	make -C arm-trusted-firmware -s "${MAKE_CC[@]}" PLAT="$ATF_PLAT" DEBUG=1 -j"$JOBS" bl31 > atf-build.log 2>&1 ||
		{ echo "TF-A build failed (see $WORK/atf-build.log)"; tail -20 atf-build.log; exit 1; }
fi
echo "bl31.bin: $(stat -c %s "$BL31") bytes"

# 3. Reset the U-Boot tree to the pristine tag and apply patches the way Armbian does:
# names from <dir>/*.patch and <dir>/board_<BOARD>/*.patch, LC_ALL=C sorted by basename,
# `patch --batch -p1 -N`, every failure is fatal in Armbian (here: collected and reported).
cd u-boot
git checkout -q -f "$UBOOT_TAG" 2> /dev/null || git checkout -q -f FETCH_HEAD
git clean -qfdx -e /build
: > ../patch-failures.txt
applied=0; failed=0
while read -r name; do
	for d in "$PATCHROOT/board_$BOARD" "$PATCHROOT"; do
		p="$d/$name"
		[[ -f $p ]] || continue
		[[ -s $p ]] || { echo "skipped (empty): $name"; break; }
		# Armbian removes files the patch creates before applying (idempotency)
		lsdiff -s --strip=1 "$p" 2> /dev/null | awk '/^\+/ {print $2}' | xargs -r rm -f
		if patch --batch -p1 -N --quiet --reject-file=- -i "$p" > ../patch-last.log 2>&1; then
			applied=$((applied + 1))
		else
			failed=$((failed + 1))
			{ echo "=== $name"; cat ../patch-last.log; } >> ../patch-failures.txt
		fi
		break
	done
done < <({ ls "$PATCHROOT"/*.patch "$PATCHROOT/board_$BOARD"/*.patch 2> /dev/null || true; } | xargs -rn1 basename | LC_ALL=C sort -u)
echo "patches applied: $applied, failed: $failed"
[[ $failed -eq 0 ]] || { echo "patch failures (see $WORK/patch-failures.txt):"; grep '^===' ../patch-failures.txt; }
[[ $STAGE == patch ]] && { echo "STAGE=patch done (tree in $PWD)"; exit "$failed"; }

# 4. Configure (out of tree, like Armbian's tweaks: BOOTDELAY, LOCALVERSION)
O="$WORK/build"
mkdir -p "$O"
make -s "${MAKE_CC[@]}" O="$O" "$BOOTCONFIG" > ../config.log 2>&1
scripts/config --file "$O/.config" --set-val CONFIG_BOOTDELAY "$BOOTDELAY" --disable LOCALVERSION_AUTO --set-str LOCALVERSION "_armbian-check"
make -s "${MAKE_CC[@]}" O="$O" olddefconfig >> ../config.log 2>&1
for pat in ${CFG_CHECK:-}; do
	if grep -qx -- "$pat" "$O/.config"; then echo "CFG_CHECK ok: $pat"; else echo "CFG_CHECK MISSING: $pat ($(grep -- "^.*${pat%%=*}[= ]" "$O/.config" | head -1))"; fi
done

# 5. Build the Armbian target (UBOOT_TARGET_MAP: BINMAN_ALLOW_MISSING=1 ;; u-boot-sunxi-with-spl.bin)
rc=0
make "${MAKE_CC[@]}" O="$O" -j"$JOBS" BL31="$BL31" BINMAN_ALLOW_MISSING=1 > ../build.log 2>&1 || rc=$?
grep -E ' error:|Error [0-9]|undefined reference' ../build.log | head -20 || true
echo "build exit: $rc; C warnings: $(grep -c 'warning:' ../build.log || true)"
if [[ $rc -eq 0 ]]; then
	for f in spl/sunxi-spl.bin u-boot-nodtb.bin u-boot.dtb u-boot.itb u-boot-sunxi-with-spl.bin; do
		[[ -f $O/$f ]] && printf '%-28s %9d bytes\n' "$f" "$(stat -c %s "$O/$f")"
	done
	sz=$(stat -c %s "$O/u-boot-sunxi-with-spl.bin")
	echo "u-boot-sunxi-with-spl.bin: $sz bytes = $((sz / 1024)) KiB; fits 2 MiB SPI NOR: $([[ $sz -le $((2 * 1024 * 1024)) ]] && echo yes || echo NO), SPL max $(grep -o 'CONFIG_SPL_MAX_SIZE=.*' "$O/.config")"
fi
echo "artifacts in $O; overall exit: $rc"
exit "$rc"
