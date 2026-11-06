#!/bin/bash
# Runner package for job 19-datasheet-w: dsw-job.sh (no arguments). See HANDOFF.md.
# One DEV chunk "cumul": installs the newest cumulative kernel (vdec fallback armed), adds the user overlays
# dsw-spdif-out / dsw-i2s3-ph / dsw-ahub-dam (host-built .dtbo in /boot/overlay-user), reboots, runs board-dsw.sh,
# reads the detached half-duplex result, copies everything off, then chunk "restore": removes the overlays and the
# trial kernel, reboots to the stock image kernel. Self-contained: board lock (fresh owner per acquire), stall
# watchdog, resumable (chunks in $OUT/state are skipped). Exit 0 = done; 2 = blocked ($OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/datasheet-w; SSH=$H/harness/ssh.sh; VP=$H/harness/research/vdec-perf
CK=$H/kernel-check/cumulative-kernels.txt; DW=$H/kernel-check/datasheet-w
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
OUT=$S/logs/runner; mkdir -p $OUT; touch $OUT/state; rm -f $OUT/BLOCKED
CT=900; STALL=300; STOCK=vmlinuz-7.3.1-edge-sunxi64; UOV="dsw-spdif-out dsw-i2s3-ph dsw-ahub-dam"
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-dsw-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
reboot_board() { $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 20; }
clean_env() { # remove our user overlays + dtbos (idempotent)
  $SSH -n "sed -i '/^user_overlays=dsw-/d' /boot/armbianEnv.txt; rm -f /boot/overlay-user/dsw-*.dtbo; sync; grep -c '^user_overlays=' /boot/armbianEnv.txt" 2>/dev/null; }
