#!/bin/bash
# Round 3 (board, cumulative kernel c2 = test/cumulative + feat/sunxi-h616-vdec-60fps: AVS2 AFBC capture + VE 624 MHz):
# AVS2 4K Main10 AFBC vs P010 rates, then md5 regression of the 10-bit paths and 8-bit AVS2.
# Rates at the kernel default (624 MHz), then at 600 MHz through PLL_VE N (devmem, restored after).
cd /root/vdec-streams || exit 1
V=/root/vp; DM="python3 -I $V/devmem.py"; TL=$V/ve-timeline.sh; A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2
F="$V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"; FD="$F -hwaccel_output_format drm_prime"
curl -sS $U/avs2dec-q -o $A; chmod +x $A; curl -sS $U/cctv4k-10bit.avs2 -o /tmp/cc.avs2; curl -sS $U/main-2160p-ra.avs2 -o /tmp/m8.avs2
PV=0x03001058; P4=$((0x047FA210 + 4 * 16)); o4=$($DM $P4); o=$($DM $PV)
echo "kernel $(uname -rv) pll-ve $o clk $(cat /sys/kernel/debug/clk/ve/clk_rate) uptime $(cut -d" " -f1 /proc/uptime) cedrus-timeouts-so-far $(dmesg | grep -c "timed out")"
ff() { lbl=$1; shift; echo "[$lbl] $($TL "$@" | tr '\n' ' ') $(tail -1 /tmp/vtl.out | cut -c1-120)"; }
rates() {
  ff "$1 avs2-p010" env AVS2_NOOUT=1 $A /tmp/cc.avs2
  ff "$1 avs2-afbc" env AVS2_NOOUT=1 AVS2_CAP=AFBC $A /tmp/cc.avs2
  ff "$1 avs2-afbc-depth3" env AVS2_NOOUT=1 AVS2_DEPTH=3 AVS2_CAP=AFBC $A /tmp/cc.avs2
  ff "$1 vp9p2-p010" env V4L2REQUEST_PIXFMT=P010 $FD -i vp9-p2-2160p60.webm -f null -
  ff "$1 h265m10-p010" env V4L2REQUEST_PIXFMT=P010 $FD -i hevc-main10-2160p60.mkv -f null -
}
rates k624
$DM $P4 $(( o4 | 0xe )); rates k624q; $DM $P4 $o4
$DM $PV $(( (o & ~0xff00) | (24 << 8) )); echo "pll-ve $($DM $PV) (600 MHz)"; rates k600; $DM $PV $o; echo "restored pll-ve $($DM $PV)"
echo "== md5 regression (kernel default rate, U-Boot MBUS)"
for t in vp9-p2-2160p60.webm hevc-main10-2160p60.mkv; do
  r=$(V4L2REQUEST_PIXFMT=P010 $F -i $t -pix_fmt p010le -f md5 - 2>&1 | tail -1); ref=$(cut -d= -f2 $t.p010le.md5)
  res=FAIL; [ "${r#MD5=}" = "$ref" ] && res=PASS; echo "[md5 $t P010] $res ${r#MD5=}"; done
r=$($A /tmp/m8.avs2 2>/dev/null | tail -1 | awk '{print $NF}'); res=FAIL; [ "$r" = 3a3d5d7eb9a6f548042e160d9e461388 ] && res=PASS; echo "[md5 avs2-8bit-2160p] $res $r"
r=$(timeout 900 $A /tmp/cc.avs2 2>/dev/null | tail -1 | awk '{print $NF}'); res=FAIL; [ "$r" = be9985dea38abffc850d73024165c990 ] && res=PASS; echo "[md5 avs2-10bit-cctv4k P010] $res $r"
v4l2-compliance -d /dev/video0 2>&1 | tail -1 | sed 's/^/[compliance] /'
rm -f /tmp/cc.avs2 /tmp/m8.avs2
dmesg | grep -iE 'cedrus|iommu|fault|timed out' | tail -5 | sed 's/^/[dmesg] /'
echo "uptime $(cut -d" " -f1 /proc/uptime) cedrus-timeouts $(dmesg | grep -c "timed out")"
echo ROUND-DONE
