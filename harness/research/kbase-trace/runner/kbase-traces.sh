#!/bin/bash
# Runner package: Arm kbase trial + libmali g24p0 GLES 3.2 reference traces (status.md item 8 step 1): kbase-traces.sh
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
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
KO=$H/kernel-check/kbase-trial/src/drivers/gpu/arm/bifrost/bifrost_kbase.ko
BLOB=$A/dl/libmali-bifrost-g31-g24p0-gbm.so
BTFFIX=bd60a159b                          # iommu-sun55i: drop the stale iommu_dma_cookie copy (kbase BTF validates only with it)
OUT=$A/traces/runner                      # results (arm-blob/ is git-ignored: blob-derived traces never get committed)
R=/root/armblob                           # board work dir
ENV="LD_LIBRARY_PATH=$R/lib"
TESTS="basic gs_pass gs_amp gs_inv tess_tri tess_gs tess_quad gs_xfb gs_layer"
RGBA="basic gs_pass gs_amp gs_inv tess_tri tess_gs tess_quad gs_xfb gs_layer0 gs_layer1"
STEPS="load info probe trace"
OWN=""
mkdir -p $OUT/files; touch $OUT/state
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { # panfrost back (kbase out), then the stock image kernel
  log "restore: dri after rebind: $($SSH -n "rmmod bifrost_kbase 2>/dev/null; echo 1800000.gpu > /sys/bus/platform/drivers/panfrost/bind 2>/dev/null; sleep 1; ls /dev/dri" 2>&1 | tr '\n' ' ')"
  $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image; ls /dev/dri | tr "\n" " "' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
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
    probe) body="rm -rf $R/out/probe; mkdir -p $R/out/probe; cd $R/out/probe
n=\$(dmesg | wc -l); $ENV timeout 120 $R/gles32probe $R/out/probe; echo PROBE-RC \$?
cat info.txt; ls -la
dmesg | tail -n +\$((n+1)) | sed 's/^/DMESG: /'" ;;
    trace) body="rm -rf $R/out/trace; mkdir -p $R/out/trace; cd $R/out/trace
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
  local s=$1 ct=$2 stall=$3 f=$OUT/step-$1.txt
  step_script $s | $SSH "mkdir -p $R; cat > $R/step-$s.sh" || { log "step $s: cannot write the board script"; return 1; }
  $SSH -n "timeout $ct bash $R/step-$s.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 10
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $stall ]; then log "STALL: step $s no output for $stall s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
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
  for s in probe trace; do f=$OUT/step-$s.txt
    grep -q '^STEP-DONE' $f 2>/dev/null && p "step $s finished" || fl "step $s did not finish (no STEP-DONE)"
    grep -q "^${s^^}-RC 0" $f 2>/dev/null && p "gles32probe ($s) rc 0" || fl "gles32probe ($s) rc: $(grep "^${s^^}-RC" $f 2>/dev/null || echo missing)"
    [ -s $OUT/files/$s/info.txt ] && grep -q '^done' $OUT/files/$s/info.txt && p "files/$s/info.txt complete" || fl "files/$s/info.txt missing or incomplete"
    for t in $RGBA; do [ -s $OUT/files/$s/$t.rgba ] && p "files/$s/$t.rgba" || fl "files/$s/$t.rgba missing or empty"; done
    for t in $TESTS; do [ -s $OUT/files/$s/$t.progbin ] && p "files/$s/$t.progbin" || fl "files/$s/$t.progbin missing or empty"; done
    n=$(grep -c -E 'Unhandled|Oops|BUG:|WARNING:|Call trace|mali.*(fault|error)' $OUT/dmesg-$s.txt 2>/dev/null); [ "${n:-0}" = 0 ] && p "dmesg-$s.txt: no fault/oops lines" || { fl "dmesg-$s.txt fault/oops lines: $n"; grep -E 'Unhandled|Oops|BUG:|WARNING:|Call trace|mali.*(fault|error)' $OUT/dmesg-$s.txt; }
  done
  [ -s $OUT/files/trace/kbtrace.bin ] && p "files/trace/kbtrace.bin $(stat -c %s $OUT/files/trace/kbtrace.bin) bytes" || fl "files/trace/kbtrace.bin missing or empty"
  [ -s $OUT/files/trace/decoded/index.txt ] && p "decoded: $(ls $OUT/files/trace/decoded | grep -c '^submit-') submits, index.txt $(wc -l < $OUT/files/trace/decoded/index.txt) lines" || fl "files/trace/decoded/index.txt missing (kbdecode)"
  grep -q '^restored: .*7.3.1-edge-sunxi64' $OUT/runner.log 2>/dev/null && grep '^restored: ' $OUT/runner.log | tail -1 | grep -q 'renderD128' && p "stock kernel restored, panfrost renderD128 back" || fl "stock kernel not restored or no renderD128: $(grep '^restored: ' $OUT/runner.log | tail -1)"
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
[ "$(md5sum < $TREE/arch/arm64/boot/Image | cut -c1-32)" = "$want" ] || { log "kernel-check/work-cumul is not at $TAG (Image md5 differs: build in progress or newer tree?): retry later"; exit 1; }
if [ "$(stat -c %Y $KO)" -lt "$(stat -c %Y $TREE/vmlinux)" ]; then
  log "$KO is older than the $TAG vmlinux: rebuilding with kernel-check/kbase-trial/port/build.sh"
  mkdir -p $H/kernel-check/.locks; exec 9>$H/kernel-check/.locks/kernel-build.lock
  flock -n 9 || { log "a kernel build is running (kernel-build.lock busy): retry later"; exit 1; }
  bash $H/kernel-check/kbase-trial/port/build.sh > $H/kernel-check/kbase-trial/build-$TAG.log 2>&1 || { log "kbase build failed: $(tail -3 $H/kernel-check/kbase-trial/build-$TAG.log | tr '\n' ' ')"; exit 1; }
  exec 9>&-; log "rebuilt: $(tail -1 $H/kernel-check/kbase-trial/build-$TAG.log)"
