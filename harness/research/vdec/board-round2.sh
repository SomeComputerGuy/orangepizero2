#!/bin/bash
# Round 2 (sequential, one decoder at a time unless stated): payload check, concurrency repro, md5 reruns.
cd /root/vdec-streams
echo "kernel $(uname -v)"
echo "== A: P010 bytes for 20 frames (expect $((24883200*20)))"
gst-launch-1.0 -q filesrc location=hevc-main10-2160p60.mkv num-buffers=20 ! matroskademux ! h265parse ! v4l2slh265dec ! video/x-raw,format=P010_10LE ! fdsink fd=1 2>/dev/null | wc -c
echo "== B: concurrency: HEVC 8-bit and VP9 P0 at the same time"
dmesg -C
gst-launch-1.0 -q filesrc location=hevc-main-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! video/x-raw,format=NV12_32L32 ! fakesink sync=false & a=$!
gst-launch-1.0 -q filesrc location=vp9-p0-2160p60.webm ! matroskademux ! vp9parse ! v4l2slvp9dec ! video/x-raw,format=NV12_32L32 ! fakesink sync=false & b=$!
wait $a; ra=$?; wait $b; rb=$?
echo "rc hevc=$ra vp9=$rb setup-fails=$(dmesg | grep -c 'Failed to setup') other: $(dmesg | grep -iE 'cedrus|iommu' | grep -v 'Failed to setup' | tail -2 | tr '\n' ' ')"
echo "== B2: concurrency: HEVC 8-bit and H.264 at the same time"
dmesg -C
gst-launch-1.0 -q filesrc location=hevc-main-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! video/x-raw,format=NV12_32L32 ! fakesink sync=false & a=$!
gst-launch-1.0 -q filesrc location=h264-high-2160p30.mkv ! matroskademux ! h264parse ! v4l2slh264dec ! video/x-raw,format=NV12_32L32 ! fakesink sync=false & b=$!
wait $a; ra=$?; wait $b; rb=$?
echo "rc hevc=$ra h264=$rb setup-fails=$(dmesg | grep -c 'Failed to setup')"
echo "== C: md5 reruns"
dmesg -C
/root/board-bench.sh /root/vdec-streams hevc-main-2160p60.mkv 2>&1 | grep -E "bitexact|dmesg"
cp /root/vdec-out/hevc-main-2160p60.mkv.nv12.framemd5 /root/vdec-out/r2a-hevc-main.framemd5
/root/board-bench.sh /root/vdec-streams hevc-main-2160p60.mkv 2>&1 | grep -E "bitexact|dmesg"
cp /root/vdec-out/hevc-main-2160p60.mkv.nv12.framemd5 /root/vdec-out/r2b-hevc-main.framemd5
for n in vp9-p0-2160p60.webm vp9-p2-2160p60.webm hevc-main10-2160p60.mkv; do /root/board-bench.sh /root/vdec-streams $n 2>&1 | grep -E "rc=|bitexact|dmesg"; done
echo ROUND2-DONE
