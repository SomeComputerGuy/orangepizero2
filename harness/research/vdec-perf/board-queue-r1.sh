#!/bin/bash
# Queue-depth round 1 (run on the board as root, image kernel, no reboot): where do the 10-bit 4K pipelines lose time?
#  A. timelines (ve-timeline.sh) for FFmpeg VP9 P2 / H.265 Main10 P010, threads auto / 1, governor schedutil / performance
#  B. GStreamer H.265 Main10: fakesink vs fakevideosink (video meta -> no copy), plus the copy decision in the log
#  C. MBUS knobs (devmem, restored at the end): IOMMU port 25 bandwidth limit off; VE ports 4/26 priority + QoS HIGHEST
#  D. AVS2 cctv4k 10-bit P010 timeline (avs2dec AVS2_NOOUT=1) with and without C; frame 291 dump for the davs2 compare
cd /root/vdec-streams || exit 1
V=/root/vp; DM="python3 -I $V/devmem.py"; TL=$V/ve-timeline.sh
F="$V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request -hwaccel_output_format drm_prime"
U=http://10.56.0.1:8643/avs2
echo "kernel $(uname -rv) ve=$(cat /sys/kernel/debug/clk/ve/clk_rate) gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) cpu=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)"
echo "mbus tmr=$($DM 0x047FA00C) bwcr=$($DM 0x047FA200)"
for p in 0 1 2 3 4 5 6 8 11 14 16 21 22 25 26 37 38 39 40; do
  a=$((0x047FA210 + p * 16)); echo "mbus port $p cfg0=$($DM $a) cfg1=$($DM $((a + 4)))"; done
