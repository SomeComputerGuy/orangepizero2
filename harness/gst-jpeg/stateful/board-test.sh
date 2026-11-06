#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side of runner job 57 (harness/gst-jpeg/stateful/HANDOFF.md): GStreamer's stateful v4l2jpegdec
# (gst-plugins-good, dev build with patches/gst-plugins-good1.0 0101-0102) on cedrus JPEG with the kernel fixes
# "media: cedrus: jpeg: drain on V4L2_DEC_CMD_STOP" (c41+) and "media: cedrus: change formats with CAPTURE buffers
# left while stopped" (c42+). Before it, v4l2jpegdec decoded the picture, then STOP failed with -EINVAL and the
# empty-buffer fallback looped until the timeout (job 22 norank16: rc=124, dmesg +133).
#   board-test.sh DIR      DIR holds plugins/ (dev v4l2codecs + jpegformat + video4linux2), vec/
# Every run: timeout 60, output converted to I420 into a file, md5 + size, kernel log lines added, and (stateful runs)
# from a GStreamer debug log the count of refused decoder commands and of "Waiting for decoder stop".
# Output in DIR/out (results.txt); checked on the host by check.sh.
set -u
D=$1; O=$D/out; rm -rf "$O"; mkdir -p "$O"
SYS=/usr/lib/aarch64-linux-gnu/gstreamer-1.0
P=$D/pdir; rm -rf "$P"; mkdir -p "$P"
for f in "$SYS"/*.so; do
	case $(basename "$f") in libgstv4l2codecs.so|libgstjpegformat.so|libgstvideo4linux2.so) ;; *) ln -s "$f" "$P/";; esac
done
cp "$D"/plugins/*.so "$P/"
export GST_PLUGIN_SYSTEM_PATH=$P GST_REGISTRY=$D/registry.bin GST_DEBUG_NO_COLOR=1
rm -f "$GST_REGISTRY"
dmesg > "$O/dmesg-before.txt"
{ uname -r; uname -v; gst-launch-1.0 --version | head -2; cat "$D/BUILD.txt"
  gst-inspect-1.0 --exists v4l2jpegdec; echo "EXISTS v4l2jpegdec=$?"
  gst-inspect-1.0 --exists v4l2sljpegdec; echo "EXISTS v4l2sljpegdec=$?"; } > "$O/inspect.txt" 2>&1
R=$O/results.txt; : > "$R"
T="timeout -k 5 60"
V=$D/vec
dl() { dmesg | wc -l; }
# run NAME RANK SRC-AND-DECODER-CHAIN   (RANK: value for GST_PLUGIN_FEATURE_RANK, "-" = unset)
run() {
	n=$1 rk=$2; shift 2
	d0=$(dl)
	if [ "$rk" = - ]; then unset GST_PLUGIN_FEATURE_RANK; else export GST_PLUGIN_FEATURE_RANK=$rk; fi
	GST_DEBUG=v4l2videodec:5,v4l2codecs*:4 GST_DEBUG_FILE=$O/$n.gstdebug.txt \
		$T gst-launch-1.0 -v "$@" ! videoconvert ! video/x-raw,format=I420 ! filesink location="$O/$n.yuv" \
		> "$O/$n.log" 2>&1
	rc=$?
	unset GST_PLUGIN_FEATURE_RANK
	picked=$(grep -o 'v4l2sljpegdec[0-9]*\|v4l2jpegdec[0-9]*\|[^a-z0-9]jpegdec[0-9]*\|v4l2slh264dec[0-9]*' "$O/$n.log" | tr -d '/:.' | sort -u | tr '\n' ' ')
	dmabuf=$(grep -c 'v4l2jpegdec0.GstPad:src: caps = video/x-raw(memory:DMABuf)' "$O/$n.log")
	cmdfail=$(grep -c 'Failed to send decoder command' "$O/$n.gstdebug.txt" 2>/dev/null)
	stopwait=$(grep -c 'Waiting for decoder stop' "$O/$n.gstdebug.txt" 2>/dev/null)
	echo "$n rc=$rc md5=$(md5sum < "$O/$n.yuv" 2>/dev/null | cut -c1-32) size=$(stat -c %s "$O/$n.yuv" 2>/dev/null || echo 0) dmesg=+$(( $(dl) - d0 )) cmdfail=${cmdfail:-0} stopwait=${stopwait:-0} dmabuf=${dmabuf:-0} picked=[$picked]" >> "$R"
	head -c 4000000 "$O/$n.gstdebug.txt" > "$O/$n.gstdebug.tmp" 2>/dev/null && mv "$O/$n.gstdebug.tmp" "$O/$n.gstdebug.txt"
	rm -f "$O/$n.yuv"
}
MF="multifilesrc location=$V/z1920x1088.jpg num-buffers=5 caps=image/jpeg,framerate=(fraction)5/1"
run sl-still  - filesrc location="$V/z1920x1088.jpg" ! jpegparse ! v4l2sljpegdec
run sf-still  - filesrc location="$V/z1920x1088.jpg" ! jpegparse ! v4l2jpegdec
run sl-loop5  - $MF ! jpegparse ! v4l2sljpegdec
run sf-loop5  - $MF ! jpegparse ! v4l2jpegdec
run sl-mjmix  - filesrc location="$V/mjmix.mkv" ! matroskademux ! jpegparse ! v4l2sljpegdec
run sf-mjmix  - filesrc location="$V/mjmix.mkv" ! matroskademux ! jpegparse ! v4l2jpegdec
run sl-mjmixup - filesrc location="$V/mjmix-up.mkv" ! matroskademux ! jpegparse ! v4l2sljpegdec
run sf-mjmixup - filesrc location="$V/mjmix-up.mkv" ! matroskademux ! jpegparse ! v4l2jpegdec
run nr16-db   - filesrc location="$V/z1920x1088.jpg" ! decodebin
run ov16-db   v4l2jpegdec:MARGINAL filesrc location="$V/z1920x1088.jpg" ! decodebin
run h264      - filesrc location="$V/h264-640x480.mkv" ! matroskademux ! h264parse ! v4l2slh264dec
run h264mix   - filesrc location="$V/h264mix.h264" ! h264parse ! v4l2slh264dec
dmesg > "$O/dmesg-after.txt"
tail -n +$(( $(wc -l < "$O/dmesg-before.txt") + 1 )) "$O/dmesg-after.txt" > "$O/dmesg.txt"
rm -f "$O/dmesg-before.txt" "$O/dmesg-after.txt"
cat "$R"
