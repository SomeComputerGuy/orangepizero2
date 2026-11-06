#!/bin/bash
# Runner package for the DE33 writeback connector check: wb-job.sh wb40 (job 40; "wb" = jobs 21/30, logs kept)
# Self-contained: board lock (fresh owner name), one chunk "wb" on the newest cumulative kernel (installed with the
# one-shot fallback armed through harness/research/vdec-perf/install-kernel.sh; it must contain the writeback commit,
# else BLOCKED), HDMI-A-1 forced on at 1024x768@60 (no sink), harness/kms-wb/out/kms-wb: probe, solid-colour and
# colour-bar captures compared pixel by pixel (XR24; NV12 and XR30 with a tolerance), then page-flip sequences with a
# capture per flip (commit right after the flip event, 4 ms and 12 ms later) looking for torn frames. Kernel counters
# de33_wb_* and de33_latch_* are read before and after. Results are copied off; the stock image kernel
# (vmlinuz-7.3.1-edge-sunxi64) is restored at the end and before every lock hand-over. Resumable: re-running skips the
# chunks listed in $OUT/state. Exit 0 = chunk ran (judge with HANDOFF.md "Checks"); 2 = blocked ($OUT/BLOCKED);
# 3 = Oops/WARN on the serial log or in dmesg (lines in $OUT/OOPS); 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/de33-writeback; V=$H/harness/research/vdec-perf; SSH="timeout 120 $H/harness/ssh.sh"   # every board command: ServerAlive (ssh.sh) + a 120 s step timeout
J=${1:?job: wb41 (flips rerun) or wb40 (wb = the job 21/30 run, kept for its logs)}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR
   -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED $OUT/OOPS
case $J in
  wb|wb40) CHUNKS="wb"; CT=500; STALL=120; RUNS="probe solid1 solid2 solid3 solid4 bars nv12 xr30 flips-d0 flips-d4 flips-d12" ;;
  wb41) CHUNKS="wb"; CT=400; STALL=120; RUNS="probe solid1 flips-d0 flips-d4 flips-d12" ;;   # job 41: flips rerun (client fix) + solid sanity
  *) echo "unknown job $J"; exit 1 ;;
