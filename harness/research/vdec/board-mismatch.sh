#!/bin/bash
# Repeat the 8-bit H.265 4K bit-exact run, dumping mismatching frames (REF = host ffmpeg nv12 framemd5).
cd /root/vdec-streams; rm -f /root/vdec-out/bad-*.raw
for r in 1 2 3; do
	mkdir -p /root/vdec-out/mm$r
	gst-launch-1.0 -q filesrc location=hevc-main-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! video/x-raw,format=NV12 ! fdsink fd=1 2>/dev/null | REF=hevc-main-2160p60.mkv.nv12.framemd5 python3 /root/framemd5.py 3840 2160 /root/vdec-out/mm$r/list 1
	mv /root/vdec-out/bad-*.raw /root/vdec-out/mm$r/ 2>/dev/null; ls /root/vdec-out/mm$r
	grep MemAvailable /proc/meminfo
done
echo MISMATCH-DONE
