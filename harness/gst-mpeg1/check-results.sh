#!/bin/bash
# Mechanical checks of a run-job.sh result directory: check-results.sh <build/gst-mpeg1/results>; prints CHECK n ...: PASS|FAIL|SKIP and VERDICT.
R=${1:?dir}; ST=$R/out-stock; TE=$R/out-test; fail=0
res() { echo "CHECK $1 $2: $3 ($4)"; [ "$3" = FAIL ] && fail=1; return 0; }
rl() { grep -E "^$2 $3 " $1/results.txt 2>/dev/null | head -1; }   # rl <outdir> NAME TAG
irqs() { grep -o 'irqs=[0-9-]*' <<< "$1" | cut -d= -f2; }
# 0 kernels: stock phase on the image kernel, test phase on a cumulative kernel (run-job.sh refuses one without the MG1S commit)
k=$(head -1 $R/kernel.txt 2>/dev/null); s=$(cat $R/kernel-stock.txt 2>/dev/null)
[[ $k == cumulative\ c* ]] && [[ $s == stock\ 7.3.1* ]] && res 0 "kernels" PASS "$s | $k $(sed -n 2p $R/kernel.txt)" || res 0 "kernels" FAIL "kernel-stock.txt: ${s:-missing}; kernel.txt: ${k:-missing}"
# 1 stock kernel without MG1S: the plugin must not offer mpegversion=1 ("MPEG-1 not supported") and decodebin must pick a software decoder for ccm1
smg=$(grep -c MG1S $ST/fmts.txt 2>/dev/null); db=$(rl $ST ccm1 db)
if [ "$smg" = 0 ]; then
  if grep -q 'MPEG-1 not supported' $ST/inspect.txt && ! grep -qE 'mpegversion: *(1|\{[^}]*\(int\)1)' $ST/inspect.txt && grep -q 'rc=0' <<< "$db" && ! grep -q v4l2slmpeg2dec <<< "$db" && [ "$(irqs "$db")" = 0 ]; then
    res 1 "software fallback without MG1S" PASS "stock: no MG1S, 'MPEG-1 not supported', no mpegversion=1 caps; ccm1 db: $db"
  else res 1 "software fallback without MG1S" FAIL "stock MG1S lines=$smg; inspect: $(grep -E 'MPEG-1|mpegversion' $ST/inspect.txt 2>/dev/null | tr -s ' ' | tr '\n' ';'); ccm1 db: ${db:-missing}"; fi
elif [ -n "$smg" ]; then res 1 "software fallback without MG1S" SKIP "stock kernel $s already enumerates MG1S; ccm1 db: $db"
else res 1 "software fallback without MG1S" FAIL "out-stock/fmts.txt missing"; fi
# 2 test kernel: MG1S on cedrus, plugin says "MPEG-1 supported" and offers mpegversion=1
if [ "$(grep -c MG1S $TE/fmts.txt 2>/dev/null)" = 1 ] && grep -q 'MPEG-1 supported' $TE/inspect.txt && grep -qE 'mpegversion: *(1|\{[^}]*\(int\)1)' $TE/inspect.txt; then
  res 2 "MG1S caps on the test kernel" PASS "$(grep MG1S $TE/fmts.txt | tr -s ' '); $(grep -E 'MPEG-1|mpegversion' $TE/inspect.txt | tr -s ' ' | tr '\n' ';')"
else res 2 "MG1S caps on the test kernel" FAIL "fmts MG1S lines=$(grep -c MG1S $TE/fmts.txt 2>/dev/null); $(grep -E 'MPEG-1|mpegversion' $TE/inspect.txt 2>/dev/null | tr -s ' ' | tr '\n' ';')"; fi
# 3 ccm1 in hardware: rc=0, 129 frames bit-exact against host software (simple IDCT), 129 cedrus IRQs
h=$(rl $TE ccm1 hw); c=$(grep -P '^ccm1\t' $R/compare.tsv 2>/dev/null)
grep -q 'rc=0' <<< "$h" && [ "$(irqs "$h")" = 129 ] && grep -q 'simple: frames=129 exact=129' <<< "$c" && res 3 "ccm1 hw md5" PASS "$h | $(grep -o 'simple: [^	]*' <<< "$c")" || res 3 "ccm1 hw md5" FAIL "${h:-no hw line} | ${c:-no compare line}"
# 4 tcela-18: 31 D-pictures decoded in hardware, bit-exact against the DC reference, probe says decoded
h=$(rl $TE tcela-18 hw); c=$(grep -P '^tcela-18\t' $R/compare.tsv 2>/dev/null); pr=$(grep -h 'D-pictures are' $TE/tcela-18.hw.log 2>/dev/null | head -1)
grep -q 'rc=0' <<< "$h" && [ "$(irqs "$h")" = 31 ] && grep -q 'frames=31 exact=31' <<< "$c" && grep -q 'D-pictures are decoded by the device' <<< "$pr" && res 4 "tcela-18 D-pictures in hardware" PASS "$h | $c | ${pr##*mpeg2dec }" || res 4 "tcela-18 D-pictures in hardware" FAIL "${h:-no hw line} | ${c:-no compare line} | probe: ${pr:-no line}"
# 5 IDCT envelope (MEI x2, tcela-16, tcela-19): rc=0, all frames, irqs == frames, HW within max(2, simple~int envelope) of the closest software IDCT
python3 -I - "$R/compare.tsv" "$TE/results.txt" <<'PY'
import re, sys
exp = {'MEI.stream16.long': 61, 'MEI.stream16v2': 4, 'tcela-16': 31, 'tcela-19': 31}
seen = {}; out = []
res = {}
try:
    for l in open(sys.argv[2]):
        f = l.split()
        if len(f) > 2 and f[1] == 'hw': res[f[0]] = l
    for line in open(sys.argv[1]):
        f = line.rstrip('\n').split('\t'); tag = f[0]
        if tag not in exp or len(f) < 6: continue
        def g(s, k): return int(re.search(k + r'=(\d+)', s).group(1))
        idcts = [x for x in f[2:] if not x.startswith('envelope')]; env = [x for x in f[2:] if x.startswith('envelope')][0]
        frames = min(g(x, 'frames') for x in idcts); best = min(g(x, 'maxdiff') for x in idcts); envm = g(env, 'maxdiff')
        r = res.get(tag, ''); rc0 = 'rc=0' in r; irqs = g(r, 'irqs') if 'irqs=' in r else -1
        ok = rc0 and frames == exp[tag] and best <= max(2, envm) and irqs == frames
        seen[tag] = ok; out.append(f"{tag} rc0={rc0} frames={frames}/{exp[tag]} irqs={irqs} hw_max={best} env_max={envm} {'ok' if ok else 'BAD'}")
