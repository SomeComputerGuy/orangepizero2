#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board side of the v4l2sljpegdec recheck (harness/gst-jpeg/recheck/HANDOFF.md): the failing cases of jobs 05 and 06
# on a kernel that enumerates frame sizes, with the dev plugins (patches 0101-0107).
#   board-test.sh DIR      DIR holds plugins/ (dev .so files), vec/ (cases.txt, jpg, mkv), jpegtest
# Per case (vec/cases.txt: NAME W H still SAMP | NAME W H size SAMP | NAME 0 0 clip SEQ): the caps jpegparse gives
# (width x height on its src pad), a direct hardware decode, a jpegdec decode, decodebin/playbin autoplugging, the
# driver's own output (stills, jpegtest) and the kernel log lines the case added. "size" cases (too large for the
# hardware) are SKIPPED on a kernel without ENUM_FRAMESIZES. Last, the two no-override runs (norank: odd size, the
# stateful v4l2jpegdec declines it; norank16: 16-aligned, the stateful decoder takes it and hangs), each with its own
# kernel log line count and a GStreamer debug log.
# Output in DIR/out; checked on the host by compare.py.
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
cat "$D/BUILD.txt" 2>/dev/null
# gst-inspect prints the PLUGIN's name under "Name" (v4l2codecs), never the element's: the element is proven by --exists
gst-inspect-1.0 --exists v4l2sljpegdec; echo "EXISTS=$?"
gst-inspect-1.0 v4l2sljpegdec 2>&1 | grep -E 'Name|Rank|Long-name|Klass|image/jpeg|sof-marker|sampling|colorspace|interlace|scans|component-tables|width|height|SINK|SRC' | head -40
} > "$O/inspect.txt" 2>&1
# a kernel that enumerates frame sizes gives the SINK caps a width/height range (the SRC template always has one)
if sed -n '/SINK template/,/SRC template/p' "$O/inspect.txt" | grep -Eq '^ *width: \['; then KSIZES=1; else KSIZES=0; fi
echo "KSIZES=$KSIZES" >> "$O/inspect.txt"
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
	if [ "$kind" = size ] && [ "$KSIZES" != 1 ]; then
		echo "$n SKIPPED kernel-without-ENUM_FRAMESIZES" >> "$R"
		continue
	fi
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
		if [ "$kind" = still ]; then
			timeout 20 "$D/jpegtest" -f yu12 -o "$O/$n.drv.yuv" "$f" > "$O/$n.drv.log" 2>&1
			echo "$n drv rc=$? $(md5sum < "$O/$n.drv.yuv" 2>/dev/null | cut -c1-32) $(stat -c %s "$O/$n.drv.yuv" 2>/dev/null || echo 0)" >> "$R"
		fi
	fi
	echo "$n dmesg +$(( $(dmesg_lines) - d0 ))" >> "$R"
done < "$D/vec/cases.txt"
# Without the shipped MARGINAL override the stateful v4l2jpegdec (gst-plugins-good, rank 257 like ours, first by name)
# is tried first. On a kernel that enumerates frame sizes (c11+) its probed sink caps carry the driver's 16-pixel step
# ([16, 4096, 16] x [16, 2304, 16]), so for a picture that is not a multiple of 16 (z1921x1081) it returns EMPTY sink caps
# and decodebin moves on to v4l2sljpegdec: rc=0 expected, no kernel log line. A 16-aligned picture (z1920x1088) does go
# to the stateful decoder, which hangs on this stateless device (rc=124 expected; work-list item): recorded with the
# kernel log lines it causes and a GStreamer debug log of its V4L2 traffic, so the log noise of the run is attributed.
norank() { # name file
	d0=$(dmesg_lines)
	GST_PLUGIN_FEATURE_RANK= GST_DEBUG=v4l2videodec:6,v4l2bufferpool:6,v4l2object:5 GST_DEBUG_NO_COLOR=1 \
		GST_DEBUG_FILE=$O/$1.gstdebug.txt \
		$T gst-launch-1.0 -v filesrc location="$2" ! decodebin ! fakesink > "$O/$1.log" 2>&1
	echo "$1 rc=$? picked=[$(grep -o 'v4l2sljpegdec[0-9]*\|v4l2jpegdec[0-9]*\|[^a-z0-9]jpegdec[0-9]*' "$O/$1.log" | tr -d '/:.' | sort -u | tr '\n' ' ')] dmesg +$(( $(dmesg_lines) - d0 )) stateful-empty-caps=$(grep -c 'v4l2jpegdec[0-9]*> Returning sink caps EMPTY' "$O/$1.gstdebug.txt" 2>/dev/null)" >> "$R"
	if [ -f "$O/$1.gstdebug.txt" ]; then
		head -c 8000000 "$O/$1.gstdebug.txt" > "$O/$1.gstdebug.tmp" && mv "$O/$1.gstdebug.tmp" "$O/$1.gstdebug.txt"
	fi
}
norank norank "$D/vec/z1921x1081.jpg"
norank norank16 "$D/vec/z1920x1088.jpg"
dmesg > "$O/dmesg-after.txt"
tail -n +$(( $(wc -l < "$O/dmesg-before.txt") + 1 )) "$O/dmesg-after.txt" > "$O/dmesg.txt"
rm -f "$O/dmesg-before.txt" "$O/dmesg-after.txt"
cat "$R"
