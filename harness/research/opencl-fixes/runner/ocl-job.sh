#!/bin/bash
# Runner package for the OpenCL/GPU board jobs: ocl-job.sh softstop2 | img3d | rgbtdim
# rgbtdim (runner job 46): A/B of the Mesa fork fix 02df5721016 (pan/layout: one cache line of slack after 24/96-bit
# images) against the CL_RGB page faults: board/t_rgbedge.py reads the last texel of linear RGB images whose data ends on
# a 2 MiB boundary (nothing mapped after the BO) with the old build (cl2, dc7266d584b) and the new one (cl3, deployed by
# this script), then the CTS 2Darray RGB8 reads (job 09's fault) A/B and the 3D RGB32I read on cl3; then Thread
# Dimensions with gpu_scheduler tracepoints and a per-minute progress line (lost job vs slow job), no 800 s limit for 3D.
# img3d (runner job 45): repeat the OpenCL-CTS 3D image read of the 96-bit formats that faulted in job 28 (CL_RGB
# SIGNED_INT32: "Unhandled Page fault in AS0 at VA 0xB2F8000", JOB_BUS_FAULT) on a kernel that names the BOs around an
# unhandled fault (fa9d166f6, fix/sunxi-panfrost-fault-bo-info), plus the Thread Dimensions quick tests under their real
# names (job 28's tdim chunk asked for quick_2d/quick_3d, which do not exist).
# Self-contained: board lock (fresh owner name per acquire), install the newest cumulative kernel with the one-shot
# fallback armed (harness/research/vdec-perf/install-kernel.sh c), check that it carries the whole panfrost soft-stop
# series (e544ddb00 soft-stop/resume, 0b7e3a208 live-status wait, e17629bba 5 s soft-stop budget + hard stop + no resume
# across a reset), run a compute soft-stop stress chunk, the two Vulkan fragment chunks, then the OpenCL-CTS chunks (each
# at most ~15 min) on the fork Mesa under a stall watchdog, copy the results off after every chunk, restore the stock
# image kernel (vmlinuz-7.3.1-edge-sunxi64), release. Between chunks the lock is handed over (stock kernel restored
# first) if another session waits. Resumable: re-running the same command skips chunks listed in $OUT/state.
# Every chunk: the board-side script kills the previous chunk's leftover process group, resets ftrace and traces
# panfrost_job_timedout (the 500 ms watchdog hits); the host collects dmesg and the trace count AFTER the chunk, so a
# chunk that is cut off by its time limit still leaves dmesg-<c>.txt and trace-<c>.txt. Fail fast: an Oops / NULL
# dereference / workqueue lockup / panfrost_dequeue_job line on the serial log or in the chunk's dmesg ends the job at
# once (exit 3, lines in $OUT/OOPS). Exit 0 = all chunks ran (pass/fail is judged from the results, see HANDOFF.md);
# 2 = blocked (reason in $OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/opencl-fixes; V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
J=${1:?job: softstop2 | img3d}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED
case $J in
  softstop2) CHUNKS="stress vk vklong intops tdim math-a math-b reg img3d"; CT=870; STALL=870
             FIX=e17629bba ;;   # fix/sunxi-panfrost-softstop-budget HEAD (contains e544ddb00 + 0b7e3a208)
  img3d)     CHUNKS="tdim2 tdim3 s32-1 s32-2 s32-3 s32-4 u32-1 u32-2 f32-1 ctl"; CT=870; STALL=870
             FIX=fa9d166f6 ;;   # fix/sunxi-panfrost-fault-bo-info HEAD ("fault bo:" lines; contains the soft-stop series)
  rgbtdim)   CHUNKS="edgeA edgeB edgeA2 edgeB2 ctsA ctsB ctsA2 ctsB2 s32B tdim2x tdim3e tdim3i"; CT=870; STALL=870
             FIX=fa9d166f6
             MFIX=02df5721016 ;; # mesa-cl commit the cl3 build must contain (the 24/96-bit image padding)
  *) echo "unknown job $J"; exit 1 ;;
