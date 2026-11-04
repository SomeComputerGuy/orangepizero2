#!/bin/bash
# Usage: mp4dbg-tests.sh <outdir> <dbg-hex>...   (test kernel Image.mp4dbg1 with /sys/module/sunxi_cedrus/parameters/mpeg4_dbg)
# Per dbg value: HW decode of the probe streams (NV12), compared on the host with the reference.
#   xvid-gmc frames 0-30   (ref: FFmpeg SW)            -> MBs 0-6 of frame 24 and frames 23-29
#   a1ge2_asp_L4 frames 0-2 (interlaced qpel P, ref SW) -> chroma errors
#   vcon_ge_1_asp_l4 frames 0-5 (interlaced B, ref SW)  -> direct-mode luma errors
H=$(cd "$(dirname "$0")/../../.." && pwd); SSH=$H/harness/ssh.sh; SERVE=$H/kernel-check/legacy-serve; O=$1; shift; mkdir -p "$O"
FF="-nostdin -hide_banner -loglevel error"; BFF=${BFF:-/root/vp/ffmpeg-m1}
P=${PROBES:-"gen/xvid-gmc-1080p60.avi:31::1920:1080 mpeg4asp/a1ge2_asp_L4.bits:3:-f_m4v:1920:1088 mpeg4asp/vcon_ge_1_asp_l4.bits:6:-f_m4v:1920:1088 mpeg4asp/a1ge9_asp_L1.bits:20:-f_m4v:352:288"}
for p in $P; do IFS=: read rel n opts w h <<< "$p"; opts=${opts//_/ }; t=$(basename "${rel%.*}")
  [ -s "$O/$t.sw.nv12" ] || ffmpeg $FF $opts -i "$SERVE/$rel" -fps_mode passthrough -frames:v $n -pix_fmt nv12 -f rawvideo - > "$O/$t.sw.nv12"; done
for d in "$@"; do
  $SSH -n "echo $((d)) > /sys/module/sunxi_cedrus/parameters/mpeg4_dbg; cat /sys/module/sunxi_cedrus/parameters/mpeg4_dbg" > /dev/null
  for p in $P; do IFS=: read rel n opts w h <<< "$p"; opts=${opts//_/ }; t=$(basename "${rel%.*}")
    $SSH -n "$BFF $FF -hwaccel v4l2request -hwaccel_output_format drm_prime $opts -i http://10.56.0.1:8644/$rel -fps_mode passthrough -frames:v $n -vf hwdownload,format=nv12 -f rawvideo -" > "$O/$t.hw.$d.nv12"
    printf '%s\t%s\t%s\n' "$d" "$t" "$(python3 -I "$(dirname "$0")/mb-err.py" $w $h "$O/$t.sw.nv12" "$O/$t.hw.$d.nv12")" | tee -a "$O/summary.tsv"
    rm -f "$O/$t.hw.$d.nv12"
  done
done
$SSH -n "echo 0 > /sys/module/sunxi_cedrus/parameters/mpeg4_dbg"
