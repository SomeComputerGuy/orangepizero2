# Job 63 panfrost-map-enomem summary
Kernel under test: c48 (b82264f81), uname -v #51 SMP PREEMPT Fri Nov 6 20:28:54 UTC 2026; stock restored: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026
Start 2026-11-06 20:37:16, end 20:49:57. Results: harness/research/panfrost-map-enomem/logs/runner/

1 PASS
kernel: #51 SMP PREEMPT Fri Nov  6 20:28:54 UTC 2026
2026-11-06 20:39:12 kernel fix: present (c48 contains a524d09da, panfrost.ko md5 42ee8fcd541195bff4d3dd1ec9a81df6)
2026-11-06 20:39:29 deployed pme ok (libgallium md5 e6d61c47e1be92b9ed72f0b4b0369300)
2 PASS: WARN/oops counts oom=0 gles31-di=0 gles31-compute=0 khr-compute=0 ocl=0
3 PASS (6 ROUND lines, rows=2, no HANG/Timeout/rc=124)
ROUND 600M-1: rc=0 s=155 rows=2  2 OOM  err12=0
GPU-ALIVE 600M-1: dEQP-GLES31.functional.compute.basic.ubo_to_ssbo_single_invocation,Pass 
ROUND 600M-2: rc=0 s=27 rows=2  2 OOM  err12=0
GPU-ALIVE 600M-2: dEQP-GLES31.functional.compute.basic.ubo_to_ssbo_single_invocation,Pass 
ROUND 600M-3: rc=0 s=31 rows=2  2 OOM  err12=0
GPU-ALIVE 600M-3: dEQP-GLES31.functional.compute.basic.ubo_to_ssbo_single_invocation,Pass 
ROUND 450M: rc=0 s=12 rows=2  2 OOM  err12=4
GPU-ALIVE 450M: dEQP-GLES31.functional.compute.basic.ubo_to_ssbo_single_invocation,Pass 
ROUND 500M: rc=0 s=13 rows=2  2 OOM  err12=4
GPU-ALIVE 500M: dEQP-GLES31.functional.compute.basic.ubo_to_ssbo_single_invocation,Pass 
ROUND 700M: rc=0 s=37 rows=2  2 OOM  err12=0
GPU-ALIVE 700M: dEQP-GLES31.functional.compute.basic.ubo_to_ssbo_single_invocation,Pass 
4 EXERCISED: 'Memory cgroup out of memory' count 21; err12=4 in 450M and 500M
5 PASS: 6 GPU-ALIVE lines with ubo_to_ssbo_single_invocation,Pass (above)
6 PASS
gles31-di: SUMMARY cases=221 {'Pass': 203, 'NotSupported': 18} REGRESSIONS=0 FIXED=2 CHANGED=0 MISSING=0
gles31-compute: SUMMARY cases=195 {'Pass': 195} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
khr-compute: SUMMARY cases=39 {'Pass': 37, 'NotSupported': 2} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
gles31-di FIXED:
FIXED dEQP-GLES31.functional.draw_indirect.compute_interop.large.drawelements_separate_grid_1000x1000_drawcount_5000 OOM -> Pass
FIXED dEQP-GLES31.functional.draw_indirect.compute_interop.large.drawelements_combined_grid_1000x1000_drawcount_5000 OOM -> Pass
7 PASS
suite,verdict,exit,summary,seconds,command
Compute Info,Pass,0,PASSED 3 of 3 tests.,2,computeinfo/test_computeinfo
Atomics,Pass,0,PASSED 13 of 13 tests.,5,atomics/test_atomics
Select,Pass,0,PASSED 22 of 22 tests.,10,select/test_select -w
Half Ops,Pass,0,PASSED 13 of 13 tests.,58,half/test_half -w
C11 Atomics,Pass,0,PASSED 32 of 32 tests.,7,c11_atomics/test_c11_atomics
Workgroups,Pass,0,,1,workgroups/test_workgroups
Subgroups,Pass,0,,1,subgroups/test_subgroups
8 PASS: js fault etc counts gles31-di=0 gles31-compute=0 khr-compute=0 ocl=0; oom chunk: fault count 0, oom-kill/Killed process count 62 (data)
9 PASS: all 5 chunk files end ROUND-DONE
10 PASS: 2026-11-06 20:49:57 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 
state: oom gles31-di gles31-compute khr-compute ocl 
Abnormal dmesg: none flagged by the checks.
