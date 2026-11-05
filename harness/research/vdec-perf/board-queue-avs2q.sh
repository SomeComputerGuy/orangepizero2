#!/bin/bash
# Runner job avs2q: FFmpeg AVS2 request queueing (patches/ffmpeg 0313, output hold-back = two decode requests in flight).
# Binary ffmpeg-avs2q = dev build (harness/ffmpeg/dev-build.sh) of the shared series head + 0313, sha256 01a23cd93c89daf9...
# 1. VE timeline of the 4K Main10 stream: the starved gaps (request not yet queued at IRQ time) must stay at the aq1 level
#    (1 per run; 151 without the hold-back). The low_delay run turns the hold-back off and is data only.
# 2. Whole-stream md5 of cctv4k Main10 (P010 -> yuv420p10le) and of the 17 8-bit streams (yuv420p, output order) against
#    refs-8bit.md5 (PKU md5.txt / xavs2 reconstruction). Per-frame md5 lists in /root/ffq/out. No VE timeout anywhere.
set -o pipefail
cd /root || exit 1
D=/root/ffq; U=http://10.56.0.1:8643/avs2; TL=/root/vp/ve-timeline.sh; mkdir -p $D/out; rm -f $D/out/*
curl -sS --fail $U/ffmpeg-avs2q -o $D/ffmpeg && chmod +x $D/ffmpeg || { echo "download failed: ffmpeg-avs2q"; exit 1; }
curl -sS --fail $U/refs-8bit.md5 -o $D/refs.md5 || { echo "download failed: refs-8bit.md5"; exit 1; }
curl -sS --fail $U/cctv4k-10bit.avs2 -o /dev/shm/c.avs2 || { echo "download failed: cctv4k-10bit.avs2"; exit 1; }
to() { dmesg | grep -c "timed out"; }
echo "kernel $(uname -rv) clk $(cat /sys/kernel/debug/clk/ve/clk_rate) timeouts $(to)"
echo "[binary] sha256 $(sha256sum $D/ffmpeg | cut -c1-16) avs2-decoder $($D/ffmpeg -hide_banner -decoders 2>/dev/null | grep -c ' avs2 ')"
F="$D/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"
FB="-hide_banner -nostats -loglevel info -benchmark -hwaccel v4l2request -hwaccel_output_format drm_prime"
tl() { lbl=$1; shift; echo "[$lbl] $($TL "$@" | tr '\n' ' ') $(grep -o 'rtime=[0-9.]*s' /tmp/vtl.out | tail -1)"; }
echo "== VE timelines (ve-timeline.sh): holdback = 0313 on, lowdelay = -flags low_delay (hold-back off, data only)"
for rep in 1 2; do tl "gaps cctv4k-10bit holdback r$rep" $D/ffmpeg $FB -i /dev/shm/c.avs2 -f null -; done
tl "gaps cctv4k-10bit lowdelay r1" $D/ffmpeg $FB -flags low_delay -i /dev/shm/c.avs2 -f null -
echo "== md5 (hold-back on)"
t0=$(to); m=$(timeout 900 $F -i /dev/shm/c.avs2 -fps_mode passthrough -pix_fmt yuv420p10le -f md5 - 2>$D/out/cctv4k-10bit.err | tail -1); rc=$?
res=FAIL; [ "${m#MD5=}" = be9985dea38abffc850d73024165c990 ] && res=PASS
echo "[md5 cctv4k-10bit] $res ${m#MD5=} ref=be9985dea38abffc850d73024165c990 rc=$rc new-timeouts $(( $(to) - t0 )) errors $(grep -ci error $D/out/cctv4k-10bit.err)"
rm -f /dev/shm/c.avs2
while read -r s ref; do
  [ -n "$s" ] || continue
  curl -sS --fail $U/$s.avs2 -o /dev/shm/in.avs2 || { echo "[md5 $s] FAIL download failed"; continue; }
  t0=$(to)
  m=$(timeout 600 $F -i /dev/shm/in.avs2 -fps_mode passthrough -pix_fmt yuv420p -f md5 - 2>$D/out/$s.err | tail -1); rc=$?
  $F -i /dev/shm/in.avs2 -fps_mode passthrough -pix_fmt yuv420p -f framemd5 - > $D/out/$s.framemd5 2>>$D/out/$s.err
  n=$(grep -c '^0,' $D/out/$s.framemd5)
  res=FAIL; [ "${m#MD5=}" = "$ref" ] && res=PASS
  echo "[md5 $s] $res ${m#MD5=} ref=$ref rc=$rc frames=$n new-timeouts $(( $(to) - t0 )) errors $(grep -ci error $D/out/$s.err)"
done < $D/refs.md5
rm -f /dev/shm/in.avs2 /tmp/vtl.trace
dmesg | grep -iE 'cedrus|iommu|fault|timed out' | tail -5 | sed 's/^/[dmesg] /'
echo "timeouts $(to)"; echo ROUND-DONE
