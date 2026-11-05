#!/bin/sh
# GLES 3.1 mustpass (dEQP gles31-main + KHR gles31-khr-main) on the fork Mesa, same runner/options as run-cts-queue.sh
R=/root/oclfix/full-9049a3c; D=/root/cts/deqp-gles; mkdir -p $R
export LD_LIBRARY_PATH=/root/opiz2-mesa/cl/lib:/root/cts/lib __EGL_VENDOR_LIBRARY_FILENAMES=/root/opiz2-mesa/cl/50_mesa.json EGL_PLATFORM=surfaceless
run() { python3 $D/deqp-run.py --deqp "$1" --caselist "$2" --out "$3" --jobs 2 --timeout 180; sync; }
[ -f $R/gles31-main/results.csv ] || run $D/gles31/deqp-gles31 $D/mustpass/gles31-main.txt $R/gles31-main
[ -f $R/gles31-khr-main/results.csv ] || run $D/glcts/glcts $D/mustpass/gles31-khr-main.txt $R/gles31-khr-main
cat $R/gles31-main/summary.txt $R/gles31-khr-main/summary.txt 2>/dev/null | head -20
echo FULL-GLES-DONE
