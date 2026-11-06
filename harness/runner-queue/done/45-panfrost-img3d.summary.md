# 45-panfrost-img3d summary
Verdict: FAIL / NOT FINISHED (no GPU fault). Kernel: '#38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026' (c38). 10/10 chunks ran, all ROUND-DONE, no CUT-OFF/LEFTOVER, no OOPS. Start ~11:07, end 12:04:42; stock kernel restored (7.3.1-edge-sunxi64 #17).
Check 1 PASS: 2026-11-06 11:07:26 kernel fix: present (panfrost.ko md5 9014bbc7a2b41c667e3c562193d22eec); kernel: #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026
Check 2: F (Unhandled Page fault) = 0 in all 10 chunks. Other dmesg line (tdim2 only), verbatim:
DMESG: [  180.287076] panfrost 1800000.gpu: gpu sched timeout, js=1, config=0x7300, status=0x0, head=0xa0501c0, tail=0xa0501c0, sched_job=000000006a4dd30b
Per-chunk verdicts:
- tdim2: FAIL, TDIM-RC 1; quick_2d_explicit_local FAILED, quick_2d_implicit_local passed; "TDIM: FAILED 1 of 2 tests."; TIMEDOUT 102
- tdim3: NOT FINISHED, TDIM-RC 124; only "TDIM: quick_3d_explicit_local..." printed; TIMEDOUT 1201
- s32-1: PASS IMG-RC 0 t=278s F=0 (IMG: PASSED 11 of 11 sub-tests / PASSED test)
- s32-2: PASS IMG-RC 0 t=278s F=0
- s32-3: PASS IMG-RC 0 t=278s F=0
- s32-4: PASS IMG-RC 0 t=278s F=0
- u32-1: PASS IMG-RC 0 t=277s F=0
- u32-2: PASS IMG-RC 0 t=277s F=0
- f32-1: PASS IMG-RC 0 t=178s F=0
- ctl: PASS IMG-RC 0 t=336s F=0
TRACE TIMEDOUT: tdim2 102, tdim3 1201, all image chunks 0.
Overall: the job-28 page fault did NOT reproduce on c38 (8 image chunks PASS); tdim2 FAIL and tdim3 timeout are the failing parts.
State file: tdim2 tdim3 s32-1 s32-2 s32-3 s32-4 u32-1 u32-2 f32-1 ctl
Files: harness/research/opencl-fixes/logs/runner-img3d/
