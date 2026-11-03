#!/bin/sh
# On-board TVE/TCON TV1 observables (root on the Zero2). No TV is needed.
# usage: observe.sh <outdir>
set -u
OUT=${1:?outdir}; mkdir -p "$OUT"; cd "$OUT" || exit 1
M="python3 -I /root/afbc/devmem.py"
P=/root/afbc/afbc-kms-play
log() { echo "== $*" | tee -a summary.txt; }
regs() {
	echo "TCON_TOP TV_SETUP 0x06510000 = $($M 0x06510000)  (bit4 = TV1 clock from TVE)"
	echo "TCON_TOP PORT_SEL 0x0651001c = $($M 0x0651001c)"
	echo "TCON_TOP GATE_SRC 0x06510020 = $($M 0x06510020)  (H616: bit20 TV0, bit21 TV1)"
	echo "TCON_TV1 GCTL     0x06516000 = $($M 0x06516000)"
	echo "TCON_TV1 TCON1_CTL 0x06516090 = $($M 0x06516090)"
	a=$($M 0x065160fc); sleep 0.05; b=$($M 0x065160fc)
	echo "TCON_TV1 DEBUG(line) 0x065160fc = $a then $b  (must differ when running)"
	echo "TVE GCTL 0x06524000 = $($M 0x06524000)  (bit31 clock for load detect)"
	echo "TVE AUTO_DETECT_EN 0x06524030 = $($M 0x06524030)  (expect 0x80000001)"
	echo "TVE AUTO_DETECT_STATUS 0x06524038 = $($M 0x06524038)  (bits1:0 = 1 means load)"
	echo "IRQ: $(grep 6516000 /proc/interrupts | tr -s ' ')"
	for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status) $(cat $c/enabled)"; done
}
uname -a | tee -a summary.txt
cat /proc/cmdline | tee -a summary.txt
grep -E 'tve0|tcon-tv1|tcon-top-tv1|pll-video1 ' /sys/kernel/debug/clk/clk_summary | tee -a summary.txt
log "idle (no TV attached): Composite-1 must be disconnected, no flip_done errors"
regs | tee -a summary.txt
dmesg | grep -iE 'flip_done|vblank wait|tve|tv-encoder|tcon' | tee -a summary.txt
log "forced: unbind fbcon, force Composite-1 on, 100 XR24 flips (timeout 30 s)"
echo 0 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
echo on > /sys/class/drm/card0-Composite-1/status
dmesg -C
timeout -s KILL 30 $P --pattern XR24 -c Composite-1 -m 720x576 -n 100 -o tve-pal.csv > tve-pal.txt 2>&1 &
pp=$!; sleep 4; regs | tee -a summary.txt; wait $pp; echo "client rc $?" | tee -a summary.txt
tail -9 tve-pal.txt | tee -a summary.txt
log "forced NV12 on the mixer1 VI plane (DE33 YUV output path)"
timeout -s KILL 30 $P --pattern NV12 -c Composite-1 -m 720x576 -n 100 -o tve-nv12.csv > tve-nv12.txt 2>&1
echo "client rc $?" | tee -a summary.txt; tail -9 tve-nv12.txt | tee -a summary.txt
echo detect > /sys/class/drm/card0-Composite-1/status
echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null
sleep 1; log "after release"; regs | tee -a summary.txt
dmesg | grep -iE 'flip_done|vblank wait|WARNING|tve' | tee -a summary.txt
