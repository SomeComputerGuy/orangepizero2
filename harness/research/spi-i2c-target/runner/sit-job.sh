#!/bin/bash
# Runner package for job 31-spi-i2c-target (job 20 reworked): sit-job.sh (no arguments). See HANDOFF.md.
# Chunks: "wiring" (stock kernel: GPIO probe for the loopback jumpers), "spi" (installs the newest cumulative kernel
# with the vdec fallback armed and the matching DTB, boots it with the user overlays sit-spi1-target + sit-spi-gpio-pc,
# runs board-sit.sh checks-spi), "i2c" (reboots the trial kernel with sit-i2c3-slave + sit-i2c2-ph, runs checks-i2c),
# "restore" (removes the overlays, restores Image/DTB/modules, reboots to the stock image kernel). The two overlay sets
# boot separately because spi1-target (CS0) and i2c3 (SDA) both use PH5 = header pin 3 (job 20 FAIL root cause).
# Self-contained: board lock (fresh owner per acquire), stall watchdog, resumable (chunks in $OUT/state are skipped).
# Exit 0 = done; 2 = blocked ($OUT/BLOCKED, "not ready"); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/spi-i2c-target; SSH=$H/harness/ssh.sh; VP=$H/harness/research/vdec-perf
CK=$H/kernel-check/cumulative-kernels.txt; SD=$H/kernel-check/spi-i2c-target
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner; mkdir -p $OUT/board; touch $OUT/state; rm -f $OUT/BLOCKED
CT=600; STALL=300; STOCK=vmlinuz-7.3.1-edge-sunxi64; DTB=/boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb
UOV_spi="sit-spi1-target sit-spi-gpio-pc"; UOV_i2c="sit-i2c3-slave sit-i2c2-ph"
FIX_TITLE='h616 SPI and TWI target'          # 03961fad0, fix/sunxi-h616-spi-i2c-target (drivers + overlays)
FIX2=85e6dcb38                               # fix/sunxi-h616-spi1-target-spidev: spidev "slave" child in the spi1-target overlay
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-sit-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
reboot_board() { $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 20; }
clean_env() { $SSH -n "sed -i '/^user_overlays=sit-/d' /boot/armbianEnv.txt; rm -f /boot/overlay-user/sit-*.dtbo; sync; grep -c '^user_overlays=' /boot/armbianEnv.txt" 2>/dev/null; }
restore() { clean_env > /dev/null
  $VP/restore-kernel.sh | tee -a $OUT/runner.log       # Image -> stock, DTB -> .stock, modules .good back, reboot
  sleep 20
  if waitup; then log "restored: $($SSH -n "uname -v; readlink /boot/Image; readlink $DTB 2>/dev/null || echo dtb-file; grep -c sit- /boot/armbianEnv.txt" | tr '\n' ' ')"; echo restore >> $OUT/state
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
precheck() { # the newest cumulative kernel must contain both fix commits; the host-built overlays must exist
  T=$(tail -1 $CK | cut -d' ' -f1); sha=$(tail -1 $CK | cut -d' ' -f3)
  [ -n "$(git -C $H/wt-cumulative log --format=%H --grep="$FIX_TITLE" $sha 2>/dev/null)" ] || blocked "newest cumulative kernel $T ($sha) does not contain the fix commit '$FIX_TITLE' (fix/sunxi-h616-spi-i2c-target not merged yet)"
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX2 $sha 2>/dev/null || blocked "newest cumulative kernel $T ($sha) lacks $FIX2 (fix/sunxi-h616-spi1-target-spidev not merged yet)"
  want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || blocked "no Image.$T in kernel-check/vdec-serve"
  [ -s $H/kernel-check/vdec-serve/sun50i-h616-orangepi-zero2.dtb.$T ] || blocked "no sun50i-h616-orangepi-zero2.dtb.$T in kernel-check/vdec-serve"
  for f in spi1-target spi-gpio-pc i2c3-ph-slave-eeprom i2c2-ph; do [ -s $SD/dtbo/sun50i-h616-$f.dtbo ] || blocked "missing $SD/dtbo/sun50i-h616-$f.dtbo"; done
  # the host-built spi1-target overlay must be the one with the "slave" child (commit FIX2)
  $H/kernel-check/work-cumul/linux-7.3.1/scripts/dtc/dtc -q -I dtb -O dts $SD/dtbo/sun50i-h616-spi1-target.dtbo 2>/dev/null | grep -q 'armbian,spi-dev' || blocked "$SD/dtbo/sun50i-h616-spi1-target.dtbo lacks the armbian,spi-dev slave child: rebuild it from $FIX2 (dtc -@ -I dts -O dtb)"; }
install_trial() { # from the stock kernel: install Image + modules + DTB with the fallback armed (no reboot here)
  on_stock || blocked "board not on the stock image kernel ($($SSH -n 'readlink /boot/Image'))"
  log "installing $T (Image md5 $want)"
  $VP/install-kernel.sh $T 2>&1 | tail -4 | tee -a $OUT/runner.log
  $SSH -n "mkdir -p /boot/overlay-user /root/sit; cp -n /boot/armbianEnv.txt /root/sit/armbianEnv.orig" || blocked "ssh failed before the overlay copy"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-spi1-target.dtbo root@10.56.0.107:/boot/overlay-user/sit-spi1-target.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-spi-gpio-pc.dtbo root@10.56.0.107:/boot/overlay-user/sit-spi-gpio-pc.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-i2c3-ph-slave-eeprom.dtbo root@10.56.0.107:/boot/overlay-user/sit-i2c3-slave.dtbo || blocked "scp dtbo failed"
  scp -q "${K[@]}" $SD/dtbo/sun50i-h616-i2c2-ph.dtbo root@10.56.0.107:/boot/overlay-user/sit-i2c2-ph.dtbo || blocked "scp dtbo failed"
  ship_tests || blocked "scp of the test files failed"; }
boot_set() { # boot_set <spi|i2c>: trial kernel (installed first if the board is on the stock kernel) with that overlay set
  local set=$1 uov; uov=$(eval echo \$UOV_$set)
  on_stock && install_trial
  $SSH -n "sed -i '/^user_overlays=sit-/d' /boot/armbianEnv.txt; echo 'user_overlays=$uov' >> /boot/armbianEnv.txt; sync; grep -E '^(user_)?overlays=' /boot/armbianEnv.txt" | tee -a $OUT/runner.log
  reboot_board
  waitup || { log "trial kernel did not come up with set $set (the fallback reverts on the next boot)"; echo "trial boot failed ($set)" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  dtbwant=$(md5sum < $H/kernel-check/vdec-serve/sun50i-h616-orangepi-zero2.dtb.$T | cut -c1-32); dtbhave=$($SSH -n "md5sum < $DTB | cut -c1-32")
  [ "$dtbhave" = "$dtbwant" ] || blocked "$T DTB not installed: board md5 $dtbhave, want $dtbwant (install-kernel.sh DTB step)"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed "s/^/kernel ($set): /" | tee -a $OUT/runner.log
  $SSH -n 'dmesg | grep -i "Applying\|overlay" | head -4; ls /proc/device-tree/__symbols__ >/dev/null 2>&1 && echo "dt: symbols present"' | sed "s/^/boot ($set): /" | tee -a $OUT/runner.log; }
run_checks() { # run_checks <spi|i2c>: board-sit.sh checks-<set> <wired>, output appended to checks.txt, dmesg-<set>.txt
  local set=$1 f=$OUT/checks.txt w
  w=$(grep -oE "^WIRED_$(echo $set | tr a-z A-Z)=[01]" $OUT/wiring.txt | cut -d= -f2)
  $SSH -n "timeout $CT bash /root/sit/board-sit.sh checks-$set ${w:-0}" > $OUT/checks-$set.txt 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 15
    n=$(stat -c %s $OUT/checks-$set.txt); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $OUT/checks-$set.txt; break; fi
  done; wait $p 2>/dev/null
  cat $OUT/checks-$set.txt >> $f
  $SSH -n 'dmesg | grep -iE "spi|i2c|twi|pinctrl|fault|timed out|oops|bug:|warn|call trace" | grep -viE "ACPI|EFI|spi-nor|mtd" | tail -60' > $OUT/dmesg-$set.txt 2>&1
  scp -q "${K[@]}" 'root@10.56.0.107:/root/sit/*.txt' 'root@10.56.0.107:/root/sit/*.out' 'root@10.56.0.107:/root/sit/*.err' $OUT/board/ 2>/dev/null
  echo $set >> $OUT/state; log "chunk $set done: $(grep -c 'CHECK .* PASS' $OUT/checks-$set.txt) PASS, $(grep -c 'CHECK .* FAIL' $OUT/checks-$set.txt) FAIL, $(grep -c 'CHECK .* SKIP' $OUT/checks-$set.txt) SKIP"; }
log "job 31-spi-i2c-target start, done before: $(tr '\n' ' ' < $OUT/state)"
if ! grep -qx spi $OUT/state && ! grep -qx i2c $OUT/state; then : > $OUT/checks.txt; fi   # fresh run: start the combined file
trap 'release' EXIT
acquire
precheck
if ! grep -qx wiring $OUT/state; then wiring; fi
for set in spi i2c; do
  if ! grep -qx $set $OUT/state; then boot_set $set; log "checks $set start"; run_checks $set; fi
done
if ! grep -qx restore $OUT/state; then restore; fi
release
log "job 31-spi-i2c-target end: $(tr '\n' ' ' < $OUT/state)"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
