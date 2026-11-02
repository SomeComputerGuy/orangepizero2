#!/bin/bash
# Usage: mem-probe.sh <stream> <parse> <dec> <fmt> : decode to fakesink, sample memory, list V4L2 buffer allocations.
f=$1; p=$2; d=$3; fmt=$4
m() { awk '/MemAvailable|CmaFree/{printf "%s %d MB  ", $1, $2/1024}' /proc/meminfo; }
echo "idle: $(m)"
GST_DEBUG=v4l2codecs-allocator:5,v4l2codecs-decoder:5 gst-launch-1.0 -q filesrc location=$f ! matroskademux ! $p ! $d ! video/x-raw,format=$fmt ! fakesink sync=false > /tmp/memprobe-gst.log 2>&1 & g=$!
minav=999999; mincma=999999; maxrss=0
while kill -0 $g 2>/dev/null; do
	a=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo); c=$(awk '/CmaFree/{print int($2/1024)}' /proc/meminfo)
	r=$(awk '/VmRSS/{print int($2/1024)}' /proc/$g/status 2>/dev/null); r=${r:-0}
	(( a < minav )) && minav=$a; (( c < mincma )) && mincma=$c; (( r > maxrss )) && maxrss=$r
	sleep 0.5
done
wait $g; echo "rc=$? min MemAvailable=${minav}MB min CmaFree=${mincma}MB max gst RSS=${maxrss}MB"
echo "after: $(m)"
grep -E "Try to create|Creating .* buffers|sizeimage|Created|REQBUFS|allocat" /tmp/memprobe-gst.log | sed 's/\x1b\[[0-9;]*m//g' | awk '{$1="";$2="";$3="";$4=""; print}' | sort | uniq -c | head -20
dmesg | grep -iE "oom|alloc.*fail|cedrus" | tail -3
