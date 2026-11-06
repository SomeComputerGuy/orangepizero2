#!/bin/bash
# Runner package for job 60-tearing-wb3 (was 58-tearing-wb, 59-tearing-wb2): writeback proof that no scanned-out frame mixes two commits (DE33 display tearing).
# `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh` (job id t60; logs harness/research/display-tearing/logs/runner-t60/)
# Self-contained: board lock (fresh owner name), the newest cumulative kernel (must contain the latch-event fix $FIX) installed
# with the one-shot fallback armed (harness/research/vdec-perf/install-kernel.sh, Image+modules+DTB), HDMI-A-1 forced on at
# 1024x768@60 (no sink; mode missing = NOT TESTED), harness/kms-wb/out/kms-wb `tear N`: a different full-screen picture every
# frame and a writeback capture of every frame, each capture must be exactly its own commit's picture. Chunk `base`: no load,
# commit phases d0/d4/d12/random + 4 short bursts after 7 s idle (vblank IRQ re-enabled each time). Chunk `load`: the same
# under a 4K H.265 cedrus decode loop, a 4-thread memcpy load, both (3 runs), and a printk flood. Kernel counters (de33_latch_*,
# de33_wb_*, sun4i_tcon vblank_stale_cleared) before/after every run. Resumable: re-running skips the chunks in $OUT/state;
# the trial kernel is booted once and kept across chunks unless another session waits (then restore + hand-over). The stock
# image kernel is restored at the end. Stall watchdog: no chunk output for $STALL s kills the chunk.
# Exit 0 = chunks ran (judge with HANDOFF.md checks); 2 = BLOCKED ($OUT/BLOCKED); 3 = Oops/WARN ($OUT/OOPS); 1 = setup/lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/display-tearing; V=$H/harness/research/vdec-perf; SSH="timeout 120 $H/harness/ssh.sh"
J=t60
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR
   -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED $OUT/OOPS
CHUNKS="base load"; CT=900; STALL=150
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
FIX=3e0255e2f                              # fix/sunxi-h616-de33-latch-event HEAD (writeback captures only its own snapshot); the kernel must contain it
CLIENT=$H/harness/kms-wb/out/kms-wb       # built by harness/kms-wb/build.sh
P=/root/wb/kms-wb
R=/root/tearwb                            # board results dir
U63=http://10.56.0.1:8643; U64=http://10.56.0.1:8644   # kernel-check/vdec-serve (ffmpeg-avs2q), kernel-check/legacy-serve (4K stream)
MODE=1024x768@60
OOPS='Unable to handle|Oops|WARNING:|flip_done timed out|vblank wait timed out|workqueue lockup|iommu.*fault|Page fault'
SER=$H/harness/serial.log
OWN=""; TRIAL=0
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-tearwb-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { [ $TRIAL = 1 ] || return 0
  timeout 600 $V/restore-kernel.sh | tee -a $OUT/runner.log   # Image, DTB (.stock), modules (.good), reboot
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"; TRIAL=0
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"; }
ship_client() {
  local want_sha have_sha; want_sha=$(sha256sum < $CLIENT | cut -d' ' -f1)
  have_sha=$($SSH -n "sha256sum < $P 2>/dev/null | cut -d' ' -f1")
  [ "$want_sha" = "$have_sha" ] && { log "client on the board is current ($want_sha)"; return; }
  $SSH -n "mkdir -p $(dirname $P) $R"
  timeout 300 $V/ship.sh $CLIENT $P 2>&1 | tail -1 | tee -a $OUT/runner.log; $SSH -n "chmod +x $P"
  have_sha=$($SSH -n "sha256sum < $P | cut -d' ' -f1"); [ "$want_sha" = "$have_sha" ] || blocked "client ship failed"; log "client shipped ($want_sha)"; }
boot_trial() {
  local c; c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the latch-event fix $FIX"
  on_stock
  timeout 900 $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log; TRIAL=1
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  dtbwant=$(md5sum < $H/kernel-check/vdec-serve/sun50i-h616-orangepi-zero2.dtb.$T | cut -c1-32)
  dtbhave=$($SSH -n 'md5sum < /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb | cut -c1-32')
  [ "$dtbhave" = "$dtbwant" ] || blocked "$T DTB not installed: board md5 $dtbhave, want $dtbwant"
  $SSH -n 'test -f /sys/module/sun8i_mixer/parameters/de33_latch_deferred && test -f /sys/module/sun4i_tcon/parameters/vblank_stale_cleared' \
    || blocked "kernel $T has no de33_latch_deferred / vblank_stale_cleared parameters (fix $FIX not in the running kernel)"
  $SSH -n 'ls -d /sys/class/drm/card*-Writeback-1 >/dev/null 2>&1' || blocked "kernel $T has no Writeback-1 connector"
  log "kernel $T up (dtb $dtbhave), writeback present"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
runs_of() { case $1 in
  base) echo "selftest probe t-d0 t-d4 t-d12 t-rand burst1 burst2 burst3 burst4" ;;
  load) echo "ve-d4 ve-rand mem-d4 mem-rand vemem-rand vemem-rand2 vemem-rand3 kmsg-rand" ;; esac; }
