#!/bin/sh
# Board: decode the 8-bit AVS2 reference streams, streamed over HTTP, one per-frame md5 list each.
# Usage (on the board): board-avs2-8bit.sh <outdir>
U=http://10.56.0.1:8643/avs2; O=${1:-/root/avs2/out8}; mkdir -p "$O"
for s in BasketballPass_416x240_50_ai BasketballPass_416x240_50_ld BasketballPass_416x240_50_ra \
	BQMall_832x480_60_ra BQSquare_416x240_60_ai BQSquare_416x240_60_ld BQSquare_416x240_60_ra \
	ParkScene_1920x1080_24_ra PartyScene_832x480_50_ra RaceHorses_416x240_30_ai \
	RaceHorses_416x240_30_ld RaceHorses_416x240_30_ra \
	main-1080p-ra main-1080p-ldp main-1080p-tid main-1080p-lf main-2160p-ra; do
	t0=$(date +%s.%N)
	curl -sS "$U/$s.avs2" | timeout 300 /root/avs2/avs2dec -f - > "$O/$s.txt" 2>&1
	rc=$?
	t1=$(date +%s.%N)
	echo "$s rc=$rc $(grep -c '^frame' "$O/$s.txt") frames $(echo "$t1 - $t0" | bc 2>/dev/null)s"
done
dmesg | grep -iE 'cedrus|iommu|timed out' | tail -5
