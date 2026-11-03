#!/bin/sh
# SPDX-License-Identifier: MIT
# Board side: decode every case of gen.sh's cases.txt with jpegtest.
#   run.sh VECTORDIR [FMT]     (FMT: nv12 default, nv21, yu12, yv12)
# Writes VECTORDIR/out-FMT/NAME.yuv and VECTORDIR/out-FMT/results.txt
# ("NAME EXPECT rc"), then the throughput of s420 and z4096x2304 (100 runs).
d=$1
f=${2:-nv12}
t=$(dirname "$0")/jpegtest
o=$d/out-$f
mkdir -p "$o"
: > "$o/results.txt"
while read -r n w h r e; do
	timeout 20 "$t" -f "$f" -o "$o/$n.yuv" "$d/$n.jpg" > "$o/$n.log" 2>&1
	echo "$n $e $?" >> "$o/results.txt"
done < "$d/cases.txt"
for n in s420 s444 z4096x2304; do
	echo "== $n" >> "$o/perf.txt"
	"$t" -f "$f" -n 100 "$d/$n.jpg" >> "$o/perf.txt" 2>&1
done
cat "$o/results.txt" "$o/perf.txt"
dmesg | grep -i cedrus | tail -20 > "$o/dmesg.txt"
