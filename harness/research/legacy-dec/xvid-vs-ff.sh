#!/bin/bash
# Usage: xvid-vs-ff.sh <outdir> <stream>...   host only: FFmpeg SW (simple IDCT) vs xvidcore 1.3.7 (plain C) on raw MPEG-4 Part 2
# elementary streams, I420 display order. Per stream: frame counts, frames differing > 4, max |diff|, min Y PSNR, worst frame.
H=$(cd "$(dirname "$0")/../../.." && pwd); X=$H/kernel-check/xviddec-tool/xviddec; T=$H/kernel-check/legacy-tmp
O=$1; shift; mkdir -p "$O" "$T"
for f in "$@"; do
  n=$(basename "${f%.*}"); wh=$(ffprobe -v error -f m4v -show_entries stream=width,height -of csv=p=0 "$f" | head -1 | tr , ' ')
  ffmpeg -nostdin -loglevel error -f m4v -i "$f" -fps_mode passthrough -pix_fmt yuv420p -f rawvideo - > $T/$n.ff.yuv 2>"$O/$n.ff.err"
  $X "$f" > $T/$n.xv.yuv 2>"$O/$n.xv.err"
  printf '%s\t%s\t%s\n' "$n" "${wh/ /x}" "$(python3 -I "$H/harness/research/legacy-dec/cmp-i420.py" $wh $T/$n.ff.yuv $T/$n.xv.yuv "$O/$n.perframe")"
  rm -f $T/$n.ff.yuv $T/$n.xv.yuv
done
