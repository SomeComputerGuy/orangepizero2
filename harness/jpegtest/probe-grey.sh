#!/bin/sh
# SPDX-License-Identifier: MIT
# Board side, TRIAL kernel "greytrial" only: greyscale register probe.
#   probe-grey.sh DIR    (DIR holds jpegtest and the probe vectors)
# Each run sets the trial parameters of the cedrus JPEG probe patch
# (jpeg_grey, jpeg_trig_xor, jpeg_ctrl_xor, jpeg_mcu_se, jpeg_reg/_val),
# decodes one picture into a capture pre-filled with 0x5a and keeps the
# jpegtest log, packed + raw output and the kernel log (register dumps).
# Results in DIR/out/<n>/, the parameters of run n in DIR/out/variants.txt.
d=$1
t=$d/jpegtest
M=$(dirname "$(ls /sys/module/*/parameters/jpeg_trig_xor 2>/dev/null | head -1)")
[ -f "$M/jpeg_grey" ] || { echo "no jpeg_grey parameter: not the greytrial kernel"; exit 1; }
mkdir -p "$d/out"; : > "$d/out/variants.txt"
n=0
set_p() { # GREY TRIG CTRL MCUSE REG VAL
	echo "$1" > "$M/jpeg_grey"; echo "$2" > "$M/jpeg_trig_xor"; echo "$3" > "$M/jpeg_ctrl_xor"
	echo "$4" > "$M/jpeg_mcu_se"; echo "$5" > "$M/jpeg_reg"; echo "$6" > "$M/jpeg_reg_val"
}
one() { # NAME FMT GREY TRIG CTRL MCUSE REG VAL
	n=$((n + 1)); o=$d/out/$n; mkdir -p "$o"
	set_p "$3" "$4" "$5" "$6" "$7" "$8"
	echo "$n $1 $2 grey=$3 trig_xor=$4 ctrl_xor=$5 mcu_se=$6 reg=$7 val=$8" >> "$d/out/variants.txt"
	dmesg -C
	timeout 20 "$t" -f "$2" -F 0x5a -o "$o/$1.$2.yuv" -r "$o/$1.$2.raw" "$d/$1.jpg" > "$o/$1.$2.log" 2>&1
	echo "rc $?" >> "$o/$1.$2.log"
	dmesg -c > "$o/$1.$2.dmesg"
	echo "$n $1 $2 trig^$4 ctrl^$5 se$6 r$7=$8: $(tail -2 "$o/$1.$2.log" | tr '\n' ' ')"
}
g() { one g64 nv12 1 "$@"; }
echo 1 > "$M/jpeg_dump"
# controls: 4:2:0 (also shows the 0xE00 block in a working decode), grey baseline
one c64 nv12 0 0 0 0 -1 0
g 0 0 0 -1 0
one g64 tiled 1 0 0 0 -1 0
one g64s22 nv12 1 0 0 0 -1 0
one grey nv12 1 0 0 0 -1 0
# 1. chroma format codes 0-7 (bits 29:27), bits 30/31
for k in 0 1 2 3 4 6 7; do g $(( (5 ^ k) << 27 )) 0 0 -1 0; done
g 0x40000000 0 0 -1 0
g 0x80000000 0 0 -1 0
# 2. MCU_START/END: rows-1|cols-1, rows|cols, n-1, n
for s in 1 2 3 4; do g 0 0 $s -1 0; done
# 3. CTRL single-bit flips (bits 3-5 are the IRQ enables: left alone)
for b in 0 1 2 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
	g 0 $((1 << b)) 0 -1 0
done
# 4. TRIGGER bits 8-23 (the low byte is the command, 0x0e)
for b in 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do g $((1 << b)) 0 0 -1 0; done
# 5. MPEG registers the JPEG path does not program: 1 and the JPEG_SIZE value
for r in 0x00 0x04 0x08 0x0c 0x10 0x20 0x24 0x38 0x3c 0x40 0x44 0x48 0x4c 0x50 0x54 0x58 0x5c \
	 0x60 0x64 0x68 0x6c 0x70 0x74 0x78 0x7c 0x84 0x88 0x8c 0x90 0x94 0x98 0x9c \
	 0xa0 0xa4 0xa8 0xac 0xb0 0xb4 0xbc 0xc4 0xc8 0xd8 0xdc 0xe8 0xec 0xf0 0xf4 0xf8 0xfc; do
	g 0 0 0 $r 1
	g 0 0 0 $r 0x50007
done
# 6. TRIGGER bits 24-26 (decoder mode, 3 = JPEG): last, they may start another decoder
for m in 0 1 2 4 5 6 7; do g $(( (3 ^ m) << 24 )) 0 0 -1 0; done
one c64 nv12 0 0 0 0 -1 0
set_p 0 0 0 0 -1 0; echo 0 > "$M/jpeg_dump"
echo done
