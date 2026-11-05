#!/bin/sh
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b9; rm -rf $O; mkdir -p $O; cd /root/opiz2-mesa
export MESA_SHADER_CACHE_DISABLE=true
PAN_BI_TRAILBAR=0 timeout 600 python3 t_loop64.py > $O/loop64-old.log 2>&1; echo "old rc=$?"; cut -c1-120 $O/loop64-old.log
timeout 600 python3 t_loop64.py > $O/loop64-new.log 2>&1; echo "new rc=$?"; cut -c1-120 $O/loop64-new.log
timeout 600 python3 t_vsh.py > $O/vsh.log 2>&1; echo "vsh rc=$?"; cut -c1-120 $O/vsh.log
timeout 600 python3 t_async.py > $O/async.log 2>&1; echo "async rc=$?"; cut -c1-100 $O/async.log
timeout 600 python3 t_tdim.py > $O/tdim.log 2>&1; echo "tdim rc=$?"; cut -c1-160 $O/tdim.log
timeout 900 python3 t_mt.py sub > $O/mt.log 2>&1; timeout 900 python3 t_mt.py own >> $O/mt.log 2>&1; timeout 900 python3 t_mt.py write >> $O/mt.log 2>&1; timeout 900 python3 t_mt.py cts >> $O/mt.log 2>&1; CL_TEST_X=1 timeout 900 python3 t_mt.py cts >> $O/mt.log 2>&1; echo "mt"; cut -c1-300 $O/mt.log
( unset OCL_ICD_FILENAMES LD_LIBRARY_PATH LIBGL_DRIVERS_PATH; export RUSTICL_ENABLE=panfrost; timeout 900 python3 t_mt.py cts; timeout 900 python3 t_loop64.py g64 midbar ) > $O/sys.log 2>&1; echo "system mesa:"; cut -c1-300 $O/sys.log
echo BATCH9-DONE
