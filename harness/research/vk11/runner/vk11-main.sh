#!/bin/bash
# Runner package job 68: the full dEQP-VK vk-main (vulkan-cts-1.4.6.2, 3 247 552 cases) on the fork panvk that now
# reports Vulkan 1.1 on the G31 (mesa-cl panfrost-opencl-fixes 9d278fabfc2 = 0dbf521d381 backport + core-builtins fix
# ded6ccea0bc + lazy JM descriptor pool 039c393b7fb + Bifrost warp count 9d278fabfc2, on top of ab1caa7378f/0e274280595). No MESA_VK_VERSION_OVERRIDE: the driver's own apiVersion is tested.
# Derived from harness/research/gpu-invalid-enc/runner/invalid-enc.sh (job 52).
# Self-contained: board lock (fresh owner name per acquire), newest cumulative kernel with the fallback armed
# (vdec-perf/install-kernel.sh, must carry the panfrost soft-stop fix e544ddb00), stock kernel restored with
# vdec-perf/restore-kernel.sh at the end, at every lock hand-over and when paused or blocked.
# Work unit: vk-main is split on the host into 64 parts (part-00..part-63, ~50 700 cases each, file order). A round
# runs deqp-run.py on the current part for at most 780 s (--budget), then the host copies the part's results off.
# A part is done when its summary.txt exists; it may take several rounds. Resumable at round granularity:
# re-running the same command skips finished parts and continues the current part where it stopped.
# Pause: `touch harness/research/vk11/logs/runner/PAUSE` (or --max-hours H): stops after the current round, stock
# kernel, lock released, exit 4. Hand-over: between rounds, if another session waits for the board, or every 3.5 h
# (the lock shows STALE? after 4 h), stock kernel -> release -> re-acquire -> trial kernel -> continue.
# Stall watchdog: no output for 300 s, or no new result row for 660 s (per-case timeout is 300 s) = stall: the round
# is killed (exact PIDs), the case that was running is recorded as Hang (from the qpa) and the part continues.
# Memory: deqp-run.py runs in a 600 MB memcg scope with OOMPolicy=continue (without it systemd stops the whole scope
# at the first OOM kill, job 68 chunk 1); an OOM-killed case is retried once, then recorded as OOM. Stuck case: a round
# that adds no row records the case deqp-run.py was in (shard-0.current); the 2nd such round for the same case records
# it as ResourceLimit (an OOM kill in that round) or Stuck, and the part goes on. No case can block a part.
# New build: a frozen copy, host results and board results of another fork commit are moved away / removed at start.
# Exit: 0 all parts done; 4 paused; 2 blocked (reason in logs/runner/BLOCKED); 1 setup or lock error.
# Checks: `vk11-main.sh --check` prints the mechanical checks of HANDOFF.md.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/vk11; VH=$H/harness/research/vk-hangs; MW=$H/mesa-work
V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; R=$S/runner
J=vk11
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid
OUT=$S/logs/runner; mkdir -p $OUT/files $OUT/dmesg $OUT/parts; touch $OUT/state $OUT/runner.log
FORK=9d278fabfc2                          # mesa-cl commit the build must be (git string in the driver)
SOFTSTOP=e544ddb00                        # panfrost soft-stop/resume fix the cumulative kernel must contain
NPART=64; BUDGET=780; CT=960; QUIET=300; NOPROG=660; REFRESH=12600
MAIN=$H/harness/research/gpu-src/vk-mustpass-1.4.6.2/vk-main.txt; MAINLINES=3247552
LIB=$MW/build-cl/src/panfrost/vulkan/libvulkan_panfrost.so
FROZEN=$S/frozen/vk3                      # copy of the first deploy; later runs deploy exactly this (git-ignored)
B=/root/vk11; VK=/root/cts/deqp-vk; DN=vk3
VKENV='unset MESA_VK_VERSION_OVERRIDE; export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 PANVK_DEBUG=sync'
FORKENV=". /root/opiz2-mesa/$DN/env.sh; export VK_ICD_FILENAMES=\$VK_DRIVER_FILES; $VKENV"
DMESG_RE='INSTR_INVALID_ENC|js fault|gpu sched timeout|Page fault|Unhandled|MMU|translation fault|AS_ACTIVE|panfrost.*(fault|error|reset|timeout)|Soft-stop|Out of memory|oom-kill|BUG|Oops|WARNING'
OWN=""; T0=$(date +%s); MAXH=0
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
partname() { printf 'part-%02d' $1; }

