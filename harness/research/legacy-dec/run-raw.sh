#!/bin/bash
# Usage: run-raw.sh <list> <outdir>
# For codecs whose IDCT is not normative (MPEG-1/2, MPEG-4 Part 2, H.263, Spark; IEEE 1180 accuracy only):
# 1. board HW decode (FFmpeg fork, v4l2request, hwdownload -> fails on SW fallback), raw NV12 streamed to the host;
# 2. host SW decodes with FFmpeg IDCTs simple (default), int (jref), faani (float AAN);
# 3. cmp-raw.py: HW vs each (exact frames, max|diff|, Y PSNR), plus the envelope simple-vs-int (how far two
#    IEEE-1180 IDCTs drift apart on this stream). Pass = HW within the envelope of the closest reference.
H=$(cd "$(dirname "$0")/../../.." && pwd); SSH=$H/harness/ssh.sh; SERVE=$H/kernel-check/legacy-serve; C="$H/harness/research/legacy-dec/cmp-raw.py"
L=$1; O=$2; mkdir -p "$O"; S="$O/raw.tsv"; : > "$S"
FF="-nostdin -hide_banner -loglevel warning"; NF=${FRAMES:+-frames:v $FRAMES}   # env FRAMES=n caps decoded frames
waitfree() { while $SSH -n "pgrep -x 'avs2dec|gst-launch-1.0|ffmpeg' >/dev/null"; do sleep 30; done; }
irq() { $SSH -n "awk '/1c0e000.video-codec/{print \$2+\$3+\$4+\$5}' /proc/interrupts"; }
sw() { ffmpeg $FF -idct $1 $opts -i "$SERVE/$rel" -fps_mode passthrough $NF -pix_fmt nv12 -f rawvideo - 2>>"$O/$tag.raw-sw.err"; }
while read -r tag rel opts; do
  [ -z "$tag" ] || [ "${tag#\#}" != "$tag" ] && continue
  wh=$(ffprobe -v error $opts -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$SERVE/$rel" | head -1 | tr , ' ')
  waitfree; i0=$(irq)
  $SSH -n "/root/vp/ffmpeg $FF -hwaccel v4l2request -hwaccel_output_format drm_prime $opts -i http://10.56.0.1:8644/$rel -fps_mode passthrough $NF -vf hwdownload,format=nv12 -f rawvideo -" > "$O/$tag.hw.nv12" 2>"$O/$tag.raw-hw.err"
  rc=$?; i1=$(irq)
  line="$tag\t$rel\t${wh/ /x}\trc=$rc\tirqs=$((i1-i0))"
  for i in simple int faani; do line="$line\t$i: $(PERFRAME="$O/$tag.$i.perframe" python3 -I $C $wh <(sw $i) "$O/$tag.hw.nv12")"; done
  line="$line\tenvelope(simple~int): $(python3 -I $C $wh <(sw simple) <(sw int))"
  printf "$line\n" | tee -a "$S"
  rm -f "$O/$tag.hw.nv12"
done < "$L"
