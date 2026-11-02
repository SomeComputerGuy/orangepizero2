#!/bin/bash
# Usage: ve-busy.sh <gst pipeline tail...>  -- measures VE busy time per frame (cedrus_device_run -> cedrus_irq)
T=/sys/kernel/tracing
echo 0 > $T/tracing_on; echo > $T/trace; echo function > $T/current_tracer
echo 'cedrus_device_run cedrus_irq' > $T/set_ftrace_filter
echo 1 > $T/tracing_on
s=$(date +%s.%N); gst-launch-1.0 -q "$@" > /dev/null 2>&1; rc=$?; e=$(date +%s.%N)
echo 0 > $T/tracing_on
awk -v wall=$(echo "$e - $s" | bc) -v rc=$rc '/cedrus_device_run/{split($0,a," ");for(i in a) if(a[i] ~ /^[0-9]+\.[0-9]+:$/){t=a[i]+0}; st=t} /cedrus_irq/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+:$/){t=$i+0}; if(st){busy+=t-st;n++;if(t-st>mx)mx=t-st;st=0}} END{printf "rc=%d frames=%d wall=%.2fs ve_busy=%.2fs avg=%.2fms max=%.2fms => hw-bound fps %.1f, pipeline fps %.1f\n",rc,n,wall,busy,busy/n*1000,mx*1000,n/busy,n/wall}' $T/trace
echo nop > $T/current_tracer; echo > $T/set_ftrace_filter
