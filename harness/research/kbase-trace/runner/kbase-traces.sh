#!/bin/bash
# Runner package: Arm kbase trial + libmali g24p0 GLES 3.2 reference traces (status.md item 8 step 1): kbase-traces.sh
# v2 (runner job 64, 2026-11-06), after job 16: kbtrace.so no longer segfaults at the first mali ioctl (record before
# init, kbtrace.c); every board call is bounded (harness/ssh-opts.sh keepalive, SSH_TIMEOUT on one-shot calls, the
# step watchdog kills its own ssh by exact PID); the restore no longer does rmmod + panfrost rebind (job 16: the board
# reset ~15 s into that call, a hard hang caught by the hardware watchdog, and the old keepalive-less ssh sat 1.5 h);
# the module unload is now the separate diagnostic step `unload`, run only after all results are off the board, with
# console loglevel 8 and the serial.log slice saved. Results: arm-blob/traces/runner-j64/.
# v3 (runner job 65, 2026-11-06), after job 64: (a) kbtrace.bin held no memory (process_vm_readv cannot read kbase's
# VM_PFNMAP mappings): kbtrace.so reads through a pipe now and records the JIT soft-job payloads, kbdecode re-decodes
# every faulting submit from the after-event memory (submit-NNNN-post.txt; POST/JITADDR lines in index.txt);
# (b) bifrost_kbase.ko v3: the sunxi glue term now asserts RST_BUS_GPU, turns clocks + supply off and marks runtime PM
# suspended (as panfrost_remove does) before genpd cuts the GPU domain (job 16/64 reset at the panfrost rebind), plus a
# rate-limited `sunxi diag: slot N status 0x.. head .. tail ..` line per job fault; (c) `unload` (rmmod + runtime-PM /
# genpd / clock state before and after) and `bind` (panfrost rebind) are separate steps and are now real checks.
# Results: arm-blob/traces/runner-j65/.
# v4 (runner job 66, 2026-11-06), after job 65: cause of the fragment DATA_INVALID_FAULT found in job 65's memory: every
# failing fragment job (18/18) has an AFBC colour render target (fault_ptr = FBD + 0xc0 = the RT descriptor), every
# fragment job with a linear RT (18/18) completes. This G31 has no AFBC (AFBC_FEATURES 0x10001, job 51), kbase exports no
# AFBC property and the blob picks AFBC from the product ID. New step `afbc`: the basic case under four blob config
# files (MALI_PLATFORM_CONFIG / MALI_DEBUG_CONFIG; v0 none, v1 GLES_DISABLE_TEXTURE_AFBC + GLES_DISABLE_SURFACE_AFBC,
# v2 + GLES_DISABLE_CRC, v3 + GLES_FORCE_LINEAR_LAYOUT_UNCOMPRESSED_TEXTURE); probe and trace then run under the first
# variant (v1..v3) that renders (v3 if none). bifrost_kbase.ko v4: no -ENXIO IRQ lines, no workqueue WARNING at load,
# no unbalanced regulator disable at unload (port-7.3-v4.py). Results: arm-blob/traces/runner-j66/.
# Self-contained: board lock (fresh owner name per acquire), install the newest cumulative kernel with the one-shot
# fallback armed (harness/research/vdec-perf/install-kernel.sh, like the vdec/OpenCL jobs; it must carry the BTF dedup
# fix bd60a159b), stage bifrost_kbase.ko + the blob + the tools in /root/armblob (runtime files only: nothing is
# installed into the system, the blob never goes into an image), unbind panfrost at runtime, insmod kbase, run the
# gles32probe cases plain and under the kbtrace.so LD_PRELOAD, fetch /root/armblob/out, rebind panfrost, restore the
# stock image kernel (vmlinuz-7.3.1-edge-sunxi64), release. Every board step runs under a host timeout + stall
# watchdog. One chunk (~10-15 min); resumable: re-running skips the steps listed in $OUT/state.
# Exit 0 = all steps ran (pass/fail from `--check`, see HANDOFF.md); 2 = blocked (reason in $OUT/BLOCKED); 1 = setup error.
#   kbase-traces.sh           run the job
#   kbase-traces.sh --check   print the mechanical checks (PASS/FAIL lines) from the results; no board access
#   kbase-traces.sh --print   print the board step scripts; no board access
set -u
H=/home/aruni/orangepizero2; T=$H/harness/research/kbase-trace; A=$H/harness/research/arm-blob; V=$H/harness/research/vdec-perf
SSH=$H/harness/ssh.sh; J=kbase
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
S1() { SSH_TIMEOUT=${T1:-90} $SSH "$@"; }   # one-shot board command: killed after T1 s (default 90)
SERIAL=$H/harness/serial.log
KO=$H/kernel-check/kbase-trial/src/drivers/gpu/arm/bifrost/bifrost_kbase.ko
BLOB=$A/dl/libmali-bifrost-g31-g24p0-gbm.so
BTFFIX=bd60a159b                          # iommu-sun55i: drop the stale iommu_dma_cookie copy (kbase BTF validates only with it)
OUT=${KBT_OUT:-$A/traces/runner-j66}      # results (arm-blob/ is git-ignored: blob-derived traces never get committed)
R=/root/armblob                           # board work dir
ENV="LD_LIBRARY_PATH=$R/lib"
TESTS="basic gs_pass gs_amp gs_inv tess_tri tess_gs tess_quad gs_xfb gs_layer"
RGBA="basic gs_pass gs_amp gs_inv tess_tri tess_gs tess_quad gs_xfb gs_layer0 gs_layer1"
STEPS="load info afbc probe trace unload bind"
VARIANTS="v0 v1 v2 v3"
# blob config (key=value per line; the blob strips an optional MALI_ prefix): v0 = control, v1..v3 = AFBC off (+CRC off, +linear)
vcfg() { case $1 in v0) ;; v1) printf "GLES_DISABLE_TEXTURE_AFBC=1\nGLES_DISABLE_SURFACE_AFBC=1\n";;
  v2) vcfg v1; echo GLES_DISABLE_CRC=1;; v3) vcfg v2; echo GLES_FORCE_LINEAR_LAYOUT_UNCOMPRESSED_TEXTURE=1;; esac; }
