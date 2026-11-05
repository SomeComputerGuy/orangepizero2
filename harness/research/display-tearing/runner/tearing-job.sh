#!/bin/bash
# Runner package for the DE33 display-tearing check: tearing-job.sh latch
# Self-contained: board lock (fresh owner name), chunk "stock" on the stock image kernel (baseline: where the KMS commits
# land in the frame), chunk "fix" on the newest cumulative kernel (installed with the one-shot fallback armed through
# harness/research/vdec-perf/install-kernel.sh; it must contain the DE33 vblank-latch fix, else BLOCKED), each chunk a
# forced-on HDMI-A-1 at 1024x768@60 (no sink) with afbc-kms-play --pattern XR24 page flips: 600 frames back-to-back,
# then with the commit delayed 4 ms and 12 ms after the flip event (deep in the active video), reading the kernel's
# de33_latch_* counters before and after each run. Results are copied off after every chunk; the stock image kernel
# (vmlinuz-7.3.1-edge-sunxi64) is restored at the end and before every lock hand-over. Resumable: re-running skips the
# chunks listed in $OUT/state. Exit 0 = both chunks ran (judge with HANDOFF.md "Checks"); 2 = blocked ($OUT/BLOCKED);
# 3 = Oops/WARN on the serial log or in dmesg (lines in $OUT/OOPS); 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/display-tearing; V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
J=${1:?job: latch}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED $OUT/OOPS
case $J in
  latch) CHUNKS="stock fix"; CT=400; STALL=120 ;;
  *) echo "unknown job $J"; exit 1 ;;
esac
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
FIX=b04527be4                              # fix/sunxi-h616-de33-vblank-latch HEAD (armbian-build); the kernel must have it
CLIENT=$H/harness/afbc-kms-play/out/afbc-kms-play   # built by harness/afbc-kms-play/build.sh (has --commit-delay)
P=/root/afbc/afbc-kms-play
R=/root/tearing                           # board results dir
MODE=1024x768@60; FRAMES=600
OOPS='Unable to handle|Oops|WARNING:|flip_done timed out|vblank wait timed out|workqueue lockup'
SER=$H/harness/serial.log
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-tearing-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"; }
ship_client() { # the test client: ship it only when the board copy differs
  local want_sha have_sha; want_sha=$(sha256sum < $CLIENT | cut -d' ' -f1)
  have_sha=$($SSH -n "sha256sum < $P 2>/dev/null | cut -d' ' -f1")
  [ "$want_sha" = "$have_sha" ] && { log "client on the board is current ($want_sha)"; return; }
  $V/ship.sh $CLIENT $P 2>&1 | tail -1 | tee -a $OUT/runner.log; $SSH -n "chmod +x $P; mkdir -p $R"
  have_sha=$($SSH -n "sha256sum < $P | cut -d' ' -f1"); [ "$want_sha" = "$have_sha" ] || blocked "client ship failed"; }
