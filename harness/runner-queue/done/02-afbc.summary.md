# 02-afbc summary
Verdict: BLOCKED (package not ready). Not a FAIL, no checks run.
Start 2026-11-06 10:34:31, end 10:38:16. Board stayed on / was restored to stock 7.3.1-edge-sunxi64 #17 (Fri Oct 30 12:09:52 UTC 2026).
Script lines (verbatim):
- BLOCKED: c9 Image md5 mismatch after install
- restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64
- rc=2
Cause: the job pins kernel c9 (Image md5 c210a5b247cacdf366b38062385d3a3f); the installed Image did not match. Needs the coordinator to re-point to a current cumulative kernel.
Checks: GL_RENDERER / quick ok / F-C-M table: NOT TESTED (no chunks ran). No dmesg captured.
Files: harness/research/vdec-perf/logs/runner-afbc/{BLOCKED,runner.log,state}
