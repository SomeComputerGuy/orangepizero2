#!/bin/bash
# SPDX-License-Identifier: MIT
# Host side of std-ctrl-test.sh: OUT_OLD OUT_NEW [TRUTHDIR]
#  - every output of the old kernel/tool must be bit-identical on the new one (same items by name, moved IDs)
#  - a method change while streaming: the outputs after it equal a fresh stream in the new method
#  - EBUSY cases: the stream goes on unchanged
#  - "Bob, Field Rate": luma PSNR against the truth (vs "Bob, Frame Rate")
set -u
O=$1; N=$2; TR=${3:-}; fails=0
ok() { printf '%-58s %s\n' "$1" "$2"; [[ $2 == PASS* ]] || fails=$((fails + 1)); }
for f in "$O"/*.yuv "$O"/fmd.stats.txt; do
	b=${f##*/}
	if [[ ! -f $N/$b ]]; then ok "old=new $b" "FAIL (missing)"
	elif cmp -s "$f" "$N/$b"; then ok "old=new $b" PASS
	else ok "old=new $b" "FAIL (differs)"; fi
done
fs=622080 # 720x576 I420/YV12
tailcmp() { # name sw fresh skip_frames
	local n=$1 s=$N/$2.yuv r=$N/$3.yuv k=$4
	if cmp -s <(tail -c +$((k * fs + 1)) "$s") "$r"; then ok "$n" PASS; else ok "$n" "FAIL"; fi
}
for p in field:bobfield:20 bobfield:field:20 frame:bob:10 bob:weave:10 weave:frame:10 frame:weave:10; do
	IFS=: read -r a b k <<< "$p"
	grep -q "switch to $b at input 10: ok" "$N/sw.$a.$b.log" || ok "switch $a -> $b accepted" FAIL
	tailcmp "switch $a -> $b = fresh $b after the switch" sw.$a.$b fresh.$b.k10 "$k"
done
grep -q 'switch to bob at input 10: ok' "$N/sw.tnr.frame.bob.log" || ok "switch tnr frame -> bob accepted" FAIL
tailcmp "TNR: switch frame -> bob = fresh" sw.tnr.frame.bob fresh.tnr.bob.k10 10
tailcmp "TNR: switch bob -> frame = fresh" sw.tnr.bob.frame fresh.tnr.frame.k10 10
grep -q 'switch to frame at input 10: Device or resource busy' "$N/sw.field.frame.log" &&
	cmp -s "$N/sw.field.frame.yuv" "$N/m576.field.yuv" && ok "field -> frame: EBUSY, stream unchanged" PASS ||
	ok "field -> frame: EBUSY, stream unchanged" FAIL
grep -q 'switch to tnr at input 10: Device or resource busy' "$N/sw.frame.tnr.log" &&
	cmp -s "$N/sw.frame.tnr.yuv" "$N/m576.frame.yuv" && ok "frame -> tnr-only: EBUSY, stream unchanged" PASS ||
	ok "frame -> tnr-only: EBUSY, stream unchanged" FAIL
for f in "$N"/prog.*.log; do
	b=${f##*/}; grep -q 'weave check: PASS' "$f" && ok "pass-through ${b%.log}" PASS || ok "pass-through ${b%.log}" FAIL
done
grep -q '^PASS' "$N/di300err.log" && ok "di300err" PASS || ok "di300err" FAIL
for v in m576 m576b m1080 m1080b; do
	n=$(stat -c %s "$N/$v.bobfield.yuv"); i=$(stat -c %s "$N/$v.weave.yuv")
	[[ $n -eq $((2 * i)) ]] && ok "$v bobfield: 2 outputs per input" PASS || ok "$v bobfield: 2 outputs per input" FAIL
done
echo "== kept fields (Bob, Field Rate; TFF then BFF) and timestamps"
grep -h -E '^(keep|out)' "$N/keep.bobfield.log" "$N/keep.bobfield.b.log"
if [[ -n $TR ]]; then
	echo "== luma PSNR vs truth"
	for v in m576 m576b; do
		for m in bobfield field; do
			echo "$v $m: $(python3 -I "$(dirname "$0")/psnr.py" 720 576 "$TR/$v.truth.yuv" "$N/$v.$m.yuv" 4 | tail -1)"
		done
	done
fi
echo "compliance (new): $(grep -E '^Total' "$N/compliance.log")"
echo "compliance (old): $(grep -E '^Total' "$O/compliance.log")"
echo "failures: $fails"
