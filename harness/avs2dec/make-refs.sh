#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build the approved AVS2 reference tools on the HOST and make reference
# md5s and test streams for the cedrus AVS2 decoder (harness/research/impl-avs2.md §5).
#
# Approved external code (user, 2026-11-02, "Approve both"), host only:
#   pkuvcl/davs2 b41cf117452e2d73d827f02d3e30aa20f1c721ac (GPL-2.0+), 8- and 10-bit
#   pkuvcl/xavs2 eae1e8b9d12468059bdd7dee893508e470fa83d8 (GPL-2.0), 8- and 10-bit
# Sources (already cloned, sha256 of `git archive HEAD` tar):
#   kernel-check/dl-avs2/build-src-davs2/davs2  9c61d8021b960bf27fbc30993903942aa1137407e503cf3dfa60c86aed07c5f5
#   kernel-check/dl-avs2/build-src-xavs2/xavs2  071ef366ea5603478e896cb229c752498378fba7717be11e1d2e5da5474d5e5d
# Builds go to kernel-check/avs2-build/, streams and md5s to kernel-check/avs2-es/.
# No nasm on the host: built with --disable-asm (slow but bit-exact).
#
#   STAGE=build|pku|cctv|encode|all ./make-refs.sh
set -euo pipefail
TOP=/home/aruni/orangepizero2
K=$TOP/kernel-check
SRC=$K/dl-avs2
B=$K/avs2-build
ES=$K/avs2-es
H=$TOP/harness/avs2dec
STAGE=${STAGE:-all}
J=${JOBS:-$(nproc)}
YT="python3 -I $H/yuvtool.py"
mkdir -p "$B" "$ES"

DAVS2_SHA=b41cf117452e2d73d827f02d3e30aa20f1c721ac
XAVS2_SHA=eae1e8b9d12468059bdd7dee893508e470fa83d8

check_src() {
	[[ $(git -C "$SRC/build-src-davs2/davs2" rev-parse HEAD) == "$DAVS2_SHA" ]]
	[[ $(git -C "$SRC/build-src-xavs2/xavs2" rev-parse HEAD) == "$XAVS2_SHA" ]]
}

# build NAME SRCDIR BITS [EXTRA_CFLAGS]
build() {
	local name=$1 src=$2 bits=$3 extra=${4:-} d=$B/$1
	[[ -x $d/build/linux/${name%%-*} ]] && return 0
	rm -rf "$d"
	cp -a "$src" "$d"
	(cd "$d/build/linux" &&
	 ./configure --bit-depth="$bits" --disable-asm --extra-cflags="$extra" > "$B/$name.configure.log" 2>&1 &&
	 make -j"$J" > "$B/$name.make.log" 2>&1)
	ls -l "$d/build/linux/${name%%-*}"
}

DAVS2_8=$B/davs2-8/build/linux/davs2
DAVS2_10=$B/davs2-10/build/linux/davs2
XAVS2_8=$B/xavs2-8/build/linux/xavs2
XAVS2_10=$B/xavs2-10/build/linux/xavs2
XAVS2_10WQ=$B/xavs2-10wq/build/linux/xavs2

stage_build() {
	check_src
	build davs2-8 "$SRC/build-src-davs2/davs2" 8
	build davs2-10 "$SRC/build-src-davs2/davs2" 10
	build xavs2-8 "$SRC/build-src-xavs2/xavs2" 8
	build xavs2-10 "$SRC/build-src-xavs2/xavs2" 10
	# xavs2 compiles weighting quantization out (ENABLE_WQUANT is never
	# defined); try a build with it on. Best effort: the code may not build.
	build xavs2-10wq "$SRC/build-src-xavs2/xavs2" 10 "-DENABLE_WQUANT=1" ||
		echo "xavs2 with ENABLE_WQUANT=1 failed to build (see $B/xavs2-10wq.make.log)"
}