# probe/trace: blob config of the variant the afbc step selected ($R/out/afbc/SELECTED)
CFGENV="CFG=\$(cat $R/out/afbc/SELECTED 2>/dev/null || echo v3); echo CONFIG \$CFG; cat $R/cfg/\$CFG.config; export MALI_PLATFORM_CONFIG=$R/cfg/\$CFG.config MALI_DEBUG_CONFIG=$R/cfg/\$CFG.config"
GPUDEV=/sys/bus/platform/devices/1800000.gpu
# board-side snippet: runtime PM, genpd and clock state of the GPU (unload/bind steps)
PMSTATE="echo PM: status=\$(cat $GPUDEV/power/runtime_status 2>/dev/null) usage=\$(cat $GPUDEV/power/runtime_usage 2>/dev/null) driver=\$(basename \$(readlink $GPUDEV/driver) 2>/dev/null)
grep -i gpu /sys/kernel/debug/pm_genpd/pm_genpd_summary 2>/dev/null | sed 's/^/GENPD: /'
grep -i -E 'gpu' /sys/kernel/debug/clk/clk_summary 2>/dev/null | sed 's/^/CLK: /'"
OWN=""
mkdir -p $OUT/files; touch $OUT/state
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; T1=20 S1 -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { # the stock image kernel; the reboot drops kbase (no rmmod/rebind here, see the header)
  waitup || { log "BOARD UNREACHABLE before restore"; echo "board unreachable before restore" > $OUT/BLOCKED; serial_save; return; }
  T1=30 S1 -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $(S1 -n 'uname -rv; readlink /boot/Image; ls /dev/dri | tr "\n" " "' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; serial_save; }
serial_save() { # serial.log bytes written since this run started -> $OUT/serial.txt (kernel messages of a hang or reset)
  [ -f $SERIAL ] && [ -n "${SER0:-}" ] && tail -c +$((SER0 + 1)) $SERIAL > $OUT/serial.txt 2>/dev/null; return 0; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
step_script() { # print the board script of a step; it ends with STEP-DONE
  local body
  case $1 in
    load)  body="fuser -v /dev/dri/renderD128 2>&1 | tail -3
dmesg -C
echo 1800000.gpu > /sys/bus/platform/drivers/panfrost/unbind; sleep 1
test -e /sys/bus/platform/drivers/panfrost/1800000.gpu && echo PANFROST-STILL-BOUND || echo PANFROST-UNBOUND
insmod $R/bifrost_kbase.ko; echo INSMOD-RC \$?
sleep 2; dmesg | sed 's/^/DMESG: /'
ls -la /dev/mali0 && echo MALI0-PRESENT || echo MALI0-MISSING
test -e /sys/kernel/btf/bifrost_kbase && echo MODULE-BTF-PRESENT || echo MODULE-BTF-MISSING
ls /sys/class/misc/mali0/device/ 2>/dev/null | head -40" ;;
    info)  body="cat /sys/class/misc/mali0/device/gpuinfo 2>/dev/null; cat /sys/class/misc/mali0/device/power_policy 2>/dev/null
cat /sys/kernel/debug/clk/gpu0/clk_rate 2>/dev/null; cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -i -A2 dcdc" ;;
    afbc)  body="rm -rf $R/out/afbc; mkdir -p $R/out/afbc; sel=''
