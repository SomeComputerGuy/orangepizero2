#!/bin/bash
# Mechanical checks of a run-job.sh result directory: check-results.sh <logs/runner>; prints CHECK n ...: PASS|FAIL|SKIP and VERDICT.
O=${1:?dir}; fail=0
res() { echo "CHECK $1 $2: $3 ($4)"; [ "$3" = FAIL ] && fail=1; return 0; }
# 0 kernel: the test kernel is a cumulative kernel (run-job.sh refuses one without the MG1S commit)
k=$(head -1 $O/kernel.txt 2>/dev/null); [[ $k == cumulative\ c* ]] && res 0 "kernel" PASS "$k $(sed -n 2p $O/kernel.txt)" || res 0 "kernel" FAIL "kernel.txt: ${k:-missing}"
# 1 stock kernel: coded formats recorded; MG1S is or is not there (fact)
if [ -s $O/fmts-stock.txt ]; then if grep -q MG1S $O/fmts-stock.txt; then smg=1; res 1 "stock formats" PASS "stock kernel $(cat $O/kernel-stock.txt 2>/dev/null) already enumerates MG1S"; else smg=0; res 1 "stock formats" PASS "stock kernel $(cat $O/kernel-stock.txt 2>/dev/null) has no MG1S: $(grep -c "'" $O/fmts-stock.txt) formats listed"; fi; else smg=-1; res 1 "stock formats" FAIL "fmts-stock.txt missing"; fi
# 2 probe: without MG1S the MPEG-1 hwaccel must not initialise: same md5 as software and 0 cedrus IRQs for both streams
if [ $smg = 0 ]; then n=$(awk -F'\t' '$4=="same=1" && $5=="irqs=0"' $O/swfb-stock.tsv 2>/dev/null | wc -l); t=$(wc -l < $O/swfb-stock.tsv 2>/dev/null)
  [ "$t" = 2 ] && [ "$n" = 2 ] && res 2 "software fallback without MG1S" PASS "2/2 streams same=1 irqs=0" || res 2 "software fallback without MG1S" FAIL "$n of ${t:-0} streams same=1 irqs=0: $(cat $O/swfb-stock.tsv 2>/dev/null | tr '\n' ' ')"