fi
[ "$(modinfo -F vermagic $KO)" = "7.3.1 SMP preempt mod_unload aarch64" ] || { log "unexpected vermagic: $(modinfo -F vermagic $KO)"; exit 1; }
komd5=$(md5sum < $KO | cut -c1-32); blobmd5=$(md5sum < $BLOB | cut -c1-32)
log "job $J start, kernel $TAG ($c, Image md5 $want), kbase.ko md5 $komd5 ($(stat -c %y $KO | cut -c1-19)), blob md5 $blobmd5, done before: $(tr '\n' ' ' < $OUT/state)"
boot_trial() { # install the newest cumulative kernel with the fallback armed (skip when it is already running)
  local img; img=$($SSH -n 'readlink /boot/Image') || blocked "board does not answer ssh"
  if [ "$img" = vmlinuz-7.3.1-vdec-$TAG ] && [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ]; then
    log "board already on $TAG"; $SSH -n 'touch /run/vdec-ok'
  else
    [ "$img" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start (Image -> $img)"
    $V/install-kernel.sh $TAG 2>&1 | tail -3 | tee -a $OUT/runner.log
    $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
    waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
    [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$TAG Image md5 mismatch after install"
    $SSH -n 'touch /run/vdec-ok'
  fi
  $SSH -n 'uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  $SSH -n 'test -e /sys/kernel/btf/vmlinux' && log "kernel fix: present ($TAG contains $BTFFIX, /sys/kernel/btf/vmlinux exists)" || blocked "/sys/kernel/btf/vmlinux missing on $TAG"
  $SSH -n 'test -e /sys/bus/platform/drivers/panfrost/1800000.gpu' || blocked "panfrost is not bound to 1800000.gpu at start"; }
stage() { # /root/armblob: module + blob via ship.sh (HTTP pieces, sha256-checked; skipped when the md5 already matches), tools via scp
  $SSH -n "mkdir -p $R/lib $R/out"
  [ "$($SSH -n "md5sum < $R/bifrost_kbase.ko 2>/dev/null | cut -c1-32")" = "$komd5" ] && log "stage: bifrost_kbase.ko already on the board" || \
    { $V/ship.sh $KO $R/bifrost_kbase.ko 2>&1 | tail -1 | tee -a $OUT/runner.log; [ "$($SSH -n "md5sum < $R/bifrost_kbase.ko | cut -c1-32")" = "$komd5" ] || blocked "bifrost_kbase.ko md5 mismatch after ship"; }
  [ "$($SSH -n "md5sum < $R/lib/libmali.so.1 2>/dev/null | cut -c1-32")" = "$blobmd5" ] && log "stage: libmali.so.1 already on the board" || \
    { $V/ship.sh $BLOB $R/lib/libmali.so.1 2>&1 | tail -1 | tee -a $OUT/runner.log; [ "$($SSH -n "md5sum < $R/lib/libmali.so.1 | cut -c1-32")" = "$blobmd5" ] || blocked "libmali.so.1 md5 mismatch after ship"; }
  scp -q "${K[@]}" $T/kbtrace.so $T/gles32probe root@10.56.0.107:$R/ || blocked "cannot copy kbtrace.so / gles32probe"
  $SSH -n "cd $R/lib; for l in libEGL.so.1 libGLESv2.so.2 libGLESv1_CM.so.1 libgbm.so.1 libOpenCL.so.1; do ln -sf libmali.so.1 \$l; done; chmod +x $R/gles32probe; modinfo -F vermagic $R/bifrost_kbase.ko" | sed 's/^/stage: board vermagic /' | tee -a $OUT/runner.log; }
kbase_up() { $SSH -n 'test -e /dev/mali0'; }
trap 'release' EXIT
acquire; boot_trial; stage
# load: idempotent (skipped when /dev/mali0 is already there from an earlier run on this boot)
if kbase_up; then log "step load: kbase already loaded (/dev/mali0 present)"; grep -qx load $OUT/state || echo load >> $OUT/state
else run_step load 120 60 || blocked "step load did not finish"
  kbase_up || { log "kbase did not come up; dmesg:"; cat $OUT/dmesg-load.txt | tail -20 | tee -a $OUT/runner.log; restore; release; log "job $J end: kbase load failed"; exit 0; }
fi
grep -qx info $OUT/state || run_step info 60 30
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
restore; release
log "job $J end: steps done: $(tr '\n' ' ' < $OUT/state)"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
