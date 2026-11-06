#!/bin/bash
# Runner package for the vdec board jobs: vdec-job.sh <t1f9|afbc|soak3|t1fix|avs2q>
# Self-contained: board lock (fresh owner name per acquire), install the newest cumulative kernel (all jobs; for t1fix it must contain fix/sunxi-avs2-poc-base fa73c3e5e) with the vdec fallback armed,
# run the job's board script in chunks of at most ~15 min under a stall watchdog, copy the results off after every chunk,
# restore the stock image kernel (vmlinuz-7.3.1-edge-sunxi64), release. Between chunks the lock is handed over (stock
# kernel restored first) if another session waits. Resumable: re-running the same command skips chunks listed in
# $OUT/state. Exit 0 = all chunks ran (pass/fail is judged from the results, see HANDOFF.md); 2 = blocked (reason in
# $OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; J=${1:?job: t1f9|afbc|soak3|t1fix|avs2q}
# install-kernel.sh always installs the NEWEST cumulative tag for any c<N> (AGENT-RULES "Builds"), so the md5 check
# must use that tag too (job 02 was blocked: it compared against the old c9 Image)
CK=$H/kernel-check/cumulative-kernels.txt; T=$(tail -1 $CK | cut -d' ' -f1); FIX=fa73c3e5e80f5af2c77158bfa8d783ef6218a163
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner-$J; mkdir -p $OUT; touch $OUT/state; rm -f $OUT/BLOCKED
case $J in
  t1f9)  BQ=board-queue-t1r.sh;  CHUNKS="1"; CT=900; STALL=600; ENV=""; FETCH="/root/avs2/out/*" ;;
  afbc)  BQ=board-queue-afbc.sh; CHUNKS="vp9p2 hevc10 avs2 hevc8 vp9p0"; CT=1000; STALL=1000; ENV="AFBC_BUDGET_MS=600000"
         FETCH="/root/afbc/*.txt /root/afbc/dump/*" ;;
  soak3) BQ=board-queue-soak.sh; CHUNKS="1 2 3 4 5 6 7 8"; CT=900; STALL=900; ENV="SOAK=60"; FETCH="" ;;
  t1fix) BQ=board-queue-t1fix.sh; CHUNKS="1"; CT=900; STALL=600; ENV=""; FETCH="/root/avs2/out/*"
         T=$(tail -1 $CK | cut -d' ' -f1); sha=$(tail -1 $CK | cut -d' ' -f3)
         git -C $H/wt-cumulative merge-base --is-ancestor $FIX $sha 2>/dev/null || {
           echo "newest cumulative kernel $T ($sha) does not contain fix/sunxi-avs2-poc-base $FIX" | tee $OUT/BLOCKED; exit 2; } ;;
  avs2q) BQ=board-queue-avs2q.sh; CHUNKS="1"; CT=1200; STALL=600; ENV=""; FETCH="/root/ffq/out/*"
         T=$(tail -1 $CK | cut -d' ' -f1) ;;   # newest cumulative kernel; FFmpeg 0313 AVS2 request queueing
  *) echo "unknown job $J"; exit 1 ;;
esac
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { $S/restore-kernel.sh 2>&1 | tail -1 | tee -a $OUT/runner.log   # Image, DTB (.stock) and modules (7.3.1.good), reboots
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
boot_trial() {
  [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"
  $S/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  scp -q "${K[@]}" $S/ve-timeline.sh $S/$BQ root@10.56.0.107:/root/vp/ || blocked "scp of the board script failed"; }
# afbc: afbc-gpu-check needs the Mesa fork (mesa-work/mesa, build-arm64, 27.0-devel) at /root/opiz2-mesa/main; the system
# Mesa 26.2.4 rejects every AFBC YUV dma-buf import (EGL 0x3009). Job 47 was blocked because nothing deployed it: the job
# now deploys it itself (rsync, side by side; system Mesa untouched) and checks the libgallium md5 on the board.
MW=$H/mesa-work; MLIB=libgallium-27.0.0-devel.so
if [ $J = afbc ]; then   # host-side precondition: the build exists and is current (no rebuild inside the job)
  [ -f $MW/build-arm64/src/gallium/targets/dri/$MLIB ] || { echo "missing build: mesa-work/build-arm64 $MLIB (run: . mesa-work/tools/env.sh; ninja -C mesa-work/build-arm64)"; exit 1; }
  mh=$(git -C $MW/mesa rev-parse --short=10 HEAD)
  strings $MW/build-arm64/src/gallium/targets/dri/$MLIB | grep -q "(git-$mh)" || { echo "mesa-work/build-arm64 is not built from mesa HEAD $mh (run: . mesa-work/tools/env.sh; ninja -C mesa-work/build-arm64)"; exit 1; }
  # job 51: the served checker must carry the AFBC probe (AFBC_FEATURES + EGL modifier lists)
  strings $H/kernel-check/vdec-serve/afbc/afbc-gpu-check | grep -q "gpu-afbc" || { echo "stale checker: kernel-check/vdec-serve/afbc/afbc-gpu-check has no probe (cross-build vdec-perf/afbc/afbc-gpu-check.c)"; exit 1; }
fi
deploy_main() { # afbc: fork build -> /root/opiz2-mesa/main, verified by md5
  $MW/tools/deploy.sh build-arm64 main 2>&1 | tail -1 | tee -a $OUT/runner.log
  local want=$(md5sum < $MW/deploy/main/lib/$MLIB | cut -c1-32)
  local have=$($SSH -n "md5sum < /root/opiz2-mesa/main/lib/$MLIB | cut -c1-32")
  [ -n "$want" ] && [ "$want" = "$have" ] && $SSH -n 'test -f /root/opiz2-mesa/main/env.sh' || blocked "main deploy mismatch (host $want board $have) or env.sh missing"
  log "deployed main ok (mesa $(git -C $MW/mesa rev-parse --short=11 HEAD), $MLIB md5 $have)"; }
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
acquire; boot_trial; [ $J = afbc ] && deploy_main
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; boot_trial; [ $J = afbc ] && deploy_main; fi
  log "chunk $c start"; run_chunk $c
done
restore; release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
