#!/bin/sh
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b8; rm -rf $O; mkdir -p $O; cd /root/opiz2-mesa
for m in sub own write sub; do timeout 600 python3 t_mt.py $m >> $O/mt.log 2>&1; echo "mt $m rc=$?"; done; cat $O/mt.log | cut -c1-300
echo BATCH8-DONE
