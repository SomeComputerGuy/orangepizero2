#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Board test of the cavs_v4l2request hwaccel (FFmpeg worktree wt-avs, build-avs). Caller holds the board lock.
# Usage: harness/ffmpeg/avs-board-test.sh <outdir> [copy]   ("copy": scp ffmpeg + streams to /root/ffavs first)
# Per stream: HW decode on the board -> framecrc and framemd5 (yuv420p, via hwdownload; a software fallback makes
# hwdownload fail), compared with kernel-check/avs1-refs-master (crc column only); then a -f null run for fps.
set -uo pipefail
H=$(cd "$(dirname "$0")/../.." && pwd); SSH=$H/harness/ssh.sh; O=${1:?outdir}; mkdir -p "$O"
DL=$H/kernel-check/dl-avs1; REF=$H/kernel-check/avs1-refs-master
B=/root/ffavs
if [ "${2:-}" = copy ]; then
	$SSH "mkdir -p $B"
	. "$H/harness/ssh-opts.sh"; scp -q "${BOARD_SSH_OPTS[@]}" \
		"$H/kernel-check/ffmpeg-deb/build-avs/ffmpeg" "$DL/fate-bunny/bunny.mp4" \
		"$DL/fate-avsplus-1080i-testcard/avsplus-1080i-testcard.ts" "$DL/fate-cavs/cavs.mpg" \
		"$DL/ffsamples-avsfileformat/AVSFileFormat.es" "root@10.56.0.107:$B/"
fi
FF="$B/ffmpeg -nostdin -hide_banner -loglevel warning"
HW="-hwaccel v4l2request -hwaccel_output_format drm_prime"
OUT="-an -fps_mode passthrough -noautoscale -vf hwdownload,format=nv12,format=yuv420p"
irq() { $SSH -n "awk '/1c0e000.video-codec/{print \$2+\$3+\$4+\$5}' /proc/interrupts"; }
crc() { grep -v '^#' "$1" | awk -F, '{print $NF}' | tr -d ' '; }
: > "$O/summary.tsv"
while IFS='|' read -r tag file opts ref; do
	[ -z "$tag" ] && continue
	i0=$(irq)
	$SSH -n "$FF $HW $opts -i $B/$file $OUT -f framecrc -" > "$O/$tag.hw.framecrc" 2> "$O/$tag.framecrc.err"; rc=$?
	i1=$(irq)
	$SSH -n "$FF $HW $opts -i $B/$file $OUT -f framemd5 -" > "$O/$tag.hw.framemd5" 2> "$O/$tag.framemd5.err"
	n=$(grep -vc '^#' "$O/$tag.hw.framecrc")
	if [ -n "$ref" ] && [ -f "$REF/$ref.framecrc" ]; then
		nref=$(grep -vc '^#' "$REF/$ref.framecrc")
		bad=$(diff <(crc "$O/$tag.hw.framecrc") <(crc "$REF/$ref.framecrc") | grep -c '^[<>]')
		md5bad=$(diff <(crc "$O/$tag.hw.framemd5") <(crc "$REF/$ref.framemd5") | grep -c '^[<>]')
		res="crc frames $n/$nref, differing lines $bad; md5 differing lines $md5bad"
	else
		res="frames $n (no reference)"
	fi
	# throughput: decode only, no download
	t=$($SSH -n "TIMEFORMAT=%R; time $B/ffmpeg -nostdin -hide_banner -loglevel error $HW $opts -i $B/$file -an -f null - 2>/dev/null" 2>&1 | tail -1)
	printf '%s\t%s\trc=%s\tirqs=%s\t%s\tnull-run %ss (%s frames)\n' "$tag" "$file" "$rc" "$((i1-i0))" "$res" "$t" "$n" | tee -a "$O/summary.tsv"
done <<'EOF'
bunny|bunny.mp4|-f cavsvideo|bunny.mp4
testcard|avsplus-1080i-testcard.ts||avsplus-1080i-testcard.ts
cavs|cavs.mpg||cavs.mpg
aff|AVSFileFormat.es|-f cavsvideo|
EOF
