#!/bin/sh
# Board batch 1 for the OpenCL fixes (runs under /root/opiz2-mesa/cl env). Output: /root/oclfix/b1/
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b1; rm -rf $O; mkdir -p $O; T=/root/cts/opencl-cts/test_conformance
r() { n=$1; shift; d=$1; shift; ( cd $T/$d && timeout ${TO:-1800} "$@" ) > $O/$n.log 2>&1; echo "$n rc=$? $(grep -E '^(PASSED|FAILED) [0-9]+ of' $O/$n.log | tail -1)"; }
MESA_SHADER_CACHE_DISABLE=true BIFROST_MESA_DEBUG=shaders r relationals relationals ./test_relationals relational_any
tail -c 300000 $O/relationals.log > $O/relationals.tail; rm $O/relationals.log
MESA_SHADER_CACHE_DISABLE=true BIFROST_MESA_DEBUG=shaders r intops integer_ops ./test_integer_ops quick_long_math
tail -c 300000 $O/intops.log > $O/intops.tail; rm $O/intops.log
r half half ./test_half -w
r basic3 basic ./test_basic async_copy_local_to_global async_strided_copy_local_to_global enqueue_map_image
r threaddim thread_dimensions ./test_thread_dimensions quick_2d_explicit_local quick_3d_explicit_local quick_2d_implicit_local
r sl_int images/samplerlessReads ./test_samplerless_reads int
r api_alloc api ./test_api min_max_mem_alloc_size
heap_memory_percent=0.3 r api_alloc_heap30 api ./test_api min_max_mem_alloc_size
TO=2400 r math math_brute_force ./test_bruteforce -w
echo BATCH1-DONE
