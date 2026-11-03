#!/bin/bash
# Round A on dbg4 (series + hidden-AFBC P010 patch + debug counters). Run on the board as root.
cd /root/vdec-streams
P=/sys/module/sunxi_cedrus/parameters
echo 504000000 > /sys/class/devfreq/1800000.gpu/min_freq; sleep 1
echo "kernel $(uname -v) ve=$(cat /sys/kernel/debug/clk/ve/clk_rate) vdd-gpu-sys=$(cat /sys/class/regulator/regulator.6/microvolts 2>/dev/null)"
F="/root/vp/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"
FD="$F -hwaccel_output_format drm_prime"
md5() { # file pixfmt v4l2fmt ref
  r=$(V4L2REQUEST_PIXFMT=$3 $F -i $1 -pix_fmt $2 -f md5 - 2>&1 | tail -1); ref=$(cut -d= -f2 $4)
  res=FAIL; [ "${r#MD5=}" = "$ref" ] && res=PASS; echo "[md5 $1 $3] $r ref=$ref $res"; }
# throughput + counters
V4L2REQUEST_PIXFMT=P010 /root/vp/perf-run.sh h265-10-p010-afbcrecon $FD -i hevc-main10-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=AS01 /root/vp/perf-run.sh h265-10-afbc $FD -i hevc-main10-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=P010 /root/vp/perf-run.sh vp9-p2-p010-afbcrecon $FD -i vp9-p2-2160p60.webm -f null -
V4L2REQUEST_PIXFMT=AS01 /root/vp/perf-run.sh vp9-p2-afbc $FD -i vp9-p2-2160p60.webm -f null -
V4L2REQUEST_PIXFMT=ST12 /root/vp/perf-run.sh h265-8-tiled $FD -i hevc-main-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=NV12 /root/vp/perf-run.sh h265-8-linear $FD -i hevc-main-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=ST12 /root/vp/perf-run.sh vp9-p0-tiled $FD -i vp9-p0-2160p60.webm -f null -
# GStreamer (generic userspace) P010 rate
/root/vp/ve-busy.sh filesrc location=hevc-main10-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! fakesink sync=false | sed 's/^/[gst h265-10] /'
/root/vp/ve-busy.sh filesrc location=vp9-p2-2160p60.webm ! matroskademux ! vp9parse ! v4l2slvp9dec ! fakesink sync=false | sed 's/^/[gst vp9-p2] /'
# knobs on P010 HEVC: rec_wr_mode bit 20; VE 624 MHz
echo $((1<<20)) > $P/dbg_mode_or
V4L2REQUEST_PIXFMT=P010 /root/vp/perf-run.sh h265-10-p010-recwr2mb $FD -i hevc-main10-2160p60.mkv -f null -
V4L2REQUEST_PIXFMT=AS01 /root/vp/perf-run.sh h265-10-afbc-recwr2mb $FD -i hevc-main10-2160p60.mkv -f null -
echo 0 > $P/dbg_mode_or
# bit-exactness
md5 hevc-main10-2160p60.mkv p010le P010 hevc-main10-2160p60.mkv.p010le.md5
md5 vp9-p2-2160p60.webm p010le P010 vp9-p2-2160p60.webm.p010le.md5
md5 hevc-main-2160p60.mkv nv12 NV12 hevc-main-2160p60.mkv.nv12.md5
md5 vp9-p0-2160p60.webm nv12 NV12 vp9-p0-2160p60.webm.nv12.md5
md5 h264-high-2160p30.mkv nv12 NV12 h264-high-2160p30.mkv.nv12.md5
echo 306000000 > /sys/class/devfreq/1800000.gpu/min_freq
dmesg | grep -iE "cedrus|iommu|fault|timed out|oom" | tail -5 | sed 's/^/[dmesg] /'
echo ROUND-A-DONE
