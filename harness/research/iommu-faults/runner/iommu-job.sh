#!/bin/bash
# Runner package for job iommu-faults: iommu-job.sh (no arguments). See HANDOFF.md.
# Two chunks: "stock" runs board-iommu.sh on the stock image kernel (positive control: the unfixed decode logs the
# 0xfff00000 fault), "fixed" installs the newest cumulative kernel (it must contain fix/sunxi-iommu-prefetch-pt-fault
# c411b37fb, else BLOCKED) with the vdec fallback armed, runs the same script, and restores the stock kernel.
# Self-contained: board lock (fresh owner per acquire), stall watchdog, results copied after every chunk, resumable
# (chunks listed in $OUT/state are skipped). Exit 0 = both chunks ran; 2 = blocked (reason in $OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/iommu-faults; SSH=$H/harness/ssh.sh; VP=$H/harness/research/vdec-perf
CK=$H/kernel-check/cumulative-kernels.txt; FIX=c411b37fb65185fff26763471f3e15220f8c450a
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
OUT=$S/logs/runner-iommu-faults; mkdir -p $OUT; touch $OUT/state; rm -f $OUT/BLOCKED
CT=900; STALL=400; STOCK=vmlinuz-7.3.1-edge-sunxi64
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-iommu-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { $SSH -n "ln -sfn $STOCK /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &"
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = $STOCK ]; }
boot_fixed() {
  on_stock || blocked "board not on the stock image kernel at start"
  T=$(tail -1 $CK | cut -d' ' -f1); sha=$(tail -1 $CK | cut -d' ' -f3)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX $sha 2>/dev/null || blocked "newest cumulative kernel $T ($sha) does not contain fix/sunxi-iommu-prefetch-pt-fault $FIX"
  want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || blocked "no Image.$T in kernel-check/vdec-serve"
  log "installing $T (Image md5 $want)"
  $VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
run_chunk() { # run_chunk <stock|fixed>: board script under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt
  scp -q "${K[@]}" $S/runner/board-iommu.sh root@10.56.0.107:/root/board-iommu.sh || blocked "scp of the board script failed"
  $SSH -n "timeout $CT bash /root/board-iommu.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill_pid $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  $SSH -n 'echo detect > /sys/class/drm/card0-HDMI-A-1/status 2>/dev/null; dmesg | grep -iE "iommu|fault|timed out|oops|bug:" | tail -30' > $OUT/dmesg-$c.txt 2>&1
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
log "job iommu-faults start, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire
if ! grep -qx stock $OUT/state; then
  on_stock || blocked "board not on the stock image kernel at start"
  log "chunk stock start ($($SSH -n 'uname -v'))"; run_chunk stock
fi
if ! grep -qx fixed $OUT/state; then
  if others_waiting; then log "another session waits: handing over the lock"; release; acquire; fi
  boot_fixed; log "chunk fixed start"; run_chunk fixed; restore
fi
release
log "job iommu-faults end: $(wc -l < $OUT/state) of 2 chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
