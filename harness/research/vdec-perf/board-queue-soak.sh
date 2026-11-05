#!/bin/bash
# Soak (board, newest cumulative kernel, VE at the kernel default 624 MHz, no register knobs): SOAK seconds (default
# 3900) of VP9 P2 / H.265 Main10 / AVS2 8-bit + 10-bit md5 runs plus VP9 and AVS2 AFBC load runs. VDD-SYS held at its
# floor: GPU devfreq governor powersave (restored after). Logs temperature, vdd-gpu-sys, cedrus timeouts every 5 min.
cd /root/vdec-streams || exit 1
SOAK=${SOAK:-3900}; V=/root/vp; A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2
F="$V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"; FD="$F -hwaccel_output_format drm_prime"
curl -sS $U/avs2dec-q -o $A; chmod +x $A; curl -sS $U/cctv4k-10bit.avs2 -o /tmp/cc.avs2; curl -sS $U/main-2160p-ra.avs2 -o /tmp/m8.avs2
temp() { cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | tr '\n' ' '; }
volt() { for r in /sys/class/regulator/regulator.*; do [ "$(cat $r/name 2>/dev/null)" = vdd-gpu-sys ] && cat $r/microvolts; done; }
G=/sys/class/devfreq/1800000.gpu; og=$(cat $G/governor); echo powersave > $G/governor
to() { dmesg | grep -c "timed out"; }
echo "kernel $(uname -rv) clk $(cat /sys/kernel/debug/clk/ve/clk_rate) gpu $(cat $G/governor) $(cat $G/cur_freq) vdd-gpu-sys $(volt) temp $(temp) timeouts $(to) uptime $(cut -d' ' -f1 /proc/uptime)"
chk() { # chk <label> <expected md5> <cmd...>
  lbl=$1; ref=$2; shift 2; r=$("$@" 2>&1 | tail -1); r=${r#MD5=}; r=${r##* }
  if [ "$r" = "$ref" ]; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "[FAIL $lbl] $r $(date +%T) temp $(temp)"; fi; }
load() { lbl=$1; shift; if "$@" > /dev/null 2>&1; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "[FAIL $lbl] rc=$? $(date +%T)"; fi; }
vp=$(cut -d= -f2 vp9-p2-2160p60.webm.p010le.md5); hv=$(cut -d= -f2 hevc-main10-2160p60.mkv.p010le.md5)
t0=$(date +%s); last=$t0; ok=0; bad=0; it=0; maxt=0
while [ $(( $(date +%s) - t0 )) -lt $SOAK ]; do
  it=$((it + 1))
  chk vp9p2-p010 $vp env V4L2REQUEST_PIXFMT=P010 $F -i vp9-p2-2160p60.webm -pix_fmt p010le -f md5 -
  chk h265m10-p010 $hv env V4L2REQUEST_PIXFMT=P010 $F -i hevc-main10-2160p60.mkv -pix_fmt p010le -f md5 -
  chk avs2-8bit 3a3d5d7eb9a6f548042e160d9e461388 $A /tmp/m8.avs2
  chk avs2-10bit be9985dea38abffc850d73024165c990 $A /tmp/cc.avs2
  load vp9p2-afbc env V4L2REQUEST_PIXFMT=AS01 $FD -i vp9-p2-2160p60.webm -f null -
  load avs2-10bit-afbc env AVS2_NOOUT=1 AVS2_CAP=AFBC $A /tmp/cc.avs2
  for t in $(temp); do [ $t -gt $maxt ] && maxt=$t; done
  now=$(date +%s); if [ $((now - last)) -ge 300 ]; then last=$now
    echo "[t+$((now - t0))s] it=$it ok=$ok bad=$bad vdd-gpu-sys $(volt) gpu $(cat $G/cur_freq) temp $(temp) timeouts $(to)"; fi
done
echo "[soak] $(( $(date +%s) - t0 ))s iterations=$it runs ok=$ok fail=$bad max-temp $maxt vdd-gpu-sys $(volt) timeouts $(to)"
echo $og > $G/governor; echo "gpu governor restored $(cat $G/governor)"
rm -f /tmp/cc.avs2 /tmp/m8.avs2
dmesg | grep -iE 'cedrus|iommu|fault|timed out' | tail -6 | sed 's/^/[dmesg] /'
echo ROUND-DONE
