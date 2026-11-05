# 07-opencl-timeout-fix: BLOCKED (package not ready: kernel c14 lacks the panfrost soft-stop fix)
Start 2026-11-05 20:38:03 UTC, end 20:40:43 UTC. Script exit code 2 (blocked per HANDOFF; not a FAIL). No chunk ran, no checks applicable.
Kernel installed (newest cumulative, c14, Image md5 959a7cd6d2929c0ea1e74c6a2e21d434): uname -v "#15 SMP PREEMPT Thu Nov  5 20:31:54 UTC 2026".
Needed: merge fix/sunxi-panfrost-softstop-resume into test-cumulative and build/serve the next cumulative kernel (c15 or later).
Last runner.log lines:
2026-11-05 20:38:03 job timeout-fix start, kernel c14 (Image md5 959a7cd6d2929c0ea1e74c6a2e21d434), chunks: intops tdim math-a math-b reg img3d, done before: 
2026-11-05 20:38:03 acquired by runner-timeout-fix-1793911083
shipped /root/stage/modules-c14.tgz 62478507bb8cc0cbcfb3b0e053969a09bc8f560acbce91385f54e9d51e8264be
running 7.3.1-edge-sunxi64 Image=vmlinuz-7.3.1-edge-sunxi64
armed fallback to vmlinuz-7.3.1-edge-sunxi64
kernel: #15 SMP PREEMPT Thu Nov  5 20:31:54 UTC 2026
2026-11-05 20:39:58 BLOCKED: kernel c14 lacks the panfrost soft-stop fix (merge fix/sunxi-panfrost-softstop-resume into test-cumulative and build first)
2026-11-05 20:40:43 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64
released by runner-timeout-fix-1793911083
Board restored to stock kernel, lock released. dmesg: none collected.
Results dir: harness/research/opencl-fixes/logs/runner-timeout-fix/
