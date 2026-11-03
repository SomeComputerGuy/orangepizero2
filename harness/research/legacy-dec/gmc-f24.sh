#!/bin/bash
# Usage: gmc-f24.sh <outdir>   board HW decode of gen/xvid-gmc-1080p60.avi frames 0-30 (NV12), then gmc-f24.py:
# per MB of row 0 (cols 0-10) in display frame 24 (S-VOP): |HW-SW|, |HW-pred|, |SW-pred|, pred = display frame 22 (its
# forward reference P-VOP) shifted down 2 px (the warp there: dy = 2.00-2.01 px, dx < 0.05 px). HW ~ pred while SW far
# from pred = residual of the coded GMC MBs lost; HW far from both = prediction wrong.
H=$(cd "$(dirname "$0")/../../.." && pwd); SSH=$H/harness/ssh.sh; SERVE=$H/kernel-check/legacy-serve; O=$1; mkdir -p "$O"
FF="-nostdin -hide_banner -loglevel warning"; rel=gen/xvid-gmc-1080p60.avi
$SSH -n "${BFF:-/root/vp/ffmpeg} $FF -hwaccel v4l2request -hwaccel_output_format drm_prime -i http://10.56.0.1:8644/$rel -fps_mode passthrough -frames:v 31 -vf hwdownload,format=nv12 -f rawvideo -" > "$O/f24.hw.nv12" 2>"$O/f24.hw.err"
ffmpeg $FF -i "$SERVE/$rel" -fps_mode passthrough -frames:v 31 -pix_fmt nv12 -f rawvideo - > "$O/f24.sw.nv12"
python3 -I "$(dirname "$0")/gmc-f24.py" "$O/f24.hw.nv12" "$O/f24.sw.nv12" | tee "$O/f24.txt"
