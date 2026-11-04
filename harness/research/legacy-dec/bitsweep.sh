#!/bin/bash
# per candidate: param=value -> vcon_ge_1 MB120 bwd f0 MV (MV2) and a1ge2 3-frame chroma/luma MBs vs vm_dec
SSH=/home/aruni/orangepizero2/harness/ssh.sh; C=/home/aruni/orangepizero2/harness/research/legacy-dec/cmp3.py
for kv in "$@"; do p=${kv%=*}; v=${kv#*=}
  r=$($SSH -n "echo $v > /sys/module/sunxi_cedrus/parameters/$p; echo 121 > /sys/module/sunxi_cedrus/parameters/mpeg4_stopmb; dmesg -C; timeout 60 /root/vp/ffmpeg-m1 -nostdin -loglevel quiet -hwaccel v4l2request -hwaccel_output_format drm_prime -f m4v -i http://10.56.0.1:8644/mpeg4asp/vcon_ge_1_asp_l4.bits -frames:v 2 -f null - ; dmesg | grep -m1 mp4dbg | awk '{print \$(NF-6)}'; echo 0 > /sys/module/sunxi_cedrus/parameters/mpeg4_stopmb")
  $SSH -n "timeout 120 /root/vp/ffmpeg-m1 -nostdin -loglevel quiet -hwaccel v4l2request -hwaccel_output_format drm_prime -f m4v -i http://10.56.0.1:8644/mpeg4asp/a1ge2_asp_L4.bits -frames:v 3 -vf hwdownload,format=nv12 -f rawvideo -" > /tmp/sweep.nv12
  $SSH -n "echo 0 > /sys/module/sunxi_cedrus/parameters/$p"
  echo "$kv MV2=$r a1ge2: $(python3 -I $C 1920 1088 /tmp/vm/a1ge2.yuv.yuv /tmp/sweep.nv12 3)"
done
