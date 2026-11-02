#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Build the approved AVS2 reference tools on the HOST and make reference
# md5s and test streams for the cedrus AVS2 decoder
# (harness/research/impl-avs2.md §5, research/avs2/test-streams.md).
#
# Approved external code (user, 2026-11-02, "Approve both"), host only:
#   pkuvcl/davs2 b41cf117452e2d73d827f02d3e30aa20f1c721ac (GPL-2.0+)
#   pkuvcl/xavs2 eae1e8b9d12468059bdd7dee893508e470fa83d8 (GPL-2.0)
# Both are 8-bit only at these commits:
#   - both configure scripts reject --bit-depth=9/10 ("not supported currently");
#   - an 8-bit davs2 rejects Main10 sequences ("Un-supported bit-depth",
#     source/common/header.cc:1064). Its HIGH_BIT_DEPTH path is untested
#     upstream and is NOT forced on here;
#   - xavs2 has no 10-bit code at all: pel_t is always uint8_t
#     (source/common/basic_types.h:50), and its 10-bit recon writer would
#     write half rows anyway (yuv_writer.c, img_w bytes per row).
# So this script makes 8-bit references only. For the 10-bit gap see
# impl-avs2.md §5b.
#
# Sources (sha256 of `git archive HEAD`):
#   kernel-check/dl-avs2/build-src-davs2/davs2  9c61d8021b960bf27fbc30993903942aa1137407e503cf3dfa60c86aed07c5f5
#   kernel-check/dl-avs2/build-src-xavs2/xavs2  071ef366ea5603478e896cb229c752498378fba7717be11e1d2e5da5474d5e5d
# Builds: kernel-check/avs2-build/   Streams and md5s: kernel-check/avs2-es/
# No nasm on the host: built with --disable-asm (slow, bit-exact).
#
# References:
#   PKU streams: md5.txt, checked against davs2-8.
#   xavs2 streams: the xavs2 encoder reconstruction (ReconFile, output
#     order), which a conforming decoder reproduces by construction. davs2-8
#     md5s are added as a cross-check; they are expected to DIFFER for the
#     WQ streams, because davs2 never parses picture-level WQ.
#   cctv4k-10bit: no reference (no open 10-bit AVS2 decoder). Only the
#     davs2-8 probe is run, which records whether davs2-8 refuses the
#     stream or decodes it (an untrusted result either way).
#
# Every step is independent and non-fatal. Finished builds and outputs are
# reused, and a per-step PASS/FAIL/SKIP summary is printed at the end.
#
#   ./make-refs.sh               all stages: build pku probe10 src encode
#   ./make-refs.sh pku encode    only some stages
set -uo pipefail
TOP=/home/aruni/orangepizero2
K=$TOP/kernel-check
SRC=$K/dl-avs2
B=$K/avs2-build
ES=$K/avs2-es
H=$TOP/harness/avs2dec
J=${JOBS:-$(nproc)}
YT=(python3 -I "$H/yuvtool.py")
mkdir -p "$B" "$ES"
LOG=$ES/make-refs.log
SUMMARY=()

DAVS2_SHA=b41cf117452e2d73d827f02d3e30aa20f1c721ac
XAVS2_SHA=eae1e8b9d12468059bdd7dee893508e470fa83d8
DAVS2_8=$B/davs2-8/build/linux/davs2
XAVS2_8=$B/xavs2-8/build/linux/xavs2
XAVS2_8WQ=$B/xavs2-8wq/build/linux/xavs2

log() { echo "$*" | tee -a "$LOG"; }
result() { SUMMARY+=("$1 $2${3:+ ($3)}"); log "== $1: $2${3:+ ($3)}"; }

# step NAME CMD...: run one step and record PASS/FAIL; never abort the script
step() {
	local name=$1
	shift
	log "-- $name"
	if "$@" >> "$LOG" 2>&1; then
		result "$name" PASS
	else
		result "$name" FAIL "see $LOG"
	fi
}