esac
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
R=/root/oclfix/$J                         # board results dir (clcts-run.py resumes from $R/opencl-mesa/binaries.csv: fresh per job)
CTS=/root/cts/opencl-cts
OOPS='Unable to handle|Oops|workqueue lockup|panfrost_dequeue_job'   # fail-fast patterns (serial log and dmesg)
# the fault report is one multi-line message: Reason/raw fault status/.../source id lines carry no "panfrost" prefix
DMESG_PAT="panfrost|gpu sched|js fault|Soft-stop|Hard-stop|Page fault|Reason:|raw fault status|decoded fault status|exception type|access type|source id|fault bo:|Purging|$OOPS|WARNING|Call trace"
SER=$H/harness/serial.log                 # our serial logger's file (host side)
VK=/root/cts/deqp-vk
VKENV='export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 PANVK_DEBUG=sync VK_ICD_FILENAMES=$VK_DRIVER_FILES'
DEQP_ARGS='--deqp-log-images=disable --deqp-log-shader-sources=disable --deqp-shadercache=disable'
# the 7 spirv_assembly vec4 fragment cases that are long jobs (> 500 ms, harness/research/impl-gpu-spec.md), API 1.0.
# The five in FRAG_SHORT passed in 4-28 s on c25 (soft-stopped and resumed); the two count64 cases in FRAG_LONG never
# reached a task boundary within the old 100 ms soft-stop budget (job 18) and get 400 s each here.
FRAG_SHORT="dEQP-VK.spirv_assembly.type.vec4.i8.clamp_frag dEQP-VK.spirv_assembly.type.vec4.u32.bit_field_insert_offset16_count16_frag dEQP-VK.spirv_assembly.type.vec4.i16.bit_field_insert_offset8_count16_frag dEQP-VK.spirv_assembly.type.vec4.u16.bit_field_insert_offset8_count16_frag dEQP-VK.spirv_assembly.type.vec4.i64.bit_field_u_extract_offset8_count16_frag"
FRAG_LONG="dEQP-VK.spirv_assembly.type.vec4.i8.bit_field_insert_offset16_count64_frag dEQP-VK.spirv_assembly.type.vec4.u64.bit_field_insert_offset8_count64_frag"
MATH_A="acos acosh acospi add asin asinh asinpi assignment atan atan2 atan2pi atanh atanpi cbrt ceil cos cosh cospi divide erf erfc exp exp10 exp2 expm1 fabs fdim floor fma fmax fmin fmod fract frexp hypot ilogb isequal isfinite isgreater isgreaterequal isinf isless islessequal islessgreater isnan isnormal isnotequal isordered isunordered ldexp lgamma lgamma_r log log10"
MATH_B="log1p log2 logb mad maxmag minmag modf multiply nan negation nextafter not pow pown powr half_recip remainder remquo rint rootn round rsqrt signbit sin sincos sinh sinpi sqrt subtract tan tanh tanpi tgamma trunc"
REG='^(Atomics|C11 Atomics|Half Ops|Relationals|Events|Buffers|Compiler|Select|Common Functions|Geometric Functions|Compute Info|Workgroups|Subgroups|Profiling|Printf|Device Partitioning|Mem \(Host Flags\)|Images \(API Info\)|Images \(Kernel Methods\))$'
ct_of() { case $1 in tdim3e|tdim3i) echo 1900 ;; *) echo $CT ;; esac; }   # board-side limit per chunk (s)
MW=$H/mesa-work; LIB=$MW/build-cl/src/gallium/targets/rusticl/libRusticlOpenCL.so.1.0.0
if [ $J = rgbtdim ]; then   # host-side preconditions of the cl3 build (no board needed)
  [ -f $LIB ] || { echo "missing build: $LIB (run: . mesa-work/tools/env-cl.sh; ninja -C mesa-work/build-cl)"; exit 1; }
  git -C $MW/mesa-cl merge-base --is-ancestor $MFIX HEAD 2>/dev/null || { echo "mesa-cl HEAD lacks $MFIX"; exit 1; }