for v in $VARIANTS; do mkdir -p $R/out/afbc/\$v; cd $R/out/afbc/\$v; n=\$(dmesg | wc -l)
  MALI_PLATFORM_CONFIG=$R/cfg/\$v.config MALI_DEBUG_CONFIG=$R/cfg/\$v.config $ENV timeout 60 $R/gles32probe $R/out/afbc/\$v basic > run.txt 2>&1; rc=\$?
  b=\$(grep -m1 '^basic: lit pixels' info.txt 2>/dev/null)
  echo \"VARIANT \$v rc \$rc faults \$(dmesg | tail -n +\$((n+1)) | grep -c DATA_INVALID) cfg [\$(tr '\\n' ' ' < $R/cfg/\$v.config)] \${b:-no basic line}\"
  grep -m3 -i -E 'config|error|warn' run.txt | sed 's/^/BLOB: /'
  [ -z \"\$sel\" ] && [ \$v != v0 ] && echo \"\$b\" | grep -q 'lit pixels [1-9]' && sel=\$v
done
echo \${sel:-v3} > $R/out/afbc/SELECTED; echo SELECTED \${sel:-v3} \$([ -n \"\$sel\" ] && echo renders || echo none-rendered)" ;;
    probe) body="rm -rf $R/out/probe; mkdir -p $R/out/probe; cd $R/out/probe
$CFGENV
n=\$(dmesg | wc -l)
# job 16: every case rendered nothing (glError 0x505 GL_OUT_OF_MEMORY, fragment-slot DATA_INVALID_FAULT): sample the
# per-context kbase debugfs (JIT counters, atoms, allocations, the blob's mem_profile) while the probe runs
mkdir -p kctx; ( while :; do for d in /sys/kernel/debug/mali0/ctx/*/; do [ -d \$d ] || continue
  echo \"== \$(date +%T.%N) \$d \$(for f in mem_jit_count mem_jit_phys mem_jit_vm mem_jit_used; do echo \$f=\$(cat \$d\$f 2>/dev/null | tr '\\n' ' '); done)\"
  for f in atoms mem_allocs mem_zones mem_profile; do cat \$d\$f > kctx/\$f.tmp 2>/dev/null && [ -s kctx/\$f.tmp ] && mv kctx/\$f.tmp kctx/\$f; done; done; sleep 0.3; done ) > kctx/jitstats.txt 2>&1 & SP=\$!
$ENV timeout 120 $R/gles32probe $R/out/probe; echo PROBE-RC \$?
kill \$SP; wait \$SP 2>/dev/null; rm -f kctx/*.tmp; echo KCTX-SAMPLES \$(grep -c '^==' kctx/jitstats.txt); ls kctx | tr '\\n' ' '; echo
cat info.txt; ls -la
dmesg | tail -n +\$((n+1)) | sed 's/^/DMESG: /'" ;;
    unload) body="dmesg -n 8; sync; n=\$(dmesg | wc -l)
echo BEFORE-RMMOD; $PMSTATE
echo RMMOD-START; timeout 40 rmmod bifrost_kbase; echo RMMOD-RC \$?
sleep 3; echo AFTER-RMMOD; $PMSTATE
dmesg | tail -n +\$((n+1)) | sed 's/^/DMESG: /'; sync" ;;
    bind) body="dmesg -n 8; sync; n=\$(dmesg | wc -l)
echo BEFORE-BIND; $PMSTATE; sync
echo BIND-START; timeout 40 sh -c 'echo 1800000.gpu > /sys/bus/platform/drivers/panfrost/bind'; echo BIND-RC \$?; sleep 3
echo AFTER-BIND; $PMSTATE
dmesg | tail -n +\$((n+1)) | sed 's/^/DMESG: /'
echo DRI: \$(ls /dev/dri | tr '\\n' ' ')" ;;
    trace) body="rm -rf $R/out/trace; mkdir -p $R/out/trace; cd $R/out/trace
$CFGENV
n=\$(dmesg | wc -l); $ENV KBTRACE_OUT=$R/out/trace/kbtrace.bin LD_PRELOAD=$R/kbtrace.so timeout 300 $R/gles32probe $R/out/trace; echo TRACE-RC \$?
ls -la; tail -25 info.txt
dmesg | tail -n +\$((n+1)) | sed 's/^/DMESG: /'" ;;
  esac
  cat <<EOS
cd /root; uname -v
$body
echo STEP-DONE
EOS
}
run_step() { # run_step <step> <timeout s> <stall s>: remote command under timeout + stall watchdog; output to $OUT/step-<s>.txt
  local s=$1 ct=$2 stall=$3 f=$OUT/step-$1.txt rc
  step_script $s | T1=30 S1 "mkdir -p $R; cat > $R/step-$s.sh" || { log "step $s: cannot write the board script"; return 1; }
  # bounds: board-side `timeout ct`; host-side SSH_TIMEOUT ct+60; keepalive ends it within 2 min if the board dies;
  # stall watchdog below: no new output for `stall` s -> kill_pid of exactly this ssh (never pkill -f)
  SSH_TIMEOUT=$((ct + 60)) $SSH -n "timeout $ct bash $R/step-$s.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 5
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $stall ]; then log "STALL: step $s no output for $stall s, killing ssh $p"; kill_pid $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null; rc=$?; [ $rc = 0 ] || log "step $s: ssh rc $rc (255 = connection lost, 124/137 = host timeout, 143 = watchdog)"
  grep '^DMESG: ' $f > $OUT/dmesg-$s.txt
  grep -q STEP-DONE $f && { echo $s >> $OUT/state; log "step $s done"; return 0; } || { log "step $s ended without STEP-DONE"; return 1; }; }
checks() { # mechanical checks from the results (HANDOFF.md); prints PASS/FAIL lines, exit 1 if any FAIL
  local bad=0 f n
  p() { echo "PASS $*"; }; fl() { echo "FAIL $*"; bad=1; }
  grep -q '^kernel: ' $OUT/runner.log 2>/dev/null && p "kernel: $(grep '^kernel: ' $OUT/runner.log | tail -1)" || fl "no 'kernel:' line in runner.log"
  grep -qs 'kernel fix: present' $OUT/runner.log && p "BTF fix $BTFFIX in the kernel" || fl "runner.log lacks 'kernel fix: present'"
  f=$OUT/step-load.txt
  grep -q '^PANFROST-UNBOUND' $f 2>/dev/null && p "panfrost unbound" || fl "panfrost not unbound (step-load.txt)"
  grep -q '^INSMOD-RC 0' $f 2>/dev/null && p "insmod rc 0" || fl "insmod rc: $(grep '^INSMOD-RC' $f 2>/dev/null || echo missing)"
  n=$(grep -c -i -E 'failed to validate module|BTF' $OUT/dmesg-load.txt 2>/dev/null); [ -f $OUT/dmesg-load.txt ] && [ "${n:-0}" = 0 ] && p "no BTF lines in dmesg after insmod" || { fl "BTF lines in dmesg after insmod: ${n:-no dmesg-load.txt}"; grep -i -E 'failed to validate module|BTF' $OUT/dmesg-load.txt 2>/dev/null; }
  grep -q '^MALI0-PRESENT' $f 2>/dev/null && p "/dev/mali0 present" || fl "/dev/mali0 missing"
  grep -q '^MODULE-BTF-PRESENT' $f 2>/dev/null && p "/sys/kernel/btf/bifrost_kbase present" || fl "/sys/kernel/btf/bifrost_kbase missing"
  n=$(grep -c -E 'Kernel DDK version' $OUT/dmesg-load.txt 2>/dev/null); [ "${n:-0}" -ge 1 ] && p "kbase probed: $(grep -E 'Kernel DDK version|sunxi glue' $OUT/dmesg-load.txt | head -2 | tr '\n' ' ')" || fl "no 'Kernel DDK version' in dmesg-load.txt"
  # v4: load noise fixed in kbase.ko v4 (port-7.3-v4.py)
  n=$(grep -c -E 'IRQ (JOB|MMU|GPU) not found' $OUT/dmesg-load.txt 2>/dev/null); [ -f $OUT/dmesg-load.txt ] && [ "${n:-0}" = 0 ] && p "load: no 'IRQ ... not found' lines" || fl "load: 'IRQ ... not found' lines: ${n:-no dmesg-load.txt}"
  n=$(grep -c -E 'WARNING:|Call trace' $OUT/dmesg-load.txt 2>/dev/null); [ -f $OUT/dmesg-load.txt ] && [ "${n:-0}" = 0 ] && p "load: no WARNING/Call trace in dmesg-load.txt" || { fl "load: WARNING/Call trace lines in dmesg-load.txt: ${n:-no file}"; grep -E 'WARNING:|workqueue' $OUT/dmesg-load.txt 2>/dev/null | head -3; }
  # v4: AFBC variants (the fix under test): v1..v3 disable AFBC in the blob config; v0 is the control
  f=$OUT/step-afbc.txt
  grep -q '^STEP-DONE' $f 2>/dev/null && p "step afbc finished" || fl "step afbc did not finish (no STEP-DONE)"
  grep '^VARIANT ' $f 2>/dev/null | sed 's/^/INFO afbc: /'; grep '^BLOB: ' $f 2>/dev/null | head -8 | sed 's/^/INFO afbc /'
  grep -q '^SELECTED v[1-3] renders' $f 2>/dev/null && p "afbc: $(grep '^SELECTED' $f)" || fl "afbc: no variant rendered ($(grep '^SELECTED' $f 2>/dev/null || echo no SELECTED line))"
  for s in probe trace; do f=$OUT/step-$s.txt
    grep '^CONFIG ' $f 2>/dev/null | sed "s/^/INFO $s blob /"
    grep -q '^STEP-DONE' $f 2>/dev/null && p "step $s finished" || fl "step $s did not finish (no STEP-DONE)"
    grep -q "^${s^^}-RC 0" $f 2>/dev/null && p "gles32probe ($s) rc 0" || fl "gles32probe ($s) rc: $(grep "^${s^^}-RC" $f 2>/dev/null || echo missing)"
    [ -s $OUT/files/$s/info.txt ] && grep -q '^done' $OUT/files/$s/info.txt && p "files/$s/info.txt complete" || fl "files/$s/info.txt missing or incomplete"
    for t in $RGBA; do [ -s $OUT/files/$s/$t.rgba ] && p "files/$s/$t.rgba" || fl "files/$s/$t.rgba missing or empty"; done
    for t in $TESTS; do [ -s $OUT/files/$s/$t.progbin ] && p "files/$s/$t.progbin" || fl "files/$s/$t.progbin missing or empty"; done
    n=$(grep -c -E 'Unhandled|Oops|BUG:|WARNING:|Call trace|mali.*(fault|error)' $OUT/dmesg-$s.txt 2>/dev/null); [ "${n:-0}" = 0 ] && p "dmesg-$s.txt: no fault/oops lines" || { fl "dmesg-$s.txt fault/oops lines: $n"; grep -E 'Unhandled|Oops|BUG:|WARNING:|Call trace|mali.*(fault|error)' $OUT/dmesg-$s.txt | head -5; }
  done
  [ -s $OUT/files/trace/kbtrace.bin ] && p "files/trace/kbtrace.bin $(stat -c %s $OUT/files/trace/kbtrace.bin) bytes" || fl "files/trace/kbtrace.bin missing or empty"
  [ -s $OUT/files/trace/decoded/index.txt ] && p "decoded: $(ls $OUT/files/trace/decoded | grep -c '^submit-') submits, index.txt $(wc -l < $OUT/files/trace/decoded/index.txt) lines" || fl "files/trace/decoded/index.txt missing (kbdecode)"
  grep -E '^[a-z_0-9]+: lit pixels' $OUT/files/probe/info.txt 2>/dev/null | sed 's/^/INFO probe case: /'
  for s in probe trace; do n=$(grep -m1 '^basic: lit pixels' $OUT/files/$s/info.txt 2>/dev/null)
    echo "$n" | grep -q 'lit pixels [1-9]' && p "$s: basic case rendered ($n)" || fl "$s: basic case did not render (${n:-no basic line})"; done
  # runner.log lines carry a date prefix, so match ' restored: ' (job 16's '^restored: ' could never match)
  n=$(grep ' restored: ' $OUT/runner.log 2>/dev/null | tail -1)
  echo "$n" | grep -q '7.3.1-edge-sunxi64' && echo "$n" | grep -q 'renderD128' && p "stock kernel restored, panfrost renderD128 back" || fl "stock kernel not restored or no renderD128: ${n:-no restored line}"
  # v3: the trace now holds the GPU memory: the fragment job headers decode (job 64: every header read as zero)
  n=$(grep -l 'Type: Fragment' $OUT/files/trace/decoded/submit-*.txt 2>/dev/null | wc -l)
  [ "$n" -ge 1 ] && p "trace memory captured: $n submit files decode a fragment job" || fl "trace memory not captured: no 'Type: Fragment' in files/trace/decoded/submit-*.txt"
  # v4: render-target block format of every fragment job vs its status after the run (job 65: AFBC 18/18 faulted)
  n=$(for x in $OUT/files/trace/decoded/submit-*.txt; do awk '/^Job Header/{es=""} /^  Exception Status/{es=$3} /^  Type: Fragment/{fr=1} /Writeback Block Format/{if(fr){print es, $4; fr=0}}' $x; done 2>/dev/null | sort | uniq -c | tr '\n' ';')
  echo "INFO rt: fragment RT format by job status (count status format): ${n:-none}"
  n=$(cat $OUT/files/trace/decoded/submit-*.txt 2>/dev/null | grep -c 'Writeback Block Format: AFBC')
  [ -s $OUT/files/trace/decoded/index.txt ] && [ "${n:-0}" = 0 ] && p "trace: no AFBC render target in the decoded submits" || fl "trace: AFBC render targets in the decoded submits: ${n:-no decode}"
  f=$OUT/files/trace/decoded/index.txt
  if [ -f $f ]; then grep -m8 -E ' POST atom ' $f | sed 's/^ */INFO post: /'; grep -m4 -E 'JIT_ALLOC ' $f | sed 's/^ */INFO jit: /'
    grep -m6 -E ' JITADDR ' $f | sed 's/^ */INFO jitaddr: /'; fi
  grep -h -m4 'sunxi diag:' $OUT/dmesg-probe.txt $OUT/dmesg-trace.txt 2>/dev/null | sed 's/^/INFO diag: /'
  # v3: unload (rmmod) and bind (panfrost rebind) are real checks now (glue term fix); a reset shows as no STEP-DONE
  f=$OUT/step-unload.txt
  if [ -f $f ]; then
    grep -q '^RMMOD-RC 0' $f && grep -q '^STEP-DONE' $f && p "unload: rmmod rc 0, step finished" || fl "unload: $(grep -E '^RMMOD-RC|^STALLED' $f | tr '\n' ' ')$(grep -q '^STEP-DONE' $f || echo '(no STEP-DONE: board hung or reset)')"
    grep -q 'sunxi glue: reset asserted' $OUT/dmesg-unload.txt 2>/dev/null && p "unload: glue term ran ($(grep -o 'sunxi glue: reset asserted.*' $OUT/dmesg-unload.txt | head -1))" || fl "unload: no 'sunxi glue: reset asserted' line in dmesg-unload.txt (old kbase.ko?)"
    grep -E '^(PM|GENPD|CLK):|^(BEFORE|AFTER)-' $f | sed 's/^/INFO unload /'
    n=$(grep -c -E 'WARNING:|unbalanced' $OUT/dmesg-unload.txt 2>/dev/null); [ "${n:-0}" = 0 ] && p "unload: no WARNING/unbalanced lines (kbase.ko v4)" || fl "unload: WARNING/unbalanced lines in dmesg-unload.txt: $n"
    grep -E 'Unhandled|Oops|BUG:|WARNING:|Call trace|Internal error|SError|hung|mali|panfrost' $OUT/dmesg-unload.txt 2>/dev/null | head -20 | sed 's/^/INFO unload /'
  else fl "unload: step not run"; fi
  f=$OUT/step-bind.txt
  if [ -f $f ]; then
    grep -q '^BIND-RC 0' $f && grep -q '^STEP-DONE' $f && grep -q '^DRI: .*renderD128' $f && p "bind: panfrost rebound, renderD128 present, step finished" || fl "bind: $(grep -E '^BIND-RC|^DRI:|^STALLED' $f | tr '\n' ' ')$(grep -q '^STEP-DONE' $f || echo '(no STEP-DONE: board hung or reset)')"
    grep -E '^(PM|GENPD|CLK):|^(BEFORE|AFTER)-' $f | sed 's/^/INFO bind /'
    grep -E 'Unhandled|Oops|BUG:|WARNING:|Call trace|Internal error|SError|hung|mali|panfrost' $OUT/dmesg-bind.txt 2>/dev/null | head -20 | sed 's/^/INFO bind /'
  else fl "bind: step not run (unload failed or board reset)"; fi
  n=$(grep -a -c 'U-Boot SPL' $OUT/serial.txt 2>/dev/null); echo "INFO serial: U-Boot SPL count ${n:-0} (expected 2: trial-kernel boot + restore reboot; more = a reset)"
  grep -a -E 'Unhandled|Oops|BUG:|WARNING:|Call trace|Internal error|SError|rcu.*stall|watchdog|U-Boot SPL' $OUT/serial.txt 2>/dev/null | head -20 | sed 's/^/INFO serial /'
  [ -f $OUT/BLOCKED ] && fl "BLOCKED: $(cat $OUT/BLOCKED)"
  echo "state: $(tr '\n' ' ' < $OUT/state)"
  return $bad; }
case "${1:-}" in
  --print) for s in $STEPS; do echo "## $s"; step_script $s; done; exit 0 ;;
  --check) checks; exit $? ;;