# ------------------------------------------------------------------ build
# build_one NAME SRCDIR EXTRA_CFLAGS SHA; reuses a finished build (.ok marker)
build_one() {
	local name=$1 src=$2 extra=$3 sha=$4 d=$B/$1 bin=${1%%-*}
	if [[ -f $d/.ok && -x $d/build/linux/$bin ]]; then
		echo "$name: reusing $d"
		return 0
	fi
	# A binary built by an earlier version of this script is reused too.
	if [[ -x $d/build/linux/$bin && -f $B/$name.make.log ]] && grep -q "$sha" <(git -C "$d" rev-parse HEAD 2>/dev/null); then
		touch "$d/.ok"
		echo "$name: reusing earlier build $d"
		return 0
	fi
	[[ $(git -C "$src" rev-parse HEAD) == "$sha" ]] || { echo "$src is not at $sha"; return 1; }
	rm -rf "${d:?}"
	cp -a "$src" "$d" || return 1
	(cd "$d/build/linux" &&
	 ./configure --bit-depth=8 --disable-asm ${extra:+--extra-cflags="$extra"} \
		> "$B/$name.configure.log" 2>&1 &&
	 make -j"$J" > "$B/$name.make.log" 2>&1) ||
		{ echo "$name: build failed, see $B/$name.*.log"; return 1; }
	touch "$d/.ok"
}

# xavs2 (2019) predates GCC 14, which made -Wincompatible-pointer-types an error
# (xavs2_threadpool_run callers in encoder.c); downgrade it back to a warning.
stage_build() {
	# davs2 has no supported 10-bit build; remove the failed first attempt
	rm -rf "${B:?}/davs2-10"
	step build:davs2-8  build_one davs2-8  "$SRC/build-src-davs2/davs2" "" $DAVS2_SHA
	step build:xavs2-8  build_one xavs2-8  "$SRC/build-src-xavs2/xavs2" "-Wno-error=incompatible-pointer-types" $XAVS2_SHA
	# xavs2 compiles weighting quantization out (ENABLE_WQUANT is never
	# defined). Best effort: the WQ code may not build or may not work.
	step build:xavs2-8wq build_one xavs2-8wq "$SRC/build-src-xavs2/xavs2" "-DENABLE_WQUANT=1 -Wno-error=incompatible-pointer-types" $XAVS2_SHA
}

