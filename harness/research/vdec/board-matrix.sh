#!/bin/bash
# VE clock / DDR-mode matrix for the intermittent 4K H.265 mismatch (debug kernel with sunxi_cedrus.dbg_* params).
cd /root/vdec-streams; P=/sys/module/sunxi_cedrus/parameters
for cfg in "432000000 0" "600000000 128" "600000000 0"; do
	set -- $cfg; echo $1 > $P/dbg_mod_rate; echo $2 > $P/dbg_ddr
	for r in 1 2 3; do
		out=$(gst-launch-1.0 -q filesrc location=hevc-main-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! video/x-raw,format=NV12 ! fdsink fd=1 2>/dev/null | python3 /root/framemd5.py 3840 2160 /tmp/mx.list 1)
		bad=$(paste -d' ' <(awk '{print $2}' /tmp/mx.list) <(grep -v '^#' hevc-main-2160p60.mkv.nv12.framemd5 | awk -F', *' '{print $6}') | awk '$1!=$2{printf "%d,", NR-1}')
		echo "rate=$1 ddr=$2 run=$r clk=$(cat /sys/kernel/debug/clk/ve/clk_rate 2>/dev/null) $out bad=[${bad:-none}]"
	done
done
echo MATRIX-DONE
