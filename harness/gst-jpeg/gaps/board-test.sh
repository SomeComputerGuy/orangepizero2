#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side of the v4l2sljpegdec caps-gap test (harness/gst-jpeg/gaps/HANDOFF.md).
#   board-test.sh DIR      DIR holds plugins/ (dev .so files), vec/ (cases.txt, jpg, mkv), jpegtest
# For every case in vec/cases.txt (NAME W H EXPECT CAPS): the caps jpegparse gives the image, a direct
# hardware decode, a jpegdec decode, decodebin/playbin autoplugging, and (hw cases) the driver's own
# output (jpegtest). Output in DIR/out; checked on the host by compare.py.
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
dmesg > "$O/dmesg-before.txt"
{
uname -r; uname -v; gst-launch-1.0 --version | head -2
gst-inspect-1.0 v4l2sljpegdec 2>&1 | grep -E 'Rank|Long-name|image/jpeg|sof-marker|sampling|colorspace|interlace|scans|component-tables|width|height|SINK|SRC' | head -40
} > "$O/inspect.txt" 2>&1
# a kernel that enumerates frame sizes gives the sink caps a width/height range
if grep -Eq '^ *width: \[' "$O/inspect.txt"; then KSIZES=1; else KSIZES=0; fi
echo "KSIZES=$KSIZES" >> "$O/inspect.txt"
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
caps() { # name file demux-chain : the scans / component-tables fields jpegparse sets
	n=$1 f=$2 chain=$3
	$T gst-launch-1.0 -v filesrc location="$f" ! $chain jpegparse ! fakesink > "$O/$n.caps.log" 2>&1
	echo "$n caps rc=$? $(grep -o 'scans=(int)[0-9]*' "$O/$n.caps.log" | sort -u | tr '\n' ' ')$(grep -o 'component-tables=(string)[a-z-]*' "$O/$n.caps.log" | sort -u | tr '\n' ' ')" >> "$O/results.txt"
}
: > "$O/results.txt"
while read -r n w h e c; do
	case $n in ''|'#'*) continue;; esac
	if [ "$e" = size ] && [ "$KSIZES" != 1 ]; then
		echo "$n SKIPPED kernel-without-ENUM_FRAMESIZES" >> "$O/results.txt"
		continue
	fi
	case $n in
	mj-*)
		f=$D/vec/$n.mkv
		caps "$n" "$f" "matroskademux !"
		dec "$n" "$f" "matroskademux ! jpegparse ! v4l2sljpegdec" hw
		dec "$n" "$f" "matroskademux ! jpegparse ! jpegdec" sw
		auto "$n" "$f" decodebin db
		auto "$n" "$f" playbin pb
		auto "$n" "$f" playbin3 pb3
		;;
	*)
		f=$D/vec/$n.jpg
		caps "$n" "$f" ""
		dec "$n" "$f" "jpegparse ! v4l2sljpegdec" hw
		dec "$n" "$f" "jpegparse ! jpegdec" sw
		auto "$n" "$f" decodebin db
		auto "$n" "$f" playbin pb
		auto "$n" "$f" decodebin3 db3
		if [ "$e" = hw ]; then
			timeout 20 "$D/jpegtest" -f yu12 -o "$O/$n.drv.yuv" "$f" > "$O/$n.drv.log" 2>&1
			echo "$n drv rc=$? $(md5sum < "$O/$n.drv.yuv" 2>/dev/null | cut -c1-32)" >> "$O/results.txt"
		fi
		;;
	esac
done < "$D/vec/cases.txt"
dmesg > "$O/dmesg-after.txt"
tail -n +$(( $(wc -l < "$O/dmesg-before.txt") + 1 )) "$O/dmesg-after.txt" > "$O/dmesg.txt"
rm -f "$O/dmesg-before.txt" "$O/dmesg-after.txt"
cat "$O/results.txt"
