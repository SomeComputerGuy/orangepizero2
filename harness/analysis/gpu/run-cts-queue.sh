#!/bin/sh
# Board-side CTS queue (dEQP GLES mustpass lists, then Mesa's OpenCL-CTS profile, then the dEQP-VK subset).
# Every step resumes from its partial results, so the unit can be restarted after a reboot or kill.
# Start: systemd-run --unit=cts --collect -p MemoryMax=320M -p OOMScoreAdjust=1000 -p Restart=on-failure \
#   -p RestartSec=60 -p BindReadOnlyPaths=/root/cts/mesa-libclc/spirv64-mesa3d-.spv:/usr/lib/clc/spirv64-mesa3d-.spv \
#   sh /root/cts/run-cts-queue.sh
set -e
export LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless
D=/root/cts/deqp-gles; R=/root/cts/results; J=${JOBS:-2}
run() { python3 $D/deqp-run.py --deqp "$1" --caselist "$2" --out "$3" --jobs $J --timeout 180; sync; }
[ -f $R/gles2-main/results.csv ]  || run $D/gles2/deqp-gles2   $D/mustpass/gles2-main.txt  $R/gles2-main
[ -f $R/gles3-main/results.csv ]  || run $D/gles3/deqp-gles3   $D/mustpass/gles3-main.txt  $R/gles3-main
[ -f $R/gles31-main/results.csv ] || run $D/gles31/deqp-gles31 $D/mustpass/gles31-main.txt $R/gles31-main
for k in gles2-khr-main gles3-khr-main gles31-khr-main gles32-khr-main; do
  [ -f $R/$k/results.csv ] || run $D/glcts/glcts $D/mustpass/$k.txt $R/$k
done
if [ ! -f $R/opencl-mesa/done ]; then
  RUSTICL_ENABLE=panfrost python3 /root/cts/opencl-cts/clcts-run.py --cts /root/cts/opencl-cts/test_conformance \
    --profile /root/cts/opencl-cts/opencl_conformance_tests_mesa.csv --out $R/opencl-mesa --timeout 5000
  touch $R/opencl-mesa/done; sync
fi
V=/root/cts/deqp-vk
if [ -x $V/deqp-vk ] && [ ! -f $R/vk-subset/results.csv ]; then
  VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.json PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 \
    python3 $D/deqp-run.py --deqp $V/deqp-vk --caselist $V/mustpass/vk-subset.txt --out $R/vk-subset --jobs 1 --timeout 300
  sync
fi
echo ALL-DONE > $R/queue.done; sync
