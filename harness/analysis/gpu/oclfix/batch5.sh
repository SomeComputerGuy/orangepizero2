#!/bin/sh
# math index-0 discriminator: threads / host fill
. /root/opiz2-mesa/cl/env.sh
O=/root/oclfix/b5; rm -rf $O; mkdir -p $O; T=/root/cts/opencl-cts/test_conformance/math_brute_force
F="fabs sqrt negation reciprocal subtract"
m() { n=$1; e=$2; a=$3; ( cd $T && timeout 1500 env $e ./test_bruteforce -w $a $F ) > $O/$n.log 2>&1; echo "$n rc=$? $(grep -E '^FAILED [0-9]+ of|^PASSED' $O/$n.log | tr '\n' ' ')"; }
m default X=1 ""
m single CL_TEST_SINGLE_THREADED=1 ""
m hostfill X=1 -b
( cd /root/cts/opencl-cts/test_conformance/images/samplerlessReads && timeout 900 ./test_samplerless_reads 1Dbuffer int debug_trace ) > $O/sl1db.log 2>&1; echo "sl1db rc=$?"; grep -n -m3 -B12 "differ" $O/sl1db.log | cut -c1-200
echo BATCH5-DONE