# ---------------- --check: mechanical checks (host only, no board) ----------------
check() {
  local f=$OUT/chunk-probe.txt v
  echo "== job 68 checks ($(date '+%F %T'))"
  v=FAIL; grep -q "fork: $FORK" $OUT/runner.log && grep -q "deployed $DN ok" $OUT/runner.log && grep -q "kernel fix: present" $OUT/runner.log && v=PASS
  echo "1 setup (fork $FORK, $DN deployed, kernel with $SOFTSTOP): $v"
  v=FAIL; grep -q '^apiVersion 1\.1\.' $f 2>/dev/null && grep -q '^VKPROPS-OK' $f && v=PASS
  echo "2 board apiVersion 1.1 + vkCreateDevice with all 1.1 features: $v ($(grep -m1 '^apiVersion' $f 2>/dev/null))"
  local cc; cc=$(awk '/^shaderCoreCount/{print $2; exit}' $f 2>/dev/null)
  v=PASS; [ -n "$cc" ] || v=FAIL
  for t in 1x1x1 4x1x1 3x5x7; do l=$(grep "^DIAG fork-d9-core-$t " $f 2>/dev/null)
    echo "$l" | grep -q ' rc=0 ' || v=FAIL; echo "$l" | grep -q 4294967295 && v=FAIL
    xs=$(echo "$l" | sed 's/.*out=\[\([^]]*\)\].*/\1/'); [ $(echo $xs | wc -w) -ge 16 ] || v=FAIL
    for x in $xs; do [ $(( (x >> 8) & 255 )) = "$cc" ] || v=FAIL; done; done
  echo "3 ARM core builtins probe d9 (rc=0, ids <= max, core count = shaderCoreCount $cc): $v"
  v=PASS; local wpc; wpc=$(awk '/^shaderWarpsPerCore/{print $2; exit}' $f 2>/dev/null); [ -n "$wpc" ] || v=FAIL
  for t in 1x1x1-g4x2x2:16 4x1x1-g4x2x2:64 3x5x7-g4x2x2:1680 64x1x1-g16x8x1:8192; do l=$(grep "^DIAG fork-d10-raw-${t%:*} " $f 2>/dev/null)
    echo "$l" | grep -q ' rc=0 ' || v=FAIL; local r=($(echo "$l" | grep -o 'out=\[[0-9 ]*\]' | tr -d 'out=[]') x x x x x x x x x)
    [ "${r[2]}" = 0 ] && [ "${r[3]}" = 0 ] && [ "${r[8]}" = "${t#*:}" ] && [ "${r[1]}" -le "${r[6]}" ] && [ "${r[0]}" -lt "${r[7]}" ] && [ "${r[7]}" = "$cc" ] && [ "${r[6]}" = $(( ${wpc:-0} - 1 )) ] 2>/dev/null || v=FAIL
    echo "  d10 ${t%:*}: max core ${r[0]}, max warp ${r[1]}, warp>max ${r[2]}, core>=count ${r[3]}, warp max ${r[6]}, count ${r[7]}, invocations ${r[8]} (want ${t#*:})"; done
  echo "3b raw core builtins d10 (no id above max, max warp id = shaderWarpsPerCore $wpc - 1, all invocations ran): $v"
  v=PASS
  grep -q '^DIAG fork-d2-ballot-4x1x1 rc=0 .*out=\[15 15 15 15 ' $f 2>/dev/null || v=FAIL
  grep -q '^DIAG fork-d3-elect-4x1x1 rc=0 .*out=\[42 13 13 13 ' $f 2>/dev/null || v=FAIL
  grep -q '^DIAG fork-d6-broadcast-4x1x1 rc=0 .*out=\[260 260 260 260 ' $f 2>/dev/null || v=FAIL
  grep -q '^DIAG fork-d8-cts-elect-4x1x1 rc=0 .*out=\[1 1 1 1 ' $f 2>/dev/null || v=FAIL
  echo "4 subgroup probes d2/d3/d6/d8 = job 52 values: $v"
  local np; np=$(grep -c '^part-' $OUT/state)
  v=FAIL; [ "$np" = $NPART ] && v=PASS; echo "5 parts complete: $np of $NPART: $v"
  local bad=0; for d in $OUT/files/part-*; do [ -f $d/results.csv.xz ] || continue
    n=$(xz -dc $d/results.csv.xz | wc -l); want=$(( $(zcat $OUT/parts/$(basename $d).txt.gz | wc -l) + 1 ))
    [ "$n" = "$want" ] || { bad=$((bad+1)); echo "  rows $(basename $d): $n, want $want"; }; done
  v=FAIL; [ $bad = 0 ] && v=PASS; echo "6 every finished part has one row per case: $v"
  local ie jf pf st; ie=$(cat $OUT/dmesg/*.txt 2>/dev/null | grep -c INSTR_INVALID_ENC)
  jf=$(cat $OUT/dmesg/*.txt 2>/dev/null | grep -c 'js fault')
  pf=$(cat $OUT/dmesg/*.txt 2>/dev/null | grep -Eci 'Page fault|translation fault|Unhandled')
  st=$(cat $OUT/dmesg/*.txt 2>/dev/null | grep -c 'gpu sched timeout')
  v=FAIL; [ $ie = 0 ] && v=PASS; echo "7 INSTR_INVALID_ENC in dmesg: $ie: $v"
  v=FAIL; [ $jf = 0 ] && [ $pf = 0 ] && [ $st = 0 ] && v=PASS
  echo "8 GPU faults in dmesg (js fault $jf, page/MMU fault $pf, gpu sched timeout $st): $v"
  [ $v = FAIL ] && grep -lE 'js fault|Page fault|translation fault|Unhandled|gpu sched timeout' $OUT/dmesg/*.txt | sed 's/^/  in /'
  if ls $OUT/files/part-*/results.csv.xz >/dev/null 2>&1; then
    python3 -I $R/vk11-cmp.py final $OUT/files $OUT/cmp.txt > $OUT/cmp-head.txt
    local reg; reg=$(awk '/^REGRESSIONS/{print $2}' $OUT/cmp-head.txt)
    v=FAIL; [ "$reg" = 0 ] && v=PASS; echo "9 regressions against the baselines (cmp.txt): $reg: $v"
    echo "INFO $(grep '^COUNTS' $OUT/cmp-head.txt)"
    grep '^BASELINE' $OUT/cmp.txt | sed 's/^/INFO /'
  else echo "9 regressions: no finished part yet: FAIL"; fi
  echo "INFO Hang rows (stall watchdog): $(grep -c 'HANG-MARKED' $OUT/runner.log) ; stalls: $(grep -c 'STALL:' $OUT/runner.log)"
  echo "INFO stuck-case rows (ResourceLimit/Stuck): $(grep -c STUCK-MARKED $OUT/runner.log)"
  echo "INFO Soft-stop lines in dmesg: $(cat $OUT/dmesg/*.txt 2>/dev/null | grep -c Soft-stop)"
  [ -f $OUT/BLOCKED ] && echo "INFO BLOCKED: $(cat $OUT/BLOCKED)"; true
}
case "${1:-}" in
  --check) check; exit 0 ;;
  --max-hours) MAXH=${2:?hours} ;;
  --print) ;;
  "") ;;
  *) echo "usage: vk11-main.sh [--max-hours H] | --check"; exit 1 ;;
