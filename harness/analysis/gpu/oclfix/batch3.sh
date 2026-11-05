#!/bin/sh
# mixedSequence diagnosis: system Mesa vs fork, plus env knobs. qpa kept.
O=/root/oclfix/b3; rm -rf $O; mkdir -p $O; D=/root/cts/deqp-gles
C='KHR-GLES31.core.blend_equation_advanced.test_coherency.*'
g() { n=$1; shift; ( cd $D/glcts && env LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless "$@" ./glcts --deqp-case="$C" --deqp-log-filename=$O/$n.qpa --deqp-surface-type=pbuffer --deqp-gl-config-name=rgba8888d24s8ms0 --deqp-surface-width=256 --deqp-surface-height=256 ) > $O/$n.log 2>&1
  echo "$n: $(grep -E 'Exceeds|Pass|Fail' $O/$n.log | tr '\n' ' ' | cut -c1-300)"; }
g sys
g sys_dirty PAN_MESA_DEBUG=dirty
g sys_sync PAN_MESA_DEBUG=sync
g sys_noafbc PAN_MESA_DEBUG=noafbc,nocrc
. /root/opiz2-mesa/cl/env.sh
g fork LD_LIBRARY_PATH=/root/opiz2-mesa/cl/lib:/root/cts/lib
echo BATCH3-DONE
