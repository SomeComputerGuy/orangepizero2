#!/bin/bash
# Usage: run-fps.sh <list> <log>  -- VE-bound fps (ftrace cedrus_device_run->cedrus_irq, /root/vp/ve-busy-cmd.sh)
# and pipeline fps (wall), FFmpeg fork -hwaccel v4l2request, drm_prime frames to null, stream over HTTP.
# Refuses to run if ftrace is in use by someone else (current_tracer != nop) or another VE client is running.
H=$(cd "$(dirname "$0")/../../.." && pwd); SSH=$H/harness/ssh.sh
while read -r tag rel opts; do
  [ -z "$tag" ] || [ "${tag#\#}" != "$tag" ] && continue
  r=$($SSH -n "[ \"\$(cat /sys/kernel/tracing/current_tracer)\" = nop ] || { echo BUSY-ftrace; exit; }; pgrep -x 'avs2dec|gst-launch-1.0|ffmpeg' >/dev/null && { echo BUSY-ve; exit; }; /root/vp/ve-busy-cmd.sh /root/vp/ffmpeg -nostdin -hide_banner -loglevel error -hwaccel v4l2request -hwaccel_output_format drm_prime $opts -i http://10.56.0.1:8644/$rel -f null -")
  printf '%s\t%s\t%s\n' "$tag" "$rel" "$r" | tee -a "$2"
done < "$1"