fi
deploy_cl3() { # rgbtdim: fork build -> /root/opiz2-mesa/cl3, the repro scripts -> /root/oclfix/board; cl2 must exist
  MESA_ENV=$MW/tools/env-cl.sh $MW/tools/deploy.sh build-cl cl3 2>&1 | tail -1 | tee -a $OUT/runner.log
  local want=$(md5sum < $MW/deploy/cl3/lib/libRusticlOpenCL.so.1.0.0 | cut -c1-32)
  local have=$($SSH -n 'md5sum < /root/opiz2-mesa/cl3/lib/libRusticlOpenCL.so.1.0.0 | cut -c1-32')
  [ -n "$want" ] && [ "$want" = "$have" ] || blocked "cl3 deploy mismatch (host $want board $have)"
  $SSH -n 'mkdir -p /root/oclfix/board' && scp -q "${K[@]}" $S/runner/board/hostclk.py $S/runner/board/t_rgbedge.py root@10.56.0.107:/root/oclfix/board/ || blocked "cannot copy runner/board to the board"
  $SSH -n 'test -f /root/opiz2-mesa/cl2/env.sh && test -f /root/opiz2-mesa/cl3/env.sh && python3 -c "import ctypes"' || blocked "/root/opiz2-mesa/cl2 (job 09 build) or cl3 missing on the board"
  log "deployed cl3 ok (mesa-cl $(git -C $MW/mesa-cl rev-parse --short=11 HEAD), libRusticlOpenCL md5 $have); cl2 present"; }
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
  # the kernel must carry the whole panfrost soft-stop series (fix/sunxi-panfrost-softstop-budget HEAD $FIX, which contains
  # e544ddb00 and 0b7e3a208). dev_dbg strings are compiled out (no CONFIG_DYNAMIC_DEBUG), so compare the board's module
  # with the one built from a tree that contains the fix ($FIX must be an ancestor of the tag's commit; cumul-build
  # packages that tree's panfrost.ko).
  c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the panfrost fix $FIX"
  d=$(mktemp -d); tar xzf $H/kernel-check/vdec-serve/modules-$T.tgz -C $d 7.3.1/kernel/drivers/gpu/drm/panfrost/panfrost.ko
  want_sv=$(md5sum < $d/7.3.1/kernel/drivers/gpu/drm/panfrost/panfrost.ko | cut -c1-32); rm -rf $d
  have_sv=$($SSH -n 'md5sum < $(modinfo -n panfrost) | cut -c1-32')
  [ -n "$want_sv" ] && [ "$want_sv" = "$have_sv" ] && log "kernel fix: present (panfrost.ko md5 $have_sv)" || blocked "panfrost.ko on the board ($have_sv) is not the $T module ($want_sv)"
  $SSH -n "test -f /root/opiz2-mesa/cl/env.sh && test -f /root/opiz2-mesa/cl/panfrost_icd.json && test -x $CTS/test_conformance/integer_ops/test_integer_ops && test -x $VK/deqp-vk && test -x $CTS/test_conformance/images/kernel_read_write/test_image_streams && mkdir -p $R/img /root/oclfix/vklogs" || blocked "fork Mesa (/root/opiz2-mesa/cl with panvk), the OpenCL CTS or deqp-vk is missing on the board"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