chunk_script() { # board script of a chunk ($1); ends with ROUND-DONE
  cat <<EOS
set -u; D=$R/$1; rm -rf \$D; mkdir -p \$D/dump; cd \$D
uname -v > kernel.txt; cat /proc/cmdline > cmdline.txt; cat /proc/sys/kernel/printk > printk.txt
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
params() { for f in /sys/module/sun8i_mixer/parameters/de33_latch_* /sys/module/sun8i_mixer/parameters/de33_wb_* /sys/module/sun4i_tcon/parameters/vblank_stale_cleared /sys/module/sun4i_tcon/parameters/arm_line_*; do [ -f "\$f" ] && echo "\$(basename \$f)=\$(cat \$f)"; done; true; }
veirq() { grep -iE 'cedrus|1c0e000|video-codec' /proc/interrupts | awk '{s=0; for(i=2;i<=NF;i++) if (\$i ~ /^[0-9]+\$/) s+=\$i; else break; t+=s} END {print t+0}'; }
params > params-boot.txt
ls /sys/class/drm/ | grep -i 'card[0-9]-' | tr '\n' ' ' > connectors.txt; echo >> connectors.txt
for c in /sys/class/drm/card*-HDMI-A-1; do echo on > \$c/status; done; sleep 2
for c in /sys/class/drm/card*-HDMI-A-1; do echo "\$c status=\$(cat \$c/status) modes: \$(tr '\n' ' ' < \$c/modes)"; done | tee -a connectors.txt
grep -q 1024x768 connectors.txt || echo MODE-UNAVAILABLE | tee -a connectors.txt
run() { local name=\$1; shift
  mkdir -p \$D/dump/\$name
  params > \$name.params.before; veirq > \$name.ve.before
  timeout 120 $P -c HDMI-A-1 -m $MODE -o \$D/dump/\$name "\$@" > \$name.txt 2>&1; echo "RC \$?" >> \$name.txt
  params > \$name.params.after; veirq > \$name.ve.after
  cp \$D/dump/\$name/tear.csv \$name.csv 2>/dev/null
  echo "== \$name: $P \$*"; grep -E "^RESULT (probe|selftest (pass|fail)|tear|tear_full|event_order|flip_rate|seq_gap_max|commit_phase|mode)|^RC |error|Error|failed| (WRONG|MIXED|BAD|FULL_[A-Z]+) " \$name.txt | head -20; }
# VE load: decode into drm_prime frames (no 4K NV12 download to system RAM, which capped job 58 at ~9.5 VE IRQs/s), loop
# until ve_stop. The loop's stdout/stderr never reach the ssh session (job 58: a loop that survived ve_stop kept the chunk's
# ssh open -> STALL after ROUND-DONE). ve_stop kills the loop shell first, then ffmpeg, and waits until no ffmpeg is left.
ve_start() { [ -s /dev/shm/in.mkv ] || curl -sS --fail $U64/vdec/hevc-main-2160p60.mkv -o /dev/shm/in.mkv || { echo VE-DOWNLOAD-FAILED; return; }
  [ -x /root/tearwb/ffmpeg ] || { curl -sS --fail $U63/avs2/ffmpeg-avs2q -o /root/tearwb/ffmpeg && chmod +x /root/tearwb/ffmpeg; } || { echo VE-DOWNLOAD-FAILED; return; }
  ve_loop "-hwaccel_output_format drm_prime"
  [ \$VERATE -ge 20 ] || { echo "VE drm_prime rate \$VERATE/2s too low, retrying with system-memory frames"; ve_stop; ve_loop ""; }; }
ve_loop() { rm -f \$D/ve.stop
  ( while [ ! -f \$D/ve.stop ]; do timeout 100 /root/tearwb/ffmpeg -nostdin -hide_banner -nostats -loglevel error -hwaccel v4l2request \$1 -i /dev/shm/in.mkv -f null - 2>>\$D/ve.err; done ) </dev/null >/dev/null 2>&1 &
  VEPID=\$!; sleep 3; a=\$(veirq); sleep 2; b=\$(veirq); VERATE=\$((b - a)); echo "VE load started pid \$VEPID (\${1:-system-memory frames}), \$VERATE VE IRQs in 2 s"; }
ve_stop() { touch \$D/ve.stop; [ -n "\${VEPID:-}" ] && kill \$VEPID 2>/dev/null; pkill -f 'tearwb/ffmpeg' 2>/dev/null
  for i in \$(seq 1 20); do pgrep -f 'tearwb/ffmpeg' >/dev/null || break; sleep 0.5; done
  pkill -9 -f 'tearwb/ffmpeg' 2>/dev/null; [ -n "\${VEPID:-}" ] && wait \$VEPID 2>/dev/null; VEPID=
  pgrep -f 'tearwb/ffmpeg' >/dev/null && echo VE-STOP-FAILED || echo "VE load stopped"; true; }
mem_start() { $P memload \$1 4 32 </dev/null > \$D/memload.\$2.txt 2>&1 & MEMPID=\$!; sleep 1; }
case $1 in
base)
  timeout 30 $P selftest > selftest.txt 2>&1; echo "RC \$?" >> selftest.txt; grep -E '^RESULT selftest (pass|fail)|^RC' selftest.txt
  run probe probe
  run t-d0 tear 600
  run t-d4 -D 4000 tear 600
  run t-d12 -D 12000 tear 600
  run t-rand -D -1 tear 1200
  for b in 1 2 3 4; do sleep 7; run burst\$b -D 4000 tear 60; done ;;
