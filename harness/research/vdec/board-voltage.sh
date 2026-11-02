#!/bin/bash
# VE at 600 MHz with the shared vdd-gpu-sys rail raised by pinning GPU devfreq (504 MHz OPP = 890 mV, 600 MHz = 950 mV).
cd /root/vdec-streams; P=/sys/module/sunxi_cedrus/parameters; G=/sys/class/devfreq/1800000.gpu
echo 600000000 > $P/dbg_mod_rate; echo 0 > $P/dbg_ddr
for gf in 504000000 600000000; do
	echo $gf > $G/min_freq; sleep 1
	for r in 1 2 3; do
		out=$(gst-launch-1.0 -q filesrc location=hevc-main-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! video/x-raw,format=NV12 ! fdsink fd=1 2>/dev/null | python3 /root/framemd5.py 3840 2160 /tmp/mx.list 1)
		bad=$(paste -d' ' <(awk '{print $2}' /tmp/mx.list) <(grep -v '^#' hevc-main-2160p60.mkv.nv12.framemd5 | awk -F', *' '{print $6}') | awk '$1!=$2{printf "%d,", NR-1}')
		echo "gpu_min=$gf vdd-gpu-sys=$(cat /sys/class/regulator/regulator.6/microvolts) ve=$(cat /sys/kernel/debug/clk/ve/clk_rate) run=$r $out bad=[${bad:-none}]"
	done
done
echo 306000000 > $G/min_freq
echo VOLT-DONE