cts_cmd() { echo "python3 $CTS/clcts-run.py --cts $CTS/test_conformance --profile $CTS/opencl_conformance_tests_mesa.csv --out $R/opencl-mesa --timeout 800 --only '$1'"; }
stress_cmd() { # compute soft-stop/resume stress: the compute jobs that run > 500 ms. 2 rounds of the Integer Ops long16 64-bit
  # '/' and '%' tests, one Thread Dimensions quick_2d job (a multi-second job, stopped and resumed several times).
  cat <<EOS
for i in 1 2; do t0=\$(date +%s)
  ( cd $CTS/test_conformance/integer_ops && timeout --foreground 300 ./test_integer_ops quick_long_math quick_ulong_math ) 2>&1 | grep -E '^(quick_|PASSED|FAILED)|Verification failed|ERROR' | head -20 | sed "s/^/INTOPS \$i: /"
  echo "INTOPS \$i: t=\$(( \$(date +%s) - t0 ))s"; done
t0=\$(date +%s)
( cd $CTS/test_conformance/thread_dimensions && timeout --foreground 400 ./test_thread_dimensions quick_2d_explicit_local ) 2>&1 | grep -E '^(quick_|PASSED|FAILED)|ERROR' | head -10 | sed 's/^/TDIM: /'
echo "TDIM: t=\$(( \$(date +%s) - t0 ))s"
true
EOS
}
vk_cmd() { # vk_cmd <rounds> <per-case timeout> <cases>: the Vulkan fragment long jobs (panvk from the fork Mesa,
  # PANVK_DEBUG=sync aborts on a reset job). timeout --foreground keeps deqp-vk in the chunk's process group, so the chunk
  # limit (or the next chunk's leftover kill) ends it too.
  local rounds=$1 to=$2; shift 2
  cat <<EOS
$VKENV
cd $VK
for i in \$(seq 1 $rounds); do for c in $*; do t0=\$(date +%s)
  timeout --foreground $to ./deqp-vk --deqp-case=\$c $DEQP_ARGS --deqp-log-filename=/root/oclfix/vklogs/\$c.qpa > /root/oclfix/vklogs/\$c.txt 2>&1; rc=\$?
  echo "VK \$i \$c rc=\$rc t=\$(( \$(date +%s) - t0 ))s result=[\$(grep -E '^  (Pass|Fail|NotSupported|QualityWarning|Crash|Timeout|InternalError)' /root/oclfix/vklogs/\$c.txt | head -1 | tr -s ' ')] msg=[\$(grep -E 'Incomplete job|Assert|FATAL|Aborted|DEVICE_LOST' /root/oclfix/vklogs/\$c.txt | head -1)]"
done; done
true
EOS
}
img_cmd() { # img_cmd <chunk> <int|uint|float> <channel order> <channel type>: one OpenCL-CTS 3D image read run, NEAREST,
  # restricted to one format (all address modes and coordinate kinds of that format); full log in $R/img/<chunk>.log
  cat <<EOS
cd $CTS/test_conformance/images/kernel_read_write; t0=\$(date +%s)
timeout --foreground 800 ./test_image_streams CL_FILTER_NEAREST $2 3D $3 $4 > $R/img/$1.log 2>&1; echo "IMG-RC \$? t=\$(( \$(date +%s) - t0 ))s"
grep -E '^(PASSED|FAILED)|^FAILED:|did not validate|got \(|ERROR' $R/img/$1.log | head -20 | sed 's/^/IMG: /'
true
EOS
}
edge_cmd() { # edge_cmd <A|B> <mesa dir>: t_rgbedge.py per case in a fresh process, dmesg delta per case
  cat <<EOS
cd /root/oclfix/board
for c in rgb8 rgb32i rgba8 rgba32i rgb8s rgb32is; do n0=\$(dmesg | wc -l)
  ( . /root/opiz2-mesa/$2/env.sh; timeout --foreground 120 python3 t_rgbedge.py \$c ) > /root/oclfix/board/\$c-$1.log 2>&1; rc=\$?
  grep -E '^(CASE|RESULT)|Error|assert' /root/oclfix/board/\$c-$1.log | head -8 | sed "s/^/EDGE $1 \$c: /"
  d=\$(dmesg | tail -n +\$((n0+1)))
  echo "EDGE $1 \$c RC \$rc FAULTS \$(echo "\$d" | grep -c 'Unhandled Page fault')"
  echo "\$d" | grep -E 'Unhandled Page fault|fault bo:|js fault' | head -8 | sed "s/^/EDGE $1 \$c DMESG: /"
done
true
EOS
}
rgbcts_cmd() { # rgbcts_cmd <chunk> <mesa dir>: CTS 2Darray float read of the two RGB8 formats (job 09 f2d-r2da faults)
  cat <<EOS
. /root/opiz2-mesa/$2/env.sh
cd $CTS/test_conformance/images/kernel_read_write
for t in CL_UNORM_INT8 CL_SNORM_INT8; do t0=\$(date +%s); n0=\$(dmesg | wc -l)
  timeout --foreground 400 ./test_image_streams read CL_FILTER_NEAREST float 2Darray CL_RGB \$t > $R/img/$1-\$t.log 2>&1; rc=\$?
  echo "RGBCTS $1 \$t RC \$rc t=\$(( \$(date +%s) - t0 ))s FAULTS \$(dmesg | tail -n +\$((n0+1)) | grep -c 'Unhandled Page fault')"
  grep -E '^(PASSED|FAILED)|^FAILED:|ERROR' $R/img/$1-\$t.log | head -12 | sed "s/^/RGBCTS $1 \$t: /"
done
true
EOS
}
tdim_cmd() { # tdim_cmd <limit s> <tests...>: Thread Dimensions with gpu_scheduler run/done events streamed to a file and a
  # progress line per minute: jobs run/done/timeouts so far. A lost job = run without done while TIMEDOUT grows.
  local lim=$1; shift
  cat <<EOS
TR=/sys/kernel/tracing; F=/root/oclfix/tdim-trace.txt; : > \$F
echo 1 > \$TR/events/gpu_scheduler/drm_sched_job_run/enable; echo 1 > \$TR/events/gpu_scheduler/drm_sched_job_done/enable
cat \$TR/trace_pipe > \$F & tp=\$!
( t0=\$(date +%s); while sleep 60; do echo "PROG t=\$(( \$(date +%s) - t0 ))s run=\$(grep -c drm_sched_job_run: \$F) done=\$(grep -c drm_sched_job_done: \$F) timedout=\$(grep -c panfrost_job_timedout \$F)"; done ) & pg=\$!
cd $CTS/test_conformance/thread_dimensions
rm -f /root/oclfix/tdim-*.log; i=0
for t in $*; do t0=\$(date +%s); i=\$((i+1))
  timeout --foreground $lim ./test_thread_dimensions \$t > /root/oclfix/tdim-\$i-\$t.log 2>&1; rc=\$?
  echo "TDIM \$i \$t RC \$rc t=\$(( \$(date +%s) - t0 ))s"; grep -E '^(quick_|PASSED|FAILED)|ERROR|Verification|Error|rror' /root/oclfix/tdim-\$i-\$t.log | head -12 | sed "s/^/TDIM \$i \$t: /"
done
kill \$pg; sleep 1; kill \$tp
echo 0 > \$TR/events/gpu_scheduler/drm_sched_job_run/enable; echo 0 > \$TR/events/gpu_scheduler/drm_sched_job_done/enable
echo "TDIM-TRACE run=\$(grep -c drm_sched_job_run: \$F) done=\$(grep -c drm_sched_job_done: \$F) timedout=\$(grep -c panfrost_job_timedout \$F)"
true
EOS
}
chunk_script() { # print the board script of a chunk; it ends with ROUND-DONE
  local cmd
  case $1 in
    stress) cmd=$(stress_cmd) ;;
    vk)     cmd=$(vk_cmd 2 80 $FRAG_SHORT) ;;
    vklong) cmd=$(vk_cmd 1 400 $FRAG_LONG) ;;
    intops) cmd=$(cts_cmd '^Integer Ops$') ;;
    tdim)   cmd="cd $CTS/test_conformance/thread_dimensions && timeout --foreground 800 ./test_thread_dimensions quick_2d_explicit_local quick_2d_implicit_local quick_3d_explicit_local quick_3d_implicit_local 2>&1 | grep -E '^(quick_|PASSED|FAILED)|ERROR|Verification|Error' | head -40 | sed 's/^/TDIM: /'; echo TDIM-RC \${PIPESTATUS[0]}" ;;
    tdim2)  cmd="cd $CTS/test_conformance/thread_dimensions && timeout --foreground 800 ./test_thread_dimensions quick_2d_explicit_local quick_2d_implicit_local 2>&1 | grep -E '^(quick_|PASSED|FAILED)|ERROR|Verification|Error' | head -40 | sed 's/^/TDIM: /'; echo TDIM-RC \${PIPESTATUS[0]}" ;;
    tdim3)  cmd="cd $CTS/test_conformance/thread_dimensions && timeout --foreground 800 ./test_thread_dimensions quick_3d_explicit_local quick_3d_implicit_local 2>&1 | grep -E '^(quick_|PASSED|FAILED)|ERROR|Verification|Error' | head -40 | sed 's/^/TDIM: /'; echo TDIM-RC \${PIPESTATUS[0]}" ;;
    s32-*)  cmd=$(img_cmd $1 int CL_RGB CL_SIGNED_INT32) ;;
    u32-*)  cmd=$(img_cmd $1 uint CL_RGB CL_UNSIGNED_INT32) ;;
    f32-*)  cmd=$(img_cmd $1 float CL_RGB CL_FLOAT) ;;
    ctl)    cmd=$(img_cmd $1 int CL_RGBA CL_SIGNED_INT32) ;;   # control: 128-bit texels, same kernels
    reg)    cmd=$(cts_cmd "$REG") ;;
    edgeA|edgeA2) cmd=$(edge_cmd A cl2) ;;     # old build (no padding): expected to fault on rgb8 / rgb32i
    edgeB|edgeB2) cmd=$(edge_cmd B cl3) ;;     # the fix
    ctsA|ctsA2) cmd=$(rgbcts_cmd $1 cl2) ;;
    ctsB|ctsB2) cmd=$(rgbcts_cmd $1 cl3) ;;
    s32B)   cmd=". /root/opiz2-mesa/cl3/env.sh; $(img_cmd $1 int CL_RGB CL_SIGNED_INT32)" ;;
    tdim2x) cmd=". /root/opiz2-mesa/cl3/env.sh; $(tdim_cmd 400 quick_2d_explicit_local quick_2d_explicit_local quick_2d_explicit_local)" ;;
    tdim3e) cmd=". /root/opiz2-mesa/cl3/env.sh; $(tdim_cmd 1800 quick_3d_explicit_local)" ;;
    tdim3i) cmd=". /root/opiz2-mesa/cl3/env.sh; $(tdim_cmd 1800 quick_3d_implicit_local)" ;;
    img3d)  cmd=$(cts_cmd '^Images \(Kernel 3D int\)$') ;;
    math-a) cmd="cd $CTS/test_conformance/math_brute_force && timeout --foreground 800 ./test_bruteforce -w $MATH_A" ;;
    math-b) cmd="cd $CTS/test_conformance/math_brute_force && timeout --foreground 800 ./test_bruteforce -w $MATH_B" ;;
  esac
  cat <<EOS
