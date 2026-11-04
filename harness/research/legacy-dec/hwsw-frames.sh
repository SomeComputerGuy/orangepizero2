#!/bin/bash
# Usage: hwsw-frames.sh <W> <H> <rel path under legacy-serve> [ffmpeg input opts]... -> bad frames (mb-frames.py) of board HW vs host SW
H=$(cd "$(dirname "$0")/../../.." && pwd); SSH=$H/harness/ssh.sh; SERVE=$H/kernel-check/legacy-serve; W=$1 Hh=$2 rel=$3; shift 3
T=$(mktemp -d /tmp/hwsw.XXXX); FF="-nostdin -hide_banner -loglevel error"
ffmpeg $FF "$@" -i "$SERVE/$rel" -fps_mode passthrough -pix_fmt nv12 -f rawvideo $T/sw.nv12
$SSH -n "${BFF:-/root/vp/ffmpeg-m1} $FF -hwaccel v4l2request -hwaccel_output_format drm_prime $* -i http://10.56.0.1:8644/$rel -fps_mode passthrough -vf hwdownload,format=nv12 -f rawvideo -" > $T/hw.nv12
python3 -I "$(dirname "$0")/mb-frames.py" $W $Hh $T/sw.nv12 $T/hw.nv12; rm -rf $T