esac
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
FIX=30706dcc8                              # fix/sunxi-h616-de33-wb-fb-formats HEAD (on top of 6dbed6c18); the kernel must have it
CLIENT=$H/harness/kms-wb/out/kms-wb       # built by harness/kms-wb/build.sh
P=/root/wb/kms-wb
R=/root/wbtest                            # board results dir
MODE=1024x768@60; FLIPS=300
OOPS='Unable to handle|Oops|WARNING:|flip_done timed out|vblank wait timed out|workqueue lockup|iommu.*fault|Page fault'
SER=$H/harness/serial.log
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-wb-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { timeout 600 $V/restore-kernel.sh | tee -a $OUT/runner.log   # Image, DTB (.stock), modules (.good), reboot
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image; readlink /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
evidence() { # evidence <tag> <dt-node regex> <unused> <module> <lsmod regex> <driver glob>: what a blocked kernel looks like, into files/blocked-$1/
  local d=$OUT/files/blocked-$1; mkdir -p $d
  $SSH -n 'dmesg' > $d/dmesg.txt 2>&1
  $SSH -n "uname -rv; echo Image=\$(readlink /boot/Image); echo dtb=\$(readlink /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb 2>/dev/null || echo file) md5=\$(md5sum < /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb | cut -c1-32)
    echo '--- DT nodes (path status compatible):'; find /proc/device-tree -maxdepth 4 -type d | grep -iE '$2' | while read n; do echo \$n \$(tr -d '\\0' < \$n/status 2>/dev/null || echo no-status) \$(tr -d '\\0' < \$n/compatible 2>/dev/null); done
    echo '--- devices_deferred:'; mount -t debugfs none /sys/kernel/debug 2>/dev/null; cat /sys/kernel/debug/devices_deferred 2>&1
    echo '--- modinfo:'; modinfo $4 2>&1 | head -12; echo '--- lsmod:'; lsmod | grep -iE '$5'; echo '--- platform drivers:'; ls -d /sys/bus/platform/drivers/*$6* 2>&1; ls /sys/bus/platform/drivers/*$6*/ 2>&1" > $d/state.txt 2>&1
  log "evidence in $d"; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"; }
ship_client() { # the test client: ship it only when the board copy differs
  local want_sha have_sha; want_sha=$(sha256sum < $CLIENT | cut -d' ' -f1)
  have_sha=$($SSH -n "sha256sum < $P 2>/dev/null | cut -d' ' -f1")
  [ "$want_sha" = "$have_sha" ] && { log "client on the board is current ($want_sha)"; return; }
  timeout 300 $V/ship.sh $CLIENT $P 2>&1 | tail -1 | tee -a $OUT/runner.log; $SSH -n "chmod +x $P; mkdir -p $R"
  have_sha=$($SSH -n "sha256sum < $P | cut -d' ' -f1"); [ "$want_sha" = "$have_sha" ] || blocked "client ship failed"; }
boot_trial() { # install the newest cumulative kernel with the fallback armed; it must contain the writeback commit
  local c; c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the DE33 writeback commit $FIX"
  on_stock
  timeout 900 $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  dtbwant=$(md5sum < $H/kernel-check/vdec-serve/sun50i-h616-orangepi-zero2.dtb.$T | cut -c1-32)
  dtbhave=$($SSH -n 'md5sum < /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb | cut -c1-32')
  [ "$dtbhave" = "$dtbwant" ] || { evidence dtb "display-engine|writeback|de33" "writeback@|display-engine" "sun8i-mixer" "sun8i|sun4i" "sun8i-mixer"; blocked "$T DTB not installed: board md5 $dtbhave, want $dtbwant (install-kernel.sh DTB step)"; }
  log "kernel dtb: $T ($dtbhave)"
  $SSH -n 'ls /sys/module/sun8i_mixer/parameters/ | grep -q de33_wb_jobs' \
    || { evidence params "display-engine|writeback|de33" "writeback@|display-engine" "sun8i-mixer" "sun8i|sun4i" "sun8i-mixer"; blocked "kernel $T has no /sys/module/sun8i_mixer/parameters/de33_wb_* (writeback code not in this kernel; see files/blocked-params/)"; }
  $SSH -n 'ls -d /sys/class/drm/card*-Writeback-1 >/dev/null 2>&1' \
    || { evidence connector "display-engine|writeback|de33" "writeback@|display-engine" "sun8i-mixer" "sun8i|sun4i" "sun8i-mixer"; $SSH -n 'ls /sys/class/drm/' > $OUT/files/blocked-connector/drm-classes.txt 2>&1; blocked "kernel $T has no Writeback-1 connector (DT node missing or sun50i_wb bind failed; see files/blocked-connector/)"; }
  log "kernel writeback: present ($($SSH -n 'ls -d /sys/class/drm/card*-Writeback-1' | tr '\n' ' '))"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
chunk_script() { # board script of a chunk ($1 = chunk name); ends with ROUND-DONE
  cat <<EOS
set -u; D=$R/$1; rm -rf \$D; mkdir -p \$D/dump; cd \$D
uname -v > kernel.txt; cat /proc/cmdline > cmdline.txt
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
params() { for f in /sys/module/sun8i_mixer/parameters/de33_wb_* /sys/module/sun8i_mixer/parameters/de33_latch_*; do [ -f "\$f" ] && echo "\$(basename \$f)=\$(cat \$f)"; done; true; }
params > params-boot.txt
ls /sys/class/drm/ | grep -i 'card[0-9]-' | tr '\n' ' ' > connectors.txt; echo >> connectors.txt
# force the HDMI connector on (no sink): DRM offers its built-in modes, 1024x768 among them
for c in /sys/class/drm/card*-HDMI-A-1; do echo on > \$c/status; done; sleep 2
for c in /sys/class/drm/card*-HDMI-A-1; do echo "\$c status=\$(cat \$c/status) modes: \$(tr '\n' ' ' < \$c/modes)"; done | tee -a connectors.txt
grep -q 1024x768 connectors.txt || echo MODE-UNAVAILABLE | tee -a connectors.txt
run() { local name=\$1; shift
  case " $RUNS " in *" \$name "*) ;; *) return 0 ;; esac   # only the runs of this job
  params > \$name.params.before
  timeout 90 $P -c HDMI-A-1 -m $MODE -o \$D/dump "\$@" > \$name.txt 2>&1; echo "RC \$?" >> \$name.txt
  params > \$name.params.after
  echo "== \$name: $P $*"; grep -E "^RESULT (probe|writeback_|wb_|mode|solid|bars|flips|flip_rate|commit_phase|first_torn|capture [0-9]+ (pixels|fence))|^RC |error|Error|failed" \$name.txt | head -40; }
run probe probe
run solid1 solid 3c7ab4
run solid2 solid c81e5a
run solid3 solid 000000
run solid4 solid ffffff
run bars bars
run nv12 -w NV12 -t 3 solid 3c7ab4
run xr30 -w XR30 -t 4 solid 3c7ab4
run flips-d0 flips $FLIPS
run flips-d4 -D 4000 flips $FLIPS
run flips-d12 -D 12000 flips $FLIPS
for c in /sys/class/drm/card*-HDMI-A-1; do echo detect > \$c/status; done
dmesg | tail -n +\$((n1+1)) > dmesg-chunk.txt
grep -E 'sun4i|sun8i|sun50i|drm|iommu|$OOPS' dmesg-chunk.txt | tail -60 | sed 's/^/DMESG: /'
ls -la dump | tail -n +2 | sed 's/^/DUMP: /'
echo ROUND-DONE
EOS
}
extract() { # host side: one line per run and key into $OUT/results.txt (chunk run key value)
  local c=$1 d=$OUT/files/$1 r k
  for r in $RUNS; do
    [ -f $d/$r.txt ] || { echo "$c $r missing 1" >> $OUT/results.txt; continue; }
    awk -v c=$c -v r=$r '
      /^RC / { print c, r, "rc", $2 }
      /^RESULT writeback_connectors / { print c, r, "writeback_connectors", $3 }
      /^RESULT wb_reaches_crtc / { print c, r, "wb_reaches_crtc", $3 }
      /^RESULT wb_format_offered / { print c, r, "wb_format_offered", $3 }
      /^RESULT wb_formats / { $1=""; $2=""; print c, r, "wb_formats", $0 }
      /^RESULT mode_unavailable / { print c, r, "mode_unavailable", $3 }
      /^RESULT probe / { print c, r, "probe", $3 }
      /^RESULT (solid|bars) / { print c, r, "captures", $(NF-2); print c, r, "captures_failed", $NF }
      /^RESULT capture [0-9]+ pixels / { for (i = 1; i <= NF; i++) { if ($i == "mismatches") m = $(i+1); if ($i == "max_dev") dv = $(i+1); if ($i == "fence_ms") fm = $(i+1) }
                                         print c, r, "capture" $3 "_mismatches", m; print c, r, "capture" $3 "_max_dev", dv; print c, r, "capture" $3 "_fence_ms", fm }
      /^RESULT capture [0-9]+ fence_error / { print c, r, "capture" $3 "_fence_error", $5 }
      /^RESULT capture [0-9]+ commit_error / { print c, r, "capture" $3 "_commit_errno", $5 }
      /^RESULT capture_buffer_error / { print c, r, "capture_buffer_errno", $3 }
      /^RESULT modeset_commit_error / { print c, r, "modeset_commit_errno", $3 }
      /^RESULT flip [0-9]+ commit_error / { print c, r, "flip_commit_errno", $5; print c, r, "flip_commit_error_at", $3 }
      /^RESULT flips / { print c, r, "flips_requested", $3; for (i = 4; i < NF; i += 2) print c, r, $i, $(i+1) }
      /^RESULT flip_rate / { print c, r, "flip_rate", $3; print c, r, "seq_gaps", $5 }
      /^RESULT commit_phase / { for (i = 1; i <= NF; i++) if ($i == "outside_blanking") { print c, r, "commits_outside_blanking", $(i+1); print c, r, "commits_counted", $(i+3) } }
      /^RESULT first_torn_flip / { print c, r, "first_torn_flip", $3 }' $d/$r.txt >> $OUT/results.txt
    for k in jobs done failed busy_frames; do
      a=$(grep "^de33_wb_$k=" $d/$r.params.after 2>/dev/null | cut -d= -f2); b=$(grep "^de33_wb_$k=" $d/$r.params.before 2>/dev/null | cut -d= -f2)
      [ -n "$a" ] && echo "$c $r wb_${k}_delta $((a - b))" >> $OUT/results.txt
    done
    for k in flushes_late; do
      a=$(grep "^de33_latch_$k=" $d/$r.params.after 2>/dev/null | cut -d= -f2); b=$(grep "^de33_latch_$k=" $d/$r.params.before 2>/dev/null | cut -d= -f2)
      [ -n "$a" ] && echo "$c $r latch_${k}_delta $((a - b))" >> $OUT/results.txt
    done
    a=$(grep "^de33_wb_status_last=" $d/$r.params.after 2>/dev/null | cut -d= -f2); [ -n "$a" ] && echo "$c $r wb_status_last $a" >> $OUT/results.txt
  done
  grep -q MODE-UNAVAILABLE $d/connectors.txt 2>/dev/null && echo "$c all mode_unavailable 1" >> $OUT/results.txt
  echo "$c all dmesg_bad $(grep -cE "$OOPS" $d/dmesg-chunk.txt 2>/dev/null || echo 0)" >> $OUT/results.txt
  echo "$c all dmesg_iommu $(grep -ciE 'iommu' $d/dmesg-chunk.txt 2>/dev/null || echo 0)" >> $OUT/results.txt; }
oops_fail() { log "OOPS during chunk $1 ($2): $(head -3 $OUT/OOPS | tr '\n' ' ')"; restore; release; log "job $J ABORTED (exit 3)"; exit 3; }
run_chunk() { # run_chunk <chunk>: remote script under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt oops=""
  chunk_script $c | $SSH "mkdir -p $R; cat > $R/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  local soff=$(stat -c %s $SER 2>/dev/null || echo 0)
  timeout $((CT + 60)) $H/harness/ssh.sh -n "timeout $CT bash $R/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 10
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ -f $SER ] && tail -c +$((soff+1)) $SER | grep -qE "$OOPS"; then
      tail -c +$((soff+1)) $SER | grep -E "$OOPS|Call trace|pc :|lr :" | head -40 > $OUT/OOPS
      log "OOPS on the serial log during chunk $c, killing ssh $p"; kill $p; echo OOPS >> $f; oops=serial; break; fi
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c; timeout 300 scp -q -r "${K[@]}" root@10.56.0.107:$R/$c/. $OUT/files/$c/ 2>/dev/null || log "scp of $R/$c failed or timed out" 
  if [ -z "$oops" ] && grep -qE "$OOPS" $OUT/files/$c/dmesg-chunk.txt 2>/dev/null; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/files/$c/dmesg-chunk.txt | head -40 > $OUT/OOPS; oops=dmesg; fi
  extract $c
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
: > $OUT/results.txt
log "job $J start, kernel $T (Image md5 $want), writeback commit $FIX, chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; on_stock; ship_client
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; on_stock; fi
  boot_trial
  log "chunk $c start"; run_chunk $c
  restore
done
release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done; results in $OUT/results.txt"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
