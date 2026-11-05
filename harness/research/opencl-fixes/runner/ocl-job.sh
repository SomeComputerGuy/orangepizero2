#!/bin/bash
# Runner package for the OpenCL board jobs: ocl-job.sh timeout-fix
# Self-contained: board lock (fresh owner name per acquire), install the newest cumulative kernel with the one-shot
# fallback armed (harness/research/vdec-perf/install-kernel.sh c), check that it carries the panfrost soft-stop fix
# (both commits of fix/sunxi-panfrost-softstop-resume: e544ddb00 soft-stop/resume + 0b7e3a208 live-status wait, the
# fix for the panfrost_dequeue_job Oops of c14), run a soft-stop stress chunk first, then the OpenCL-CTS chunks (each at
# most ~15 min) on the fork Mesa under a stall watchdog, copy the results off after every chunk, restore the stock image
# kernel (vmlinuz-7.3.1-edge-sunxi64), release. Between chunks the lock is handed over (stock kernel restored first) if
# another session waits. Resumable: re-running the same command skips chunks listed in $OUT/state. Fail fast: an Oops /
# NULL dereference / workqueue lockup / panfrost_dequeue_job line on the serial log or in the chunk's dmesg ends the job
# at once (exit 3, lines in $OUT/OOPS). Exit 0 = all chunks ran (pass/fail is judged from the results, see HANDOFF.md);
# 2 = blocked (reason in $OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/opencl-fixes; V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
J=${1:?job: timeout-fix}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED
case $J in
  timeout-fix) CHUNKS="stress intops tdim math-a math-b reg img3d"; CT=870; STALL=870 ;;
  *) echo "unknown job $J"; exit 1 ;;
esac
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
R=/root/oclfix/tofix                      # board results dir (clcts-run.py resumes from $R/opencl-mesa/binaries.csv)
CTS=/root/cts/opencl-cts
FIX=0b7e3a208                             # fix/sunxi-panfrost-softstop-resume HEAD (contains e544ddb00); the kernel must have it
OOPS='Unable to handle|Oops|workqueue lockup|panfrost_dequeue_job'   # fail-fast patterns (serial log and dmesg)
SER=$H/harness/serial.log                 # our serial logger's file (host side)
VK=/root/cts/deqp-vk
VKENV='export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 PANVK_DEBUG=sync VK_ICD_FILENAMES=$VK_DRIVER_FILES'
DEQP_ARGS='--deqp-log-images=disable --deqp-log-shader-sources=disable --deqp-shadercache=disable'
# the 7 spirv_assembly vec4 fragment cases that are long jobs (> 500 ms, harness/research/impl-gpu-spec.md), API 1.0
FRAG="dEQP-VK.spirv_assembly.type.vec4.i8.clamp_frag dEQP-VK.spirv_assembly.type.vec4.u32.bit_field_insert_offset16_count16_frag dEQP-VK.spirv_assembly.type.vec4.i16.bit_field_insert_offset8_count16_frag dEQP-VK.spirv_assembly.type.vec4.u16.bit_field_insert_offset8_count16_frag dEQP-VK.spirv_assembly.type.vec4.i8.bit_field_insert_offset16_count64_frag dEQP-VK.spirv_assembly.type.vec4.i64.bit_field_u_extract_offset8_count16_frag dEQP-VK.spirv_assembly.type.vec4.u64.bit_field_insert_offset8_count64_frag"
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
  # the kernel must carry the whole panfrost soft-stop/resume fix (fix/sunxi-panfrost-softstop-resume HEAD $FIX, which
  # contains e544ddb00; e544ddb00 alone oopses in panfrost_dequeue_job). dev_dbg strings are compiled out (no
  # CONFIG_DYNAMIC_DEBUG), so compare the board's module with the one built from a tree that contains the fix ($FIX must be
  # an ancestor of the tag's commit; cumul-build packages that tree's panfrost.ko).
  c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the panfrost soft-stop fix $FIX (0b7e3a208 on top of e544ddb00)"
  d=$(mktemp -d); tar xzf $H/kernel-check/vdec-serve/modules-$T.tgz -C $d 7.3.1/kernel/drivers/gpu/drm/panfrost/panfrost.ko
  want_sv=$(md5sum < $d/7.3.1/kernel/drivers/gpu/drm/panfrost/panfrost.ko | cut -c1-32); rm -rf $d
  have_sv=$($SSH -n 'md5sum < $(modinfo -n panfrost) | cut -c1-32')
  [ -n "$want_sv" ] && [ "$want_sv" = "$have_sv" ] && log "kernel fix: present (panfrost.ko md5 $have_sv)" || blocked "panfrost.ko on the board ($have_sv) is not the $T module ($want_sv)"
  $SSH -n "test -f /root/opiz2-mesa/cl/env.sh && test -f /root/opiz2-mesa/cl/panfrost_icd.json && test -x $CTS/test_conformance/integer_ops/test_integer_ops && test -x $VK/deqp-vk && mkdir -p $R /root/oclfix/vklogs" || blocked "fork Mesa (/root/opiz2-mesa/cl with panvk), the OpenCL CTS or deqp-vk is missing on the board"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