# ------------------------------------------------------------------ pku
# (1) PKU md5 convention: davs2-8 output (8-bit I420, output order) vs md5.txt.
pku_one() {
	local f=$1 n out=$ES/pku want got w yuv
	n=$(basename "$(dirname "$f")")
	yuv=$B/pku-$n.yuv
	mkdir -p "$out"
	want=$(grep -oiE '[0-9a-f]{32}' "$(dirname "$f")/md5.txt" | head -1 | tr A-F a-f)
	if [[ ! -s $out/$n.framemd5 ]]; then
		"$DAVS2_8" -i "$f" -o "$yuv" > "$out/$n.davs2.log" 2>&1 || return 1
		w=${n#*_}
		w=${w%%_*}
		"${YT[@]}" md5 "${w%x*}" "${w#*x}" 1 "$yuv" > "$out/$n.framemd5.tmp" || return 1
		mv "$out/$n.framemd5.tmp" "$out/$n.framemd5"
		# ParkScene is kept as the encoder source (stage src)
		[[ $n == ParkScene_1920x1080_24_ra ]] || rm -f "${yuv:?}"
	fi
	got=$(tail -1 "$out/$n.framemd5" | awk '{print $NF}')
	echo "$n md5.txt=$want davs2-8=$got"
	[[ $want == "$got" ]]
}

stage_pku() {
	local f
	[[ -x $DAVS2_8 ]] || { result pku SKIP "no davs2-8"; return; }
	for f in "$SRC"/streams-gitee-hwren/repo/ES/*/test.avs2; do
		step "pku:$(basename "$(dirname "$f")")" pku_one "$f"
	done
}

# ------------------------------------------------------------------ probe10
# Does davs2-8 decode a Main10 stream? Expected: it refuses the sequence.
# Both outcomes PASS; the summary says which one happened.
probe10() {
	local s=$ES/cctv4k-10bit.avs2 o=$ES/cctv4k-10bit.davs2-8-probe yuv=$B/probe10.yuv rc size
	[[ -f $s ]] || python3 -I "$H/mkv2es.py" \
		"$SRC/streams-github-xatabhk/CCTV4K.AVS2-10bit.AC3.CB.08-27-6s.mkv" "$s" || return 1
	if [[ ! -s $o.result ]]; then
		timeout 900 "$DAVS2_8" -i "$s" -o "$yuv" > "$o.log" 2>&1
		rc=$?
		size=$(stat -c %s "$yuv" 2>/dev/null || echo 0)
		if grep -q 'Un-supported bit-depth' "$o.log" || (( size == 0 )); then
			echo "REFUSED rc=$rc output_bytes=$size" > "$o.result"
		else
			# It produced output: record it, but it is NOT a reference
			# (an 8-bit build cannot reconstruct 10-bit samples).
			echo "DECODED rc=$rc output_bytes=$size md5=$(md5sum < "$yuv" | cut -c1-32) (untrusted, not a reference)" > "$o.result"
		fi
		rm -f "${yuv:?}"
	fi
	cat "$o.result"
}

stage_probe10() {
	[[ -x $DAVS2_8 ]] || { result probe10 SKIP "no davs2-8"; return; }
	step probe10:davs2-8-on-main10 probe10
	SUMMARY[-1]="${SUMMARY[-1]} -> $(cat "$ES/cctv4k-10bit.davs2-8-probe.result" 2>/dev/null)"
}

# ------------------------------------------------------------------ src
# Encoder sources, from the md5-verified PKU ParkScene decode (8-bit 1080p):
# its first 30 frames, and a 2x upscale of them for 4K.
S1080=$B/src-1080p-8bit.yuv
S2160=$B/src-2160p-8bit.yuv
make_src() {
	local p=$B/pku-ParkScene_1920x1080_24_ra.yuv
	if [[ ! -s $S1080 ]]; then
		[[ -s $p ]] || { echo "run stage pku first ($p missing)"; return 1; }
		"${YT[@]}" head 1920 1080 1 30 "$p" "$S1080.tmp" && mv "$S1080.tmp" "$S1080" || return 1
	fi
	if [[ ! -s $S2160 ]]; then
		"${YT[@]}" up2 1920 1080 1 "$S1080" "$S2160.tmp" && mv "$S2160.tmp" "$S2160" || return 1
	fi
	ls -l "$S1080" "$S2160"
}

stage_src() { step src:parkscene-derived make_src; }

# ------------------------------------------------------------------ encode
# encode_one NAME ENCODER W H FRAMES INPUT CFG [-p k=v ...]
encode_one() {
	local name=$1 enc=$2 w=$3 h=$4 n=$5 in=$6 cfg=$7
	shift 7
	local level=$(( w > 1920 ? 0x54 : 0x42 ))
	local rec=$B/$name.rec.yuv dec=$B/$name.dec.yuv fs=$(( w * h * 3 / 2 ))
	[[ -x $enc ]] || { echo "encoder $enc not built"; return 1; }
	[[ -s $in ]] || { echo "source $in missing"; return 1; }
	if [[ ! -s $ES/$name.avs2 || ! -s $ES/$name.xavs2-recon.framemd5 ]]; then
		"$enc" -f "$SRC/build-src-xavs2/xavs2/config/$cfg" \
			-p InputFile="$in" -p SourceWidth="$w" -p SourceHeight="$h" \
			-p InputSampleBitDepth=8 -p SampleBitDepth=8 \
			-p ProfileID=32 -p LevelID=$level -p fps=50 \
			-p FramesToBeEncoded="$n" -p IntraPeriodMin=24 -p IntraPeriodMax=24 \
			-p PresetLevel=2 -p ThreadFrames=0 -p ThreadRows=0 -p LogLevel=1 \
			-p OutputFile="$ES/$name.avs2.tmp" -p ReconFile="$rec" "$@" \
			> "$ES/$name.xavs2.log" 2>&1 || return 1
		[[ $(stat -c %s "$rec" 2>/dev/null) == $(( n * fs )) ]] ||
			{ echo "$name: recon size $(stat -c %s "$rec" 2>/dev/null) != $(( n * fs ))"; return 1; }
		"${YT[@]}" md5 "$w" "$h" 1 "$rec" > "$ES/$name.xavs2-recon.framemd5" || return 1
		mv "$ES/$name.avs2.tmp" "$ES/$name.avs2"
		rm -f "${rec:?}"
	fi
	echo "$name: recon $(tail -1 "$ES/$name.xavs2-recon.framemd5")"
	# davs2-8 cross-check (informational; the recon is the reference)
	if [[ -x $DAVS2_8 && ! -s $ES/$name.davs2-8.framemd5 ]]; then
		if "$DAVS2_8" -i "$ES/$name.avs2" -o "$dec" > "$ES/$name.davs2-8.log" 2>&1; then
			"${YT[@]}" md5 "$w" "$h" 1 "$dec" > "$ES/$name.davs2-8.framemd5"
		fi
		rm -f "${dec:?}"
	fi
	if [[ -s $ES/$name.davs2-8.framemd5 ]]; then
		if [[ $(tail -1 "$ES/$name.davs2-8.framemd5") == "$(tail -1 "$ES/$name.xavs2-recon.framemd5")" ]]; then
			echo "$name: davs2-8 matches recon"
		else
			echo "$name: davs2-8 DIFFERS from recon (expected only for WQ streams)"
		fi
	fi
}

stage_encode() {
	step enc:main-1080p-ra   encode_one main-1080p-ra   "$XAVS2_8" 1920 1080 30 "$S1080" encoder_ra.cfg
	step enc:main-1080p-ldp  encode_one main-1080p-ldp  "$XAVS2_8" 1920 1080 30 "$S1080" encoder_ldp.cfg
	step enc:main-1080p-tid  encode_one main-1080p-tid  "$XAVS2_8" 1920 1080 30 "$S1080" encoder_ra.cfg \
		-p TemporalIdExistFlag=1
	step enc:main-1080p-lf   encode_one main-1080p-lf   "$XAVS2_8" 1920 1080 30 "$S1080" encoder_ra.cfg \
		-p LoopFilterParameter=1 -p LoopFilterAlphaOffset=3 -p LoopFilterBetaOffset=-2 \
		-p ChromaDeltaQPDisable=0 -p ChromaDeltaU=2 -p ChromaDeltaV=-3
	step enc:main-2160p-ra   encode_one main-2160p-ra   "$XAVS2_8" 3840 2160 20 "$S2160" encoder_ra.cfg
	# Weighting quantization (only if the -DENABLE_WQUANT=1 build worked)
	step enc:wq-seqdef-1080p encode_one wq-seqdef-1080p "$XAVS2_8WQ" 1920 1080 30 "$S1080" encoder_ra.cfg \
		-p WQEnable=1 -p SeqWQM=0 -p PicWQEnable=1 -p PicWQDataIndex=0
	step enc:wq-param1-1080p encode_one wq-param1-1080p "$XAVS2_8WQ" 1920 1080 30 "$S1080" encoder_ra.cfg \
		-p WQEnable=1 -p SeqWQM=0 -p PicWQEnable=1 -p PicWQDataIndex=1 -p WQParam=1 -p WQModel=1
	step enc:wq-param2-2160p encode_one wq-param2-2160p "$XAVS2_8WQ" 3840 2160 20 "$S2160" encoder_ra.cfg \
		-p WQEnable=1 -p SeqWQM=0 -p PicWQEnable=1 -p PicWQDataIndex=1 -p WQParam=2 -p WQModel=3
	(cd "$ES" && sha256sum ./*.avs2 > SHA256SUMS) || true
}

STAGES=("$@")
(( ${#STAGES[@]} )) || STAGES=(build pku probe10 src encode)
log "make-refs.sh $(date -Is) stages: ${STAGES[*]}"
for s in "${STAGES[@]}"; do
	case $s in
	build|pku|probe10|src|encode) "stage_$s" ;;
	*) result "$s" FAIL "unknown stage" ;;
	esac
done

echo
echo "==================== summary ===================="
printf '%s\n' "${SUMMARY[@]}" | tee "$ES/make-refs-summary.txt"
grep -q ' FAIL' "$ES/make-refs-summary.txt" && exit 1
exit 0