restore() { clean_env > /dev/null
  $SSH -n "ln -sfn $STOCK /boot/Image; rm -f /boot/vdec-trial; if [ -d /lib/modules/7.3.1.good ]; then rm -rf /lib/modules/7.3.1; mv /lib/modules/7.3.1.good /lib/modules/7.3.1; fi; sync"
  reboot_board
  if waitup; then log "restored: $($SSH -n 'uname -v; readlink /boot/Image; grep -c dsw- /boot/armbianEnv.txt' | tr '\n' ' ')"; echo restore >> $OUT/state
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = $STOCK ]; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
boot_cumul() {
  on_stock || blocked "board not on the stock image kernel at start ($($SSH -n 'readlink /boot/Image'))"
  T=$(tail -1 $CK | cut -d' ' -f1); sha=$(tail -1 $CK | cut -d' ' -f3)
  git -C $H/wt-cumulative merge-base --is-ancestor 4c8c3f819 $sha 2>/dev/null || blocked "newest cumulative kernel $T ($sha) predates the UM-review merges (spdif clk fix)"
  # W18: the ahub-dam overlay (821dfb5bd, c20) and the machine-driver fix that lets its controls-only card probe
  # (fix/sunxi-h616-ahub-dam-aux-card 61fb5e0e2; job 19's "no ahubdam card" was "probe ... failed with error -22")
  git -C $H/wt-cumulative merge-base --is-ancestor 61fb5e0e22dcf1aca221797fb69cf66e8d4530ea $sha 2>/dev/null || blocked "newest cumulative kernel $T ($sha) does not contain fix/sunxi-h616-ahub-dam-aux-card 61fb5e0e2 (ahubdam card, W18)"
  want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || blocked "no Image.$T in kernel-check/vdec-serve"
  for f in sun50i-h616-spdif-out sun50i-h616-i2s3-ph sun50i-h616-ahub-dam; do [ -s $DW/dtbo/$f.dtbo ] || blocked "missing $DW/dtbo/$f.dtbo"; done
  [ -x $DW/busybox-armhf ] || blocked "missing $DW/busybox-armhf"
  log "installing $T (Image md5 $want)"
  $VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  # user overlays: host-built dtbos under their own names, so nothing in /boot/dtb is touched
  $SSH -n "mkdir -p /boot/overlay-user /root/dsw; cp -n /boot/armbianEnv.txt /root/dsw/armbianEnv.orig" || blocked "ssh failed before the overlay copy"
  scp -q "${K[@]}" $DW/dtbo/sun50i-h616-spdif-out.dtbo root@10.56.0.107:/boot/overlay-user/dsw-spdif-out.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $DW/dtbo/sun50i-h616-i2s3-ph.dtbo root@10.56.0.107:/boot/overlay-user/dsw-i2s3-ph.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $DW/dtbo/sun50i-h616-ahub-dam.dtbo root@10.56.0.107:/boot/overlay-user/dsw-ahub-dam.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $DW/busybox-armhf $H/harness/di300test/di300test $S/runner/board-dsw.sh root@10.56.0.107:/root/dsw/ || blocked "scp of the test files failed"
  $SSH -n "chmod +x /root/dsw/busybox-armhf /root/dsw/di300test /root/dsw/board-dsw.sh; sed -i '/^user_overlays=dsw-/d' /boot/armbianEnv.txt; echo 'user_overlays=$UOV' >> /boot/armbianEnv.txt; sync; grep -E '^(user_)?overlays=' /boot/armbianEnv.txt" | tee -a $OUT/runner.log
  reboot_board
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log; }
run_checks() { local f=$OUT/checks.txt
  $SSH -n "timeout $CT bash /root/dsw/board-dsw.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 15
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: no output for $STALL s, killing ssh $p"; kill_pid $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  grep -q ROUND-DONE $f || { log "checks ended without ROUND-DONE"; return; }
  # detached half-duplex test: wait for HD-DONE (link bounces end0 for ~40 s)
  for i in $(seq 1 12); do sleep 10; $SSH -n 'grep -q HD-DONE /root/dsw/hd.txt 2>/dev/null' && break; done
  $SSH -n 'cat /root/dsw/hd.txt 2>/dev/null; cat /root/dsw/hd.err 2>/dev/null' > $OUT/hd.txt 2>&1
  awk '/^forced 100 half/{ s=($0 ~ /duplex Half/ && $0 !~ /ping-received 0\/5/) ? "PASS" : "FAIL"; print "CHECK W31-half-100 " s " " $0 }
       /^forced 10 half/{ s=($0 ~ /duplex Half/ && $0 !~ /ping-received 0\/5/) ? "PASS" : "FAIL"; print "CHECK W31-half-10 " s " " $0 }
       /^autoneg on/{ s=($0 ~ /Link detected: yes/ && $0 ~ /Auto-negotiation: on/) ? "PASS" : "FAIL"; print "CHECK W31-autoneg-restored " s " " $0 }' $OUT/hd.txt >> $f
  grep -q HD-DONE $OUT/hd.txt || echo "CHECK W31-half-duplex FAIL no HD-DONE in hd.txt (board link did not come back or ethtool missing): $(tr '\n' '|' < $OUT/hd.txt)" >> $f
  $SSH -n 'dmesg | grep -iE "iommu|fault|timed out|oops|bug:|warn|error" | grep -viE "ACPI|EFI" | tail -40' > $OUT/dmesg.txt 2>&1
  mkdir -p $OUT/board; scp -q "${K[@]}" 'root@10.56.0.107:/root/dsw/*.txt' $OUT/board/ 2>/dev/null
  echo cumul >> $OUT/state; log "chunk cumul done: $(grep -c 'CHECK .* PASS' $f) PASS, $(grep -c 'CHECK .* FAIL' $f) FAIL, $(grep -c 'CHECK .* SKIP' $f) SKIP"; }
log "job datasheet-w start, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire
if ! grep -qx cumul $OUT/state; then boot_cumul; log "checks start"; run_checks; fi
if ! grep -qx restore $OUT/state; then restore; fi
release
log "job datasheet-w end: $(tr '\n' ' ' < $OUT/state)"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