esac
rm -f $OUT/BLOCKED
# host-side preconditions (no board needed)
[ -f $KO ] || { log "missing $KO (build: bash kernel-check/kbase-trial/port/build.sh)"; exit 1; }
[ -f $BLOB ] || { log "missing blob $BLOB"; exit 1; }
[ -x $T/gles32probe ] && [ -f $T/kbtrace.so ] && [ -x $T/kbdecode ] || { log "missing $T/gles32probe, kbtrace.so or kbdecode"; exit 1; }
TAG=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$TAG | cut -c1-32) || exit 1
c=$(awk -v t=$TAG '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
git -C $H/wt-cumulative merge-base --is-ancestor $BTFFIX "$c" 2>/dev/null || { log "kernel $TAG ($c) lacks the BTF dedup fix $BTFFIX"; exit 1; }
# the build tree must be at $TAG (its Image = the served Image) and the .ko newer than its vmlinux: M= builds do not
# depend on vmlinux, so a .ko from an older tree carries stale distilled BTF (build.sh deletes the old .ko first).
# A stale .ko is rebuilt here (host only, ccache, ~1 min) under the kernel build lock; a running kernel build = retry later.
TREE=$H/kernel-check/work-cumul/linux-7.3.1
if [ "$(cat $KO.tag 2>/dev/null)" = "$TAG $want" ] && [ "$(stat -c %Y $KO.tag)" -ge "$(stat -c %Y $KO)" ]; then
  log "kbase.ko was built for $TAG ($KO.tag)"
else
[ "$(md5sum < $TREE/arch/arm64/boot/Image | cut -c1-32)" = "$want" ] || { log "kernel-check/work-cumul is not at $TAG (Image md5 differs: build in progress or newer tree?): retry later"; exit 1; }
if [ "$(stat -c %Y $KO)" -lt "$(stat -c %Y $TREE/vmlinux)" ]; then
  log "$KO is older than the $TAG vmlinux: rebuilding with kernel-check/kbase-trial/port/build.sh"
  mkdir -p $H/kernel-check/.locks; exec 9>$H/kernel-check/.locks/kernel-build.lock
  flock -n 9 || { log "a kernel build is running (kernel-build.lock busy): retry later"; exit 1; }
  bash $H/kernel-check/kbase-trial/port/build.sh > $H/kernel-check/kbase-trial/build-$TAG.log 2>&1 || { log "kbase build failed: $(tail -3 $H/kernel-check/kbase-trial/build-$TAG.log | tr '\n' ' ')"; exit 1; }
  exec 9>&-; log "rebuilt: $(tail -1 $H/kernel-check/kbase-trial/build-$TAG.log)"
fi
echo "$TAG $want" > $KO.tag
fi
[ "$(modinfo -F vermagic $KO)" = "7.3.1 SMP preempt mod_unload aarch64" ] || { log "unexpected vermagic: $(modinfo -F vermagic $KO)"; exit 1; }
komd5=$(md5sum < $KO | cut -c1-32); blobmd5=$(md5sum < $BLOB | cut -c1-32)
log "job $J start, kernel $TAG ($c, Image md5 $want), kbase.ko md5 $komd5 ($(stat -c %y $KO | cut -c1-19)), blob md5 $blobmd5, done before: $(tr '\n' ' ' < $OUT/state)"
boot_trial() { # install the newest cumulative kernel with the fallback armed (skip when it is already running)
  local img; img=$(S1 -n 'readlink /boot/Image') || blocked "board does not answer ssh"
  if [ "$img" = vmlinuz-7.3.1-vdec-$TAG ] && [ "$(S1 -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ]; then
    log "board already on $TAG"; S1 -n 'touch /run/vdec-ok'
  else
    [ "$img" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start (Image -> $img)"
    $V/install-kernel.sh $TAG 2>&1 | tail -3 | tee -a $OUT/runner.log
    T1=30 S1 -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
    waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
    [ "$(S1 -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$TAG Image md5 mismatch after install"
    S1 -n 'touch /run/vdec-ok'
  fi
  S1 -n 'uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  S1 -n 'test -e /sys/kernel/btf/vmlinux' && log "kernel fix: present ($TAG contains $BTFFIX, /sys/kernel/btf/vmlinux exists)" || blocked "/sys/kernel/btf/vmlinux missing on $TAG"
  S1 -n 'test -e /sys/bus/platform/drivers/panfrost/1800000.gpu' || blocked "panfrost is not bound to 1800000.gpu at start"; }
stage() { # /root/armblob: module + blob via ship.sh (HTTP pieces, sha256-checked; skipped when the md5 already matches), tools via scp
  S1 -n "mkdir -p $R/lib $R/out"
  [ "$(S1 -n "md5sum < $R/bifrost_kbase.ko 2>/dev/null | cut -c1-32")" = "$komd5" ] && log "stage: bifrost_kbase.ko already on the board" || \
    { $V/ship.sh $KO $R/bifrost_kbase.ko 2>&1 | tail -1 | tee -a $OUT/runner.log; [ "$(S1 -n "md5sum < $R/bifrost_kbase.ko | cut -c1-32")" = "$komd5" ] || blocked "bifrost_kbase.ko md5 mismatch after ship"; }
  [ "$(S1 -n "md5sum < $R/lib/libmali.so.1 2>/dev/null | cut -c1-32")" = "$blobmd5" ] && log "stage: libmali.so.1 already on the board" || \
    { $V/ship.sh $BLOB $R/lib/libmali.so.1 2>&1 | tail -1 | tee -a $OUT/runner.log; [ "$(S1 -n "md5sum < $R/lib/libmali.so.1 | cut -c1-32")" = "$blobmd5" ] || blocked "libmali.so.1 md5 mismatch after ship"; }
  scp -q "${K[@]}" $T/kbtrace.so $T/gles32probe root@10.56.0.107:$R/ || blocked "cannot copy kbtrace.so / gles32probe"
  for v in $VARIANTS; do vcfg $v | T1=30 S1 "mkdir -p $R/cfg; cat > $R/cfg/$v.config" || blocked "cannot write $R/cfg/$v.config"; done
  S1 -n "cd $R/lib; for l in libEGL.so.1 libGLESv2.so.2 libGLESv1_CM.so.1 libgbm.so.1 libOpenCL.so.1; do ln -sf libmali.so.1 \$l; done; chmod +x $R/gles32probe; modinfo -F vermagic $R/bifrost_kbase.ko" | sed 's/^/stage: board vermagic /' | tee -a $OUT/runner.log; }
kbase_up() { S1 -n 'test -e /dev/mali0'; }
SER0=$(stat -c %s $SERIAL 2>/dev/null || echo 0)
trap 'serial_save; release' EXIT
acquire; boot_trial; stage
# load: idempotent (skipped when /dev/mali0 is already there from an earlier run on this boot)
if kbase_up; then log "step load: kbase already loaded (/dev/mali0 present)"; grep -qx load $OUT/state || echo load >> $OUT/state
else run_step load 120 60 || blocked "step load did not finish"
  kbase_up || { log "kbase did not come up; dmesg:"; cat $OUT/dmesg-load.txt | tail -20 | tee -a $OUT/runner.log; restore; release; log "job $J end: kbase load failed"; exit 0; }
fi
grep -qx info $OUT/state || run_step info 60 30
if ! grep -qx afbc $OUT/state || [ ! -s $OUT/files/afbc/SELECTED ]; then kbase_up || blocked "/dev/mali0 vanished before step afbc"
  sed -i '/^afbc$/d' $OUT/state; run_step afbc 330 120
  mkdir -p $OUT/files/afbc; scp -q -r "${K[@]}" root@10.56.0.107:$R/out/afbc/. $OUT/files/afbc/ 2>/dev/null || log "fetch afbc: scp failed"
  log "afbc: $(grep '^SELECTED' $OUT/step-afbc.txt)"; fi
for s in probe trace; do
  grep -qx $s $OUT/state && [ -s $OUT/files/$s/info.txt ] && continue
  kbase_up || blocked "/dev/mali0 vanished before step $s"
  run_step $s $([ $s = trace ] && echo 400 || echo 200) 300
  mkdir -p $OUT/files/$s; scp -q -r "${K[@]}" root@10.56.0.107:$R/out/$s/. $OUT/files/$s/ 2>/dev/null || log "fetch $s: scp failed"
  log "fetched files/$s: $(ls $OUT/files/$s | wc -l) files"
done
# host-side decode of the trace (no board): index.txt + pandecode per submit
if [ -s $OUT/files/trace/kbtrace.bin ]; then rm -rf $OUT/files/trace/decoded
  timeout 600 $T/kbdecode $OUT/files/trace/kbtrace.bin $OUT/files/trace/decoded > $OUT/kbdecode.txt 2>&1; log "kbdecode rc $? ($(ls $OUT/files/trace/decoded 2>/dev/null | grep -c '^submit-') submits)"; fi
# diagnostic, only after every result is on the host: does kbase unload and panfrost rebind? (job 16: the board reset
# ~15 s into rmmod + bind). Console loglevel 8 so an oops reaches serial.log; a reset is caught by the keepalive /
# stall watchdog, then restore() waits for the board (the vdec fallback brings it back on the stock kernel).
# v3: unload = rmmod (glue term fix under test) with runtime-PM/genpd/clock state before and after; bind = panfrost rebind
if ! grep -qx unload $OUT/state; then kbase_up && { log "step unload: rmmod bifrost_kbase"; run_step unload 100 60 || log "step unload did not finish: board hung or reset (see serial.txt)"; grep -qx unload $OUT/state || echo unload >> $OUT/state; }; fi
if ! grep -qx bind $OUT/state && grep -q '^STEP-DONE' $OUT/step-unload.txt 2>/dev/null; then
  if T1=20 S1 -n true 2>/dev/null; then log "step bind: panfrost rebind"; run_step bind 100 60 || log "step bind did not finish: board hung or reset (see serial.txt)"
  else log "step bind: board unreachable after unload"; fi; grep -qx bind $OUT/state || echo bind >> $OUT/state; fi
restore; release
log "job $J end: steps done: $(tr '\n' ' ' < $OUT/state)"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
