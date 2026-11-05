#!/bin/sh
O=/root/oclfix/b12; rm -rf $O; mkdir -p $O; D=/root/cts/deqp-gles; n1=$(dmesg | wc -l)
g() { n=$1; shift; ( cd $D/glcts && env LD_LIBRARY_PATH=/root/opiz2-mesa/cl/lib:/root/cts/lib __EGL_VENDOR_LIBRARY_FILENAMES=/root/opiz2-mesa/cl/50_mesa.json EGL_PLATFORM=surfaceless MESA_SHADER_CACHE_DISABLE=true "$@" ./glcts --deqp-case="KHR-GLES31.core.blend_equation_advanced.*" --deqp-log-filename=$O/$n.qpa --deqp-surface-type=pbuffer --deqp-gl-config-name=rgba8888d24s8ms0 --deqp-surface-width=256 --deqp-surface-height=256 ) > $O/$n.log 2>&1; echo "$n $(grep -E '^  (Passed|Failed|Not supported):' $O/$n.log | tr -s ' ' | tr '\n' ' ') mixed=$(grep -A1 'mixedSequence' $O/$n.log | grep -oE 'Pass|Fail' | head -1)"; }
g fork-nop X=1
g fork-nonop PAN_BI_V70_NOP=0
g fork-nop-again X=1
echo "timeouts=$(dmesg | tail -n +$((n1+1)) | grep -c 'sched timeout')"
echo BATCH12-DONE
