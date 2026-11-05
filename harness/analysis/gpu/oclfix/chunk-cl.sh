#!/bin/sh
# One <=20 min chunk of the Mesa OpenCL-CTS profile on the fork Mesa; ONLY = regex of suite names (clcts-run resumes)
R=/root/oclfix/full-9049a3c; mkdir -p $R; . /root/opiz2-mesa/cl/env.sh
ONLY=$(sed -n "${IDX}p" /root/opiz2-mesa/cl-chunks.txt)
# PURGE=1: drop earlier rows of this chunk's suites (results from a run that must be discarded) so they rerun
[ "$PURGE" = 1 ] && python3 - "$ONLY" $R/opencl-mesa/binaries.csv $R/opencl-mesa/results.csv <<'PY'
import sys, re
for f in sys.argv[2:]:
    l = open(f).read().splitlines(True)
    open(f, "w").writelines([x for i, x in enumerate(l) if i == 0 or not re.search(sys.argv[1], x.split(",")[0])])
PY
echo "$(date '+%F %T') $(uname -r) ONLY=$ONLY" >> $R/kernel-versions.txt
python3 /root/cts/opencl-cts/clcts-run.py --cts /root/cts/opencl-cts/test_conformance \
  --profile /root/cts/opencl-cts/opencl_conformance_tests_mesa.csv --out $R/opencl-mesa --timeout 5000 --only "$ONLY"
sync; tail -n 3 $R/opencl-mesa/binaries.csv | cut -d, -f1-5; echo CHUNK-DONE
