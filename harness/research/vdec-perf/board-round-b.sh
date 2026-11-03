#!/bin/bash
# Round B: same kernel booted with iommu.passthrough=1 cma=320M (VE behind an identity domain:
# IOMMU disabled, buffers physically contiguous from CMA). 8-bit linear vs tiled A/B + P010.
cd /root/vdec-streams
echo 504000000 > /sys/class/devfreq/1800000.gpu/min_freq; sleep 1
echo "cmdline: $(cat /proc/cmdline | grep -o 'iommu[^ ]*\|cma=[^ ]*' | tr '\n' ' ')"
dmesg | grep -iE "default domain|cma: Reserved" | sed 's/^/[dmesg] /'
grep -i cma /proc/meminfo | tr '\n' ' '; echo
F="/root/vp/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"
FD="$F -hwaccel_output_format drm_prime"
V4L2REQUEST_PIXFMT=ST12 /root/vp/perf-run.sh pt-h265-8-tiled $FD -i hevc-main-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=NV12 /root/vp/perf-run.sh pt-h265-8-linear $FD -i hevc-main-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=NV12 /root/vp/perf-run.sh pt-h264-8-linear $FD -i h264-high-2160p30.mkv -f null -
V4L2REQUEST_PIXFMT=ST12 /root/vp/perf-run.sh pt-h264-8-tiled $FD -i h264-high-2160p30.mkv -f null -
V4L2REQUEST_PIXFMT=P010 /root/vp/perf-run.sh pt-h265-10-p010 $FD -i hevc-main10-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=AS01 /root/vp/perf-run.sh pt-h265-10-afbc $FD -i hevc-main10-2160p60.mkv -f null -
r=$(V4L2REQUEST_PIXFMT=NV12 $F -i hevc-main-2160p60.mkv -pix_fmt nv12 -f md5 - 2>&1 | tail -1); echo "[md5 pt h265-8 NV12] $r ref=$(cut -d= -f2 hevc-main-2160p60.mkv.nv12.md5)"
grep -i cma /proc/meminfo | tr '\n' ' '; echo
echo 306000000 > /sys/class/devfreq/1800000.gpu/min_freq
dmesg | grep -iE "cedrus|iommu|fault|timed out|oom|cma" | tail -6 | sed 's/^/[dmesg] /'
echo ROUND-B-DONE
