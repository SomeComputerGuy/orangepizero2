#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Host self-test of harness/flasher/init with the real arm64 BusyBox (qemu-aarch64 user mode via
# binfmt), a fake sysfs and a regular file as the "SD card". No root, no board.
#   selftest.sh            small synthetic image: write + verify, and every refusal case
#   FULL=1 selftest.sh     also a dry run against the newest real Armbian image (download + xz + sha)
set -uo pipefail
HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOP="$(dirname "$HARNESS")"
W="${WORK:-$TOP/kernel-check/work-flasher}/selftest"
BB="$TOP/kernel-check/work-flasher/x/root/bin/busybox"
[[ -x $BB ]] || { echo "run build-flasher.sh first"; exit 1; }
rm -rf "$W" && mkdir -p "$W/bin" "$W/img"
for a in $("$BB" --list); do ln -s "$BB" "$W/bin/$a"; done

# synthetic 2 MiB + 1 byte image (odd size on purpose)
head -c 2097153 /dev/urandom > "$W/img/test.img" && xz -T0 -k "$W/img/test.img" && mv "$W/img/test.img.xz" "$W/img/selftest.img.xz"
PORT=$((20000 + RANDOM % 20000))
start_srv() { python3 -I "$HARNESS/flasher/serve-image.py" --bind 127.0.0.1 --port $PORT --image "$1" \
	--cache-dir "$W/cache" --status-file "$W/status" 2> "$W/srv.log" & SRV=$!; sleep 1; }
start_srv "$W/img/selftest.img.xz"
trap 'kill $SRV 2>/dev/null' EXIT

# fake sysfs: /sys/block/mmcblk0 -> devices/platform/soc/4020000.mmc/.../block/mmcblk0
mksys() { # mksys DIR HOSTPATH TYPE DEV SECTORS
	local d=$1/devices/platform/soc/$2/mmc_host/mmc0/mmc0:aaaa/block/mmcblk0
	mkdir -p "$d/device" "$1/block" "$1/class/net"
	echo "$3" > "$d/device/type"; echo "$4" > "$d/dev"; echo "$5" > "$d/size"; echo 0 > "$d/removable"
	ln -sfn "../devices/platform/soc/$2/mmc_host/mmc0/mmc0:aaaa/block/mmcblk0" "$1/block/mmcblk0"
}
GOOD=62333952
pass=0 fail=0
run() { # run NAME EXPECT(ok|fail) SYS TARGET CMDLINE-extra
	local name=$1 exp=$2 sys=$3 tgt=$4 extra=$5 out rc
	out=$(cd "$W" && env -i PATH="$W/bin" FLASHER_TEST=1 SYS="$sys" TARGET="$tgt" \
		CMDLINE="flasher.url=http://127.0.0.1:$PORT $extra" "$W/bin/sh" "$HARNESS/flasher/init" 2>&1); rc=$?
	if { [[ $exp == ok ]] && [[ $rc == 0 ]] && grep -q 'RESULT OK' <<< "$out"; } ||
		{ [[ $exp == fail ]] && [[ $rc != 0 ]] && grep -q 'FLASHER: FAIL' <<< "$out"; }; then
		pass=$((pass + 1)); printf 'PASS %-28s %s\n' "$name" "$(grep -E 'RESULT|FAIL' <<< "$out" | head -1)"
	else
		fail=$((fail + 1)); printf 'FAIL %-28s rc=%s\n%s\n' "$name" "$rc" "$out"
	fi
}
mksys "$W/sys-good" 4020000.mmc SD 179:0 $GOOD
mksys "$W/sys-emmc" 4022000.mmc MMC 179:0 $GOOD
mksys "$W/sys-type" 4020000.mmc SDIO 179:0 $GOOD
mksys "$W/sys-major" 4020000.mmc SD 31:0 $GOOD
mksys "$W/sys-small" 4020000.mmc SD 179:0 1000000
mksys "$W/sys-huge" 4020000.mmc SD 179:0 $((600 * 1024 * 1024 * 2))
T="$W/sd.bin"
truncate -s 0 "$T"

run write-and-verify ok "$W/sys-good" "$T" "flasher.sectors=$GOOD"
cmp -n 2097153 "$T" "$W/img/test.img" > /dev/null && { pass=$((pass + 1)); echo "PASS written-bytes-match"; } || { fail=$((fail + 1)); echo "FAIL written-bytes-match"; }
run dry-run ok "$W/sys-good" "$W/untouched.bin" "flasher.dryrun=1"
[[ ! -s $W/untouched.bin ]] && { pass=$((pass + 1)); echo "PASS dry-run-wrote-nothing"; } || { fail=$((fail + 1)); echo "FAIL dry-run-wrote-nothing"; }
printf 'sentinel' > "$W/keep.bin"
run refuse-mtd-target fail "$W/sys-good" /dev/mtd0 ""
run refuse-mtdblock-target fail "$W/sys-good" /dev/mtdblock0 ""
run refuse-emmc-slot fail "$W/sys-emmc" "$W/keep.bin" ""
run refuse-non-sd-type fail "$W/sys-type" "$W/keep.bin" ""
run refuse-wrong-major fail "$W/sys-major" "$W/keep.bin" ""
run refuse-too-small fail "$W/sys-small" "$W/keep.bin" ""
run refuse-too-large fail "$W/sys-huge" "$W/keep.bin" ""
run refuse-sector-mismatch fail "$W/sys-good" "$W/keep.bin" "flasher.sectors=123"
run refuse-no-sysfs fail "$W/nonexistent" "$W/keep.bin" ""
run refuse-https-url fail "$W/sys-good" "$W/keep.bin" "flasher.url=https://x"
[[ $(cat "$W/keep.bin") == sentinel ]] && { pass=$((pass + 1)); echo "PASS refusals-wrote-nothing"; } || { fail=$((fail + 1)); echo "FAIL refusals-wrote-nothing"; }
# corrupt image: manifest says one checksum, served bytes differ
kill $SRV; wait $SRV 2> /dev/null
cp "$W/img/selftest.img.xz" "$W/img/corrupt.img.xz"; start_srv "$W/img/corrupt.img.xz"
f=$(ls "$W/cache"/corrupt.img.xz.*.json); sed -i 's/"SHA256": "[0-9a-f]*"/"SHA256": "'"$(printf 0%.0s {1..64})"'"/' "$f"
kill $SRV; wait $SRV 2> /dev/null; start_srv "$W/img/corrupt.img.xz"
run detect-sha-mismatch fail "$W/sys-good" "$W/sd2.bin" ""
grep -q 'status=ok' "$W/status" && grep -q 'status=fail' "$W/status" && { pass=$((pass + 1)); echo "PASS host-received-reports"; } || { fail=$((fail + 1)); echo "FAIL host-received-reports"; }
if [[ ${FULL:-0} == 1 ]]; then
	kill $SRV; wait $SRV 2> /dev/null
	start_srv "$(ls -t "$TOP"/armbian-build/output/images/*Orangepizero2*.img.xz | head -1)"; sleep 1
	until grep -q serving "$W/srv.log"; do sleep 2; done
	t0=$(date +%s); run real-image-dry-run ok "$W/sys-good" "$W/untouched2.bin" "flasher.dryrun=1"; echo "  ($(($(date +%s) - t0)) s)"
fi
echo "selftest: $pass passed, $fail failed"
[[ $fail == 0 ]]
