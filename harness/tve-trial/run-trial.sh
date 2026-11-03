#!/bin/bash
# One-shot TVE fix trial on the Zero2 (host side). Subcommands, in order:
#   install   ship Image.tve1 + modules-tve1.tgz, arm vdec-fallback (300 s), keep the image DTB
#   phaseA    reboot into the trial kernel WITHOUT the expansion overlay; regression checks
#   phaseB    add overlays=orangepi-zero2-expansion, reboot, require uptime > 120 s (no watchdog loop)
#   observe   run observe.sh on the board (TCON TV1 line counter, IRQ 99, load detect, forced flips)
#   restore   overlay line removed, image kernel symlink back, trial modules removed, reboot, verify
#   recover   if phaseB boot-loops: interrupt U-Boot via /dev/ttyOPIZ2 and boot without overlays,
#             then run "restore"
set -euo pipefail
H=/home/aruni/orangepizero2; SSH=$H/harness/ssh.sh; S=$H/harness/research/vdec-perf/ship.sh
OUT=$H/harness/tve-trial/results-$(date +%Y%m%d)
IMG=vmlinuz-7.3.1-edge-sunxi64
wait_ssh() { for i in $(seq 1 ${1:-60}); do $SSH -o ConnectTimeout=3 true 2>/dev/null && return 0; sleep 4; done; return 1; }
case "${1:-}" in
install)
	$SSH "test \"\$(readlink /boot/Image)\" = $IMG" || { echo "board not on the image kernel"; exit 1; }
	bash $H/harness/research/vdec-perf/install-kernel.sh tve1
	$S $H/harness/afbc-kms-play/out/afbc-kms-play /root/afbc/afbc-kms-play
	NOXZ=1 $S $H/harness/research/vdec-perf/devmem.py /root/afbc/devmem.py
	NOXZ=1 $S $H/harness/tve-trial/observe.sh /root/afbc/tve-observe.sh
	$SSH 'chmod +x /root/afbc/*; cp -n /boot/armbianEnv.txt /boot/armbianEnv.txt.tve-orig; sync'
	;;
phaseA)
	$SSH 'systemctl reboot' || true; sleep 30; wait_ssh || { echo "no ssh: use recover"; exit 1; }
	$SSH 'touch /run/vdec-ok; uname -r; dmesg | grep -ciE "flip_done|vblank wait|WARNING|Oops"; for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status)"; done; cat /sys/class/drm/card0-HDMI-A-1/modes | head -2'
	;;
phaseB)
	$SSH 'grep -q "^overlays=" /boot/armbianEnv.txt && sed -i "s/^overlays=.*/& orangepi-zero2-expansion/" /boot/armbianEnv.txt || echo overlays=orangepi-zero2-expansion >> /boot/armbianEnv.txt; grep overlays /boot/armbianEnv.txt; sync; systemctl reboot' || true
	sleep 30; wait_ssh || { echo "no ssh: use recover"; exit 1; }
	$SSH 'touch /run/vdec-ok; cat /proc/device-tree/soc/tv-encoder@6524000/status; echo'
	sleep 100
	$SSH 'up=$(cut -d. -f1 /proc/uptime); echo "uptime ${up}s"; [ $up -gt 120 ] && echo "PASS: no watchdog loop" || echo "FAIL: rebooted"; dmesg | grep -iE "flip_done|vblank wait|WARNING" | head'
	;;
observe)
	mkdir -p "$OUT"
	$SSH 'rm -rf /root/tve-out; sh /root/afbc/tve-observe.sh /root/tve-out > /root/tve-run.log 2>&1; cd /root && tar czf - tve-out tve-run.log' | tar xzf - -C "$OUT"
	cat "$OUT/tve-out/summary.txt"
	;;
recover)
	python3 -I $H/harness/afbc-kms-play/tools/uboot-noovl.py 240
	sleep 40; wait_ssh || { echo "still no ssh"; exit 1; }
	$SSH 'touch /run/vdec-ok; sed -i "s/ *orangepi-zero2-expansion//; /^overlays=$/d" /boot/armbianEnv.txt; sync; echo recovered'
	;;
restore)
	$SSH "set -e; cp /boot/armbianEnv.txt.tve-orig /boot/armbianEnv.txt && rm -f /boot/armbianEnv.txt.tve-orig
		ln -sfn $IMG /boot/Image; rm -f /boot/vdec-trial /boot/vmlinuz-7.3.1-vdec-tve1
		rm -rf /lib/modules/7.3.1 /lib/modules/7.3.1.good; sync; systemctl reboot" || true
	sleep 40; wait_ssh || { echo "no ssh after restore"; exit 1; }
	$SSH 'uname -r; uptime'
	L=$(grep -a -n 'U-Boot SPL' $H/harness/serial.log | tail -1 | cut -d: -f1)
	sed -n "$L,$((L+2))p" $H/harness/serial.log | tr -d '\r' | grep -a DRAM
	;;
*) sed -n 2,12p "$0"; exit 2 ;;
esac
