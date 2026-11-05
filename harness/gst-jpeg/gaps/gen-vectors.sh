#!/bin/bash
# SPDX-License-Identifier: MIT
# Vectors for the v4l2sljpegdec caps-gap test (harness/gst-jpeg/gaps/HANDOFF.md).
#   gen-vectors.sh OUTDIR [BASEDIR]
# BASEDIR holds the jpegtest vectors (harness/jpegtest/gen.sh output: s420.jpg, dri7.jpg,
# z4096x4096.jpg); default build/gst-jpeg/vec. Every edited vector is checked to decode
# identically to its source with ffmpeg. Writes OUTDIR/cases.txt: NAME W H EXPECT CAPS, CAPS =
# the jpegparse caps the image must get (scans:component-tables), EXPECT =
#   hw        the hardware decoder must take it (one scan, Cb and Cr tables equal in content)
#   fallback  decodebin must plug jpegdec (caps refuse it)
#   size      fallback only on a kernel that enumerates frame sizes (4096x4096 > 4096x2304)
set -euo pipefail
out=$1
here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../.." && pwd)
base=${2:-$top/build/gst-jpeg/vec}
tool="$top/harness/jpegtest/jpegtool.py"
[ -f "$base/s420.jpg" ] && [ -f "$base/z4096x4096.jpg" ] && [ -f "$base/dri7.jpg" ] || {
	echo "base vectors missing in $base: run harness/jpegtest/gen.sh $base" >&2; exit 2; }
mkdir -p "$out"
cd "$out"
: > cases.txt
md5() { ffmpeg -v error -idct int -i "$1" -f rawvideo -pix_fmt yuvj420p - | md5sum | cut -c1-32; }
ref=$(md5 "$base/s420.jpg")
same() { # NAME: decoded picture must equal s420
	[ "$(md5 "$1.jpg")" = "$ref" ] || { echo "$1.jpg does not decode like s420.jpg" >&2; exit 1; }
}
cp "$base/s420.jpg" s420.jpg;                               echo "s420 1920 1080 hw 1:luma-chroma" >> cases.txt
python3 -I "$tool" cr-table-same "$base/s420.jpg" crtq2.jpg;   same crtq2;   echo "crtq2 1920 1080 hw 1:luma-chroma" >> cases.txt
python3 -I "$tool" cr-table "$base/s420.jpg" crtable.jpg;                    echo "crtable 1920 1080 fallback 1:separate" >> cases.txt
python3 -I "$tool" cr-huffman "$base/s420.jpg" crhuff.jpg;     same crhuff;  echo "crhuff 1920 1080 fallback 1:separate" >> cases.txt
python3 -I "$tool" split-scans "$base/s420.jpg" noninter.jpg 3; same noninter; echo "noninter 1920 1080 fallback 3:luma-chroma" >> cases.txt
python3 -I "$tool" split-scans "$base/s420.jpg" noninter2.jpg 2; same noninter2; echo "noninter2 1920 1080 fallback 2:luma-chroma" >> cases.txt
python3 -I "$tool" split-scans "$base/dri7.jpg" dri7-noninter.jpg 3; same dri7-noninter; echo "dri7-noninter 1920 1080 fallback 3:luma-chroma" >> cases.txt
cp "$base/z4096x4096.jpg" z4096x4096.jpg;                   echo "z4096x4096 4096 4096 size 1:luma-chroma" >> cases.txt
# Motion JPEG clips of the fallback images (30 frames, stream copy) and one the hardware takes
for n in crhuff noninter crtq2; do
	ffmpeg -v error -f image2 -loop 1 -framerate 30 -i "$n.jpg" -c copy -frames:v 30 -y "mj-$n.mkv"
done
echo "mj-crhuff 1920 1080 fallback 1:separate" >> cases.txt
echo "mj-noninter 1920 1080 fallback 3:luma-chroma" >> cases.txt
echo "mj-crtq2 1920 1080 hw 1:luma-chroma" >> cases.txt
for f in *.jpg; do python3 -I "$tool" info "$f" | grep -E "SOF|SOS" | sed "s/^/$f: /"; done > info.txt
sha256sum ./*.jpg ./*.mkv > SHA256SUMS
rm -rf tmp
echo "$(wc -l < cases.txt) cases in $out"
