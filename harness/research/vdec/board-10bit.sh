#!/bin/bash
# 10-bit bit-exactness with the shared rail raised (GPU devfreq min 504 MHz = 890 mV), memory sampled.
cd /root/vdec-streams; G=/sys/class/devfreq/1800000.gpu
echo 504000000 > $G/min_freq; sleep 1
echo "vdd-gpu-sys=$(cat /sys/class/regulator/regulator.6/microvolts) ve=$(cat /sys/kernel/debug/clk/ve/clk_rate)"
for c in "hevc-main10-2160p60.mkv h265parse v4l2slh265dec" "vp9-p2-2160p60.webm vp9parse v4l2slvp9dec" "vp9-p0-2160p60.webm vp9parse v4l2slvp9dec NV12" "h264-high-2160p30.mkv h264parse v4l2slh264dec NV12"; do
	set -- $c; f=$1
	if [[ $4 == NV12 ]]; then fmt=NV12; bpp=1; hf=nv12; chunk=; else fmt=P010_10LE; bpp=2; hf=p010le; chunk=40435200; fi
	( minav=999999; while sleep 1; do a=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo); ((a<minav)) && { minav=$a; echo $minav > /tmp/minav; }; done ) & s=$!
	out=$(gst-launch-1.0 -q filesrc location=$f ! matroskademux ! $2 ! $3 ! video/x-raw,format=$fmt ! fdsink fd=1 2>/dev/null | python3 /root/framemd5.py 3840 2160 /tmp/b10.list $bpp $chunk)
	kill $s
	bad=$(paste -d' ' <(awk '{print $2}' /tmp/b10.list) <(grep -v '^#' $f.$hf.framemd5 | awk -F', *' '{print $6}') | awk '$1!=$2{printf "%d,", NR-1}' | cut -c1-200)
	ref=$(cut -d= -f2 $f.$hf.md5)
	res=FAIL; [[ ${out##*md5=} == $ref ]] && res=PASS
	echo "$f $hf $out ref=$ref $res bad=[${bad:-none}] minMemAvailable=$(cat /tmp/minav)MB oom=$(dmesg | grep -c 'Out of memory')"
done
echo 306000000 > $G/min_freq
echo B10-DONE