boot_trial() { # install the newest cumulative kernel with the fallback armed; it must contain the fix
  local c; c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the DE33 vblank-latch fix $FIX"
  on_stock
  $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  $SSH -n 'test -d /sys/module/sun8i_mixer/parameters && ls /sys/module/sun8i_mixer/parameters/ | grep -q de33_latch_flushes' \
    || blocked "kernel $T has no /sys/module/sun8i_mixer/parameters/de33_latch_* (fix not in this kernel)"
  log "kernel fix: present (de33_latch_* parameters)"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
chunk_script() { # board script of a chunk ($1 = chunk name); ends with ROUND-DONE
  cat <<EOS
set -u; D=$R/$1; rm -rf \$D; mkdir -p \$D; cd \$D
uname -v > kernel.txt; cat /proc/cmdline > cmdline.txt
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
params() { for f in /sys/module/sun8i_mixer/parameters/de33_latch_*; do [ -f "\$f" ] && echo "\$(basename \$f)=\$(cat \$f)"; done; true; }
params > params-boot.txt
# force the HDMI connector on (no sink): DRM offers its built-in modes, 1024x768 among them
for c in /sys/class/drm/card*-HDMI-A-1; do echo on > \$c/status; done; sleep 2
for c in /sys/class/drm/card*-HDMI-A-1; do echo "\$c status=\$(cat \$c/status) modes: \$(tr '\n' ' ' < \$c/modes)"; done | tee connectors.txt
grep -q 1024x768 connectors.txt || echo MODE-UNAVAILABLE | tee -a connectors.txt
run() { local name=\$1 delay=\$2 extra=""; [ "\$delay" != 0 ] && extra="-D \$delay"
  params > \$name.params.before
  timeout 60 $P --pattern XR24 -c HDMI-A-1 -m $MODE -n $FRAMES -o \$name.csv \$extra > \$name.txt 2>&1; echo "RC \$?" >> \$name.txt
  params > \$name.params.after
  echo "== \$name (commit delay \$delay us)"; grep -E "^flips |flips/s|commit phase|sequence gaps|^RC |mode |error|Error|failed" \$name.txt | head -12; }
run d0 0
run d4 4000
run d12 12000
for c in /sys/class/drm/card*-HDMI-A-1; do echo detect > \$c/status; done
dmesg | tail -n +\$((n1+1)) > dmesg-chunk.txt
grep -E 'sun4i|sun8i|drm|$OOPS' dmesg-chunk.txt | tail -60 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
extract() { # host side: one line per run and key into $OUT/results.txt (chunk run key value)
  local c=$1 d=$OUT/files/$1 r k
  for r in d0 d4 d12; do
    [ -f $d/$r.txt ] || { echo "$c $r missing 1" >> $OUT/results.txt; continue; }
    awk -v c=$c -v r=$r '
      /^flips [0-9]+, / { split($0, a, /[ ,]+/); print c, r, "flips", a[2]; print c, r, "flips_per_s", a[3] }
      /^vblank sequence gaps >1:/ { print c, r, "seq_gaps", $5 }
      /^commit phase after previous vblank:/ { for (i = 1; i <= NF; i++) if ($i == "of") { print c, r, "commits_outside_blanking", $(i-1); print c, r, "commits_counted", $(i+1) } }
      /^RC / { print c, r, "rc", $2 }' $d/$r.txt >> $OUT/results.txt
    for k in flushes flushes_sync flushes_late coalesced commits words_max ns_max line_min line_max line_active; do
      a=$(grep "^de33_latch_$k=" $d/$r.params.after 2>/dev/null | cut -d= -f2); b=$(grep "^de33_latch_$k=" $d/$r.params.before 2>/dev/null | cut -d= -f2)
      [ -n "$a" ] || continue
      case $k in line_min|line_max|line_active|words_max|ns_max) echo "$c $r $k $a" >> $OUT/results.txt ;;
                 *) echo "$c $r ${k}_delta $((a - b))" >> $OUT/results.txt ;; esac
    done
  done
  grep -q MODE-UNAVAILABLE $d/connectors.txt 2>/dev/null && echo "$c all mode_unavailable 1" >> $OUT/results.txt
  echo "$c all dmesg_bad $(grep -cE "$OOPS" $d/dmesg-chunk.txt 2>/dev/null || echo 0)" >> $OUT/results.txt; }
oops_fail() { log "OOPS during chunk $1 ($2): $(head -3 $OUT/OOPS | tr '\n' ' ')"; restore; release; log "job $J ABORTED (exit 3)"; exit 3; }
run_chunk() { # run_chunk <chunk>: remote script under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt oops=""
  chunk_script $c | $SSH "mkdir -p $R; cat > $R/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  local soff=$(stat -c %s $SER 2>/dev/null || echo 0)
  $SSH -n "timeout $CT bash $R/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 10
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ -f $SER ] && tail -c +$((soff+1)) $SER | grep -qE "$OOPS"; then
      tail -c +$((soff+1)) $SER | grep -E "$OOPS|Call trace|pc :|lr :" | head -40 > $OUT/OOPS
      log "OOPS on the serial log during chunk $c, killing ssh $p"; kill $p; echo OOPS >> $f; oops=serial; break; fi
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c; scp -q -r "${K[@]}" root@10.56.0.107:$R/$c/. $OUT/files/$c/ 2>/dev/null
  if [ -z "$oops" ] && grep -qE "$OOPS" $OUT/files/$c/dmesg-chunk.txt 2>/dev/null; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/files/$c/dmesg-chunk.txt | head -40 > $OUT/OOPS; oops=dmesg; fi
  extract $c
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
: > $OUT/results.txt
log "job $J start, kernel $T (Image md5 $want), fix $FIX, chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; on_stock; ship_client
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; on_stock; fi
  case $c in
    stock) $SSH -n 'uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log ;;
    fix)   boot_trial ;;
  esac
  log "chunk $c start"; run_chunk $c
  [ $c = fix ] && restore
done
release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done; results in $OUT/results.txt"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
