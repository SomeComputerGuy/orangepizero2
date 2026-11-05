#!/bin/bash
# SPDX-License-Identifier: MIT
# Vectors for the v4l2sljpegdec odd-size / resolution-change test (harness/gst-jpeg/oddsize/HANDOFF.md).
#   gen-vectors.sh OUTDIR
# Needs ffmpeg and ImageMagick. Writes OUTDIR/cases.txt, one line per case:
#   NAME W H still SAMP          a JPEG of WxH, chroma sampling SAMP (420 422 444 411); all hardware cases
#   NAME W H clip  SEQ           an MJPEG Matroska clip, SEQ = WxH*N[,WxH*N...] frame sizes in order (4:2:0)
# Every still is decoded by the hardware (odd sizes, sub-MCU sizes, the 4096x2304 limit minus one); the
# clips change their picture size mid-stream (down, up) or are an odd size throughout. compare.py decodes
# the vectors with ffmpeg on the host for the reference, so nothing else is written here.
set -euo pipefail
out=$1
mkdir -p "$out"
cd "$out"
: > cases.txt

src() { # W H -> src-WxH.png (detailed, noisy content; testsrc2 rounds odd sizes: render 16-aligned, crop)
	[ -f "src-$1x$2.png" ] || ffmpeg -loglevel error -f lavfi \
		-i "testsrc2=size=$(( ($1 + 15) & ~15 ))x$(( ($2 + 15) & ~15 )):rate=1,noise=alls=12:allf=t,format=rgb24,crop=$1:$2:0:0" \
		-frames:v 1 -y "src-$1x$2.png"
}
still() { # NAME W H SAMP(420|422|444|411)
	local n=$1 w=$2 h=$3 s=$4 f
	case $s in 420) f=2x2,1x1,1x1;; 422) f=2x1,1x1,1x1;; 444) f=1x1,1x1,1x1;; 411) f=4x1,1x1,1x1;; esac
	src "$w" "$h"
	magick "src-${w}x${h}.png" -quality 90 -define jpeg:optimize-coding=false -sampling-factor "$f" "$n.jpg"
	echo "$n $w $h still $s" >> cases.txt
}
mjpeg() { # W H N OUT.mjpeg : N frames of moving test content, 4:2:0, one JPEG per frame
	if [ $(( $1 % 2 )) = 0 ] && [ $(( $2 % 2 )) = 0 ]; then
		ffmpeg -loglevel error -f lavfi -i "testsrc2=size=$(( ($1 + 15) & ~15 ))x$(( ($2 + 15) & ~15 )):rate=30,crop=$1:$2:0:0" \
			-frames:v "$3" -c:v mjpeg -pix_fmt yuvj420p -q:v 3 -f mjpeg -y "$4"
	else # ffmpeg's mjpeg encoder rounds odd sizes to even: encode the frames with ImageMagick instead
		rm -rf tmp-frames; mkdir tmp-frames
		ffmpeg -loglevel error -f lavfi -i "testsrc2=size=$(( ($1 + 15) & ~15 ))x$(( ($2 + 15) & ~15 )):rate=30,format=rgb24,crop=$1:$2:0:0" \
			-frames:v "$3" -y tmp-frames/f%03d.png
		for f in tmp-frames/f*.png; do
			magick "$f" -quality 90 -define jpeg:optimize-coding=false -sampling-factor 2x2,1x1,1x1 "${f%.png}.jpg"
		done
		cat tmp-frames/f*.jpg > "$4"; rm -rf tmp-frames
	fi
}
clip() { # NAME SEQ : concatenate the elementary streams of each WxH*N part, mux into Matroska (stream copy)
	local n=$1 seq=$2 part parts=() i=0 wh cnt
	for part in ${seq//,/ }; do
		wh=${part%\**}; cnt=${part#*\*}
		mjpeg "${wh%x*}" "${wh#*x}" "$cnt" "tmp-$n-$i.mjpeg"; parts+=("tmp-$n-$i.mjpeg"); i=$((i + 1))
	done
	cat "${parts[@]}" > "tmp-$n.mjpeg"
	ffmpeg -loglevel error -framerate 30 -f mjpeg -i "tmp-$n.mjpeg" -c copy -y "$n.mkv"
	rm -f "${parts[@]}" "tmp-$n.mjpeg"
	echo "$n 0 0 clip $seq" >> cases.txt
}

# odd and sub-MCU picture sizes in every chroma layout the hardware takes
still z17x33 17 33 420
still z17x33-411 17 33 411
still z33x17-422 33 17 422
still z15x15-444 15 15 444
still z1x1 1 1 420
still z8x8 8 8 420
still z1921x1081 1921 1081 420
still z2049x64 2049 64 420
still z4095x2303 4095 2303 420
# resolution changes (down, up) and an odd-size clip
clip mjmix 640x480*15,320x240*15
clip mjmix-up 320x240*15,640x480*15
clip mj-z33x17 33x17*30
# the frame sizes must come out of the files as written
for f in *.mkv; do
	echo "$f: $(ffprobe -v error -select_streams v -show_entries frame=width,height -of csv=p=0 "$f" | uniq -c | awk '{printf "%s*%d ", $2, $1}')"
done > info.txt
sed -i 's/,\([0-9]*\)\*/x\1*/g' info.txt
cat info.txt
rm -f src-*.png
sha256sum ./*.jpg ./*.mkv > SHA256SUMS
echo "$(wc -l < cases.txt) cases in $out"