elif [ $smg = 1 ]; then res 2 "software fallback without MG1S" SKIP "stock kernel enumerates MG1S; swfb-stock.tsv: $(cat $O/swfb-stock.tsv | tr '\n' ' ')"
else res 2 "software fallback without MG1S" FAIL "no stock stage"; fi
# 3 test kernel: MG1S enumerated once, on the cedrus node, with the shared description
l=$(awk '/^== /{d=$0} /MG1S/{print d " :: " $0}' $O/fmts-test.txt 2>/dev/null)
if [ "$(grep -c MG1S $O/fmts-test.txt 2>/dev/null)" = 1 ] && grep -q 'driver=cedrus' <<< "$l" && grep -q "'MG1S' (MPEG-1 Parsed Slice Data, compressed)" $O/fmts-test.txt; then res 3 "MG1S enumerated on cedrus" PASS "$l; framesizes: $(head -3 $O/framesizes-test.txt | tr '\n' ' ')"
else res 3 "MG1S enumerated on cedrus" FAIL "fmts-test.txt MG1S lines: $(grep -c MG1S $O/fmts-test.txt 2>/dev/null) :: $l"; fi
# 4 v4l2-compliance (stock binary on the board): no more failures than on the stock kernel, none about MPEG
cf() { grep -h 'Total for' $1 2>/dev/null | tail -1 | sed -n 's/.*Failed: \([0-9]*\).*/\1/p'; }
ts=$(cf $O/compliance-stock.txt); tt=$(cf $O/compliance-test.txt); bad=$(grep -iE 'fail' $O/compliance-test.txt 2>/dev/null | grep -icE 'mpeg|mg1s')
if [ -n "$tt" ] && [ -n "$ts" ] && [ "$tt" -le "$ts" ] && [ "$bad" = 0 ]; then res 4 "v4l2-compliance" PASS "test: $(grep -h 'Total for' $O/compliance-test.txt | tail -1); stock: $(grep -h 'Total for' $O/compliance-stock.txt | tail -1)"
else res 4 "v4l2-compliance" FAIL "test Failed=${tt:-?} stock Failed=${ts:-?} mpeg-fail-lines=$bad; $(grep -h 'fail:' $O/compliance-test.txt 2>/dev/null | head -8 | tr '\n' ' ')"; fi
# 5 ccm1 bit-exact in hardware (129 frames, 129 IRQs)
c=$(grep -P '^m1-ccm1\t' $O/md5/summary.tsv 2>/dev/null); grep -q 'match=129/129' <<< "$c" && grep -q 'irqs=129' <<< "$c" && res 5 "ccm1 md5 in hardware" PASS "$c" || res 5 "ccm1 md5 in hardware" FAIL "${c:-no summary line}"
# 6 tcela-18: 31 D-pictures decoded in hardware, bit-exact against the DC reference, probe says decoded
d=$(cat $O/dpic.txt 2>/dev/null | tr '\n' ' '); grep -q 'frames=31 exact=31' <<< "$d" && grep -q 'irqs=31' <<< "$d" && grep -q 'D-pictures are decoded by the device' <<< "$d" && res 6 "tcela-18 D-pictures in hardware" PASS "$d" || res 6 "tcela-18 D-pictures in hardware" FAIL "${d:-no dpic.txt}"
# 7 IDCT envelope: all frames, HW within max(2, simple~int envelope) of the closest software IDCT
python3 -I - "$O/raw/raw.tsv" <<'PY'
import re, sys
exp = {'m1-MEI.stream16': 61, 'm1-MEI': 4, 'm1-tcela-16': 31, 'm1-tcela-19': 31, 'g-mpeg1-1080p30': 300}
seen = {}; out = []
try:
    for line in open(sys.argv[1]):
        f = line.rstrip('\n').split('\t')
        if len(f) < 8: continue
        tag = f[0]; irqs = int(re.search(r'irqs=(\d+)', f[4]).group(1))
        def g(s, k): return int(re.search(k + r'=(\d+)', s).group(1))
        idcts = [x for x in f[5:] if not x.startswith('envelope')]; env = [x for x in f[5:] if x.startswith('envelope')][0]
        frames = min(g(x, 'frames') for x in idcts); best = min(g(x, 'maxdiff') for x in idcts); envm = g(env, 'maxdiff')
        ok = frames == exp.get(tag, -1) and best <= max(2, envm) and irqs == frames
        seen[tag] = ok; out.append(f"{tag} frames={frames}/{exp.get(tag)} irqs={irqs} hw_max={best} env_max={envm} {'ok' if ok else 'BAD'}")
except FileNotFoundError: pass
missing = [t for t in exp if t not in seen]
ok = not missing and all(seen.values())
print(f"CHECK 7 IDCT envelope (MEI x2, tcela-16/19, 1080p30): {'PASS' if ok else 'FAIL'} ({'; '.join(out)}{'; missing: ' + ' '.join(missing) if missing else ''})")
sys.exit(0 if ok else 1)
PY
[ $? = 0 ] || fail=1
# 8 MPEG-2 unchanged (MG2S): tcela-15 61/61 and mcp10ccett 4/4 bit-exact in hardware
a=$(grep -P '^m2-tcela-15\t' $O/mpeg2/summary.tsv 2>/dev/null); b=$(grep -P '^m2-mcp10ccett\t' $O/mpeg2/summary.tsv 2>/dev/null)
grep -q 'match=61/61' <<< "$a" && grep -q 'irqs=61' <<< "$a" && grep -q 'match=4/4' <<< "$b" && grep -q 'irqs=4' <<< "$b" && res 8 "MPEG-2 regression" PASS "$a | $b" || res 8 "MPEG-2 regression" FAIL "${a:-no tcela-15 line} | ${b:-no mcp10ccett line}"
# 9 dmesg
dm=$(cat $O/dmesg-*.txt 2>/dev/null | grep -iE 'timed out|oops|warning|fault|bug:' | grep -v 'Default' | head -5)
[ -z "$dm" ] && res 9 "dmesg" PASS "no timeout/fault/Oops/WARNING in dmesg-*.txt" || res 9 "dmesg" FAIL "$dm"
[ $fail = 0 ] && echo "VERDICT: PASS" || echo "VERDICT: FAIL"
