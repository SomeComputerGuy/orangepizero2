#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Host side of runner job 56: mechanical checks of build/gst-jpeg/results-stateful/out/results.txt.
#   check.sh OUTDIR VECDIR      prints one line per check (PASS/FAIL), then VERDICT
set -u
O=$1; V=$2; R=$O/results.txt
[ -f "$R" ] || { echo "VERDICT: BLOCKED (no results.txt)"; exit 2; }
f() { grep "^$1 " "$R" | head -1 | grep -o "$2=[^ ]*" | cut -d= -f2-; }   # field of a case line
fail=0
chk() { if [ "$2" = ok ]; then echo "$1: PASS | $3"; else echo "$1: FAIL | $3"; fail=1; fi; }
F=3133440        # 1920x1088 I420
MJ=8640000       # 15 x 640x480 + 15 x 320x240 I420
line() { grep "^$1 " "$R" | head -1; }
# C0: the references (v4l2sljpegdec, unchanged) ran
s=ok; for c in sl-still sl-loop5 sl-mjmix sl-mjmixup; do [ "$(f $c rc)" = 0 ] || s=bad; done
[ "$(f sl-still size)" = $F ] && [ "$(f sl-loop5 size)" = $((5*F)) ] && [ "$(f sl-mjmix size)" = $MJ ] && [ "$(f sl-mjmixup size)" = $MJ ] || s=bad
chk C0-references $s "$(for c in sl-still sl-loop5 sl-mjmix sl-mjmixup; do echo -n "$c rc=$(f $c rc) size=$(f $c size); "; done)"
# C1..C3: explicit stateful v4l2jpegdec: EOS reached (rc 0), STOP accepted, same pixels as v4l2sljpegdec, no kernel lines
for p in "C1-still sf-still sl-still $F" "C2-loop5 sf-loop5 sl-loop5 $((5*F))" "C3a-mjmix sf-mjmix sl-mjmix $MJ" "C3b-mjmixup sf-mjmixup sl-mjmixup $MJ"; do
	set -- $p
	s=ok
	[ "$(f $2 rc)" = 0 ] || s=bad
	[ "$(f $2 size)" = "$4" ] || s=bad
	[ "$(f $2 md5)" = "$(f $3 md5)" ] || s=bad
	[ "$(f $2 cmdfail)" = 0 ] || s=bad
	[ "$(f $2 stopwait)" -ge 1 ] 2>/dev/null || s=bad
	[ "$(f $2 dmesg)" = +0 ] || s=bad
	chk $1 $s "$(line $2) | ref md5=$(f $3 md5)"
done
# C4: no rank override: decodebin autoplugs the stateful v4l2jpegdec for a 16-aligned picture and now finishes
s=ok; [ "$(f nr16-db rc)" = 0 ] && grep -q 'picked=\[.*v4l2jpegdec' <<< "$(line nr16-db)" && [ "$(f nr16-db md5)" = "$(f sl-still md5)" ] && [ "$(f nr16-db dmesg)" = +0 ] || s=bad
chk C4-norank16 $s "$(line nr16-db)"
# C5: with the image's override (v4l2jpegdec:MARGINAL) decodebin picks v4l2sljpegdec, as before
s=ok; [ "$(f ov16-db rc)" = 0 ] && grep -q 'picked=\[v4l2sljpegdec' <<< "$(line ov16-db)" && [ "$(f ov16-db md5)" = "$(f sl-still md5)" ] && [ "$(f ov16-db dmesg)" = +0 ] || s=bad
chk C5-override $s "$(line ov16-db)"
# C6: stateless regression (H.264, v4l2slh264dec): all 30 frames, no kernel lines; md5 vs host ffmpeg is info
s=ok; [ "$(f h264 rc)" = 0 ] && [ "$(f h264 size)" = $((30*460800)) ] && [ "$(f h264 dmesg)" = +0 ] || s=bad
ref=$(cat "$V/h264-640x480.i420.md5" 2>/dev/null)
if [ "$(f h264 md5)" = "$ref" ]; then m="md5 == ffmpeg"; else m="md5 != ffmpeg $ref (info)"; fi
chk C6-h264 $s "$(line h264) | $m"
# C7: the whole run left no cedrus error and no kernel warning in the log
n=$(grep -Ec 'Failed to setup decoding job|cedrus.*(rror|timed out)|WARNING:|Oops|BUG:|Unable to handle' "$O/dmesg.txt" 2>/dev/null)
[ "${n:-0}" = 0 ] && s=ok || s=bad
chk C7-dmesg $s "$(wc -l < "$O/dmesg.txt" 2>/dev/null || echo ?) kernel log lines, $n matching errors"
[ $fail = 0 ] && echo "VERDICT: PASS" || echo "VERDICT: FAIL"
exit 0