# leftover of the previous chunk (cut off by its time limit): kill its process group by exact pgid
if [ -f /root/oclfix/chunk.pgid ]; then o=\$(cat /root/oclfix/chunk.pgid); me=\$(ps -o pgid= \$\$ | tr -d ' ')
  if [ -n "\$o" ] && [ "\$o" != "\$me" ] && kill -0 -- -\$o 2>/dev/null; then echo "LEFTOVER pgid \$o killed"; kill -TERM -- -\$o; sleep 3; kill -KILL -- -\$o 2>/dev/null; fi; fi
ps -o pgid= \$\$ | tr -d ' ' > /root/oclfix/chunk.pgid
. /root/opiz2-mesa/cl/env.sh
cd /root; uname -v
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
TR=/sys/kernel/tracing; mountpoint -q \$TR || mount -t tracefs nodev \$TR 2>/dev/null
echo nop > \$TR/current_tracer 2>/dev/null; echo > \$TR/trace 2>/dev/null
echo panfrost_job_timedout > \$TR/set_ftrace_filter 2>/dev/null && echo function > \$TR/current_tracer && echo 1 > \$TR/tracing_on && echo TRACE-ON || echo TRACE-OFF
$cmd
echo CHUNK-RC \$?
echo ROUND-DONE
EOS
}
collect() { # collect <chunk>: dmesg since the chunk's DMESG-START and the watchdog count from ftrace, from the host, after the
  # chunk (also when it was cut off); results and logs copied off the board
  local c=$1 f=$OUT/chunk-$1.txt n1
  n1=$(grep -m1 '^DMESG-START ' $f | awk '{print $2}'); [ -n "$n1" ] || n1=0
  $SSH -n "dmesg | tail -n +$((n1+1))" 2>/dev/null | grep -E "$DMESG_PAT" | tail -80 | sed 's/^/DMESG: /' > $OUT/dmesg-$c.txt
  $SSH -n 'TR=/sys/kernel/tracing; a=$(grep -c panfrost_job_timedout $TR/trace 2>/dev/null); echo nop > $TR/current_tracer 2>/dev/null; echo "TRACE: TIMEDOUT ${a:-?}"' 2>/dev/null > $OUT/trace-$c.txt
  cat $OUT/dmesg-$c.txt $OUT/trace-$c.txt >> $f
  mkdir -p $OUT/files/$c; scp -q -r "${K[@]}" root@10.56.0.107:$R/opencl-mesa/. $OUT/files/$c/ 2>/dev/null
  case $c in vk|vklong) scp -q -r "${K[@]}" root@10.56.0.107:/root/oclfix/vklogs $OUT/files/$c/ 2>/dev/null ;;
    s32-*|u32-*|f32-*|ctl|s32B) scp -q "${K[@]}" root@10.56.0.107:$R/img/$c.log $OUT/files/$c/ 2>/dev/null ;;
    cts*) scp -q "${K[@]}" "root@10.56.0.107:$R/img/$c-*.log" $OUT/files/$c/ 2>/dev/null ;;
    edge*) scp -q "${K[@]}" "root@10.56.0.107:/root/oclfix/board/*.log" $OUT/files/$c/ 2>/dev/null ;;
    tdim*) scp -q "${K[@]}" "root@10.56.0.107:/root/oclfix/tdim-*.log" root@10.56.0.107:/root/oclfix/tdim-trace.txt $OUT/files/$c/ 2>/dev/null
           [ -f $OUT/files/$c/tdim-trace.txt ] && gzip -f $OUT/files/$c/tdim-trace.txt ;; esac; }
