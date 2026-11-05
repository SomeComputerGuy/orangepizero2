# 06-opencl-timeout-fix: blocked (package not ready: c13 install failed)
Start 2026-11-05 20:32:17 UTC, end 20:33:59 UTC. Script exit code 1 (setup error). No chunk ran, no checks applicable.
runner.log:
2026-11-05 20:32:17 job timeout-fix start, kernel c13 (Image md5 9271a396edc3968e49059d2c8b6fe29e), chunks: intops tdim math-a math-b reg img3d, done before: 
2026-11-05 20:32:17 acquired by runner-timeout-fix-1793910737
xz: /home/aruni/orangepizero2/kernel-check/vdec-serve/Image.c: No such file or directory
2026-11-05 20:33:09 BLOCKED: c13 Image md5 mismatch after install
2026-11-05 20:33:59 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 
released by runner-timeout-fix-1793910737
BLOCKED file: c13 Image md5 mismatch after install
Note: the line "xz: /home/aruni/orangepizero2/kernel-check/vdec-serve/Image.c: No such file or directory" suggests the install-kernel step used tag "c" instead of "c13" (kernel-check/vdec-serve has Image.c13). Board restored to stock kernel, lock released.
Results: harness/research/opencl-fixes/logs/runner-timeout-fix/
