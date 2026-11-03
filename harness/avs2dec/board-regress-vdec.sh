#!/bin/bash
# Board: H.265/VP9/H.264 bit-exactness regression on the test kernel (from vdec-perf/board-round-a.sh),
# plus the native AFBC10 rate.  Streams in /root/vdec-streams (already on the board's SD card).
cd /root/vdec-streams
F="/root/vp/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"
md5() { # file pixfmt v4l2fmt ref
  r=$(V4L2REQUEST_PIXFMT=$3 $F -i $1 -pix_fmt $2 -f md5 - 2>&1 | tail -1); ref=$(cut -d= -f2 $4)
  res=FAIL; [ "${r#MD5=}" = "$ref" ] && res=PASS; echo "[md5 $1 $3] $r ref=$ref $res"; }
echo "kernel $(uname -v)"
md5 hevc-main10-2160p60.mkv p010le P010 hevc-main10-2160p60.mkv.p010le.md5
md5 vp9-p2-2160p60.webm p010le P010 vp9-p2-2160p60.webm.p010le.md5
md5 hevc-main-2160p60.mkv nv12 NV12 hevc-main-2160p60.mkv.nv12.md5
md5 vp9-p0-2160p60.webm nv12 NV12 vp9-p0-2160p60.webm.nv12.md5
md5 h264-high-2160p30.mkv nv12 NV12 h264-high-2160p30.mkv.nv12.md5
FD="$F -hwaccel_output_format drm_prime"
V4L2REQUEST_PIXFMT=P010 /root/vp/ve-busy-cmd.sh $FD -i hevc-main10-2160p60.mkv -f null - | sed 's/^/[rate h265-10 P010] /'
V4L2REQUEST_PIXFMT=AS01 /root/vp/ve-busy-cmd.sh $FD -i hevc-main10-2160p60.mkv -f null - | sed 's/^/[rate h265-10 AFBC] /'
V4L2REQUEST_PIXFMT=P010 /root/vp/ve-busy-cmd.sh $FD -i vp9-p2-2160p60.webm -f null - | sed 's/^/[rate vp9-p2 P010] /'
dmesg | grep -iE "cedrus|iommu|fault|timed out|oom" | tail -5 | sed 's/^/[dmesg] /'
echo REGRESS-DONE
