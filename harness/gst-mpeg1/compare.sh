#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Host side: compare the I420 dumps of the test phase (build/gst-mpeg1/results/out-test/NAME.hw.yuv) with software
# references, the method of harness/research/legacy-dec/run-raw.sh: host FFmpeg (-idct simple/int/faani, yuv420p) and
# the envelope simple~int; tcela-18 against the exact D-picture reference legacy-dec/m1-dpic.py. One line per stream in
# <results>/compare.tsv: TAG WxH <idct>: frames=.. exact=.. maxdiff=.. ... envelope(simple~int): ...
# Usage: compare.sh <results dir>
set -u
H=/home/aruni/orangepizero2; LD=$H/harness/research/legacy-dec; SV=$H/kernel-check/legacy-serve/mpeg2; C=$LD/cmp-raw.py
R=$1; O=$R/out-test; S=$R/compare.tsv; : > "$S"
FF="-nostdin -hide_banner -loglevel warning"
src() { case $1 in ccm1) echo "$SV/ccm1.mpg";; MEI.*) echo "$SV/$1";; *) echo "$SV/$1.bits";; esac; }
sw() { ffmpeg $FF -threads 1 -idct $1 -f mpegvideo -i "$(src $tag)" -fps_mode passthrough -pix_fmt yuv420p -f rawvideo - 2>>"$R/$tag.sw.err"; }
for tag in ccm1 MEI.stream16.long MEI.stream16v2 tcela-16 tcela-19 tcela-15 mcp10ccett; do
  hw=$O/$tag.hw.yuv; [ -s "$hw" ] || { printf '%s\tno hw dump\n' "$tag" | tee -a "$S"; continue; }
  wh=$(ffprobe -v error -f mpegvideo -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$(src $tag)" | head -1 | tr , ' ')
  line="$tag\t${wh/ /x}"
  for i in simple int faani; do line="$line\t$i: $(python3 -I $C $wh <(sw $i) "$hw")"; done
  line="$line\tenvelope(simple~int): $(python3 -I $C $wh <(sw simple) <(sw int))"
  printf "$line\n" | tee -a "$S"
done
# tcela-18: 31 D-pictures, 720x480; exact reference (flat DC blocks, IDCT-independent), NV12 -> I420 is a plane split
tag=tcela-18; hw=$O/$tag.hw.yuv
if [ -s "$hw" ]; then
  python3 -I $LD/m1-dpic.py "$SV/tcela-18.bits" 2> "$R/dpic-ref.err" | ffmpeg $FF -f rawvideo -pix_fmt nv12 -s 720x480 -i - -pix_fmt yuv420p -f rawvideo - 2>>"$R/dpic-ref.err" > "$R/dpic-ref.i420"
  printf '%s\t720x480\tdpic-ref: %s\n' "$tag" "$(python3 -I $C 720 480 "$R/dpic-ref.i420" "$hw")" | tee -a "$S"; rm -f "$R/dpic-ref.i420"
else printf '%s\tno hw dump\n' "$tag" | tee -a "$S"; fi
