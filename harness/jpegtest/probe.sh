#!/bin/sh
# SPDX-License-Identifier: MIT
# Board side, TRIAL kernel only: greyscale / 4:1:1 register probe.
#   probe.sh DIR       (DIR holds jpegtest and the probe vectors)
# Every run: capture pre-filled with 0x5a (-F), packed output (-o), whole
# capture buffer (-r), jpegtest log, and the kernel log of that run (the
# cedrus register dump: jpeg_dump=1). Results in DIR/out/<variant>/.
d=$1
t=$d/jpegtest
P=$(ls /sys/module/*/parameters/jpeg_probe 2>/dev/null | head -1)
D=$(dirname "$P")/jpeg_dump
[ -n "$P" ] || { echo "no jpeg_probe parameter: not the trial kernel"; exit 1; }
echo 1 > "$D"
dmesg -C
one() { # VARIANT NAME FMT
	o=$d/out/$1; mkdir -p "$o"
	echo "$1" > "$P"
	timeout 20 "$t" -f "$3" -F 0x5a -o "$o/$2.$3.yuv" -r "$o/$2.$3.raw" "$d/$2.jpg" > "$o/$2.$3.log" 2>&1
	echo "rc $?" >> "$o/$2.$3.log"
	dmesg -c > "$o/$2.$3.dmesg"
	echo "$1 $2 $3: $(tail -2 "$o/$2.$3.log" | tr '\n' ' ')"
}
# control: 4:2:0 must stay correct under every variant
for v in 0 0x1 0x2 0x40 0x4 0x8 0x10 0x20 0x80 0x100 0x200 0x400; do one $v c64 nv12; done
# greyscale
for v in 0 0x1 0x2 0x40 0x4 0x10 0x20 0x80 0x100 0x200 0x3 0x41 0x181 0x184; do
	one $v g64 nv12; one $v g64 tiled
done
for v in 0 0x10; do one $v g64s22 nv12; done
for v in 0 0x1 0x2 0x4; do one $v grey nv12; done
# 4:1:1: 0 = candidate fix (FORCE_420 off, vendor rule)
for v in 0 0x1 0x2 0x40 0x400 0x404; do
	one $v f64 nv12; one $v f64 tiled; one $v z17x33-411 nv12
done
for v in 0 0x400; do one $v s411 nv12; done
one 0 s411 tiled
# last: the old setting (FORCE_420 on) at 1080p, to place the IOMMU fault
one 0x4 s411 nv12
one 0 c64 nv12
echo 0 > "$P"; echo 0 > "$D"
echo done
