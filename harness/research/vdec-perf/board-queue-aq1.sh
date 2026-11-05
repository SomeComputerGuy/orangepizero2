#!/bin/bash
# Round aq1 (board, cumulative kernel c3): FFmpeg AVS2 request queue depth. The native avs2 decoder holds its output back
# by one picture so that the hwaccel's next request is queued before the application waits on the previous one
# (ffmpeg-avs2q = patches/ffmpeg 0307+0308 + the hold-back). A/B in one binary: -flags low_delay disables the hold-back
# (= the old behaviour); ffmpeg-avs2 (desktop build of opiz2/avs2, unpatched) is the third point.
# Then md5: 4K 8-bit main-2160p-ra, 4K 10-bit cctv4k (P010), and the 17 8-bit reference streams (framemd5 + md5 + rate).
cd /root/vdec-streams || exit 1
V=/root/vp; TL=$V/ve-timeline.sh; U=http://10.56.0.1:8643/avs2; D=/root/ffq; mkdir -p $D/out
curl -sS $U/ffmpeg-avs2q -o $D/ffmpeg; chmod +x $D/ffmpeg
curl -sS $U/ffmpeg-avs2 -o $D/ffmpeg-old; chmod +x $D/ffmpeg-old
for s in cctv4k-10bit main-2160p-ra ParkScene_1920x1080_24_ra; do curl -sS $U/$s.avs2 -o /dev/shm/$s.avs2; done
echo "kernel $(uname -rv) clk $(cat /sys/kernel/debug/clk/ve/clk_rate) uptime $(cut -d" " -f1 /proc/uptime) cedrus-timeouts-so-far $(dmesg | grep -c "timed out")"
sha256sum $D/ffmpeg $D/ffmpeg-old | cut -c1-16,65- | tr '\n' ' '; echo
FB="-hide_banner -nostats -loglevel info -benchmark -hwaccel v4l2request -hwaccel_output_format drm_prime"
ff() { lbl=$1; shift; echo "[$lbl] $($TL "$@" | tr '\n' ' ') $(grep -o 'rtime=[0-9.]*s' /tmp/vtl.out | tail -1)"; }
echo "== timelines (ve-timeline.sh; new = hold-back, lowdelay = -flags low_delay = depth 1, old = unpatched binary)"
for rep in 1 2; do
  for s in cctv4k-10bit main-2160p-ra ParkScene_1920x1080_24_ra; do
    ff "$s new r$rep" $D/ffmpeg $FB -i /dev/shm/$s.avs2 -f null -
    ff "$s lowdelay r$rep" $D/ffmpeg $FB -flags low_delay -i /dev/shm/$s.avs2 -f null -
    ff "$s old r$rep" $D/ffmpeg-old $FB -i /dev/shm/$s.avs2 -f null -
  done
done
echo "== md5 (new binary, hold-back on)"
F="$D/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"
r=$($F -i /dev/shm/main-2160p-ra.avs2 -fps_mode passthrough -pix_fmt yuv420p -f md5 - 2>&1 | tail -1); res=FAIL
[ "${r#MD5=}" = 3a3d5d7eb9a6f548042e160d9e461388 ] && res=PASS; echo "[md5 avs2-8bit-2160p-ra] $res ${r#MD5=}"
r=$(timeout 900 $F -i /dev/shm/cctv4k-10bit.avs2 -fps_mode passthrough -pix_fmt yuv420p10le -f md5 - 2>&1 | tail -1); res=FAIL
[ "${r#MD5=}" = be9985dea38abffc850d73024165c990 ] && res=PASS; echo "[md5 avs2-10bit-cctv4k P010] $res ${r#MD5=}"
r=$($F -flags low_delay -i /dev/shm/main-2160p-ra.avs2 -fps_mode passthrough -pix_fmt yuv420p -f md5 - 2>&1 | tail -1); res=FAIL
[ "${r#MD5=}" = 3a3d5d7eb9a6f548042e160d9e461388 ] && res=PASS; echo "[md5 avs2-8bit-2160p-ra lowdelay] $res ${r#MD5=}"
echo "== 17 8-bit streams (board-avs2-ffmpeg.sh scheme: framemd5 + md5 + rtime), outputs in $D/out"
for s in BasketballPass_416x240_50_ai BasketballPass_416x240_50_ld BasketballPass_416x240_50_ra \
         BQMall_832x480_60_ra BQSquare_416x240_60_ai BQSquare_416x240_60_ld BQSquare_416x240_60_ra \
         ParkScene_1920x1080_24_ra PartyScene_832x480_50_ra RaceHorses_416x240_30_ai \
         RaceHorses_416x240_30_ld RaceHorses_416x240_30_ra \
         main-1080p-ra main-1080p-ldp main-1080p-tid main-1080p-lf main-2160p-ra; do
  curl -sS -o /dev/shm/in.avs2 "$U/$s.avs2" || { echo "$s: download failed"; continue; }
  $F -i /dev/shm/in.avs2 -fps_mode passthrough -pix_fmt yuv420p -f framemd5 - > "$D/out/$s.framemd5" 2> "$D/out/$s.err"; rc=$?
  m=$($F -i /dev/shm/in.avs2 -fps_mode passthrough -pix_fmt yuv420p -f md5 - 2>> "$D/out/$s.err" | tail -1)
  b=$($D/ffmpeg -hide_banner -nostats -loglevel info -benchmark -hwaccel v4l2request -hwaccel_output_format drm_prime \
      -i /dev/shm/in.avs2 -f null - 2>&1 | grep -o 'rtime=[0-9.]*s' | tail -1)
  n=$(grep -c '^0,' "$D/out/$s.framemd5")
  echo "$s rc=$rc frames=$n $m $b"
done
rm -f /dev/shm/in.avs2 /dev/shm/cctv4k-10bit.avs2 /dev/shm/main-2160p-ra.avs2 /dev/shm/ParkScene_1920x1080_24_ra.avs2
dmesg | grep -iE 'cedrus|iommu|fault|timed out' | tail -5 | sed 's/^/[dmesg] /'
echo "uptime $(cut -d" " -f1 /proc/uptime) cedrus-timeouts $(dmesg | grep -c "timed out")"
echo ROUND-DONE
