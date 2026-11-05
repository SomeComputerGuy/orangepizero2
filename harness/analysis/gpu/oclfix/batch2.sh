#!/bin/sh
# Board batch 2 (fork build with reconvergence + SEG_ADD + subgroup-4 + bany fixes)
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b2; rm -rf $O; mkdir -p $O; T=/root/cts/opencl-cts/test_conformance; cd /root/opiz2-mesa
for t in ${TESTS-}; do timeout 600 python3 $t.py > $O/$t.log 2>&1; echo "$t rc=$?"; done
timeout 600 python3 t_img1db.py 16385 20000 32767 32768 40000 65535 > $O/img1db-big.log 2>&1; echo "img1db-big rc=$?"
r() { n=$1; shift; d=$1; shift; ( cd $T/$d && timeout ${TO:-1800} "$@" ) > $O/$n.log 2>&1; echo "$n rc=$? $(grep -E '^(PASSED|FAILED) [0-9]+ of' $O/$n.log | tail -1)"; }
r relationals relationals ./test_relationals
r intops integer_ops ./test_integer_ops integer_\* quick_\*
r subgroups subgroups ./test_subgroups
r atomics atomics ./test_atomics
r workgroups workgroups ./test_workgroups
V=/root/cts/deqp-vk; export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 PANVK_DEBUG=sync
VK_ICD_FILENAMES=$VK_DRIVER_FILES
( cd $V && timeout 900 ./deqp-vk --deqp-case='dEQP-VK.subgroups.basic.compute.*' --deqp-log-filename=$O/vk.qpa ) > $O/vk-subgroups.log 2>&1
echo "vk rc=$? $(grep -E '^  (Passed|Failed|Not supported|Crash)' $O/vk-subgroups.log | tr '\n' ' ')"
dmesg | grep -i -E "panfrost|INVALID_ENC" | tail -5 > $O/dmesg.txt
echo BATCH2-DONE