cts_cmd() { echo "python3 $CTS/clcts-run.py --cts $CTS/test_conformance --profile $CTS/opencl_conformance_tests_mesa.csv --out $R/opencl-mesa --timeout 800 --only '$1'"; }
stress_cmd() { # soft-stop/resume stress: the jobs that run > 500 ms. 2 rounds of the Integer Ops long16 64-bit '/' and '%'
  # tests, one Thread Dimensions quick_2d job (a multi-second job, stopped and resumed several times), 2 rounds of the 7
  # Vulkan spirv_assembly vec4 fragment long jobs (panvk from the fork Mesa, PANVK_DEBUG=sync aborts on a reset job).
  cat <<EOS
for i in 1 2; do t0=\$(date +%s)
  ( cd $CTS/test_conformance/integer_ops && timeout 300 ./test_integer_ops quick_long_math quick_ulong_math ) 2>&1 | grep -E '^(quick_|PASSED|FAILED)|Verification failed|ERROR' | head -20 | sed "s/^/INTOPS \$i: /"
  echo "INTOPS \$i: t=\$(( \$(date +%s) - t0 ))s"; done
t0=\$(date +%s)
( cd $CTS/test_conformance/thread_dimensions && timeout 400 ./test_thread_dimensions quick_2d_explicit_local ) 2>&1 | grep -E '^(quick_|PASSED|FAILED)|ERROR' | head -10 | sed 's/^/TDIM: /'
echo "TDIM: t=\$(( \$(date +%s) - t0 ))s"
$VKENV
cd $VK
for i in 1 2; do for c in $FRAG; do t0=\$(date +%s)
  timeout 200 ./deqp-vk --deqp-case=\$c $DEQP_ARGS --deqp-log-filename=/root/oclfix/vklogs/\$c.qpa > /root/oclfix/vklogs/\$c.txt 2>&1; rc=\$?
  echo "VK \$i \$c rc=\$rc t=\$(( \$(date +%s) - t0 ))s result=[\$(grep -E '^  (Pass|Fail|NotSupported|QualityWarning|Crash|Timeout|InternalError)' /root/oclfix/vklogs/\$c.txt | head -1 | tr -s ' ')] msg=[\$(grep -E 'Incomplete job|Assert|FATAL|Aborted' /root/oclfix/vklogs/\$c.txt | head -1)]"
done; done
true
EOS
}
chunk_script() { # print the board script of a chunk; it ends with ROUND-DONE
  local cmd
  case $1 in
    stress) cmd=$(stress_cmd) ;;
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
dmesg | tail -n +\$((n1+1)) | grep -E 'panfrost|gpu sched|js fault|Soft-stop|Page fault|$OOPS|WARNING|Call trace' | tail -60 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
oops_fail() { # fail fast: kernel Oops / lockup lines (arg: where); results already copied; restore, release, exit 3
  log "OOPS during chunk $1 ($2): $(head -3 $OUT/OOPS | tr '\n' ' ')"
  restore; release; log "job $J ABORTED on the first Oops (exit 3)"; exit 3; }
run_chunk() { # run_chunk <chunk>: remote command under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt oops=""
  chunk_script $c | $SSH "cat > /root/oclfix/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  local soff=$(stat -c %s $SER 2>/dev/null || echo 0)       # serial log offset at chunk start: watch only new lines
  $SSH -n "timeout $CT bash /root/oclfix/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ -f $SER ] && tail -c +$((soff+1)) $SER | grep -qE "$OOPS"; then
      tail -c +$((soff+1)) $SER | grep -E "$OOPS|Call trace|pc :|lr :| panfrost" | head -40 > $OUT/OOPS
      log "OOPS on the serial log during chunk $c, killing ssh $p"; kill $p; echo OOPS >> $f; oops=serial; break; fi
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c; scp -q -r "${K[@]}" root@10.56.0.107:$R/opencl-mesa/. $OUT/files/$c/ 2>/dev/null
  [ $c = stress ] && scp -q -r "${K[@]}" root@10.56.0.107:/root/oclfix/vklogs $OUT/files/$c/ 2>/dev/null
  grep '^DMESG: ' $f > $OUT/dmesg-$c.txt
  if [ -z "$oops" ] && grep -qE "$OOPS" $OUT/dmesg-$c.txt; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/dmesg-$c.txt | head -40 > $OUT/OOPS; oops=dmesg; fi
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
rm -f $OUT/OOPS
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
