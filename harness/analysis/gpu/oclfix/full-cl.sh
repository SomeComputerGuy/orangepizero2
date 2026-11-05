#!/bin/sh
# Mesa OpenCL-CTS profile on the fork Mesa (rusticl), Images Kernel 3D excluded here (own long-timeout run)
R=/root/oclfix/full-9049a3c; mkdir -p $R; . /root/opiz2-mesa/cl/env.sh
python3 /root/cts/opencl-cts/clcts-run.py --cts /root/cts/opencl-cts/test_conformance \
  --profile /root/cts/opencl-cts/opencl_conformance_tests_mesa.csv --out $R/opencl-mesa --timeout ${TO:-5000} --only "${ONLY:-^(?!Images \(Kernel 3D)}"
sync; echo FULL-CL-DONE
