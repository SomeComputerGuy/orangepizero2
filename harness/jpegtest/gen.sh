#!/bin/bash
# SPDX-License-Identifier: MIT
# Generate JPEG decoder test vectors and reference decodes on the host.
#   gen.sh OUTDIR
# Needs ffmpeg and ImageMagick (libjpeg). Writes, per case NAME:
#   NAME.jpg, NAME.ref.yuv (ffmpeg -idct int, native planar format),
#   and a line "NAME W H REFFMT EXPECT" in OUTDIR/cases.txt, where
#   EXPECT is "ok" (must decode) or "reject" (must fail cleanly).
set -euo pipefail
out=$1
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
cd "$out"
: > cases.txt

src() { # W H -> src-WxH.png (detailed, noisy content)
	# testsrc2 rounds odd sizes: render 16-aligned, then crop
	[ -f "src-$1x$2.png" ] || ffmpeg -loglevel error -f lavfi \
		-i "testsrc2=size=$(( ($1 + 15) & ~15 ))x$(( ($2 + 15) & ~15 )):rate=1,noise=alls=12:allf=t,format=rgb24,crop=$1:$2:0:0" \
		-frames:v 1 -y "src-$1x$2.png"
}

ref() { # NAME REFFMT
	ffmpeg -loglevel error -idct int -i "$1.jpg" -f rawvideo \
		-pix_fmt "$2" -y "$1.ref.yuv"
}

add() { # NAME W H REFFMT EXPECT
	echo "$*" >> cases.txt
}

enc() { # NAME W H SAMPLING REFFMT [extra magick args]
	local n=$1 w=$2 h=$3 s=$4 r=$5
	shift 5
	src "$w" "$h"
	magick "src-${w}x${h}.png" -quality 90 -define jpeg:optimize-coding=false \
		-sampling-factor "$s" "$@" "$n.jpg"
	ref "$n" "$r"
	add "$n" "$w" "$h" "$r" ok
}

# 1. subsampling matrix at 1080p
enc s420 1920 1080 2x2,1x1,1x1 yuvj420p
enc s422 1920 1080 2x1,1x1,1x1 yuvj422p
enc s444 1920 1080 1x1,1x1,1x1 yuvj444p
enc s440 1920 1080 1x2,1x1,1x1 yuvj440p
enc s411 1920 1080 4x1,1x1,1x1 yuvj411p
src 1920 1080
magick src-1920x1080.png -colorspace Gray -type Grayscale -quality 90 \
	-define jpeg:optimize-coding=false grey.jpg
ref grey gray
add grey 1920 1080 gray ok

# 2. restart intervals (in MCUs; 120 = one MCU row at 1920 wide)
enc dri1 1920 1080 2x2,1x1,1x1 yuvj420p -define jpeg:restart-interval=1
enc dri7 1920 1080 2x2,1x1,1x1 yuvj420p -define jpeg:restart-interval=7
enc dri120 1920 1080 2x2,1x1,1x1 yuvj420p -define jpeg:restart-interval=120

# 3. odd sizes and limits
enc z16x16 16 16 2x2,1x1,1x1 yuvj420p
enc z17x33 17 33 2x2,1x1,1x1 yuvj420p
enc z17x33-411 17 33 4x1,1x1,1x1 yuvj411p
enc z1921x1081 1921 1081 2x2,1x1,1x1 yuvj420p
enc z2049x64 2049 64 2x2,1x1,1x1 yuvj420p
enc z4096x2304 4096 2304 2x2,1x1,1x1 yuvj420p
src 4096 4096
magick src-4096x4096.png -quality 90 -sampling-factor 2x2,1x1,1x1 z4096x4096.jpg
add z4096x4096 4096 4096 yuvj420p reject	# above CEDRUS_MAX_HEIGHT (2304)

# 4. table handling
enc opt420 1920 1080 2x2,1x1,1x1 yuvj420p -define jpeg:optimize-coding=true
python3 -I "$here/jpegtool.py" strip-dht s420.jpg nodht.jpg
cp s420.ref.yuv nodht.ref.yuv
add nodht 1920 1080 yuvj420p ok
python3 -I "$here/jpegtool.py" cr-table s420.jpg crtable.jpg
add crtable 1920 1080 yuvj420p reject
magick src-1920x1080.png -quality 90 -interlace Plane prog.jpg
add prog 1920 1080 yuvj420p reject
python3 -I "$here/jpegtool.py" truncate s420.jpg trunc.jpg 0.5
add trunc 1920 1080 yuvj420p error	# must complete, error flag or garbage, no hang

# 5. ffmpeg's own MJPEG encoder (optimal Huffman tables, Motion-JPEG style)
ffmpeg -loglevel error -i src-1920x1080.png -c:v mjpeg -q:v 3 \
	-pix_fmt yuvj422p -frames:v 1 -y mjpeg422.jpg
ref mjpeg422 yuvj422p
add mjpeg422 1920 1080 yuvj422p ok

sha256sum ./*.jpg > SHA256SUMS
echo "$(wc -l < cases.txt) cases in $out"
