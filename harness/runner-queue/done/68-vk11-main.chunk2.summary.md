# 68-vk11-main chunk 2 summary (PAUSED, exit 4, job NOT finished)
Started 2026-11-06 23:23:27, ended 23:44; fork 9d278fabfc2, kernel c48 b82264f81; restored stock: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026
Command: vk11-main.sh --max-hours 8. Script logged 'PAUSED before the next round of part-01' at 23:38:15 (no PAUSE reason known to runner: no PAUSE file left, 8h not reached; the script removes PAUSE when honoring it), so a PAUSE file existed at that moment.
Parts done: 1 of 64 (part-00 only).
Counts: cases=50743 Pass=16333 NotSupported=34410 Fail=0 Crash=0 Timeout=0 Hang=0 ResourceLimit=0 Stuck=0
STUCK-MARKED lines: none

## --check output
== job 68 checks (2026-11-06 23:44:36)
1 setup (fork 9d278fabfc2, vk3 deployed, kernel with e544ddb00): PASS
2 board apiVersion 1.1 + vkCreateDevice with all 1.1 features: PASS (apiVersion 1.1.354)
3 ARM core builtins probe d9 (rc=0, ids <= max, core count = shaderCoreCount 1): FAIL
  d10 1x1x1-g4x2x2: max core 0, max warp 99, warp>max 0, core>=count 0, warp max 127, count 1, invocations 16 (want 16)
  d10 4x1x1-g4x2x2: max core 0, max warp 99, warp>max 0, core>=count 0, warp max 127, count 1, invocations 64 (want 64)
  d10 3x5x7-g4x2x2: max core 0, max warp 122, warp>max 0, core>=count 0, warp max 127, count 1, invocations 1680 (want 1680)
  d10 64x1x1-g16x8x1: max core 0, max warp 127, warp>max 0, core>=count 0, warp max 127, count 1, invocations 8192 (want 8192)
3b raw core builtins d10 (no id above max, max warp id = shaderWarpsPerCore 128 - 1, all invocations ran): PASS
4 subgroup probes d2/d3/d6/d8 = job 52 values: PASS
5 parts complete: 1 of 64: FAIL
6 every finished part has one row per case: PASS
7 INSTR_INVALID_ENC in dmesg: 0: PASS
8 GPU faults in dmesg (js fault 0, page/MMU fault 0, gpu sched timeout 0): PASS
9 regressions against the baselines (cmp.txt): 0: PASS
INFO COUNTS cases=50743 NotSupported=34410 Pass=16333
INFO BASELINE main1in100-sys-1.0 (system Mesa 26.2.4, API 1.0): 32476 cases, 508 in this run; REGRESSIONS 0, FIXED 23
INFO BASELINE main1in100-sys-ovr1.1 (system Mesa 26.2.4, MESA_VK_VERSION_OVERRIDE=1.1): 32476 cases, 508 in this run; REGRESSIONS 0, FIXED 23
INFO BASELINE subset-sys-1.0 (system Mesa 26.2.4, API 1.0): 5225 cases, 24 in this run; REGRESSIONS 0, FIXED 1
INFO BASELINE subset-sys-ovr1.1 (system Mesa 26.2.4, override 1.1): 5225 cases, 24 in this run; REGRESSIONS 0, FIXED 1
INFO BASELINE subset-fork-job52 (fork 0e274280595 on c38, override 1.1 (job 52)): 5225 cases, 24 in this run; REGRESSIONS 0, FIXED 1
INFO Hang rows (stall watchdog): 0 ; stalls: 0
INFO stuck-case rows (ResourceLimit/Stuck): 0
INFO Soft-stop lines in dmesg: 0
