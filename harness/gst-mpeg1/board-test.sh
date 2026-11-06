#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side: MPEG-1 (MG1S) and MPEG-2 (MG2S) through the dev v4l2slmpeg2dec (patches 0001-0017, 0101-0107, 0201).
#   board-test.sh DIR PHASE      DIR holds plugins/ (dev .so), lib/ (patched libgstcodecs-1.0.so.0), vec/ (streams)
#   PHASE = stock (image kernel) | test (cumulative kernel). Output: DIR/out-PHASE/
# Every gst run is under timeout 120. results.txt lines: NAME TAG rc=N MD5 SIZE irqs=N [picked=[...]]
set -u
D=$1; PH=$2; O=$D/out-$PH; rm -rf "$O"; mkdir -p "$O"
SYS=/usr/lib/aarch64-linux-gnu/gstreamer-1.0
P=$D/pdir; rm -rf "$P"; mkdir -p "$P"
for f in "$SYS"/*.so; do
	case $(basename "$f") in libgstv4l2codecs.so|libgstjpegformat.so) ;; *) ln -s "$f" "$P/";; esac
done
cp "$D"/plugins/*.so "$P/"
export GST_PLUGIN_SYSTEM_PATH=$P GST_REGISTRY=$D/registry.bin LD_LIBRARY_PATH=$D/lib GST_DEBUG_NO_COLOR=1
rm -f "$GST_REGISTRY"
irq() { awk '/1c0e000.video-codec/{print $2+$3+$4+$5}' /proc/interrupts; }
CDEV=""; for v in /dev/video*; do v4l2-ctl -d $v -D 2>/dev/null | grep -q "Driver name *: *cedrus" && { CDEV=$v; break; }; done
{
uname -rv; echo "cedrus=$CDEV"; v4l2-ctl -d "$CDEV" --list-formats-out 2>&1 | grep -E '\[[0-9]+\]'
} > "$O/fmts.txt" 2>&1
{
uname -r; gst-launch-1.0 --version | head -2
ldd "$P/libgstv4l2codecs.so" | grep -E 'libgstcodecs|libgstcodecparsers'
# first use of the registry: the plugin logs "MPEG-1 supported" / "MPEG-1 not supported" at registration
GST_REGISTRY_FORK=no GST_DEBUG=v4l2codecs-mpeg2dec:4 gst-inspect-1.0 v4l2slmpeg2dec 2>&1 | grep -E 'MPEG-1|Rank|Long-name|mpegversion|systemstream|profile|width|height|SINK|SRC|format:' | head -60
# software MPEG-1 decoders on this image (the fallback decodebin must take when the hardware has no MG1S):
# gst-libav's avdec_mpeg2video (video/mpeg mpegversion={1,2}) or gst-plugins-ugly's mpeg2dec
for e in avdec_mpeg2video avdec_mpeg1video mpeg2dec; do gst-inspect-1.0 --exists $e && echo "SWDEC=$e $(gst-inspect-1.0 $e | grep -m1 Rank | tr -s ' ')"; done
echo "SWDEC-PROBE-DONE"
dpkg-query -W -f='PKG ${Package} ${Version} ${db:Status-Status}\n' gstreamer1.0-libav gstreamer1.0-plugins-ugly 2>&1
} > "$O/inspect.txt" 2>&1
T="timeout -k 5 120"
dec() { # name file tag chain : explicit hardware pipeline, I420 dump, cedrus IRQ delta, mpeg2dec INFO log
	n=$1 f=$2 tag=$3 chain=$4
	i0=$(irq)
	$T env GST_DEBUG=v4l2codecs-mpeg2dec:4 gst-launch-1.0 -q filesrc location="$f" ! $chain ! videoconvert ! \
		video/x-raw,format=I420 ! filesink location="$O/$n.$tag.yuv" > "$O/$n.$tag.log" 2>&1
	rc=$?; i1=$(irq)
	echo "$n $tag rc=$rc $(md5sum < "$O/$n.$tag.yuv" | cut -c1-32) $(stat -c %s "$O/$n.$tag.yuv") irqs=$((i1-i0))" >> "$O/results.txt"
}
auto() { # name file bin tag : which decoder autoplugging picked
	n=$1 f=$2 bin=$3 tag=$4
	i0=$(irq)
	if [ "$bin" = playbin3 ]; then
		$T gst-launch-1.0 -v $bin uri="file://$f" audio-sink=fakesink \
			video-sink="videoconvert ! video/x-raw,format=I420 ! filesink location=$O/$n.$tag.yuv" > "$O/$n.$tag.log" 2>&1
	else
		$T gst-launch-1.0 -v filesrc location="$f" ! $bin ! videoconvert ! video/x-raw,format=I420 ! \
			filesink location="$O/$n.$tag.yuv" > "$O/$n.$tag.log" 2>&1
	fi
	rc=$?; i1=$(irq)
	picked=$(grep -oE ':(v4l2slmpeg2dec|v4l2mpeg2dec|mpeg2dec|avdec_mpeg[a-z0-9]*)[0-9]*' "$O/$n.$tag.log" | tr -d ':' | sort -u | tr '\n' ' ')
	echo "$n $tag rc=$rc $(md5sum < "$O/$n.$tag.yuv" 2>/dev/null | cut -c1-32) $(stat -c %s "$O/$n.$tag.yuv" 2>/dev/null) irqs=$((i1-i0)) picked=[$picked]" >> "$O/results.txt"
}
: > "$O/results.txt"
if [ "$PH" = test ]; then M1="ccm1 tcela-18 MEI.stream16.long MEI.stream16v2 tcela-16 tcela-19"; else M1="ccm1"; fi
for n in $M1 tcela-15 mcp10ccett; do
	dec "$n" "$D/vec/$n" hw "mpegvideoparse ! v4l2slmpeg2dec"
done
for n in ccm1 tcela-18 tcela-15; do
	auto "$n" "$D/vec/$n" decodebin db
done
auto ccm1 "$D/vec/ccm1" playbin3 pb3
dmesg | grep -iE "cedrus|timed out|iommu|\bfault\b|oops|bug:|warning|alloc fail" | tail -40 > "$O/dmesg.txt"   # \bfault\b: not "default"
dmesg | tail -40 > "$O/dmesg-tail.txt"
rm -rf "$P" "$GST_REGISTRY"
cat "$O/results.txt"
