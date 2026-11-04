#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Host-side GPU rerun on a freshly flashed board: full CTS queue (incl. the fixed Vulkan subset),
# then the targeted extras: the 2 gles31 OOM cases alone with more memory, and mixedSequence x5.
# Results stay on the board (/root/cts/results, extras in /root/cts/results/extras) and are
# pulled to harness/analysis/gpu/cts-<tag>/ at the end. Never power-cycles.
set -uo pipefail
cd "$(dirname "$0")/../.."; H=$PWD; SSH=$H/ssh.sh; TAG=${1:-rerun}
OUT=$H/analysis/gpu/cts-$TAG; mkdir -p "$OUT"; LOG=$OUT/rerun.log
log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }
log "restage + start ($( $SSH -n 'uname -rv; . /etc/armbian-image-release 2>/dev/null; echo image=$IMAGE_TYPE' | tr '\n' ' '))"
$H/analysis/gpu/cts-restage.sh --start >> "$LOG" 2>&1 || { log "restage failed rc=$?"; exit 1; }
t0=$(date +%s)
while :; do sleep 600; st=$(timeout 30 $SSH -n 'systemctl is-active cts' 2>/dev/null)
  [ "$st" = active ] || [ "$st" = activating ] || break
  (( $(date +%s) - t0 > 12*3600 )) && { log "cts still running after 12 h - giving up waiting"; break; }; done
log "cts unit '${st:-unreachable}' after $(( ($(date +%s)-t0)/60 )) min; queue.done: $($SSH -n 'cat /root/cts/results/queue.done 2>/dev/null')"
$SSH 'cat > /root/cts/extras.sh' <<'BEOF'
#!/bin/sh
export LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless
D=/root/cts/deqp-gles; X=/root/cts/results/extras; mkdir -p $X
printf '%s\n' dEQP-GLES31.functional.draw_indirect.compute_interop.large.drawelements_separate_grid_1000x1000_drawcount_5000 \
  dEQP-GLES31.functional.draw_indirect.compute_interop.large.drawelements_combined_grid_1000x1000_drawcount_5000 > $X/oom.txt
python3 $D/deqp-run.py --deqp $D/gles31/deqp-gles31 --caselist $X/oom.txt --out $X/oom --jobs 1 --timeout 600
echo KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence > $X/mixed.txt
for i in 1 2 3 4 5; do python3 $D/deqp-run.py --deqp $D/glcts/glcts --caselist $X/mixed.txt --out $X/mixed-$i --jobs 1 --timeout 180; done
echo EXTRAS-DONE > $X/done; sync
BEOF
log "extras: OOM cases alone (MemoryMax=800M), mixedSequence x5"
$SSH -n 'systemd-run --unit=cts-extras --collect -p MemoryMax=800M -p MemorySwapMax=64M -p OOMPolicy=continue sh /root/cts/extras.sh' >> "$LOG" 2>&1
while sleep 120; st=$(timeout 30 $SSH -n 'systemctl is-active cts-extras' 2>/dev/null); [ "$st" = active ] || [ "$st" = activating ]; do :; done
$SSH -n 'cd /root/cts/results && tar cJf - --exclude="*.qpa" .' > "$OUT/results.tar.xz" 2>>"$LOG"
log "pulled $(du -h "$OUT/results.tar.xz" | cut -f1); summaries:"
$SSH -n 'cd /root/cts/results; for d in */ extras/*/; do [ -f $d/results.csv ] && echo "$d $(cut -d, -f2 $d/results.csv | sort | uniq -c | tr -s " " | tr "\n" " ")"; done' | tee -a "$LOG"
log DONE
