#!/bin/sh
# CTS spot checks on the fork build (barrier NOP + multi-context no-shadow)
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b11; rm -rf $O; mkdir -p $O; T=/root/cts/opencl-cts/test_conformance
r() { n=$1; shift; d=$1; shift; ( cd $T/$d && timeout ${TO:-1800} "$@" ) > $O/$n.log 2>&1; echo "$n rc=$? $(grep -E '^(PASSED|FAILED) [0-9]+ of' $O/$n.log | tail -1)"; }
r basic3 basic ./test_basic enqueue_map_image async_copy_local_to_global async_strided_copy_local_to_global
r half half ./test_half -w
r threaddim thread_dimensions ./test_thread_dimensions quick_1d_explicit_local quick_2d_explicit_local quick_3d_explicit_local quick_1d_implicit_local quick_2d_implicit_local quick_3d_implicit_local
r sl_int images/samplerlessReads ./test_samplerless_reads 1Dbuffer int
r sl_uint images/samplerlessReads ./test_samplerless_reads 1Dbuffer uint
r math5 math_brute_force ./test_bruteforce -w fabs sqrt negation reciprocal subtract
echo BATCH11-DONE