# (1) PKU md5 convention: davs2 output (8-bit I420, output order) vs md5.txt.
stage_pku() {
	local f n want got out=$ES/pku
	mkdir -p "$out"
	: > "$out/pku-md5-check.txt"
	for f in "$SRC"/streams-gitee-hwren/repo/ES/*/test.avs2; do
		n=$(basename "$(dirname "$f")")
		"$DAVS2_8" -i "$f" -o "$out/$n.yuv" > "$out/$n.davs2.log" 2>&1
		want=$(grep -oiE '[0-9a-f]{32}' "$(dirname "$f")/md5.txt" | head -1 | tr A-F a-f)
		got=$(md5sum < "$out/$n.yuv" | cut -c1-32)
		w=${n#*_}; w=${w%%_*}
		$YT md5 "${w%x*}" "${w#*x}" 1 "$out/$n.yuv" > "$out/$n.framemd5"
		echo "$n md5.txt=$want davs2=$got $([[ $want == "$got" ]] && echo MATCH || echo DIFF)" | tee -a "$out/pku-md5-check.txt"
		rm -f "$out/$n.yuv"
	done
}

# (2) Main10 4K capture: davs2 10-bit frame md5s, keep 60 frames as encoder input.
stage_cctv() {
	local s=$ES/cctv4k-10bit.avs2 fifo=$B/cctv.fifo
	[[ -f $s ]] || python3 -I "$H/mkv2es.py" "$SRC/streams-github-xatabhk/CCTV4K.AVS2-10bit.AC3.CB.08-27-6s.mkv" "$s"
	rm -f "$fifo"; mkfifo "$fifo"
	$YT md5pipe 3840 2160 2 "$fifo" keep 60 "$B/cctv4k-10bit-60.yuv" > "$ES/cctv4k-10bit.davs2.framemd5" &
	"$DAVS2_10" -i "$s" -o "$fifo" > "$ES/cctv4k-10bit.davs2.log" 2>&1
	wait
	rm -f "$fifo"
	tail -1 "$ES/cctv4k-10bit.davs2.framemd5"
}

# encode NAME ENCODER W H BITS INPUT CFG [-p k=v ...]
encode() {
	local name=$1 enc=$2 w=$3 h=$4 bits=$5 in=$6 cfg=$7 dec
	shift 7
	local prof=$(( bits == 10 ? 34 : 32 ))
	local level=$(( w > 1920 ? 0x54 : 0x42 ))
	"$enc" -f "$SRC/build-src-xavs2/xavs2/config/$cfg" \
		-p InputFile="$in" -p SourceWidth="$w" -p SourceHeight="$h" \
		-p InputSampleBitDepth="$bits" -p SampleBitDepth="$bits" \
		-p ProfileID=$prof -p LevelID=$level -p fps=50 \
		-p FramesToBeEncoded=30 -p IntraPeriodMin=24 -p IntraPeriodMax=24 \
		-p PresetLevel=2 -p ThreadFrames=0 -p ThreadRows=0 -p LogLevel=1 \
		-p OutputFile="$ES/$name.avs2" -p ReconFile="$B/$name.rec.yuv" "$@" \
		> "$ES/$name.xavs2.log" 2>&1
	dec=$DAVS2_8; [[ $bits == 10 ]] && dec=$DAVS2_10
	"$dec" -i "$ES/$name.avs2" -o "$B/$name.dec.yuv" > "$ES/$name.davs2.log" 2>&1 || true
	local bps=$(( bits == 10 ? 2 : 1 ))
	$YT md5 "$w" "$h" $bps "$B/$name.rec.yuv" > "$ES/$name.xavs2-recon.framemd5"
	$YT md5 "$w" "$h" $bps "$B/$name.dec.yuv" > "$ES/$name.davs2.framemd5" || true
	echo "$name recon $(tail -1 "$ES/$name.xavs2-recon.framemd5") / davs2 $(tail -1 "$ES/$name.davs2.framemd5")" | tee -a "$ES/encode-summary.txt"
	rm -f "$B/$name.rec.yuv" "$B/$name.dec.yuv"
}

# (3) xavs2 streams. xavs2 at this commit always writes
# background_picture_disable = 1, so no background (G/GB/S) streams.
stage_encode() {
	local s4=$B/cctv4k-10bit-60.yuv s2=$B/cctv1080-10bit-60.yuv s2_8=$B/cctv1080-8bit-60.yuv s4_8=$B/cctv4k-8bit-60.yuv
	[[ -f $s2 ]] || $YT half 3840 2160 2 "$s4" "$s2"
	[[ -f $s2_8 ]] || $YT to8 1920 1080 "$s2" "$s2_8"
	[[ -f $s4_8 ]] || $YT to8 3840 2160 "$s4" "$s4_8"
	: > "$ES/encode-summary.txt"
	encode main10-1080p-ra   "$XAVS2_10" 1920 1080 10 "$s2" encoder_ra.cfg
	encode main10-1080p-ldp  "$XAVS2_10" 1920 1080 10 "$s2" encoder_ldp.cfg
	encode main10-1080p-tid  "$XAVS2_10" 1920 1080 10 "$s2" encoder_ra.cfg -p TemporalIdExistFlag=1
	encode main10-1080p-lf   "$XAVS2_10" 1920 1080 10 "$s2" encoder_ra.cfg \
		-p LoopFilterParameter=1 -p LoopFilterAlphaOffset=3 -p LoopFilterBetaOffset=-2 \
		-p ChromaDeltaQPDisable=0 -p ChromaDeltaU=2 -p ChromaDeltaV=-3
	encode main10-2160p-ra   "$XAVS2_10" 3840 2160 10 "$s4" encoder_ra.cfg
	encode main-2160p-ra     "$XAVS2_8"  3840 2160 8  "$s4_8" encoder_ra.cfg
	encode main-1080p-ra     "$XAVS2_8"  1920 1080 8  "$s2_8" encoder_ra.cfg
	if [[ -x $XAVS2_10WQ ]]; then
		encode wq-seqdef-1080p   "$XAVS2_10WQ" 1920 1080 10 "$s2" encoder_ra.cfg \
			-p WQEnable=1 -p SeqWQM=0 -p PicWQEnable=1 -p PicWQDataIndex=0
		encode wq-param-1080p    "$XAVS2_10WQ" 1920 1080 10 "$s2" encoder_ra.cfg \
			-p WQEnable=1 -p SeqWQM=0 -p PicWQEnable=1 -p PicWQDataIndex=1 -p WQParam=1 -p WQModel=1
		encode wq-param2-2160p   "$XAVS2_10WQ" 3840 2160 10 "$s4" encoder_ra.cfg \
			-p WQEnable=1 -p SeqWQM=0 -p PicWQEnable=1 -p PicWQDataIndex=1 -p WQParam=2 -p WQModel=3
	fi
	(cd "$ES" && sha256sum ./*.avs2 > SHA256SUMS)
}

case $STAGE in
build) stage_build ;;
pku) stage_pku ;;
cctv) stage_cctv ;;
encode) stage_encode ;;
all) stage_build; stage_pku; stage_cctv; stage_encode ;;
*) echo "STAGE=build|pku|cctv|encode|all"; exit 2 ;;
esac
