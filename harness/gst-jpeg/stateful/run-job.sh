#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner job 56-gst-jpeg-stateful (HANDOFF.md beside this file). Pattern of harness/gst-jpeg/recheck/run-job.sh:
# board lock, install the NEWEST CUMULATIVE kernel (must be c41+ = "media: cedrus: jpeg: drain on V4L2_DEC_CMD_STOP")
# with the vdec fallback armed, reboot, Image md5 check, ship build/gst-jpeg/bundle-stateful to /root/gstjpeg-stateful,
# run board-test.sh (11 gst runs, each under timeout 60; step capped at 600 s), copy the results to
# build/gst-jpeg/results-stateful/, restore the stock image kernel (restore-kernel.sh: Image, DTB, modules), reboot, release the lock, run check.sh on the host.
# Resumable: steps are recorded in results-stateful/state; a rerun continues (RESET=1 starts over). Pause: touch
# results-stateful/PAUSE; the script stops at the next step boundary, restores the stock kernel, releases the lock and
# exits 3; rm PAUSE and rerun to resume. Stall watchdog: no runner.log line for 900 s -> STALL, restore, exit 2.
# Exit 0 = ran (verdict in compare.txt); 2 = blocked (BLOCKED says why); 3 = paused.
set -u
H=/home/aruni/orangepizero2; P=$H/harness/gst-jpeg/stateful; B=$H/build/gst-jpeg/bundle-stateful
R=$H/build/gst-jpeg/results-stateful; SSH=$H/harness/ssh.sh; VP=$H/harness/research/vdec-perf; BD=/root/gstjpeg-stateful
[ -d "$B/plugins" ] && [ -x "$B/board-test.sh" ] && [ -f "$B/vec/h264-640x480.mkv" ] || { echo "bundle missing: $B (run $P/make-bundle.sh)"; exit 1; }
TL=$(tail -1 $H/kernel-check/cumulative-kernels.txt); T=$(cut -d' ' -f1 <<< "$TL")
[ "${T#c}" -ge 41 ] 2>/dev/null || { echo "newest cumulative kernel $T is older than c41 (no STOP drain fix)"; exit 1; }
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
[ "${RESET:-0}" = 1 ] && rm -rf "${R:?}"
mkdir -p "$R"; touch "$R/state"
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $R/runner.log; }
done_() { grep -qx "$1" "$R/state"; }
mark() { echo "$1" >> "$R/state"; log "step done: $1"; }
waitup() { for i in $(seq 1 60); do sleep 5; timeout 20 $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=gst-jpeg-stateful-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN 1800) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $R/runner.log; OWN=""; }
onstock() { [ "$(timeout 20 $SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ]; }
restore() { if onstock && ! timeout 20 $SSH -n 'test -d /lib/modules/7.3.1.good'; then log "board already on the stock kernel"; return 0; fi
  timeout 60 $VP/restore-kernel.sh 2>&1 | tee -a $R/runner.log
  sleep 15; if waitup; then log "restored: $(timeout 20 $SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $R/BLOCKED; fi; }
stopwd() { [ -n "${WD:-}" ] && kill $WD 2>/dev/null; WD=""; }
blocked() { log "BLOCKED: $*"; echo "$*" > $R/BLOCKED; stopwd; restore; release; exit 2; }
pausechk() { [ -f $R/PAUSE ] || return 0; log "PAUSE requested: restoring the stock kernel"; stopwd; restore; release; log "PAUSED (rm $R/PAUSE and rerun to resume)"; exit 3; }
serve() { curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ && return 0
  log "starting the HTTP server on 10.56.0.1:8643 (kernel-check/vdec-serve)"
  (cd $H/kernel-check/vdec-serve && nohup python3 -m http.server --bind 10.56.0.1 8643 > $R/http.log 2>&1 &)
  sleep 2; curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ || return 1; }

rm -f $R/BLOCKED
log "job 56 gst-jpeg-stateful start, kernel $T (Image md5 $want), state: $(tr '\n' ' ' < $R/state)"
serve || { echo "no HTTP server on 10.56.0.1:8643" > $R/BLOCKED; exit 2; }
trap 'stopwd; release' EXIT
trap 'log "STALL/TERM"; echo "stall watchdog or TERM" > $R/BLOCKED; stopwd; restore; release; exit 2' TERM
acquire
( while sleep 60; do a=$(( $(date +%s) - $(stat -c %Y $R/runner.log) )); [ $a -gt 900 ] && { echo "$(date '+%F %T') STALL ${a}s" >> $R/runner.log; pkill -TERM -P $$; kill -TERM $$; exit; }; done ) &
WD=$!
timeout 20 $SSH -n true || blocked "board does not answer ssh"
if ! done_ tested; then
	if [ "$(timeout 20 $SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] && ! onstock; then
		log "resume: board already runs $T"
	else
		onstock || blocked "board neither on the stock kernel nor on $T at start"
		timeout 300 $VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $R/runner.log
		timeout 30 $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
		waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $R/BLOCKED; stopwd; release; exit 2; }
		[ "$(timeout 20 $SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
		timeout 20 $SSH -n 'touch /run/vdec-ok'
		mark installed
	fi
	{ echo "cumulative $TL"; timeout 20 $SSH -n 'uname -v; uname -r'; } > $R/kernel.txt 2>&1
	log "kernel: $(tr '\n' ' ' < $R/kernel.txt)"
	pausechk
	timeout 60 $SSH "rm -rf $BD; mkdir -p $BD"
	tar -C "$B" -cf - . | timeout 120 $SSH "tar -C $BD -xf -"
	timeout 20 $SSH -n "test -x $BD/board-test.sh && test -f $BD/vec/h264-640x480.mkv" || blocked "bundle not unpacked on the board"
	log "board-test start"
	timeout -k 30 600 $SSH "sh $BD/board-test.sh $BD" > "$R/board-test.stdout" 2>&1
	echo "board-test rc=$?" >> "$R/board-test.stdout"
	log "board-test end: $(tail -1 $R/board-test.stdout)"
	rm -rf "$R/out"
	timeout 120 $SSH "tar -C $BD -cf - out" > "$R/out.tar"
	timeout 60 $SSH "rm -rf $BD"
	tar -C "$R" -xf "$R/out.tar" && rm -f "$R/out.tar"
	[ -f "$R/out/results.txt" ] || blocked "no results.txt came back"
	mark tested
fi
stopwd
restore
[ -f $R/BLOCKED ] && { release; exit 2; }
mark restored
release; trap - EXIT TERM
bash $P/check.sh "$R/out" "$B/vec" > "$R/compare.txt" 2>&1
cat "$R/compare.txt"
log "done: $R"
exit 0
