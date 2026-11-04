#!/bin/bash
# Board-side. Usage: ve-perjob.sh <command...> -> one line per VE job: busy ms (cedrus_device_run -> cedrus_irq), in decode order
T=/sys/kernel/tracing
[ "$(cat $T/current_tracer)" = nop ] || { echo BUSY-ftrace; exit 1; }
echo 0 > $T/tracing_on; echo > $T/trace; echo function > $T/current_tracer
echo 'cedrus_device_run cedrus_irq' > $T/set_ftrace_filter; echo 1 > $T/tracing_on
"$@" > /tmp/vpj.out 2>&1
echo 0 > $T/tracing_on
awk '/cedrus_device_run/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+:$/) st=$i+0} /cedrus_irq/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+:$/) t=$i+0; if(st){printf "%.3f\n",(t-st)*1000; st=0}}' $T/trace
echo nop > $T/current_tracer; echo > $T/set_ftrace_filter
