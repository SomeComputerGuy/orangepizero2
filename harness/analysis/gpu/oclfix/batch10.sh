#!/bin/sh
# dEQP-VK subgroups with fork (subgroup size 4 on G31) vs system panvk; 1.3 override as in impl-gpu-spec 4c
O=/root/oclfix/b10; rm -rf $O; mkdir -p $O; V=/root/cts/deqp-vk
export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 PANVK_DEBUG=sync MESA_VK_VERSION_OVERRIDE=1.3
n0=$(dmesg | wc -l)
v() { n=$1; icd=$2; shift 2; ( cd $V && VK_DRIVER_FILES=$icd VK_ICD_FILENAMES=$icd timeout 600 ./deqp-vk --deqp-case="$@" --deqp-log-filename=$O/$n.qpa ) > $O/$n.log 2>&1; echo "$n rc=$? $(grep -E '^  (Passed|Failed|Not supported|Warnings)' $O/$n.log | tr -s ' ' | tr '\n' ' ')"; }
v sys-elect /usr/share/vulkan/icd.d/panfrost_icd.json 'dEQP-VK.subgroups.basic.compute.subgroupelect'
v fork-elect /root/opiz2-mesa/cl/panfrost_icd.json 'dEQP-VK.subgroups.basic.compute.subgroupelect'
v fork-basic /root/opiz2-mesa/cl/panfrost_icd.json 'dEQP-VK.subgroups.basic.compute.*'
v fork-ballot /root/opiz2-mesa/cl/panfrost_icd.json 'dEQP-VK.subgroups.ballot_broadcast.compute.*'
v fork-sizectl /root/opiz2-mesa/cl/panfrost_icd.json 'dEQP-VK.subgroups.size_control.generic.compute.*'
dmesg | tail -n +$((n0+1)) | grep -c INSTR_INVALID_ENC > $O/invalid-enc-count.txt; echo "INSTR_INVALID_ENC lines: $(cat $O/invalid-enc-count.txt)"
D=/root/cts/deqp-gles; n1=$(dmesg | wc -l)
g() { n=$1; shift; t0=$(date +%s.%N); ( cd $D/glcts && env LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless "$@" ./glcts --deqp-case=KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence --deqp-log-filename=$O/$n.qpa --deqp-surface-type=pbuffer --deqp-gl-config-name=rgba8888d24s8ms0 --deqp-surface-width=256 --deqp-surface-height=256 ) > $O/$n.log 2>&1; t1=$(date +%s.%N); echo "$n $(grep -E '^  (Pass|Fail)' $O/$n.log) $(awk "BEGIN{print $t1-$t0}")s timeouts=$(dmesg | tail -n +$((n1+1)) | grep -c 'sched timeout')"; }
g gl-coherent X=1
g gl-noncoherent MESA_EXTENSION_OVERRIDE=-GL_KHR_blend_equation_advanced_coherent
echo BATCH10-DONE
