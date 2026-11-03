#!/bin/bash
# Usage: perf-run.sh <label> <command...>
# Runs the command under ve-busy-cmd.sh and reports: VE top DRAM counters (dbg kernel, per job sums),
# MBUS PMU deltas (CPU 0, VE 3, VE1 10, IOMMU 11, TOTAL 13), IOMMU PMU for masters 0..8.
P=/sys/module/sunxi_cedrus/parameters
r() { python3 -I /root/vp/devmem.py $1; }
w() { python3 -I /root/vp/devmem.py $1 $2; }
lbl=$1; shift
for k in dbg_rd dbg_wr dbg_mmc dbg_cache dbg_jobs; do echo 0 > $P/$k; done
echo Y > $P/dbg_cnt
w 0x047fa09c $(( $(r 0x047fa09c) | 1 ))
declare -A m0
for n in 0 3 10 11 13; do m0[$n]=$(r $((0x047fa0a0+4*n))); done
w 0x030f0200 0; w 0x030f0210 1; sleep 0.01; w 0x030f0210 0; w 0x030f0200 1
/root/vp/ve-busy-cmd.sh "$@" > /tmp/pr.busy
w 0x030f0200 0
mb=""; for n in 0 3 10 11 13; do v=$(r $((0x047fa0a0+4*n))); mb="$mb m$n=$(( (v - m0[$n]) & 0xffffffff ))"; done
io=""
for m in 0 1 2 3 4 5 6 7 8; do
  if [ $m -lt 7 ]; then b=$((0x030f0230+0x10*m)); else b=$((0x030f02d0+0x10*(m-7))); fi
  a=$(( $(r $b) + ($(r $((b+4))) << 32) )); h=$(( $(r $((b+8))) + ($(r $((b+12))) << 32) ))
  [ $a -gt 0 ] && io="$io i$m=$a/$h"
done
for m in 2 3; do b=$((0x030f0300+0x10*m)); io="$io lat$m=$(( $(r $b) + ($(r $((b+4))) << 32) ))/max$(( $(r $((b+8))) ))"; done
echo N > $P/dbg_cnt
j=$(cat $P/dbg_jobs); [ "$j" -gt 0 ] || j=1
echo "[$lbl] $(cat /tmp/pr.busy)"
echo "[$lbl] ve/job rd=$(( $(cat $P/dbg_rd)/j )) wr=$(( $(cat $P/dbg_wr)/j )) mmc=$(( $(cat $P/dbg_mmc)/j )) cache=$(( $(cat $P/dbg_cache)/j )) jobs=$j | mbus$mb | iommu$io"
