#!/bin/bash
# Board side of runner job iommu-faults: reproduce the "Page fault for 0xfff00000 (master -1, dir rd)" trigger and
# count the IOMMU page fault lines it produces on the running kernel.
# Trigger 1: force the HDMI connector on (no monitor attached, 1024x768 fallback mode) so the DE scans out the fbcon
#            framebuffer; on an unfixed kernel the first scanout frame logs the fault within a second.
# Trigger 2: an H.264 4K decode through cedrus three times; its buffer frees flush the whole TLB while the display keeps
#            scanning out, which re-triggers the prefetch walk (unfixed kernel: more fault lines).
# Output lines are mechanical ([scanout] ... faults-new N, [decode] ... faults-new N); ends with ROUND-DONE.
set -o pipefail
cd /root || exit 1
U64=http://10.56.0.1:8644; U63=http://10.56.0.1:8643
pf() { dmesg | grep -c 'Page fault'; }
echo "kernel $(uname -rv) faults-at-start $(pf)"
C=$(ls /sys/class/drm/card*-HDMI-A-1/status 2>/dev/null | head -1)
[ -n "$C" ] || { echo "[connector] no HDMI connector in sysfs"; echo ROUND-DONE; exit 0; }
echo "[connector] $C before: $(cat $C) fb0 $(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null) bpp $(cat /sys/class/graphics/fb0/bits_per_pixel 2>/dev/null)"
b=$(pf); echo on > $C; sleep 4
echo "[scanout] status $(cat $C) enabled $(cat ${C%/status}/enabled) mode $(head -1 ${C%/status}/modes) faults-new $(( $(pf) - b ))"
# decode step (data on the stock kernel, must be 0 on the fixed one)
mkdir -p /root/iq; rm -f /dev/shm/in.mkv
if curl -sS --fail $U63/avs2/ffmpeg-avs2q -o /root/iq/ffmpeg && chmod +x /root/iq/ffmpeg && curl -sS --fail $U64/vdec/h264-high-2160p30.mkv -o /dev/shm/in.mkv; then
  b=$(pf); rcs=""
  for i in 1 2 3; do timeout 300 /root/iq/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request -i /dev/shm/in.mkv -f null - 2>/root/iq/dec$i.err; rcs="$rcs rc=$?"; sleep 2; done
  echo "[decode] h264-high-2160p30 x3$rcs faults-new $(( $(pf) - b )) timeouts $(dmesg | grep -c 'timed out')"
else
  echo "[decode] download failed (ffmpeg-avs2q from $U63/avs2 or h264-high-2160p30.mkv from $U64/vdec)"
fi
rm -f /dev/shm/in.mkv
dmesg | grep -iE 'iommu|Page fault' | tail -12 | sed 's/^/[dmesg] /'
echo detect > $C; sleep 2
echo "[connector] after: $(cat $C) faults-at-end $(pf)"
echo ROUND-DONE
