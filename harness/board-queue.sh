#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Hands-off board queue: runs the long board work back to back with no agent in the loop.
# Start it only when no agent owns the board. Never power-cycles (if the board stops answering,
# the queue stops and leaves it for a human/agent). Log: harness/queue/<date>/queue.log
#   harness/board-queue.sh [first-step]
# Steps: reflash tve grey kaslr thermal gpu eth
# Resume hooks (all under harness/queue/):
#   STATE        one line: <step> <running|done|FAILED|STOPPED> <time> <detail>  (cat it to see where it is)
#   done/<step>  marker per finished step; a restart skips these automatically (rm one to redo it)
#   current      symlink to the newest run directory (queue.log + per-step outputs)
#   GO           the queue waits for this file before touching the board (the last owner creates it)
# Restart: kill the old queue by exact PID (harness/queue/PID), then rerun harness/board-queue.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
TOP=$PWD; H=$TOP/harness; SSH=$H/ssh.sh
IMG=$TOP/images/5cc24a7c8/Armbian-unofficial_26.11.0-trunk_Orangepizero2_stonking_edge_7.3.1_minimal.img.xz
Q=$H/queue; mkdir -p "$Q/done"
OUT=$Q/$(date +%Y%m%d-%H%M); mkdir -p "$OUT"; LOG=$OUT/queue.log; ln -sfn "$OUT" "$Q/current"; echo $$ > "$Q/PID"
log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }
state() { echo "$1 $2 $(date '+%F %T') ${3:-}" > "$Q/STATE"; }
trap 'state "${cur:-none}" STOPPED "signal/exit rc=$?"' EXIT
wait_ssh() { # $1 = timeout s; succeeds once ssh answers
  local t0=$(date +%s); until timeout 20 $SSH -n true 2>/dev/null; do
    (( $(date +%s) - t0 > $1 )) && return 1; sleep 15; done; }
reboot_wait() { $SSH -n 'systemctl reboot' 2>/dev/null; sleep 45; wait_ssh 600; }
alive_or_stop() { wait_ssh 600 || { log "BOARD UNREACHABLE after $1: queue stopped (no power-cycle)"; state "$1" FAILED unreachable; trap - EXIT; exit 1; }; }
STEPS=(reflash tve grey kaslr thermal gpu eth)
start=${1:-reflash}; run=0

