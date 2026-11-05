#!/bin/bash
# Queue-depth round 2 (board, image kernel): VE at 624 MHz (vendor H616 policy) set through PLL_VE N (devmem, VE idle;
# cedrus sets the rate only at probe, so it holds), at the worst-case VDD-SYS (GPU idle -> DT floor 900 mV).
# Rates (ve-timeline.sh) with and without MBUS port 4 (VE) priority+QoS HIGHEST, md5 of every 10-bit path, then a soak
# of md5 loops. Everything is restored to 600 MHz / U-Boot MBUS values at the end.
cd /root/vdec-streams || exit 1
V=/root/vp; DM="python3 -I $V/devmem.py"; TL=$V/ve-timeline.sh; A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2
F="$V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"; FD="$F -hwaccel_output_format drm_prime"
SOAK=${SOAK:-900}
curl -sS $U/avs2dec-q -o $A; chmod +x $A; curl -sS $U/cctv4k-10bit.avs2 -o /tmp/cc.avs2; curl -sS $U/main-2160p-ra.avs2 -o /tmp/m8.avs2
PV=0x03001058; P4=$((0x047FA210 + 4 * 16)); o4=$($DM $P4); o=$($DM $PV)
hz() { v=$($DM $PV); echo $(( 24 * (((v >> 8) & 0xff) + 1) / (((v >> 1) & 1) + 1) / ((v & 1) + 1) )); }
temp() { cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | tr '\n' ' '; }
volt() { for r in /sys/class/regulator/regulator.*; do [ "$(cat $r/name 2>/dev/null)" = vdd-gpu-sys ] && cat $r/microvolts; done; }
echo "pll-ve $o = $(hz) MHz; vdd-gpu-sys $(volt) uV; gpu devfreq $(cat /sys/class/devfreq/1800000.gpu/cur_freq 2>/dev/null); temp $(temp)"
ff() { lbl=$1; shift; echo "[$lbl] $($TL "$@" | tr '\n' ' ')"; }
rates() { # tag
  ff "$1 vp9p2-p010" env V4L2REQUEST_PIXFMT=P010 $FD -i vp9-p2-2160p60.webm -f null -
  ff "$1 h265m10-p010" env V4L2REQUEST_PIXFMT=P010 $FD -i hevc-main10-2160p60.mkv -f null -
  ff "$1 avs2-p010" env AVS2_NOOUT=1 $A /tmp/cc.avs2
  ff "$1 gst-h265m10" gst-launch-1.0 -q filesrc location=hevc-main10-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! fakevideosink sync=false
  ff "$1 gst-vp9p2" gst-launch-1.0 -q filesrc location=vp9-p2-2160p60.webm ! matroskademux ! vp9parse ! v4l2slvp9dec ! fakevideosink sync=false
}
md5s() { # tag -> PASS/FAIL per path
  for t in "vp9-p2-2160p60.webm" "hevc-main10-2160p60.mkv"; do
    r=$(V4L2REQUEST_PIXFMT=P010 $F -i $t -pix_fmt p010le -f md5 - 2>&1 | tail -1); ref=$(cut -d= -f2 $t.p010le.md5)
    res=FAIL; [ "${r#MD5=}" = "$ref" ] && res=PASS; echo "[$1 md5 $t] $res ${r#MD5=}"; done
  r=$($A /tmp/m8.avs2 2>/dev/null | tail -1 | awk '{print $NF}'); res=FAIL; [ "$r" = 3a3d5d7eb9a6f548042e160d9e461388 ] && res=PASS; echo "[$1 md5 avs2-8bit-2160p] $res $r"
}
avs10() { r=$(timeout 900 $A /tmp/cc.avs2 2>/dev/null | tail -1 | awk '{print $NF}'); res=FAIL; [ "$r" = be9985dea38abffc850d73024165c990 ] && res=PASS; echo "[$1 md5 avs2-10bit-cctv4k] $res $r"; }
echo "== 600 MHz, MBUS port 4 QoS HIGHEST"
$DM $P4 $(( o4 | 0xe )); rates q600; $DM $P4 $o4
echo "== 624 MHz"
$DM $PV $(( (o & ~0xff00) | (25 << 8) )); sleep 0.1; echo "pll-ve $($DM $PV) = $(hz) MHz"
rates f624
$DM $P4 $(( o4 | 0xe )); echo "port4 $($DM $P4)"; rates f624q
md5s f624q; avs10 f624q
echo "== soak ${SOAK}s at 624 MHz + port 4 QoS, GPU idle, temp $(temp)"
t0=$(date +%s); n=0; bad=0
while [ $(( $(date +%s) - t0 )) -lt $SOAK ]; do
  out=$(md5s soak); n=$((n + 3)); b=$(echo "$out" | grep -c FAIL); bad=$((bad + b)); [ $b -gt 0 ] && echo "$out" | grep FAIL
done
echo "[soak] runs=$n fail=$bad $(( $(date +%s) - t0 ))s vdd-gpu-sys $(volt) temp $(temp)"
$DM $PV $o; $DM $P4 $o4; echo "restored pll-ve $($DM $PV) = $(hz) MHz, port4 $($DM $P4)"
rm -f /tmp/cc.avs2 /tmp/m8.avs2
dmesg | grep -iE 'cedrus|iommu|fault|timed out' | tail -5 | sed 's/^/[dmesg] /'
echo ROUND-DONE
