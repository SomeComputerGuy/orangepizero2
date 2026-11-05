#!/bin/sh
# Long CTS binaries split by their own argument (one image type per chunk); ARGS = binary + args under test_conformance
R=/root/oclfix/full-9049a3c/split; mkdir -p $R; . /root/opiz2-mesa/cl/env.sh
ARGS=$(sed -n "${IDX}p" /root/opiz2-mesa/${LISTF:-cl-split.txt})
echo "$(date '+%F %T') $(uname -r) ARGS=$ARGS" >> /root/oclfix/full-9049a3c/kernel-versions.txt
n=$(echo "$ARGS" | tr -c 'A-Za-z0-9_\n' _); cd /root/cts/opencl-cts/test_conformance/$(dirname ${ARGS%% *})
./$(basename ${ARGS%% *}) ${ARGS#* } > $R/$n.log 2>&1; echo "rc=$? $(grep -E 'PASSED|FAILED' $R/$n.log | tail -1)" | tee -a $R/$n.log
sync; echo CHUNK-DONE