echo "iommu gating=$($DM 0x030F0040) wbuf=$($DM 0x030F0044) ooo=$($DM 0x030F0048) 4kb=$($DM 0x030F004C) tlb=$($DM 0x030F0060) pf=$($DM 0x030F0070)"
ff() { lbl=$1; shift; echo "[$lbl] $($TL "$@" | tr '\n' ' ')"; }
round() { # tag
  ff "$1 vp9p2-p010" env V4L2REQUEST_PIXFMT=P010 $F -i vp9-p2-2160p60.webm -f null -
  ff "$1 h265m10-p010" env V4L2REQUEST_PIXFMT=P010 $F -i hevc-main10-2160p60.mkv -f null -
}
echo "== A: FFmpeg"
round base
ff "base vp9p2-p010 threads1" env V4L2REQUEST_PIXFMT=P010 $F -threads 1 -i vp9-p2-2160p60.webm -f null -
ff "base h265m10-p010 threads1" env V4L2REQUEST_PIXFMT=P010 $F -threads 1 -i hevc-main10-2160p60.mkv -f null -
ff "base vp9p2-afbc" env V4L2REQUEST_PIXFMT=AS01 $F -i vp9-p2-2160p60.webm -f null -
g0=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
round perf
echo $g0 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo "== B: GStreamer"
G="gst-launch-1.0 -q filesrc location=hevc-main10-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec"
ff "gst h265m10 fakesink" $G ! fakesink sync=false
ff "gst h265m10 fakevideosink" $G ! fakevideosink sync=false
ff "gst vp9p2 fakevideosink" gst-launch-1.0 -q filesrc location=vp9-p2-2160p60.webm ! matroskademux ! vp9parse ! v4l2slvp9dec ! fakevideosink sync=false
GST_DEBUG='v4l2codecs-h265dec:5,v4l2codecs-decoder:4' timeout 20 $G ! fakesink sync=false 2>&1 | grep -iE 'copy|pool|min|allocat|render|delay|buffers' | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-220 | sort | uniq -c | sort -rn | head -15 | sed 's/^/[gst-dbg] /'
echo "== C: MBUS knobs"
P25=$((0x047FA210 + 25 * 16)); P4=$((0x047FA210 + 4 * 16)); P26=$((0x047FA210 + 26 * 16))
o25=$($DM $P25); o4=$($DM $P4); o26=$($DM $P26)
$DM $P25 $(( o25 & ~1 )); echo "port25 cfg0 $o25 -> $($DM $P25)"
round mbus25
$DM $P4 $(( o4 | 0xe )); $DM $P26 $(( o26 | 0xe )); echo "port4 $o4 -> $($DM $P4) port26 $o26 -> $($DM $P26)"
round mbus25+ve
$DM $P25 $o25
round mbusve
echo "== D: AVS2"
A=/root/avs2/avs2dec
av() { lbl=$1; shift; echo "[$lbl] $($TL env "$@" $A /tmp/cc.avs2 | tr '\n' ' ') $(tail -1 /tmp/vtl.out)"; }
curl -sS $U/cctv4k-10bit.avs2 -o /tmp/cc.avs2; ls -l /tmp/cc.avs2
av "avs2 p010 mbusve" AVS2_NOOUT=1
$DM $P4 $o4; $DM $P26 $o26
av "avs2 p010 base" AVS2_NOOUT=1
$DM $P25 $(( o25 & ~1 )); $DM $P4 $(( o4 | 0xe )); $DM $P26 $(( o26 | 0xe ))
av "avs2 p010 mbus25+ve" AVS2_NOOUT=1
$DM $P25 $o25; $DM $P4 $o4; $DM $P26 $o26
echo "restored port25=$($DM $P25) port4=$($DM $P4) port26=$($DM $P26)"
Q=/root/avs2/avs2dec-q; curl -sS $U/avs2dec-q -o $Q; chmod +x $Q
avq() { lbl=$1; shift; echo "[$lbl] $($TL env "$@" $Q /tmp/cc.avs2 | tr '\n' ' ') $(tail -1 /tmp/vtl.out)"; }
avq "avs2q depth2 p010 base" AVS2_NOOUT=1
avq "avs2q depth3 p010 base" AVS2_NOOUT=1 AVS2_DEPTH=3
avq "avs2q depth1 p010 base" AVS2_NOOUT=1 AVS2_DEPTH=1
$DM $P25 $(( o25 & ~1 )); $DM $P4 $(( o4 | 0xe )); $DM $P26 $(( o26 | 0xe ))
avq "avs2q depth2 p010 mbus25+ve" AVS2_NOOUT=1
$DM $P25 $o25; $DM $P4 $o4; $DM $P26 $o26
s0=$(date +%s); r=$(timeout 900 $Q /tmp/cc.avs2 2>/dev/null | tail -1); echo "[avs2q md5 cctv4k p010] $r ($(( $(date +%s) - s0 ))s) want be9985dea38abffc850d73024165c990"
for n in main-2160p-ra main-1080p-ra; do r=$(curl -sS $U/$n.avs2 | timeout 600 $Q - 2>/dev/null | tail -1); echo "[avs2q md5 $n] $r"; done
AVS2_DUMP=291 timeout 600 $A -f -o /tmp/f291.yuv /tmp/cc.avs2 > /tmp/f291.txt 2>&1; echo "dump rc=$? $(tail -1 /tmp/f291.txt) $(ls -l /tmp/f291.yuv)"
echo "== E: VE 624 MHz (pll-ve N+1 step via devmem, VE idle; restored after)"
PV=0x03001058; o=$($DM $PV); n=$(( (o >> 8) & 0xff )); m=$(( (o >> 1) & 1 )); pd=$(( o & 1 )); r=$(( 24 * n / (m + 1) / (pd + 1) ))
echo "pll-ve $o n=$n m=$m p=$pd -> ${r} MHz, ve clk reg $($DM 0x03001690)"
if [ $r = 600 ]; then
  n2=$(( n * 624 / 600 )); $DM $PV $(( (o & ~0xff00) | (n2 << 8) )); sleep 0.2
  v=$($DM $PV); echo "pll-ve now $v (n=$(( (v >> 8) & 0xff )) lock=$(( (v >> 28) & 1 ))) = $(( 24 * n2 / (m + 1) / (pd + 1) )) MHz"
  round ve624
  avq "avs2q depth2 p010 ve624" AVS2_NOOUT=1
  for t in "vp9-p2-2160p60.webm P010" "hevc-main10-2160p60.mkv P010"; do set -- $t
    r=$(V4L2REQUEST_PIXFMT=$2 $V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request -i $1 -pix_fmt p010le -f md5 - 2>&1 | tail -1)
    echo "[ve624 md5 $1] $r ref=$(cut -d= -f2 $1.p010le.md5)"; done
  r=$(timeout 900 $Q /tmp/cc.avs2 2>/dev/null | tail -1); echo "[ve624 avs2q md5 cctv4k] $r"
  $DM $PV $o; sleep 0.2; echo "pll-ve restored $($DM $PV)"
fi
rm -f /tmp/cc.avs2
dmesg | grep -iE 'cedrus|iommu|fault|timed out|oom' | tail -5 | sed 's/^/[dmesg] /'
echo ROUND-DONE