oops_fail() { # fail fast: kernel Oops / lockup lines (arg: where); results already copied; restore, release, exit 3
  log "OOPS during chunk $1 ($2): $(head -3 $OUT/OOPS | tr '\n' ' ')"
  restore; release; log "job $J ABORTED on the first Oops (exit 3)"; exit 3; }
run_chunk() { # run_chunk <chunk>: remote command under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt oops=""
  chunk_script $c | $SSH "cat > /root/oclfix/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  local soff=$(stat -c %s $SER 2>/dev/null || echo 0)       # serial log offset at chunk start: watch only new lines
  $SSH -n "timeout $(ct_of $c) bash /root/oclfix/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ -f $SER ] && tail -c +$((soff+1)) $SER | grep -qE "$OOPS"; then
      tail -c +$((soff+1)) $SER | grep -E "$OOPS|Call trace|pc :|lr :| panfrost" | head -40 > $OUT/OOPS
      log "OOPS on the serial log during chunk $c, killing ssh $p"; kill $p; echo OOPS >> $f; oops=serial; break; fi
    if [ $(( $(date +%s) - last )) -gt $(ct_of $c) ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  grep -q ROUND-DONE $f || echo "CUT-OFF (no ROUND-DONE: chunk limit $(ct_of $c) s, stall or Oops)" >> $f
  collect $c
  if [ -z "$oops" ] && grep -qE "$OOPS" $OUT/dmesg-$c.txt; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/dmesg-$c.txt | head -40 > $OUT/OOPS; oops=dmesg; fi
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
rm -f $OUT/OOPS
log "job $J start, kernel $T (Image md5 $want), chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; boot_trial; [ $J = rgbtdim ] && deploy_cl3
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; boot_trial
    [ $J = rgbtdim ] && deploy_cl3; fi
  log "chunk $c start"; run_chunk $c
done
restore; release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