esac
[ "${1:-}" = "--print" ] || rm -f $OUT/BLOCKED

# ---------------- lock, kernel, deploy ----------------
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  log "$out"; TL=$(date +%s); }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
waitup() { for i in $(seq 1 ${1:-60}); do sleep 10; $SSH -n true 2>/dev/null && return 0; done; return 1; }
restore() { $V/restore-kernel.sh 2>&1 | tail -1 | tee -a $OUT/runner.log   # Image, DTB (.stock), modules; reboots
  sleep 20; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
boot_trial() {
  local cur; cur=$($SSH -n 'readlink /boot/Image') || { echo "board does not answer ssh" > $OUT/BLOCKED; log "BLOCKED: board does not answer ssh"; release; exit 2; }
  # trial = vmlinuz-<release>-vdec-$T, stock = the image's vmlinuz-<release>-edge-sunxi64 (7.3.3 since the 2026-11-06 image)
  if [[ $cur == vmlinuz-*-vdec-$T ]] && [ "$($SSH -n "md5sum < /boot/$cur | cut -c1-32")" = "$KIMG" ]; then
    $SSH -n 'touch /run/vdec-ok'; log "kernel fix: present (already on $T, contains $SOFTSTOP)"; return; fi
  [[ $cur == vmlinuz-*-edge-sunxi64 ]] || blocked "board neither on the stock kernel nor on $T at start (/boot/Image -> $cur)"
  $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 20
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$KIMG" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok'; log "kernel fix: present ($T contains $SOFTSTOP)"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }

# host-side preconditions (no board needed)
if [ "${1:-}" != "--print" ]; then
[ -f $LIB ] || { log "missing build: $LIB"; exit 1; }
[ -f $VH/host/vkcomp-arm64 ] && [ -f $VH/host/diag/d8-cts-elect.spv ] && [ -f $S/host/diag/d9-core.spv ] && [ -f $S/host/diag/d10-raw.spv ] && [ -f $S/host/vkprops-arm64 ] || { log "missing vkcomp-arm64, vkprops-arm64 or a diag .spv"; exit 1; }
[ -f $MAIN ] && [ "$(wc -l < $MAIN)" = $MAINLINES ] || { log "missing or wrong $MAIN (want $MAINLINES lines)"; exit 1; }
if [ -f $OUT/FORK ] && [ "$(cat $OUT/FORK)" != $FORK ]; then   # results of another build never mix with this one
  A=$S/logs/runner-$(cat $OUT/FORK); mkdir -p $A
  for x in files dmesg state progress.txt chunk-probe.txt runner.log BLOCKED cmp.txt cmp-head.txt check.txt; do [ -e $OUT/$x ] && mv $OUT/$x $A/; done
  mkdir -p $OUT/files $OUT/dmesg; touch $OUT/state $OUT/runner.log; log "results of fork $(cat $OUT/FORK) moved to $A"
fi
echo $FORK > $OUT/FORK
if [ -d $FROZEN ] && ! strings $FROZEN/lib/libvulkan_panfrost.so | grep -q "git-${FORK:0:10}"; then
  rm -rf $FROZEN; log "stale frozen copy removed (not a build of $FORK)"; fi
if [ -d $FROZEN ]; then libmd5=$(md5sum < $FROZEN/lib/libvulkan_panfrost.so | cut -c1-32)
else strings $LIB | grep -q "git-${FORK:0:10}" || { log "$LIB is not a build of $FORK (rebuild build-cl at $FORK)"; exit 1; }; libmd5=new; fi
KIMG=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || { log "no served kernel Image.$T"; exit 1; }
c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
git -C $H/wt-cumulative merge-base --is-ancestor $SOFTSTOP "$c" 2>/dev/null || { log "kernel $T ($c) lacks the panfrost soft-stop fix $SOFTSTOP"; exit 1; }
log "fork: $FORK, lib md5 $libmd5 (frozen copy: $([ -d $FROZEN ] && echo yes || echo 'not yet')); kernel $T ($c, Image md5 $KIMG)"
# the 64 part caselists (file order, contiguous); made once
if [ "$(ls $OUT/parts/part-*.txt.gz 2>/dev/null | wc -l)" != $NPART ]; then
  rm -f $OUT/parts/part-*; L=$(( (MAINLINES + NPART - 1) / NPART ))
  awk -v L=$L -v d=$OUT/parts '{ f = sprintf("%s/part-%02d.txt", d, int((NR-1)/L)); print > f }' $MAIN
  gzip -9 $OUT/parts/part-*.txt; log "split vk-main into $NPART parts of <= $L cases"
fi
n=0; for p in $OUT/parts/part-*.txt.gz; do n=$((n + $(zcat $p | wc -l))); done
[ $n = $MAINLINES ] || { log "parts hold $n cases, want $MAINLINES"; exit 1; }
fi

setup() { # deploy the fork to /root/opiz2-mesa/vk3 (first time from build-cl, later from the frozen copy)
  $SSH -n true || blocked "board does not answer ssh"
  $SSH -n 'uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  if [ ! -d $FROZEN ]; then
    MESA_ENV=$MW/tools/env-cl.sh $MW/tools/deploy.sh build-cl $DN 2>&1 | tail -2 | tee -a $OUT/runner.log
    mkdir -p $(dirname $FROZEN); rm -rf $FROZEN; cp -a $MW/deploy/$DN $FROZEN
  else $SSH -n "mkdir -p /root/opiz2-mesa" || blocked "mkdir /root/opiz2-mesa failed"; timeout 900 rsync -a --delete -e "/usr/bin/ssh ${BOARD_SSH_OPTS[*]}" $FROZEN/ root@10.56.0.107:/root/opiz2-mesa/$DN/ || blocked "rsync of the frozen $DN failed"; fi
  want=$(md5sum < $FROZEN/lib/libvulkan_panfrost.so | cut -c1-32)
  have=$($SSH -n "md5sum < /root/opiz2-mesa/$DN/lib/libvulkan_panfrost.so | cut -c1-32")
  [ -n "$want" ] && [ "$want" = "$have" ] && log "deployed $DN ok (libvulkan_panfrost md5 $have)" || blocked "$DN deploy mismatch (host $want board $have)"
  $SSH -n "test -f /root/opiz2-mesa/$DN/panfrost_icd.json && test -x $VK/deqp-vk && mkdir -p $B/parts $B/res $B/diag $B/trace" || blocked "$DN icd json or /root/cts/deqp-vk is missing on the board"
  $SSH -n "[ \"\$(cat $B/res/FORK 2>/dev/null)\" = $FORK ] || { rm -rf $B/res $B/parts/part-*.txt; mkdir -p $B/res; echo $FORK > $B/res/FORK; echo RES-RESET; }" | grep -q RES-RESET && log "board results of another build removed ($B/res)"
  avail=$($SSH -n "df --output=avail -k /root | tail -1"); [ "${avail:-0}" -gt 1500000 ] || blocked "less than 1.5 GB free on the board /root ($avail kB)"
  scp -q "${K[@]}" $VH/host/vkcomp-arm64 root@10.56.0.107:$B/vkcomp || blocked "cannot copy vkcomp"
  scp -q "${K[@]}" $S/host/vkprops-arm64 root@10.56.0.107:$B/vkprops || blocked "cannot copy vkprops"
  scp -q "${K[@]}" $VH/host/diag/d2-ballot.spv $VH/host/diag/d3-elect.spv $VH/host/diag/d6-broadcast.spv $VH/host/diag/d8-cts-elect.spv $S/host/diag/d9-core.spv $S/host/diag/d10-raw.spv root@10.56.0.107:$B/diag/ || blocked "cannot copy the diag shaders"
  scp -q "${K[@]}" $H/harness/analysis/gpu/deqp-run.py root@10.56.0.107:$VK/deqp-run.py || blocked "cannot copy deqp-run.py"
  $SSH -n "chmod +x $B/vkcomp $B/vkprops"; }

# ---------------- board scripts ----------------
dmesg_since() { # board snippet: kernel lines since uptime $t0 matching DMESG_RE
  echo "dmesg | awk -v t=\$t0 '{ if (match(\$0, /^\\[ *[0-9]+\\.[0-9]+\\]/)) { s = substr(\$0, 2, RLENGTH - 2) + 0; if (s >= t) print } }' | grep -E '$DMESG_RE' | tail -200 | sed 's/^/DMESG: /'"; }
probe_script() { # vkprops (apiVersion, 1.1 properties/features, device creation) + core-builtins and subgroup probes
  cat <<EOS
cd /root; uname -v; t0=\$(cut -d' ' -f1 /proc/uptime)
( $FORKENV; timeout 60 $B/vkprops ) 2>&1 | grep -v '^ext '
( $FORKENV; timeout 60 $B/vkprops ) 2>&1 | grep -c '^ext ' | sed 's/^/deviceExtensions-listed /'
( $FORKENV; command -v vulkaninfo >/dev/null && timeout 60 vulkaninfo --summary 2>&1 | grep -E 'apiVersion|driverInfo|deviceName|conformanceVersion' | sed 's/^/vulkaninfo: /' )
run1() { sh=\$1; lx=\$2; ly=\$3; lz=\$4; gx=\${5:-4}; gy=\${6:-2}; gz=\${7:-2}; tag=fork-\$sh-\${lx}x\${ly}x\${lz}
  [ \$# -gt 4 ] && tag=\$tag-g\${gx}x\${gy}x\${gz}
  out=\$( ( $FORKENV; timeout 30 $B/vkcomp $B/diag/\$sh.spv \$lx \$ly \$lz \$gx \$gy \$gz 1 2>&1 ) ); rc=\$?
  echo "DIAG \$tag rc=\$rc out=[\$(echo "\$out" | grep -v '^device\|^pipeline\|^dispatch' | head -2 | tr '\n' ' ' | sed 's/ *\$//')]"; }
for ls in "1 1 1" "4 1 1" "3 5 7"; do run1 d9-core \$ls; done
for a in "1 1 1 4 2 2" "4 1 1 4 2 2" "3 5 7 4 2 2" "64 1 1 16 8 1"; do run1 d10-raw \$a; done
for sh in d2-ballot d3-elect d6-broadcast d8-cts-elect; do run1 \$sh 4 1 1; done
$(dmesg_since)
echo ROUND-DONE
EOS
}
round_script() { # one round on part $1: at most $BUDGET s of deqp-run.py, progress lines every 30 s
  local P=$1 D=$B/res/$1
  cat <<EOS
cd /root; uname -v; t0=\$(cut -d' ' -f1 /proc/uptime)
# a previous round that the host gave up on must be gone (exact PIDs)
if [ -f $B/round.pid ]; then p=\$(cat $B/round.pid); kill -0 \$p 2>/dev/null && grep -q deqp-run /proc/\$p/cmdline 2>/dev/null && { kill \$p; sleep 3; kill -9 \$p 2>/dev/null; echo KILLED-OLD-ROUND \$p; }; rm -f $B/round.pid; fi
for p in \$(pidof deqp-vk); do kill -9 \$p; echo KILLED-OLD-DEQP \$p; done
avail=\$(df --output=avail -k /root | tail -1); [ \$avail -gt 500000 ] || { echo NOSPACE \$avail; echo ROUND-DONE; exit 0; }
mkdir -p $D
[ -f $B/parts/$P.txt ] || { gunzip -c $B/parts/$P.txt.gz > $B/parts/$P.tmp && mv $B/parts/$P.tmp $B/parts/$P.txt; }
if [ -f $D/STALLED ]; then # the case that was running when the host watchdog fired = Hang
  c=\$(awk '/^#beginTestCaseResult/{c=\$2; o=1} /^#(endTestCaseResult|terminateTestCaseResult)/{o=0} END{if (o) print c}' $D/shard-0.qpa 2>/dev/null)
  if [ -n "\$c" ] && ! grep -q "^\$c," $D/shard-0.csv 2>/dev/null; then echo "\$c,Hang,,stall watchdog (no result for $NOPROG s or board unreachable)" >> $D/shard-0.csv; echo "HANG-MARKED \$c"; fi
  rm -f $D/STALLED
fi
if [ -f $D/summary.txt ]; then echo PART-COMPLETE; else
  r0=\$(cat $D/shard-0.csv 2>/dev/null | wc -l)
  ( $FORKENV; cd $VK; exec systemd-run --quiet --scope -p MemoryMax=600M -p MemorySwapMax=64M -p OOMPolicy=continue python3 $VK/deqp-run.py --deqp $VK/deqp-vk --caselist $B/parts/$P.txt --out $D --jobs 1 --timeout 300 --budget $BUDGET ) > $D/round.out 2>&1 &
  pid=\$!; echo \$pid > $B/round.pid
  while kill -0 \$pid 2>/dev/null; do sleep 30; echo PROGRESS \$(cat $D/shard-0.csv 2>/dev/null | wc -l); done
  wait \$pid; echo DEQP-RC \$?; rm -f $B/round.pid; tail -12 $D/round.out
  r1=\$(cat $D/shard-0.csv 2>/dev/null | wc -l)
  if [ "\$r1" != "\$r0" ]; then rm -f $D/noprog.txt
  elif [ ! -f $D/summary.txt ] && [ -s $D/shard-0.current ]; then # no new row: count rounds stuck on the same case
    c=\$(cat $D/shard-0.current); echo "\$c" >> $D/noprog.txt; n=\$(grep -cxF "\$c" $D/noprog.txt); echo "NOPROG \$c \$n"
    if [ \$n -ge 2 ] && ! awk -F, -v c="\$c" '\$1==c{f=1} END{exit !f}' $D/shard-0.csv 2>/dev/null; then
      if $(dmesg_since) | grep -q 'oom-kill'; then st=ResourceLimit; why="memcg OOM (600 MB) in \$n rounds without a result"
      else st=Stuck; why="no result in \$n rounds (rc of deqp-run.py not 0)"; fi
      echo "\$c,\$st,,\$why" >> $D/shard-0.csv; echo "STUCK-MARKED \$c \$st"; rm -f $D/noprog.txt
    fi
  fi
  rm -f $D/shard-0.qpa
  [ -f $D/summary.txt ] && echo PART-COMPLETE || echo PART-INCOMPLETE \$(cat $D/shard-0.csv 2>/dev/null | wc -l) of \$(wc -l < $B/parts/$P.txt)
fi
$(dmesg_since)
echo ROUND-DONE
EOS
}
[ "${1:-}" = "--print" ] && { probe_script; round_script part-00; exit 0; }

# ---------------- running a board script under the watchdog ----------------
watch_run() { # watch_run <name> <logfile>: runs $B/<name>.sh; returns 0 ok, 1 stalled
  local f=$2 last=$(date +%s) sz=0 prog="" lastprog=$(date +%s)
  $SSH -n "timeout $CT bash $B/$1.sh" > $f 2>&1 & local p=$!
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    pg=$(grep '^PROGRESS' $f | tail -1); [ "$pg" != "$prog" ] && { prog=$pg; lastprog=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $QUIET ] || [ $(( $(date +%s) - lastprog )) -gt $NOPROG ]; then
      log "STALL: $1 (no output for $(( $(date +%s) - last )) s, no new result for $(( $(date +%s) - lastprog )) s), killing ssh $p"
      kill_pid $p; echo STALLED >> $f; wait $p 2>/dev/null; return 1; fi
  done; wait $p 2>/dev/null; return 0; }
after_stall() { # after_stall <part>: kill the round on the board, mark the hung case; board down -> wait, then BLOCKED
  local P=$1
  if ! $SSH -n true 2>/dev/null && ! waitup 60; then
    log "BLOCKED: board unreachable after a stall in $P"
    echo "board unreachable after a stall in $P: power-cycle per RUNNER.md, then rerun the same command (it resumes)" > $OUT/BLOCKED
    release; exit 2; fi
  $SSH -n "p=\$(cat $B/round.pid 2>/dev/null); [ -n \"\$p\" ] && grep -q deqp-run /proc/\$p/cmdline 2>/dev/null || p=; [ -n \"\$p\" ] && kill \$p 2>/dev/null; sleep 3; [ -n \"\$p\" ] && kill -9 \$p 2>/dev/null; for q in \$(pidof deqp-vk); do kill -9 \$q; done; rm -f $B/round.pid; touch $B/res/$P/STALLED" 2>/dev/null
  [[ $($SSH -n 'readlink /boot/Image') == vmlinuz-*-vdec-$T ]] || { log "board came back on another kernel after the stall: reinstalling $T"; boot_trial; setup; }
  $SSH -n 'touch /run/vdec-ok'; }
run_probe() {
  probe_script | $SSH "mkdir -p $B; cat > $B/probe.sh" || { log "probe: cannot write the board script"; return; }
  watch_run probe $OUT/chunk-probe.txt || after_stall probe-none
  grep '^DMESG' $OUT/chunk-probe.txt > $OUT/dmesg/probe.txt
  grep -q ROUND-DONE $OUT/chunk-probe.txt && { echo probe >> $OUT/state; log "probe done: $(grep -m1 '^apiVersion' $OUT/chunk-probe.txt)"; } || log "probe ended without ROUND-DONE"; }
run_round() { # run_round <part>: one round, copy off, finish the part if complete
  local P=$1 f=$OUT/files/$1/round-$(date +%Y%m%d-%H%M%S).txt d=$OUT/files/$1
  mkdir -p $d
  $SSH -n "test -f $B/parts/$P.txt -o -f $B/parts/$P.txt.gz" || scp -q "${K[@]}" $OUT/parts/$P.txt.gz root@10.56.0.107:$B/parts/ || { log "$P: cannot copy the caselist"; return; }
  round_script $P | $SSH "cat > $B/round.sh" || { log "$P: cannot write the board script"; return; }
  watch_run round $f || { after_stall $P; log "$P: stall (round log $f)"; }
  grep '^DMESG' $f >> $OUT/dmesg/$P.txt
  grep -q '^HANG-MARKED' $f && grep '^HANG-MARKED' $f | sed "s/^/$P /" | tee -a $OUT/runner.log
  grep -q '^STUCK-MARKED' $f && grep '^STUCK-MARKED' $f | sed "s/^/$P /" | tee -a $OUT/runner.log
  grep -q '^NOSPACE' $f && blocked "board /root is full ($(grep '^NOSPACE' $f))"
  scp -q "${K[@]}" root@10.56.0.107:$B/res/$P/shard-0.csv $d/ 2>/dev/null   # copy-off every round
  local rows; rows=$(cat $d/shard-0.csv 2>/dev/null | wc -l); want=$(zcat $OUT/parts/$P.txt.gz | wc -l)
  echo "$(date '+%F %T') $P $rows/$want $(grep -E '^PART-' $f | tail -1)" >> $OUT/progress.txt
  if [ "$rows" = "${lastrows:-x}" ] && ! grep -q '^PART-COMPLETE' $f; then nprog=$((nprog + 1)); else nprog=0; fi; lastrows=$rows
  if grep -q '^PART-COMPLETE' $f; then
    scp -q "${K[@]}" root@10.56.0.107:$B/res/$P/results.csv root@10.56.0.107:$B/res/$P/summary.txt $d/ || { log "$P: copy of results failed (retry next round)"; return; }
    [ "$(wc -l < $d/results.csv)" = $((want + 1)) ] || { log "$P: results.csv has $(wc -l < $d/results.csv) rows, want $((want + 1)) (retry next round)"; return; }
    xz -f -T2 $d/results.csv && rm -f $d/shard-0.csv
    python3 -I $R/vk11-cmp.py part $d/results.csv.xz $d | tee -a $OUT/runner.log
    $SSH -n "rm -rf $B/res/$P $B/parts/$P.txt $B/parts/$P.txt.gz"
    echo $P >> $OUT/state; log "$P done"
  fi
  [ $nprog -ge 4 ] && blocked "$P: 4 rounds in a row without a new result even after stuck-case marking (see $OUT/files/$P/round-*.txt)"; true; }

# ---------------- main ----------------
log "job $J start ($(grep -c '^part-' $OUT/state) of $NPART parts done before; max hours ${MAXH})"
trap 'release' EXIT
acquire; boot_trial; setup
grep -qx probe $OUT/state || { log "probe start"; run_probe; }
nprog=0; lastrows=x
for i in $(seq 0 $((NPART - 1))); do P=$(partname $i)
  while ! grep -qx $P $OUT/state; do
    if [ -f $OUT/PAUSE ] || { [ $MAXH != 0 ] && [ $(( $(date +%s) - T0 )) -gt $(( MAXH * 3600 )) ]; }; then
      log "PAUSED before the next round of $P ($(grep -c '^part-' $OUT/state) of $NPART parts done)"; rm -f $OUT/PAUSE
      restore; release; exit 4; fi
    if others_waiting || [ $(( $(date +%s) - TL )) -gt $REFRESH ]; then
      log "lock hand-over ($(others_waiting && echo 'another session waits' || echo 'periodic refresh'))"
      restore; release; acquire; boot_trial; setup; fi
    run_round $P
  done
done
restore; release
log "job $J end: $(grep -c '^part-' $OUT/state) of $NPART parts done"
bash $R/vk11-main.sh --check | tee $OUT/check.txt
[ -f $OUT/BLOCKED ] && exit 2; exit 0
