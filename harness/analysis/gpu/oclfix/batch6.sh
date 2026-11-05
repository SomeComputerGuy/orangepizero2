#!/bin/sh
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b6; rm -rf $O; mkdir -p $O; cd /root/opiz2-mesa
timeout 300 python3 t_lid.py > $O/lid.log 2>&1; echo "lid rc=$?"; cat $O/lid.log | cut -c1-400
BIFROST_MESA_DEBUG=shaders MESA_SHADER_CACHE_DISABLE=true timeout 300 python3 t_lid.py > $O/lid-shaders.log 2>&1
timeout 900 python3 t_reuse.py 1048576 > $O/reuse.log 2>&1; echo "reuse rc=$? $(tail -1 $O/reuse.log)"
D=/root/cts/deqp-gles; n0=$(dmesg | wc -l)
for c in mixedSequence multiplySequence; do ( cd $D/glcts && env LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless ./glcts --deqp-case=KHR-GLES31.core.blend_equation_advanced.test_coherency.$c --deqp-log-filename=$O/$c.qpa --deqp-surface-type=pbuffer --deqp-gl-config-name=rgba8888d24s8ms0 --deqp-surface-width=256 --deqp-surface-height=256 ) > $O/$c.log 2>&1; echo "$c $(grep -E '^  (Pass|Fail)' $O/$c.log)"; done
( cd $D/glcts && env LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless PAN_MESA_DEBUG=sync ./glcts --deqp-case=KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence --deqp-log-filename=$O/sync.qpa --deqp-surface-type=pbuffer --deqp-gl-config-name=rgba8888d24s8ms0 --deqp-surface-width=256 --deqp-surface-height=256 ) > $O/sync.log 2>&1
dmesg | tail -n +$((n0+1)) | tail -20 > $O/dmesg.txt; echo "dmesg: $(wc -l < $O/dmesg.txt) new lines"; head -5 $O/dmesg.txt
echo BATCH6-DONE
