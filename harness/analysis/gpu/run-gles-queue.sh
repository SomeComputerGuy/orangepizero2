#!/bin/sh
# Board-side: run the dEQP GLES mustpass lists one after another (Mesa CI order/args).
# Start with: systemd-run --unit=cts-gles --collect -p MemoryMax=... sh /root/cts/run-gles-queue.sh
export LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless
D=/root/cts/deqp-gles; R=/root/cts/results; J=${JOBS:-1}
run() { python3 $D/deqp-run.py --deqp "$1" --caselist "$2" --out "$3" --jobs $J --timeout 180; }
[ -f $R/gles2-main/results.csv ]   || run $D/gles2/deqp-gles2   $D/mustpass/gles2-main.txt  $R/gles2-main
[ -f $R/gles3-main/results.csv ]   || run $D/gles3/deqp-gles3   $D/mustpass/gles3-main.txt  $R/gles3-main
[ -f $R/gles31-main/results.csv ]  || run $D/gles31/deqp-gles31 $D/mustpass/gles31-main.txt $R/gles31-main
for k in gles2-khr-main gles3-khr-main gles31-khr-main gles32-khr-main; do
  [ -f $R/$k/results.csv ] || run $D/glcts/glcts $D/mustpass/$k.txt $R/$k
done
echo ALL-DONE > $R/gles-queue.done
