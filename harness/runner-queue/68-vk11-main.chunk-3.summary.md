# Job 68 vk11-main chunk 3 summary
**ALL 64 of 64 PARTS FINISHED.**

- start: 2026-11-07 17:32:45 (host UTC)   end: 2026-11-07 21:03:51 (job end); --check run 21:12:49
- exit code: 0
- parts done: 64 of 64 (48 before this chunk, 16 in this chunk)
- stock kernel restored: 2026-11-07 21:03:51 restored: 7.3.3-edge-sunxi64 #21 SMP PREEMPT Fri Nov  6 18:18:30 UTC 2026 vmlinuz-7.3.3-edge-sunxi64 
- BLOCKED/stuck/PAUSED lines this chunk: none (earlier chunk had PAUSED at 13:39:32 before part-48)

## COUNTS lines this chunk (parts 48-63)
COUNTS part-48 cases=50743 NotSupported=50743
COUNTS part-49 cases=50743 NotSupported=50743
COUNTS part-50 cases=50743 NotSupported=50743
COUNTS part-51 cases=50743 NotSupported=50743
COUNTS part-52 cases=50743 NotSupported=50145 Pass=598
COUNTS part-53 cases=50743 NotSupported=39977 Pass=10766
COUNTS part-54 cases=50743 NotSupported=30898 Pass=19845
COUNTS part-55 cases=50743 NotSupported=46634 Pass=4109
COUNTS part-56 cases=50743 NotSupported=45832 Pass=4911
COUNTS part-57 cases=50743 Crash=1 NotSupported=46716 Pass=4026
COUNTS part-58 cases=50743 NotSupported=38436 Pass=12304 QualityWarning=3
COUNTS part-59 cases=50743 NotSupported=50743
COUNTS part-60 cases=50743 NotSupported=50743
COUNTS part-61 cases=50743 NotSupported=41799 Pass=8944
COUNTS part-62 cases=50743 NotSupported=48727 Pass=2016
COUNTS part-63 cases=50743 NotSupported=45685 Pass=5058

## BLOCKED/STUCK/PAUSED grep this chunk
none

## --check output
```
== job 68 checks (2026-11-07 21:12:49)
1 setup (fork 9d278fabfc2, vk3 deployed, kernel with e544ddb00): PASS
2 board apiVersion 1.1 + vkCreateDevice with all 1.1 features: PASS (apiVersion 1.1.354)
3 ARM core builtins probe d9 (rc=0, ids <= max, core count = shaderCoreCount 1): FAIL
  d10 1x1x1-g4x2x2: max core 0, max warp 99, warp>max 0, core>=count 0, warp max 127, count 1, invocations 16 (want 16)
  d10 4x1x1-g4x2x2: max core 0, max warp 99, warp>max 0, core>=count 0, warp max 127, count 1, invocations 64 (want 64)
  d10 3x5x7-g4x2x2: max core 0, max warp 122, warp>max 0, core>=count 0, warp max 127, count 1, invocations 1680 (want 1680)
  d10 64x1x1-g16x8x1: max core 0, max warp 127, warp>max 0, core>=count 0, warp max 127, count 1, invocations 8192 (want 8192)
3b raw core builtins d10 (no id above max, max warp id = shaderWarpsPerCore 128 - 1, all invocations ran): PASS
4 subgroup probes d2/d3/d6/d8 = job 52 values: PASS
5 parts complete: 64 of 64: PASS
6 every finished part has one row per case: PASS
7 INSTR_INVALID_ENC in dmesg: 8: FAIL
8 GPU faults in dmesg (js fault 8, page/MMU fault 0, gpu sched timeout 0): FAIL
  in /home/aruni/orangepizero2/harness/research/vk11/logs/runner/dmesg/part-45.txt
  in /home/aruni/orangepizero2/harness/research/vk11/logs/runner/dmesg/part-46.txt
9 regressions against the baselines (cmp.txt): 1: FAIL
INFO COUNTS cases=3247552 Crash=9 Fail=526 NotSupported=2562827 Pass=684180 QualityWarning=8 ResourceError=2
INFO BASELINE main1in100-sys-1.0 (system Mesa 26.2.4, API 1.0): 32476 cases, 32476 in this run; REGRESSIONS 1, FIXED 482
INFO BASELINE main1in100-sys-ovr1.1 (system Mesa 26.2.4, MESA_VK_VERSION_OVERRIDE=1.1): 32476 cases, 32476 in this run; REGRESSIONS 1, FIXED 370
INFO BASELINE subset-sys-1.0 (system Mesa 26.2.4, API 1.0): 5225 cases, 5225 in this run; REGRESSIONS 0, FIXED 78
INFO BASELINE subset-sys-ovr1.1 (system Mesa 26.2.4, override 1.1): 5225 cases, 5225 in this run; REGRESSIONS 0, FIXED 50
INFO BASELINE subset-fork-job52 (fork 0e274280595 on c38, override 1.1 (job 52)): 5225 cases, 5225 in this run; REGRESSIONS 0, FIXED 34
INFO Hang rows (stall watchdog): 0 ; stalls: 0
INFO stuck-case rows (ResourceLimit/Stuck): 0
INFO Soft-stop lines in dmesg: 0
```
