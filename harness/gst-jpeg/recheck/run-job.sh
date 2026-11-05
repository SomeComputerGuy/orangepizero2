#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner job: recheck of the v4l2sljpegdec cases that failed in jobs 05 and 06, on the NEWEST CUMULATIVE KERNEL
# (kernel-check/cumulative-kernels.txt; it must enumerate frame sizes, c11+, and quiet the JPEG refusals, c14+).
# Pattern of harness/vp9-vectors/run-job.sh: takes the board lock (owner gst-jpeg-recheck-<time>), installs the
# cumulative kernel with the vdec fallback armed (harness/research/vdec-perf/install-kernel.sh), reboots, checks the
# Image md5, ships build/gst-jpeg/bundle-recheck (make-bundle.sh) to /root/gstjpeg-recheck, runs board-test.sh
# (every gst run under timeout 60; the last case, norank, is expected to hit it; ~4 min; capped at 900 s), copies
# the results to build/gst-jpeg/results-recheck/, restores the stock image kernel, reboots, releases the lock, then
# runs compare.py on the host (needs ffmpeg and python3-numpy).
# Exit 0 = ran (pass/fail per compare.txt and HANDOFF.md); 2 = blocked (results-recheck/BLOCKED says why).
set -u
H=/home/aruni/orangepizero2; P=$H/harness/gst-jpeg/recheck; B=$H/build/gst-jpeg/bundle-recheck
R=$H/build/gst-jpeg/results-recheck; SSH=$H/harness/ssh.sh; VP=$H/harness/research/vdec-perf
[ -d "$B/plugins" ] && [ -x "$B/board-test.sh" ] && [ -f "$B/vec/cases.txt" ] && [ -x "$B/jpegtest" ] || { echo "bundle missing: $B (run $P/make-bundle.sh)"; exit 1; }
TL=$(tail -1 $H/kernel-check/cumulative-kernels.txt); T=$(cut -d' ' -f1 <<< "$TL")
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
rm -rf "${R:?}"; mkdir -p "$R"
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $R/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=gst-jpeg-recheck-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN 2400) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $R/runner.log; OWN=""; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $R/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $R/BLOCKED; restore; release; exit 2; }
serve() { # the HTTP server install-kernel.sh/ship.sh download from
  curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ && return 0
  log "starting the HTTP server on 10.56.0.1:8643 (kernel-check/vdec-serve)"
  (cd $H/kernel-check/vdec-serve && nohup python3 -m http.server --bind 10.56.0.1 8643 > $R/http.log 2>&1 &)
  sleep 2; curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ || return 1; }

log "job gst-jpeg-recheck start, kernel $T (Image md5 $want)"
serve || { echo "no HTTP server on 10.56.0.1:8643" > $R/BLOCKED; exit 2; }
trap 'release' EXIT
acquire
$SSH -n true || blocked "board does not answer ssh"
[ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"
$VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $R/runner.log
$SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $R/BLOCKED; release; exit 2; }
[ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
$SSH -n 'touch /run/vdec-ok'
{ echo "cumulative $TL"; $SSH -n 'uname -v; uname -r'; } > $R/kernel.txt 2>&1
log "kernel: $(tr '\n' ' ' < $R/kernel.txt)"
$SSH 'rm -rf /root/gstjpeg-recheck; mkdir -p /root/gstjpeg-recheck'
tar -C "$B" -cf - . | $SSH 'tar -C /root/gstjpeg-recheck -xf -'
$SSH -n 'test -x /root/gstjpeg-recheck/board-test.sh && test -f /root/gstjpeg-recheck/vec/cases.txt' || blocked "bundle not unpacked on the board"
log "board-test start"
timeout -k 30 900 $SSH 'sh /root/gstjpeg-recheck/board-test.sh /root/gstjpeg-recheck' > "$R/board-test.stdout" 2>&1
echo "board-test rc=$?" >> "$R/board-test.stdout"
log "board-test end: $(tail -1 $R/board-test.stdout)"
$SSH 'tar -C /root/gstjpeg-recheck -cf - out' > "$R/out.tar"
$SSH 'rm -rf /root/gstjpeg-recheck'
tar -C "$R" -xf "$R/out.tar" && rm -f "$R/out.tar"
[ -f "$R/out/results.txt" ] || blocked "no results.txt came back"
restore; release; trap - EXIT
python3 -I $P/compare.py "$R/out" "$B/vec" > "$R/compare.txt" 2>&1
cat "$R/compare.txt"
log "done: $R"
[ -f $R/BLOCKED ] && exit 2; exit 0
