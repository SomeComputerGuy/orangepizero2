#!/bin/sh
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b4; rm -rf $O; mkdir -p $O; cd /root/opiz2-mesa
BIFROST_MESA_DEBUG=shaderdb MESA_SHADER_CACHE_DISABLE=true timeout 300 python3 t_wgsz.py > $O/wgsz.log 2>&1; echo "wgsz rc=$?"
timeout 1200 python3 t_reuse.py 2097152 > $O/reuse.log 2>&1; echo "reuse rc=$? $(tail -1 $O/reuse.log)"
timeout 1200 python3 t_tdim2.py > $O/tdim2.log 2>&1; echo "tdim2 rc=$?"
BIFROST_MESA_DEBUG=shaders MESA_SHADER_CACHE_DISABLE=true timeout 600 python3 t_vsh.py > $O/vsh-shaders.log 2>&1; echo "vshdump rc=$?"
echo BATCH4-DONE