load)
  ve_start
  run ve-d4 -D 4000 tear 600
  run ve-rand -D -1 tear 600
  ve_stop
  mem_start 14 mem-d4; run mem-d4 -D 4000 tear 600; wait \$MEMPID 2>/dev/null
  mem_start 14 mem-rand; run mem-rand -D -1 tear 600; wait \$MEMPID 2>/dev/null
  ve_start
  for v in vemem-rand vemem-rand2 vemem-rand3; do mem_start 14 \$v; run \$v -D -1 tear 600; wait \$MEMPID 2>/dev/null; done
  ve_stop
  # printk flood (IRQ latency): 50 lines/s at KERN_ERR; console loglevel in printk.txt
  ( for i in \$(seq 1 700); do echo "<3>tearing-wb printk load \$i" > /dev/kmsg; sleep 0.02; done ) </dev/null >/dev/null 2>&1 & KPID=\$!
  run kmsg-rand -D -1 tear 600; kill \$KPID 2>/dev/null; wait \$KPID 2>/dev/null
  ve_stop; rm -f /dev/shm/in.mkv ;;
esac
# nothing of this chunk may outlive it (an inherited stdout keeps the ssh session open)
pkill -f '$P memload' 2>/dev/null; pgrep -f 'tearwb/ffmpeg' >/dev/null && { echo LEFTOVER-VE; pkill -9 -f 'tearwb/ffmpeg'; }
for c in /sys/class/drm/card*-HDMI-A-1; do echo detect > \$c/status; done
dmesg | tail -n +\$((n1+1)) > dmesg-chunk.txt
grep -E 'sun4i|sun8i|sun50i|drm|iommu|$OOPS' dmesg-chunk.txt | grep -v 'tearing-wb printk load' | tail -40 | sed 's/^/DMESG: /'
ls dump/*/ 2>/dev/null | grep -c raw | sed 's/^/DUMPS: /'
echo ROUND-DONE
EOS
}
pdelta() { # pdelta <dir> <run> <param>: after - before
  local a b; a=$(grep "^$3=" $1/$2.params.after 2>/dev/null | cut -d= -f2); b=$(grep "^$3=" $1/$2.params.before 2>/dev/null | cut -d= -f2)
  [ -n "$a" ] && [ -n "$b" ] && echo $((a - b)); }
extract() { # host side: results.txt lines "<chunk> <run> <key> <value>"
  local c=$1 d=$OUT/files/$1 r k v
  if [ $c = base ]; then
    [ -f $d/selftest.txt ] && { echo "$c selftest result $(awk '/^RESULT selftest (pass|fail)/{print $3}' $d/selftest.txt)"; echo "$c selftest rc $(awk '/^RC /{print $2}' $d/selftest.txt)"; } >> $OUT/results.txt
  fi
  for r in $(runs_of $c); do
    [ $r = selftest ] && continue
    [ -f $d/$r.txt ] || { echo "$c $r missing 1" >> $OUT/results.txt; continue; }
    awk -v c=$c -v r=$r '
      /^RC / { print c, r, "rc", $2 }
      /^RESULT mode_unavailable / { print c, r, "mode_unavailable", $3 }
      /^RESULT probe / { print c, r, "probe", $3 }
      /^RESULT modeset_commit_error / { print c, r, "modeset_commit_errno", $3 }
      /^RESULT flip [0-9]+ commit_error / { print c, r, "flip_commit_errno", $5 }
      /^RESULT tear flips / { for (i = 3; i < NF; i += 2) print c, r, $i, $(i+1) }
      /^RESULT tear_full / { for (i = 3; i < NF; i += 2) print c, r, $i, $(i+1) }
      /^RESULT event_order unavailable/ { print c, r, "event_order_unavailable", 1 }
      /^RESULT event_order events_got / { print c, r, "events_got", $4; print c, r, "events_unheld", $6; print c, r, "events_unflushed", $8 }
      /^RESULT flip_rate / { print c, r, "flip_rate", $3; print c, r, "seq_gaps", $5 }
      /^RESULT seq_gap_max / { print c, r, "seq_gap_max", $3; print c, r, "first_gap_flip", $5 }
      /^RESULT commit_phase / { print c, r, "commit_phase_mean_ms", $4; print c, r, "commit_phase_max_ms", $6
                                for (i = 1; i <= NF; i++) if ($i == "outside_blanking") { print c, r, "commits_outside_blanking", $(i+1); print c, r, "commits_counted", $(i+3) } }
      /^RESULT (commit_ioctl|fence_wait|check|draw) / { print c, r, $2 "_mean_ms", $4; print c, r, $2 "_max_ms", $6 }
      / (WRONG|MIXED|BAD|FULL_WRONG|FULL_MIXED|FULL_BAD) tag_top / { n++ } END { print c, r, "anomaly_lines", n + 0 }' $d/$r.txt >> $OUT/results.txt
    for k in commits flushes flushes_late deferred forced events events_now coalesced; do v=$(pdelta $d $r de33_latch_$k); [ -n "$v" ] && echo "$c $r latch_${k}_delta $v" >> $OUT/results.txt; done
    for k in jobs done failed overflow timeout retries deferred lost busy_frames; do v=$(pdelta $d $r de33_wb_$k); [ -n "$v" ] && echo "$c $r wb_${k}_delta $v" >> $OUT/results.txt; done
    v=$(pdelta $d $r vblank_stale_cleared); [ -n "$v" ] && echo "$c $r vblank_stale_cleared_delta $v" >> $OUT/results.txt
    for k in line_min line_max line_active line_deadline; do v=$(grep "^de33_latch_$k=" $d/$r.params.after 2>/dev/null | cut -d= -f2); [ -n "$v" ] && echo "$c $r latch_${k}_after $v" >> $OUT/results.txt; done
    a=$(cat $d/$r.ve.after 2>/dev/null); b=$(cat $d/$r.ve.before 2>/dev/null); [ -n "$a" ] && [ -n "$b" ] && echo "$c $r ve_irqs_delta $((a - b))" >> $OUT/results.txt
    [ -f $d/memload.$r.txt ] && echo "$c $r memload_GBps $(awk '/^RESULT memload/{print $NF}' $d/memload.$r.txt)" >> $OUT/results.txt
  done
  grep -q MODE-UNAVAILABLE $d/connectors.txt 2>/dev/null && echo "$c all mode_unavailable 1" >> $OUT/results.txt
  grep -q VE-DOWNLOAD-FAILED $OUT/chunk-$c.txt 2>/dev/null && echo "$c all ve_download_failed 1" >> $OUT/results.txt
  k=$(grep -cE 'VE-STOP-FAILED|LEFTOVER-VE' $OUT/chunk-$c.txt 2>/dev/null); echo "$c all ve_leftover ${k:-0}" >> $OUT/results.txt
  k=$(grep -v 'tearing-wb printk load' $d/dmesg-chunk.txt 2>/dev/null | grep -cE "$OOPS"); echo "$c all dmesg_bad ${k:-0}" >> $OUT/results.txt
  k=$(grep -ciE 'iommu' $d/dmesg-chunk.txt 2>/dev/null); echo "$c all dmesg_iommu ${k:-0}" >> $OUT/results.txt; }
oops_fail() { log "OOPS during chunk $1 ($2): $(head -3 $OUT/OOPS | tr '\n' ' ')"; restore; release; log "job $J ABORTED (exit 3)"; exit 3; }
run_chunk() {
  local c=$1 f=$OUT/chunk-$1.txt oops=""
  chunk_script $c | $SSH "mkdir -p $R; cat > $R/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  local soff=$(stat -c %s $SER 2>/dev/null || echo 0)
  timeout $((CT + 60)) $H/harness/ssh.sh -n "timeout $CT bash $R/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 10
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ -f $SER ] && tail -c +$((soff+1)) $SER | grep -v 'tearing-wb printk load' | grep -qE "$OOPS"; then
      tail -c +$((soff+1)) $SER | grep -E "$OOPS|Call trace|pc :|lr :" | head -40 > $OUT/OOPS
      log "OOPS on the serial log during chunk $c, killing ssh $p"; kill $p; echo OOPS >> $f; oops=serial; break; fi
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c
  # text results only (no dump/*.raw captures, they are 3 MB each): every top-level file of the chunk dir
  timeout 300 $H/harness/ssh.sh -n "cd $R/$c && tar cf - --exclude=dump . " 2>/dev/null | tar xf - -C $OUT/files/$c 2>/dev/null || log "copy of $R/$c failed or timed out"
  $H/harness/ssh.sh -n "ls -la $R/$c/dump/*/ 2>/dev/null" > $OUT/files/$c/dump-list.txt 2>/dev/null
  if [ -z "$oops" ] && grep -v 'tearing-wb printk load' $OUT/files/$c/dmesg-chunk.txt 2>/dev/null | grep -qE "$OOPS"; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/files/$c/dmesg-chunk.txt | grep -v 'tearing-wb printk load' | head -40 > $OUT/OOPS; oops=dmesg; fi
  sed -i "/^$c /d" $OUT/results.txt 2>/dev/null; extract $c
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE (re-run the job to retry it)"; }
touch $OUT/results.txt
log "job $J start, kernel $T (Image md5 $want), fix $FIX, chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; on_stock; ship_client
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; on_stock; fi
  [ $TRIAL = 1 ] || boot_trial
  log "chunk $c start"; run_chunk $c
done
restore
release
log "job $J end: $(sort -u $OUT/state | wc -l) of $(echo $CHUNKS | wc -w) chunks done; results in $OUT/results.txt"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
