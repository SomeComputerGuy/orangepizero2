#!/bin/sh
# Board: 10-bit AVS2 self-consistency runs on one stream (streamed over HTTP).
# R1/R2 P010 twice (repeatability), R3 P010 as upper 8 bits, R4 NV12 + 2-bit linear path,
# R5 P010 with selected frames dumped for PNGs.  Usage: board-avs2-10bit.sh <name> <outdir> [dump list]
U=http://10.56.0.1:8643/avs2; s=$1; O=$2; D=${3:-0,1,2,100,200,291}; mkdir -p "$O"; B=/root/avs2/avs2dec
run() { tag=$1; shift; t0=$(date +%s); curl -sS "$U/$s.avs2" | env "$@" timeout 1800 $B -f - > "$O/$s.$tag.txt" 2> "$O/$s.$tag.err"; rc=$?; echo "$tag rc=$rc $(grep -c '^frame' "$O/$s.$tag.txt") frames $(( $(date +%s) - t0 ))s"; }
run p010-a X=1
run p010-b X=1
run p010-8 AVS2_OUT8=1
run nv12 AVS2_CAP=NV12
t0=$(date +%s); curl -sS "$U/$s.avs2" | AVS2_DUMP=$D timeout 1800 $B -f -o "$O/$s.dump.yuv" - > "$O/$s.dump.txt" 2>&1; echo "dump rc=$? $(( $(date +%s) - t0 ))s"
dmesg | grep -iE 'cedrus|iommu|fault|timed out' | tail -5
echo DONE
