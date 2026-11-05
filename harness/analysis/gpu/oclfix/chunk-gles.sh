#!/bin/sh
# One <=20 min chunk of the GLES 3.1 mustpass on the fork Mesa; LIST = gles31-main.N or gles31-khr-main
R=/root/oclfix/full-9049a3c/gles; D=/root/cts/deqp-gles; mkdir -p $R
echo "$(date '+%F %T') $(uname -r) LIST=$LIST" >> /root/oclfix/full-9049a3c/kernel-versions.txt
export LD_LIBRARY_PATH=/root/opiz2-mesa/cl/lib:/root/cts/lib __EGL_VENDOR_LIBRARY_FILENAMES=/root/opiz2-mesa/cl/50_mesa.json EGL_PLATFORM=surfaceless
case $LIST in gles31-khr*) B=$D/glcts/glcts;; *) B=$D/gles31/deqp-gles31;; esac
rm -rf $R/$LIST; python3 $D/deqp-run.py --deqp $B --caselist /root/opiz2-mesa/$LIST.txt --out $R/$LIST --jobs 2 --timeout 180
sync; cat $R/$LIST/summary.txt; echo CHUNK-DONE
