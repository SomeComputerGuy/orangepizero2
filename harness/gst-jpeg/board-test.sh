#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side: test v4l2sljpegdec (dev build) against jpegdec and the driver (jpegtest).
#   board-test.sh DIR      DIR holds plugins/ (our .so files), vec/ (jpg + clips), jpegtest
# Output in DIR/out: per case I420 dumps, md5s, element picked by decodebin/playbin, rc.
set -u
D=$1; O=$D/out; rm -rf "$O"; mkdir -p "$O"
SYS=/usr/lib/aarch64-linux-gnu/gstreamer-1.0
P=$D/pdir; rm -rf "$P"; mkdir -p "$P"
for f in "$SYS"/*.so; do
	case $(basename "$f") in libgstv4l2codecs.so|libgstjpegformat.so) ;; *) ln -s "$f" "$P/";; esac
done
cp "$D"/plugins/*.so "$P/"
export GST_PLUGIN_SYSTEM_PATH=$P GST_REGISTRY=$D/registry.bin GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL
rm -f "$GST_REGISTRY"
{
uname -r; gst-launch-1.0 --version | head -2
gst-inspect-1.0 v4l2sljpegdec 2>&1 | sed -n '1,200p' | grep -E 'Rank|Long-name|image/jpeg|sof-marker|sampling|colorspace|interlace|width|height|format:|SINK|SRC' | head -40
} > "$O/inspect.txt" 2>&1
T="timeout -k 5 60"
dec() { # name file element-chain tag
	n=$1 f=$2 chain=$3 tag=$4
	$T gst-launch-1.0 -q filesrc location="$f" ! $chain ! videoconvert ! video/x-raw,format=I420 ! \
		filesink location="$O/$n.$tag.yuv" > "$O/$n.$tag.log" 2>&1
	echo "$n $tag rc=$? $(md5sum < "$O/$n.$tag.yuv" | cut -c1-32) $(stat -c %s "$O/$n.$tag.yuv")" >> "$O/results.txt"
}
auto() { # name file bin tag : which decoder autoplugging picked
	n=$1 f=$2 bin=$3 tag=$4
	if [ "$bin" = playbin ] || [ "$bin" = playbin3 ]; then
		$T gst-launch-1.0 -v $bin uri="file://$f" audio-sink=fakesink \
			video-sink="videoconvert ! video/x-raw,format=I420 ! filesink location=$O/$n.$tag.yuv" > "$O/$n.$tag.log" 2>&1
	else
		$T gst-launch-1.0 -v filesrc location="$f" ! $bin ! videoconvert ! video/x-raw,format=I420 ! \
			filesink location="$O/$n.$tag.yuv" > "$O/$n.$tag.log" 2>&1
	fi
	rc=$?
	picked=$(grep -o 'v4l2sljpegdec[0-9]*\|v4l2jpegdec[0-9]*\|[^a-z0-9]jpegdec[0-9]*\|avdec_mjpeg[0-9]*' "$O/$n.$tag.log" | tr -d '/:.' | sort -u | tr '\n' ' ')
	echo "$n $tag rc=$rc $(md5sum < "$O/$n.$tag.yuv" 2>/dev/null | cut -c1-32) picked=[$picked]" >> "$O/results.txt"
}
: > "$O/results.txt"
for n in s420 s422 s444 s411 s440 grey prog mjpeg422 crtable trunc dri7 nodht opt420 z16x16 z17x33 z17x33-411 z2049x64 z4096x2304 z4096x4096; do
	f=$D/vec/$n.jpg
	dec "$n" "$f" "jpegparse ! v4l2sljpegdec" hw
	dec "$n" "$f" "jpegparse ! jpegdec" sw
	auto "$n" "$f" decodebin db
	auto "$n" "$f" playbin pb
	auto "$n" "$f" decodebin3 db3
	timeout 20 "$D/jpegtest" -f yu12 -o "$O/$n.drv.yuv" "$f" > "$O/$n.drv.log" 2>&1
	echo "$n drv rc=$? $(md5sum < "$O/$n.drv.yuv" 2>/dev/null | cut -c1-32)" >> "$O/results.txt"
done
for n in mj420 mj422 mj444 mjmix; do
	f=$D/vec/$n.mkv
	dec "$n" "$f" "matroskademux ! jpegparse ! v4l2sljpegdec" hw
	dec "$n" "$f" "matroskademux ! jpegparse ! jpegdec" sw
	auto "$n" "$f" decodebin db
	auto "$n" "$f" playbin pb
	auto "$n" "$f" playbin3 pb3
done
# throughput: 300 frames 1080p MJPEG through the element vs jpegdec
for e in v4l2sljpegdec jpegdec; do
	s=$(date +%s%N)
	$T gst-launch-1.0 -q filesrc location="$D/vec/mj1080.mkv" ! matroskademux ! jpegparse ! $e ! fakesink > /dev/null 2>&1
	echo "perf mj1080 $e rc=$? $(( ($(date +%s%N) - s) / 1000000 )) ms" >> "$O/results.txt"
done
# the shipped override is still needed: without it v4l2jpegdec wins (expected broken)
GST_PLUGIN_FEATURE_RANK= $T gst-launch-1.0 -v filesrc location="$D/vec/s420.jpg" ! decodebin ! fakesink > "$O/norank.log" 2>&1
echo "norank s420 rc=$? picked=[$(grep -o 'v4l2sljpegdec[0-9]*\|v4l2jpegdec[0-9]*\|[^a-z0-9]jpegdec[0-9]*' "$O/norank.log" | tr -d '/:.' | sort -u | tr '\n' ' ')]" >> "$O/results.txt"
dmesg | tail -60 > "$O/dmesg.txt"
cat "$O/results.txt"
