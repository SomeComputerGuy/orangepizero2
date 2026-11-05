#!/bin/sh
O=/root/oclfix/b7; rm -rf $O; mkdir -p $O; cd /root/opiz2-mesa
( . /root/opiz2-mesa/cl/env.sh; timeout 600 python3 t_loop64.py > $O/loop64.log 2>&1; echo "loop64 rc=$?"; cat $O/loop64.log | cut -c1-200
  BIFROST_MESA_DEBUG=shaders MESA_SHADER_CACHE_DISABLE=true timeout 300 python3 t_loop64.py > $O/loop64-shaders.log 2>&1 )
D=/root/cts/deqp-gles; n0=$(dmesg | wc -l)
for c in mixedSequence multiplySequence; do ( cd $D/glcts && env LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless ./glcts --deqp-case=KHR-GLES31.core.blend_equation_advanced.test_coherency.$c --deqp-log-filename=$O/$c.qpa --deqp-surface-type=pbuffer --deqp-gl-config-name=rgba8888d24s8ms0 --deqp-surface-width=256 --deqp-surface-height=256 ) > $O/$c.log 2>&1; echo "$c rc=$? $(grep -E '^  (Pass|Fail)' $O/$c.log)"; done
dmesg | tail -n +$((n0+1)) | tail -20 > $O/dmesg.txt; echo "dmesg: $(wc -l < $O/dmesg.txt) new lines"; head -5 $O/dmesg.txt
echo BATCH7-DONE
