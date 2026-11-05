#!/bin/bash
# Runner package for the vdec board jobs: vdec-job.sh <t1f9|afbc|soak3>
# Self-contained: board lock (fresh owner name per acquire), install cumulative kernel c9 with the vdec fallback armed,
# run the job's board script in chunks of at most ~15 min under a stall watchdog, copy the results off after every chunk,
# restore the stock image kernel (vmlinuz-7.3.1-edge-sunxi64), release. Between chunks the lock is handed over (stock
# kernel restored first) if another session waits. Resumable: re-running the same command skips chunks listed in
# $OUT/state. Exit 0 = all chunks ran (pass/fail is judged from the results, see HANDOFF.md); 2 = blocked (reason in
# $OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; J=${1:?job: t1f9|afbc|soak3}; T=c9
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner-$J; mkdir -p $OUT; touch $OUT/state; rm -f $OUT/BLOCKED
case $J in
  t1f9)  BQ=board-queue-t1r.sh;  CHUNKS="1"; CT=900; STALL=600; ENV=""; FETCH="/root/avs2/out/*" ;;
  afbc)  BQ=board-queue-afbc.sh; CHUNKS="vp9p2 hevc10 avs2 hevc8 vp9p0"; CT=1000; STALL=1000; ENV="AFBC_BUDGET_MS=600000"
         FETCH="/root/afbc/*.txt /root/afbc/dump/*" ;;
  soak3) BQ=board-queue-soak.sh; CHUNKS="1 2 3 4 5 6 7 8"; CT=900; STALL=900; ENV="SOAK=60"; FETCH="" ;;
  *) echo "unknown job $J"; exit 1 ;;
esac
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
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
  $S/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "c9 Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  scp -q "${K[@]}" $S/ve-timeline.sh $S/$BQ root@10.56.0.107:/root/vp/ || blocked "scp of the board script failed"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
run_chunk() { # run_chunk <chunk>: remote board script under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt e="$ENV"; [ $J = afbc ] && e="$e CASES=$c"
  $SSH -n "cd /root; $e timeout $CT bash /root/vp/$BQ" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  for g in $FETCH; do mkdir -p $OUT/files; scp -q "${K[@]}" "root@10.56.0.107:$g" $OUT/files/ 2>/dev/null; done
  $SSH -n 'dmesg | grep -iE "timed out|iommu|fault|oops|bug:|alloc fail|cma" | tail -20' > $OUT/dmesg-$c.txt 2>&1
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