except FileNotFoundError: pass
missing = [t for t in exp if t not in seen]
ok = not missing and all(seen.values())
print(f"CHECK 5 IDCT envelope (MEI x2, tcela-16/19): {'PASS' if ok else 'FAIL'} ({'; '.join(out)}{'; missing: ' + ' '.join(missing) if missing else ''})")
sys.exit(0 if ok else 1)
PY
[ $? = 0 ] || fail=1
# 6 MPEG-2 regression (MG2S): tcela-15 61/61 and mcp10ccett 4/4 bit-exact in hardware on the test kernel; tcela-15 md5 equal on the stock kernel
a=$(rl $TE tcela-15 hw); b=$(rl $TE mcp10ccett hw); ca=$(grep -P '^tcela-15\t' $R/compare.tsv 2>/dev/null); cb=$(grep -P '^mcp10ccett\t' $R/compare.tsv 2>/dev/null); as=$(rl $ST tcela-15 hw)
m() { cut -d' ' -f4 <<< "$1"; }
if grep -q 'rc=0' <<< "$a" && [ "$(irqs "$a")" = 61 ] && grep -q 'simple: frames=61 exact=61' <<< "$ca" && grep -q 'rc=0' <<< "$b" && [ "$(irqs "$b")" = 4 ] && grep -q 'simple: frames=4 exact=4' <<< "$cb" && [ -n "$(m "$a")" ] && [ "$(m "$a")" = "$(m "$as")" ]; then
  res 6 "MPEG-2 regression" PASS "test: $a | $b; stock tcela-15: $as"
else res 6 "MPEG-2 regression" FAIL "test: ${a:-no tcela-15} | ${b:-no mcp10ccett} | $(grep -o 'simple: [^	]*' <<< "$ca$cb" | tr '\n' ' ') | stock tcela-15: ${as:-missing}"; fi
# 7 autoplug on the test kernel: decodebin (ccm1, tcela-18, tcela-15) and playbin3 (ccm1) pick v4l2slmpeg2dec, rc=0, same md5 as the explicit hw run
ok=1; d=""
for c in "ccm1 db" "tcela-18 db" "tcela-15 db" "ccm1 pb3"; do set -- $c; l=$(rl $TE $1 $2); h=$(rl $TE $1 hw)
  grep -q 'rc=0' <<< "$l" && grep -q 'picked=\[[^]]*v4l2slmpeg2dec' <<< "$l" && [ -n "$(m "$l")" ] && [ "$(m "$l")" = "$(m "$h")" ] || ok=0; d="$d | $l"; done
[ $ok = 1 ] && res 7 "autoplug picks v4l2slmpeg2dec" PASS "${d# | }" || res 7 "autoplug picks v4l2slmpeg2dec" FAIL "${d# | }"
# 8 no hangs: no gst run hit the timeout (rc 124/137) in either phase
t=$(grep -hE 'rc=(124|137)' $ST/results.txt $TE/results.txt 2>/dev/null); [ -z "$t" ] && res 8 "no hangs" PASS "no rc=124/137 in results.txt" || res 8 "no hangs" FAIL "$t"
# 9 dmesg clean in both phases
dm=$(cat $ST/dmesg.txt $TE/dmesg.txt 2>/dev/null | grep -iE 'timed out|oops|warning|fault|bug:' | grep -v 'Default' | head -5)
[ -z "$dm" ] && res 9 "dmesg" PASS "no timeout/fault/Oops/WARNING in out-*/dmesg.txt" || res 9 "dmesg" FAIL "$dm"
[ $fail = 0 ] && echo "VERDICT: PASS" || echo "VERDICT: FAIL"