step_reflash() {
  $H/reflash.sh --image "$IMG" > "$OUT/reflash.log" 2>&1; local rc=$?
  log "reflash rc=$rc; $(grep -cE '^PASS' "$OUT/reflash.log") PASS, $(grep -cE '^FAIL' "$OUT/reflash.log") FAIL"
  grep -E '^FAIL' "$OUT/reflash.log" | tee -a "$LOG"
  [ $rc -eq 0 ] || { log "reflash failed: queue stopped"; state $cur FAILED; trap - EXIT; exit 1; }
}
step_tve() { # expansion overlay (TVE + IR) on the real image: must boot, Composite disconnected, IR present
  $SSH -n 'cp /boot/armbianEnv.txt /root/armbianEnv.queue-bak; grep -q "^overlays=" /boot/armbianEnv.txt && sed -i "s/^overlays=.*/& orangepi-zero2-expansion/" /boot/armbianEnv.txt || echo overlays=orangepi-zero2-expansion >> /boot/armbianEnv.txt; sync'
  reboot_wait || { log "tve: board not back (boot loop?) - queue stopped; recover with harness/afbc-kms-play/tools/uboot-noovl.py"; exit 1; }
  sleep 90
  $SSH -n 'echo uptime=$(cut -d. -f1 /proc/uptime); for c in /sys/class/drm/card*-Composite-*; do echo $c $(cat $c/status); done; ls /sys/class/rc/ 2>&1; dmesg | grep -ciE "flip_done|vblank wait timed out" | sed "s/^/vblank-errors=/"; dmesg -l err,warn | tail -5' > "$OUT/tve.txt" 2>&1
  log "tve: $(tr '\n' ' ' < "$OUT/tve.txt" | cut -c1-300)"
  $SSH -n 'cp /root/armbianEnv.queue-bak /boot/armbianEnv.txt; sync'; reboot_wait; alive_or_stop tve-restore
}
step_grey() { # JPEG greyscale probe (trial kernel, 300 s fallback armed by install)
  export TAG=greytrial
  $H/jpegtest/jpeg-slot.sh install > "$OUT/grey.log" 2>&1
  sleep 60; wait_ssh 900 || { log "grey: no ssh after install - queue stopped"; exit 1; }
  for s in confirm stage greyprobe restore; do $H/jpegtest/jpeg-slot.sh $s >> "$OUT/grey.log" 2>&1; log "grey $s rc=$?"; done
  sleep 60; alive_or_stop grey-restore
  log "grey: kernel now $($SSH -n 'uname -rv')"
}
step_kaslr() { # kernel base must differ between boots
  for i in 1 2 3; do echo "boot$i $($SSH -n 'grep -m1 " _text$" /proc/kallsyms; cat /proc/cmdline | grep -o "nokaslr" || true')" >> "$OUT/kaslr.txt"; reboot_wait; done
  log "kaslr: $(awk '{print $2}' "$OUT/kaslr.txt" | sort -u | wc -l) distinct _text of 3"; alive_or_stop kaslr
}
step_thermal() { # 60 min all-core + DRAM stress, temps/freqs every 30 s
  $SSH -n 'systemd-run --unit=qthermal --collect stress-ng --cpu 4 --cpu-method matrixprod --vm 1 --vm-bytes 300M -t 60m' >/dev/null 2>&1
  for i in $(seq 1 120); do $SSH -n 'echo $(date +%T) $(cat /sys/class/thermal/thermal_zone*/temp | tr "\n" " ") f=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) thr=$(cat /sys/devices/system/cpu/cpu0/cpufreq/stats/total_trans 2>/dev/null)' >> "$OUT/thermal.txt" 2>&1; sleep 30; done
  $SSH -n 'systemctl stop qthermal 2>/dev/null; dmesg | grep -iE "thermal|throttl|critical" | tail -5' >> "$OUT/thermal.txt" 2>&1
  log "thermal: max zone temps $(awk '{for(i=2;i<=5;i++) if($i>m[i]) m[i]=$i} END{print m[2],m[3],m[4],m[5]}' "$OUT/thermal.txt")"
  alive_or_stop thermal
}
step_gpu() { # GPU conformance queue (4-6 h); wait until the cts unit stops, max 9 h
  if [ "$(timeout 30 $SSH -n 'systemctl is-active cts' 2>/dev/null)" = active ]; then log "gpu: cts already running - reattaching (no restage)"
  else $H/analysis/gpu/cts-restage.sh --start > "$OUT/gpu-restage.log" 2>&1; log "gpu restage rc=$?"; fi
  local t0=$(date +%s)
  while (( $(date +%s) - t0 < 9*3600 )); do sleep 600
    st=$(timeout 30 $SSH -n 'systemctl is-active cts' 2>/dev/null); [ "$st" = active ] || [ "$st" = activating ] || break; done
  log "gpu: cts unit now '${st:-unreachable}' after $(( ($(date +%s) - t0) / 60 )) min (results stay on the board in /root/cts)"
  alive_or_stop gpu
}
step_eth() { # last: 70 min soak at 1G, then 10 min each forced 100/10 full duplex (auto-revert on the board)
  $SSH -n 'pgrep -x iperf3 >/dev/null || iperf3 -s -D'
  head -c 64M /dev/urandom > "$OUT/blob"
  soak() { # $1 rounds, $2 label
    for i in $(seq 1 $1); do
      up=$(iperf3 -c 10.56.0.107 -t 15 -J 2>/dev/null | python3 -c 'import json,sys;print(round(json.load(sys.stdin)["end"]["sum_received"]["bits_per_second"]/1e6))' 2>/dev/null)
      dn=$(iperf3 -c 10.56.0.107 -t 15 -R -J 2>/dev/null | python3 -c 'import json,sys;print(round(json.load(sys.stdin)["end"]["sum_received"]["bits_per_second"]/1e6))' 2>/dev/null)
      pl=$(ping -c 50 -i 0.2 -s 8000 10.56.0.107 | grep -o '[0-9.]*% packet loss')
      sc=$( { /usr/bin/time -f %e timeout 120 scp -q -i $H/id_ed25519 -o UserKnownHostsFile=$H/known_hosts "$OUT/blob" root@10.56.0.107:/tmp/blob; } 2>&1 | tail -1)
      echo "$(date +%T) $2 host->board=${up}Mbit board->host=${dn}Mbit ping8000=$pl scp64M=${sc}s" >> "$OUT/eth.txt"
      [ $i -lt $1 ] && sleep 240
    done; }
  soak 15 1000
  for sp in 100 10; do
    $SSH -n "systemd-run --on-active=900 --unit=qethrevert --collect ethtool -s end0 autoneg on; ethtool -s end0 speed $sp duplex full autoneg off" 2>/dev/null
    sleep 20; wait_ssh 120 && soak 2 $sp && $SSH -n "ethtool end0 | grep -E 'Speed|Duplex' | tr '\n' ' '" >> "$OUT/eth.txt"
    $SSH -n 'ethtool -s end0 autoneg on; systemctl stop qethrevert.timer 2>/dev/null' 2>/dev/null; sleep 20; wait_ssh 960
  done
  $SSH -n 'rm -f /tmp/blob; ip -s link show end0 | sed -n 3,6p; dmesg | grep -iE "end0|stmmac|dwmac" | tail -5' >> "$OUT/eth.txt" 2>&1
  rm -f "$OUT/blob"; log "eth: $(wc -l < "$OUT/eth.txt") lines; losses: $(grep -o '[0-9.]*% packet loss' "$OUT/eth.txt" | sort | uniq -c | tr '\n' ' ')"
}

log "queue start at step '$start' -> $OUT; done so far: $(ls "$Q/done" | tr '\n' ' ')"
cur=gate; state gate waiting "for $Q/GO"
until [ -e "$Q/GO" ]; do sleep 60; done
for s in "${STEPS[@]}"; do
  [ "$s" = "$start" ] && run=1; [ $run = 1 ] || continue
  [ -e "$Q/done/$s" ] && { log "== $s already done ($(cat "$Q/done/$s")) - skipped"; continue; }
  cur=$s; state $s running "$OUT"; log "== $s"
  step_$s; date '+%F %T' > "$Q/done/$s"; state $s done; log "== $s done"
done
cur=all; state all done "$OUT"; trap - EXIT; log "QUEUE DONE"
