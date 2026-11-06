#!/bin/bash
# Runner package for job 20-spi-i2c-target: sit-job.sh (no arguments). See HANDOFF.md.
# Chunks: "wiring" (stock kernel: GPIO probe for the loopback jumpers), "cumul" (installs the newest cumulative kernel
# with the vdec fallback armed, adds the user overlays sit-spi1-target / sit-spi-gpio-pc / sit-i2c3-slave / sit-i2c2-ph
# from host-built .dtbo files in /boot/overlay-user, reboots, runs board-sit.sh checks, copies everything off),
# "restore" (removes the overlays and the trial kernel, reboots to the stock image kernel). Self-contained: board
# lock (fresh owner per acquire), stall watchdog, resumable (chunks in $OUT/state are skipped).
# Exit 0 = done; 2 = blocked ($OUT/BLOCKED, "not ready"); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/spi-i2c-target; SSH=$H/harness/ssh.sh; VP=$H/harness/research/vdec-perf
CK=$H/kernel-check/cumulative-kernels.txt; SD=$H/kernel-check/spi-i2c-target
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner; mkdir -p $OUT; touch $OUT/state; rm -f $OUT/BLOCKED
CT=600; STALL=300; STOCK=vmlinuz-7.3.1-edge-sunxi64; UOV="sit-spi1-target sit-spi-gpio-pc sit-i2c3-slave sit-i2c2-ph"
FIX_TITLE='h616 SPI and TWI target'
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-sit-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
reboot_board() { $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 20; }
clean_env() { $SSH -n "sed -i '/^user_overlays=sit-/d' /boot/armbianEnv.txt; rm -f /boot/overlay-user/sit-*.dtbo; sync; grep -c '^user_overlays=' /boot/armbianEnv.txt" 2>/dev/null; }
restore() { clean_env > /dev/null
  $SSH -n "ln -sfn $STOCK /boot/Image; rm -f /boot/vdec-trial; if [ -d /lib/modules/7.3.1.good ]; then rm -rf /lib/modules/7.3.1; mv /lib/modules/7.3.1.good /lib/modules/7.3.1; fi; sync"
  reboot_board
  if waitup; then log "restored: $($SSH -n 'uname -v; readlink /boot/Image; grep -c sit- /boot/armbianEnv.txt' | tr '\n' ' ')"; echo restore >> $OUT/state
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = $STOCK ]; }
ship_tests() { $SSH -n "mkdir -p /root/sit" || return 1
  scp -q "${K[@]}" $S/runner/board-sit.sh $S/runner/spi_xfer.py $S/runner/i2c_loop.py $S/runner/i2c_funcs.py root@10.56.0.107:/root/sit/ && $SSH -n "chmod +x /root/sit/board-sit.sh"; }
wiring() { # on the stock kernel: are the loopback jumpers fitted? (needs gpiod on the board; "no" when unsure)
  on_stock || blocked "board not on the stock image kernel at start ($($SSH -n 'readlink /boot/Image'))"
  ship_tests || blocked "scp of the test files failed"
  $SSH -n "timeout 120 bash /root/sit/board-sit.sh wiring" > $OUT/wiring.txt 2>&1
  grep -q ROUND-DONE $OUT/wiring.txt || echo "WIRED_SPI=0
WIRED_I2C=0" >> $OUT/wiring.txt
  log "wiring: $(grep -E '^WIRED_' $OUT/wiring.txt | tr '\n' ' ')"; echo wiring >> $OUT/state; }
boot_cumul() {
  on_stock || blocked "board not on the stock image kernel ($($SSH -n 'readlink /boot/Image'))"
  T=$(tail -1 $CK | cut -d' ' -f1); sha=$(tail -1 $CK | cut -d' ' -f3)
  [ -n "$(git -C $H/wt-cumulative log --format=%H --grep="$FIX_TITLE" $sha 2>/dev/null)" ] || blocked "newest cumulative kernel $T ($sha) does not contain the fix commit '$FIX_TITLE' (fix/sunxi-h616-spi-i2c-target not merged yet)"
  want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || blocked "no Image.$T in kernel-check/vdec-serve"
  for f in spi1-target spi-gpio-pc i2c3-ph-slave-eeprom i2c2-ph; do [ -s $SD/dtbo/sun50i-h616-$f.dtbo ] || blocked "missing $SD/dtbo/sun50i-h616-$f.dtbo"; done
  log "installing $T (Image md5 $want)"
  $VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n "mkdir -p /boot/overlay-user /root/sit; cp -n /boot/armbianEnv.txt /root/sit/armbianEnv.orig" || blocked "ssh failed before the overlay copy"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-spi1-target.dtbo root@10.56.0.107:/boot/overlay-user/sit-spi1-target.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-spi-gpio-pc.dtbo root@10.56.0.107:/boot/overlay-user/sit-spi-gpio-pc.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-i2c3-ph-slave-eeprom.dtbo root@10.56.0.107:/boot/overlay-user/sit-i2c3-slave.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-i2c2-ph.dtbo root@10.56.0.107:/boot/overlay-user/sit-i2c2-ph.dtbo || blocked "scp dtbo failed"
  ship_tests || blocked "scp of the test files failed"
  $SSH -n "sed -i '/^user_overlays=sit-/d' /boot/armbianEnv.txt; echo 'user_overlays=$UOV' >> /boot/armbianEnv.txt; sync; grep -E '^(user_)?overlays=' /boot/armbianEnv.txt" | tee -a $OUT/runner.log
  reboot_board
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log; }
run_checks() { local f=$OUT/checks.txt ws wi
  ws=$(grep -oE '^WIRED_SPI=[01]' $OUT/wiring.txt | cut -d= -f2); wi=$(grep -oE '^WIRED_I2C=[01]' $OUT/wiring.txt | cut -d= -f2)
  $SSH -n "timeout $CT bash /root/sit/board-sit.sh checks ${ws:-0} ${wi:-0}" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 15
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  $SSH -n 'dmesg | grep -iE "spi|i2c|twi|fault|timed out|oops|bug:|warn|call trace" | grep -viE "ACPI|EFI|spi-nor|mtd" | tail -60' > $OUT/dmesg.txt 2>&1
  mkdir -p $OUT/board; scp -q "${K[@]}" 'root@10.56.0.107:/root/sit/*.txt' 'root@10.56.0.107:/root/sit/*.out' $OUT/board/ 2>/dev/null
  echo cumul >> $OUT/state; log "chunk cumul done: $(grep -c 'CHECK .* PASS' $f) PASS, $(grep -c 'CHECK .* FAIL' $f) FAIL, $(grep -c 'CHECK .* SKIP' $f) SKIP"; }
log "job 20-spi-i2c-target start, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire
if ! grep -qx wiring $OUT/state; then wiring; fi
if ! grep -qx cumul $OUT/state; then boot_cumul; log "checks start"; run_checks; fi
if ! grep -qx restore $OUT/state; then restore; fi
release
log "job 20-spi-i2c-target end: $(tr '\n' ' ' < $OUT/state)"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
