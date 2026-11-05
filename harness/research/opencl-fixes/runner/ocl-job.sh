#!/bin/bash
# Runner package for the OpenCL board jobs: ocl-job.sh timeout-fix
# Self-contained: board lock (fresh owner name per acquire), install the newest cumulative kernel with the one-shot
# fallback armed (harness/research/vdec-perf/install-kernel.sh c), check that it carries the panfrost soft-stop fix,
# run the OpenCL-CTS chunks (each at most ~15 min) on the fork Mesa under a stall watchdog, copy the results off after
# every chunk, restore the stock image kernel (vmlinuz-7.3.1-edge-sunxi64), release. Between chunks the lock is handed
# over (stock kernel restored first) if another session waits. Resumable: re-running the same command skips chunks
# listed in $OUT/state. Exit 0 = all chunks ran (pass/fail is judged from the results, see HANDOFF.md); 2 = blocked
# (reason in $OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/opencl-fixes; V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
J=${1:?job: timeout-fix}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED
case $J in
  timeout-fix) CHUNKS="intops tdim math-a math-b reg img3d"; CT=870; STALL=870 ;;
  *) echo "unknown job $J"; exit 1 ;;
esac
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
R=/root/oclfix/tofix                      # board results dir (clcts-run.py resumes from $R/opencl-mesa/binaries.csv)
CTS=/root/cts/opencl-cts
MATH_A="acos acosh acospi add asin asinh asinpi assignment atan atan2 atan2pi atanh atanpi cbrt ceil cos cosh cospi divide erf erfc exp exp10 exp2 expm1 fabs fdim floor fma fmax fmin fmod fract frexp hypot ilogb isequal isfinite isgreater isgreaterequal isinf isless islessequal islessgreater isnan isnormal isnotequal isordered isunordered ldexp lgamma lgamma_r log log10"
MATH_B="log1p log2 logb mad maxmag minmag modf multiply nan negation nextafter not pow pown powr recip remainder remquo rint rootn round rsqrt signbit sin sincos sinh sinpi sqrt subtract tan tanh tanpi tgamma trunc"
REG='^(Atomics|C11 Atomics|Half Ops|Relationals|Events|Buffers|Compiler|Select|Common Functions|Geometric Functions|Compute Info|Workgroups|Subgroups|Profiling|Printf|Device Partitioning|Mem \(Host Flags\)|Images \(API Info\)|Images \(Kernel Methods\))$'
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
boot_trial() {
  [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"
  $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  # the kernel must carry the panfrost soft-stop/resume fix (fix/sunxi-panfrost-softstop-resume)
  n=$($SSH -n 'f=$(modinfo -n panfrost 2>/dev/null); case $f in *.zst) zstdcat "$f";; *.xz) xzcat "$f";; *.gz) zcat "$f";; *) cat "$f";; esac 2>/dev/null | grep -c "soft-stopping it to resume"')
  [ "${n:-0}" -ge 1 ] && log "kernel fix: present" || blocked "kernel $T lacks the panfrost soft-stop fix (merge fix/sunxi-panfrost-softstop-resume into test-cumulative and build first)"
  $SSH -n "test -f /root/opiz2-mesa/cl/env.sh && test -x $CTS/test_conformance/integer_ops/test_integer_ops && mkdir -p $R" || blocked "fork Mesa (/root/opiz2-mesa/cl) or the OpenCL CTS is missing on the board"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
cts_cmd() { echo "python3 $CTS/clcts-run.py --cts $CTS/test_conformance --profile $CTS/opencl_conformance_tests_mesa.csv --out $R/opencl-mesa --timeout 800 --only '$1'"; }
chunk_script() { # print the board script of a chunk; it ends with ROUND-DONE
  local cmd
  case $1 in
    intops) cmd=$(cts_cmd '^Integer Ops$') ;;
    tdim)   cmd=$(cts_cmd '^Thread Dimensions$') ;;
    reg)    cmd=$(cts_cmd "$REG") ;;
    img3d)  cmd=$(cts_cmd '^Images \(Kernel 3D int\)$') ;;
    math-a) cmd="cd $CTS/test_conformance/math_brute_force && timeout 800 ./test_bruteforce -w $MATH_A" ;;
    math-b) cmd="cd $CTS/test_conformance/math_brute_force && timeout 800 ./test_bruteforce -w $MATH_B" ;;
  esac
  cat <<EOS
. /root/opiz2-mesa/cl/env.sh
cd /root; uname -v
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
$cmd
echo CHUNK-RC \$?
dmesg | tail -n +\$((n1+1)) | grep -E 'panfrost|gpu sched|js fault|Soft-stop|Page fault' | tail -40 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
run_chunk() { # run_chunk <chunk>: remote command under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt
  chunk_script $c | $SSH "cat > /root/oclfix/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  $SSH -n "timeout $CT bash /root/oclfix/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c; scp -q -r "${K[@]}" root@10.56.0.107:$R/opencl-mesa/. $OUT/files/$c/ 2>/dev/null
  grep '^DMESG: ' $f > $OUT/dmesg-$c.txt
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
log "job $J start, kernel $T (Image md5 $want), chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; boot_trial
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; boot_trial; fi
  log "chunk $c start"; run_chunk $c
done
restore; release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
