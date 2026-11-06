#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner package: fluster VP9 conformance vectors on cedrus, on the newest cumulative kernel.  run-job.sh [chunks]
# Self-contained (pattern of harness/research/vdec-perf/runner/vdec-job.sh): board lock with a fresh owner name per
# acquire, installs the newest cumulative kernel (kernel-check/cumulative-kernels.txt) with the vdec fallback armed,
# ships build/vp9-vectors/bundle.tar (make-bundle.sh) over HTTP, runs the pre-flight (one known-good vector must
# decode, else BLOCKED), then the chunks c1 c2 c3 c5 c4 (board-fluster.sh) under a timeout and a stall watchdog
# (the board script prints one timestamped line per vector), copies the results off after every chunk, restores the
# stock image kernel, releases. Resumable: chunks listed in $OUT/state are skipped; the pre-flight always runs after
# a boot. Between chunks the lock is handed over if another session waits.
# Exit 0 = all chunks ran (pass/fail: check-results.py, see HANDOFF.md); 2 = blocked ($OUT/BLOCKED); 1 = setup error.
# Other jobs on the same package (run-upsize.sh) set OUT (results dir) and JOB (check-results.py mode) and pass chunks.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/vp9-vectors; VP=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
CHUNKS=${*:-c1 c2 c3 c5 c4}; CT=1200; STALL=300; JOB=${JOB:-full}
GOOD=vp90-2-00-quantizer-00.webm  # the pre-flight vector (board-fluster.sh pre)
OUT=${OUT:-$S/logs/runner}; mkdir -p $OUT; touch $OUT/state; rm -f $OUT/BLOCKED
TL=$(tail -1 $H/kernel-check/cumulative-kernels.txt); T=$(cut -d' ' -f1 <<< "$TL")
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
[ -f $H/build/vp9-vectors/bundle.tar ] || { echo "bundle missing: run harness/vp9-vectors/make-bundle.sh"; exit 1; }
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-vp9-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
serve() { # the HTTP server ship.sh / install-kernel.sh download from
  curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ && return 0
  log "starting the HTTP server on 10.56.0.1:8643 (kernel-check/vdec-serve)"
  (cd $H/kernel-check/vdec-serve && nohup python3 -m http.server --bind 10.56.0.1 8643 > $OUT/http.log 2>&1 &)
  sleep 2; curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ || return 1; }
boot_trial() {
  [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"
  $VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  { echo "cumulative $TL"; $SSH -n 'uname -rv'; } > $OUT/kernel.txt
  $SSH -n 'rm -rf /root/vp9; mkdir -p /root/vp9'
  NOXZ=1 $VP/ship.sh $H/build/vp9-vectors/bundle.tar /root/vp9/bundle.tar 2>&1 | tail -1 | tee -a $OUT/runner.log
  log "unpacked: $($SSH -n 'cd /root/vp9 && tar xf bundle.tar && rm bundle.tar && ls resources && ls plugins' | tr '\n' ' ')"
  $SSH -n 'test -x /root/vp9/board-fluster.sh' || blocked "bundle not unpacked on the board"
  preflight; }
preflight() { # the known-good vector must decode through the exact same path as the chunks, else the run is pointless
  log "pre-flight: $GOOD"; run_chunk pre
  r=$(sed -n "s/^|$GOOD|\([^|]*\)|.*/\1/p" $OUT/out/pre.md 2>/dev/null | head -1)
  if [ "$r" != OK ]; then
    grep -h MISSING $OUT/out/env.txt 2>/dev/null | sed 's/^/  env: /' | tee -a $OUT/runner.log
    grep -hE 'WARN|ERROR|Filename|Version' $OUT/out/env.txt $OUT/out/pre.gst.txt 2>/dev/null | head -12 | sed 's/^/  gst: /' | tee -a $OUT/runner.log
    tail -3 $OUT/out/pre.log 2>/dev/null | sed 's/^/  fluster: /' | tee -a $OUT/runner.log
    blocked "pre-flight failed: known-good vector $GOOD result '${r:-none}' (want OK) on kernel $T with the dev v4l2codecs plugin; see logs/runner/out/{env.txt,pre.gst.txt,pre.log}: the decoder path is broken, no chunk was run"
  fi
  log "pre-flight OK: $GOOD decodes bit-exact ($(grep -c 'checksum=' $OUT/out/pre.gst.txt 2>/dev/null) checksum lines in pre.gst.txt)"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
run_chunk() { # remote board-fluster.sh under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt t0=$(date +%s)
  $SSH -n "timeout $CT sh /root/vp9/board-fluster.sh /root/vp9 $c" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill_pid $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/out; scp -q "${K[@]}" "root@10.56.0.107:/root/vp9/out/*" $OUT/out/ 2>/dev/null
  $SSH -n 'dmesg | grep -iE "cedrus|timed out|iommu|fault|oops|bug:|alloc fail" | tail -40' > $OUT/dmesg-$c.txt 2>&1
  local d=$(( $(date +%s) - t0 )) ran=$(grep -c '^[0-9:]* \[VP9' $f)
  if grep -q ROUND-DONE $f && [ -f $OUT/out/$c.md ]; then
    [ $c = pre ] || echo $c >> $OUT/state; log "chunk $c done in $d s ($ran vectors; $(grep -o 'Ran [0-9/]* tests' $f | tail -1))"
  else log "chunk $c ended without ROUND-DONE or without $c.md after $d s ($ran vectors seen; last: $(tail -1 $f))"; fi; }
log "job vp9-vectors start, kernel $T (Image md5 $want), chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
serve || { echo "no HTTP server on 10.56.0.1:8643" > $OUT/BLOCKED; exit 2; }
trap 'release' EXIT
acquire; boot_trial
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; boot_trial; fi
  log "chunk $c start"; run_chunk $c
done
restore; release
python3 -I $S/check-results.py $OUT $JOB > $OUT/check.txt 2>&1; log "check-results: $(tail -1 $OUT/check.txt)"
log "job end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
