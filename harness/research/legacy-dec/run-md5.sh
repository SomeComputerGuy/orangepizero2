#!/bin/bash
# Usage: run-md5.sh <list> <outdir>
#   list lines: <tag> <path relative to kernel-check/legacy-serve> [ffmpeg input options, e.g. -f mpegvideo]
# For each stream: board HW decode (Jernej FFmpeg fork, -hwaccel v4l2request, streamed over HTTP from 10.56.0.1:8644)
# -> NV12 framemd5 via hwdownload (fails if FFmpeg fell back to SW, so a PASS proves HW decode); VE IRQ delta; host SW framemd5 with the
# same input options; compare per-frame md5 (pts ignored). Writes <outdir>/<tag>.{hw,sw}.framemd5, .err, summary.tsv.
H=$(cd "$(dirname "$0")/../../.." && pwd); SSH=$H/harness/ssh.sh; SERVE=$H/kernel-check/legacy-serve
L=$1; O=$2; mkdir -p "$O"; [ -n "$SWONLY" ] || [ -n "$RESUME" ] || : > "$O/summary.tsv"; touch "$O/summary.tsv"   # env RESUME=1: skip tags already in summary.tsv   # env SWONLY=1: host refs only
FF="-nostdin -hide_banner -loglevel warning"
OUT="-fps_mode passthrough -noautoscale -pix_fmt nv12 -f framemd5 -"
waitfree() { while $SSH -n "pgrep -x 'avs2dec|gst-launch-1.0|ffmpeg' >/dev/null"; do sleep 30; done; }
irq() { $SSH -n "awk '/1c0e000.video-codec/{print \$2+\$3+\$4+\$5}' /proc/interrupts"; }
while read -r tag rel opts; do
  [ -z "$tag" ] || [ "${tag#\#}" != "$tag" ] && continue
  url="http://10.56.0.1:8644/$rel"
  [ -s "$O/$tag.sw.framemd5" ] || ffmpeg $FF $opts -i "$SERVE/$rel" $OUT > "$O/$tag.sw.framemd5" 2> "$O/$tag.sw.err"
  [ -n "$SWONLY" ] && continue
  [ -n "$RESUME" ] && grep -q "^$tag	" "$O/summary.tsv" && continue
  waitfree; i0=$(irq)
  $SSH -n "${BFF:-/root/vp/ffmpeg} $FF -hwaccel v4l2request -hwaccel_output_format drm_prime $opts -i $url -fps_mode passthrough -noautoscale -vf hwdownload,format=nv12 -f framemd5 -" > "$O/$tag.hw.framemd5" 2> "$O/$tag.err"
  rc=$?; i1=$(irq)
  r=$(python3 -I "$H/harness/research/legacy-dec/cmp-framemd5.py" "$O/$tag.sw.framemd5" "$O/$tag.hw.framemd5")
  printf '%s\t%s\trc=%s\tirqs=%s\t%s\n' "$tag" "$rel" "$rc" "$((i1-i0))" "$r" | tee -a "$O/summary.tsv"
done < "$L"
