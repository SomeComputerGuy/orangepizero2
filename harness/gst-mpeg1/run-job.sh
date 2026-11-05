#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner job gst-mpeg1 (DEV): MPEG-1 through the dev v4l2slmpeg2dec (MG1S caps, patches 0015-0017 + D-picture probe 0201).
# Pattern of harness/gst-jpeg/recheck/run-job.sh + harness/mpeg1-mg1s/run-job.sh: takes the board lock (owner
# gst-mpeg1-<time>), ships build/gst-mpeg1/bundle (make-bundle.sh) to /root/gstmpeg1, runs board-test.sh on the STOCK
# image kernel (phase stock: the plugin must not offer mpegversion=1 without MG1S, decodebin falls back to software),
# installs the NEWEST CUMULATIVE KERNEL (kernel-check/cumulative-kernels.txt; it must contain the MG1S commit $FIX, else
# BLOCKED) with the vdec fallback armed, reboots, checks the Image md5, runs phase test, copies both out-* dirs to
# build/gst-mpeg1/results/, restores the stock kernel, releases the lock, then runs compare.sh (host ffmpeg + numpy) and
# check-results.sh. Exit 0 = ran (judge with check.txt); 2 = blocked (results/BLOCKED says why); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; P=$H/harness/gst-mpeg1; B=$H/build/gst-mpeg1/bundle; R=$H/build/gst-mpeg1/results
SSH=$H/harness/ssh.sh; VP=$H/harness/research/vdec-perf; BD=/root/gstmpeg1
FIX=8140b4eeb241ea13b872edbe93dadac618de2130   # armbian-build fix/sunxi-cedrus-mpeg1-mg1s (MG1S uAPI + cedrus)
[ -d "$B/plugins" ] && [ -f "$B/lib/libgstcodecs-1.0.so.0" ] && [ -x "$B/board-test.sh" ] && [ -f "$B/vec/tcela-18" ] || { echo "bundle missing: $B (run $P/make-bundle.sh)"; exit 1; }
rm -rf "${R:?}"; mkdir -p "$R"
TL=$(tail -1 $H/kernel-check/cumulative-kernels.txt); T=$(cut -d' ' -f1 <<< "$TL"); SHA=$(cut -d' ' -f3 <<< "$TL")
git -C $H/wt-cumulative merge-base --is-ancestor $FIX $SHA 2>/dev/null || {
  echo "newest cumulative kernel $T ($SHA) does not contain fix/sunxi-cedrus-mpeg1-mg1s $FIX" | tee $R/BLOCKED; exit 2; }
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $R/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=gst-mpeg1-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN 3600) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $R/runner.log; OWN=""; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image' 2>/dev/null)" = vmlinuz-7.3.1-edge-sunxi64 ]; }
restore() { on_stock && return 0
  $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $R/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $R/BLOCKED; restore; release; exit 2; }
serve() { # the HTTP server install-kernel.sh/ship.sh download from
  curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ && return 0
  log "starting the HTTP server on 10.56.0.1:8643 (kernel-check/vdec-serve)"
  (cd $H/kernel-check/vdec-serve && nohup python3 -m http.server --bind 10.56.0.1 8643 > $R/http.log 2>&1 &)
  sleep 2; curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ || return 1; }
phase() { # phase <stock|test>: board-test.sh under a cap, results back to $R/out-<phase>
  log "board-test $1 start"
  timeout -k 30 1200 $SSH "sh $BD/board-test.sh $BD $1" > "$R/board-test-$1.stdout" 2>&1
  echo "board-test rc=$?" >> "$R/board-test-$1.stdout"
  log "board-test $1 end: $(tail -1 $R/board-test-$1.stdout)"
  $SSH "tar -C $BD -cf - out-$1" > "$R/out-$1.tar" && tar -C "$R" -xf "$R/out-$1.tar"; rm -f "$R/out-$1.tar"
  [ -f "$R/out-$1/results.txt" ] || blocked "no out-$1/results.txt came back"; }

log "job gst-mpeg1 start, kernel $T ($SHA, Image md5 $want), bundle: $(head -1 $B/BUILD.txt)"
serve || { echo "no HTTP server on 10.56.0.1:8643" > $R/BLOCKED; exit 2; }
trap 'release' EXIT
acquire
$SSH -n true || blocked "board does not answer ssh"
on_stock || blocked "board not on the stock image kernel at start ($($SSH -n 'readlink /boot/Image'))"
echo "stock $($SSH -n 'uname -rv')" > $R/kernel-stock.txt
$SSH "rm -rf $BD; mkdir -p $BD"
tar -C "$B" -cf - . | $SSH "tar -C $BD -xf -"
$SSH -n "test -x $BD/board-test.sh && test -f $BD/vec/tcela-18 && test -f $BD/lib/libgstcodecs-1.0.so.0" || blocked "bundle not unpacked on the board"
phase stock
$VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $R/runner.log
$SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $R/BLOCKED; release; exit 2; }
[ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
$SSH -n 'touch /run/vdec-ok'
{ echo "cumulative $TL"; $SSH -n 'uname -rv'; } > $R/kernel.txt 2>&1
log "kernel: $(tr '\n' ' ' < $R/kernel.txt)"
phase test
$SSH "rm -rf $BD"
restore; release; trap - EXIT
bash $P/compare.sh "$R" > "$R/compare.log" 2>&1; cat "$R/compare.tsv"
bash $P/check-results.sh "$R" > "$R/check.txt" 2>&1; cat "$R/check.txt"
log "done: $R"
[ -f $R/BLOCKED ] && exit 2; exit 0
