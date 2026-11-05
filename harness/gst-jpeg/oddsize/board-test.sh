#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side of the v4l2sljpegdec odd-size / resolution-change test (harness/gst-jpeg/oddsize/HANDOFF.md).
#   board-test.sh DIR      DIR holds plugins/ (dev .so files), vec/ (cases.txt, jpg, mkv), jpegtest
# Per case: the caps jpegparse gives (width x height seen on its src pad), a direct hardware decode, a
# jpegdec decode, decodebin/playbin autoplugging, the driver's own output (stills, jpegtest) and the
# number of kernel log lines the case added. Last, the no-override run (stateful v4l2jpegdec, expected
# to hang) with its own kernel log line count. Output in DIR/out; checked on the host by compare.py.
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
gst-inspect-1.0 v4l2sljpegdec 2>&1 | grep -E 'Name|Rank|Long-name|image/jpeg|sof-marker|sampling|colorspace|interlace|scans|component-tables|width|height|SINK|SRC' | head -40
} > "$O/inspect.txt" 2>&1
T="timeout -k 5 60"
R=$O/results.txt; : > "$R"
dmesg_lines() { dmesg | wc -l; }
dec() { # name file element-chain tag
	n=$1 f=$2 chain=$3 tag=$4
	$T gst-launch-1.0 -q filesrc location="$f" ! $chain ! videoconvert ! video/x-raw,format=I420 ! \
		filesink location="$O/$n.$tag.yuv" > "$O/$n.$tag.log" 2>&1
	echo "$n $tag rc=$? $(md5sum < "$O/$n.$tag.yuv" | cut -c1-32) $(stat -c %s "$O/$n.$tag.yuv")" >> "$R"
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
	echo "$n $tag rc=$rc $(md5sum < "$O/$n.$tag.yuv" 2>/dev/null | cut -c1-32) $(stat -c %s "$O/$n.$tag.yuv" 2>/dev/null || echo 0) picked=[$picked]" >> "$R"
}
caps() { # name file demux-chain : every width x height jpegparse put on its src pad, in order of first use
	n=$1 f=$2 chain=$3
	$T gst-launch-1.0 -v filesrc location="$f" ! $chain jpegparse ! fakesink > "$O/$n.caps.log" 2>&1
	rc=$?
	sizes=$(grep 'jpegparse0.GstPad:src: caps' "$O/$n.caps.log" | grep -o 'width=(int)[0-9]*, height=(int)[0-9]*' | \
		sed 's/width=(int)//; s/, height=(int)/x/' | awk '!s[$0]++' | tr '\n' ' ')
	echo "$n caps rc=$rc sizes=[$sizes]" >> "$R"
}
while read -r n w h kind spec; do
	case $n in ''|'#'*) continue;; esac
	d0=$(dmesg_lines)
	if [ "$kind" = clip ]; then
		f=$D/vec/$n.mkv
		caps "$n" "$f" "matroskademux !"
		dec "$n" "$f" "matroskademux ! jpegparse ! v4l2sljpegdec" hw
		dec "$n" "$f" "matroskademux ! jpegparse ! jpegdec" sw
		auto "$n" "$f" decodebin db
		auto "$n" "$f" playbin pb
		auto "$n" "$f" playbin3 pb3
	else
		f=$D/vec/$n.jpg
		caps "$n" "$f" ""
		dec "$n" "$f" "jpegparse ! v4l2sljpegdec" hw
		dec "$n" "$f" "jpegparse ! jpegdec" sw
		auto "$n" "$f" decodebin db
		auto "$n" "$f" playbin pb
		auto "$n" "$f" decodebin3 db3
		timeout 20 "$D/jpegtest" -f yu12 -o "$O/$n.drv.yuv" "$f" > "$O/$n.drv.log" 2>&1
		echo "$n drv rc=$? $(md5sum < "$O/$n.drv.yuv" 2>/dev/null | cut -c1-32) $(stat -c %s "$O/$n.drv.yuv" 2>/dev/null || echo 0)" >> "$R"
	fi
	echo "$n dmesg +$(( $(dmesg_lines) - d0 ))" >> "$R"
done < "$D/vec/cases.txt"
# Without the shipped MARGINAL override the stateful v4l2jpegdec wins and hangs (rc=124 expected): recorded with
# the kernel log lines it causes, so the log noise of the run is attributed, not judged.
d0=$(dmesg_lines)
GST_PLUGIN_FEATURE_RANK= $T gst-launch-1.0 -v filesrc location="$D/vec/z1921x1081.jpg" ! decodebin ! fakesink > "$O/norank.log" 2>&1
echo "norank rc=$? picked=[$(grep -o 'v4l2sljpegdec[0-9]*\|v4l2jpegdec[0-9]*\|[^a-z0-9]jpegdec[0-9]*' "$O/norank.log" | tr -d '/:.' | sort -u | tr '\n' ' ')] dmesg +$(( $(dmesg_lines) - d0 ))" >> "$R"
dmesg > "$O/dmesg-after.txt"
tail -n +$(( $(wc -l < "$O/dmesg-before.txt") + 1 )) "$O/dmesg-after.txt" > "$O/dmesg.txt"
rm -f "$O/dmesg-before.txt" "$O/dmesg-after.txt"
cat "$R"
