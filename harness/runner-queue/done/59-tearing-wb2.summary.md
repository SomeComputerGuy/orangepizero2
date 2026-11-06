# Job 59-tearing-wb2 summary: FAIL (check 2 and 3, run load/vemem-rand)
Kernel: c44 (Image md5 a471ce426a7389b518b5420835b01f95, fix 93b00281a), uname -v on trial: #46 SMP PREEMPT Fri Nov 6 18:56:53 UTC 2026
DTB: sun50i-h616-orangepi-zero2.dtb.vdec-c44 md5 aa4d5bbb33e171e32c349e413c68f12c
Start 2026-11-06 19:01:48, end 19:11:08, exit code 0, chunks done: base, load (2 of 2). Stock restored: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026. Lock released.
Results: harness/research/display-tearing/logs/runner-t59/ (results.txt, runner.log, chunk-*.txt, files/)

## Checks
0 PASS (no mode_unavailable, no missing)
1 PASS (selftest result pass, rc 0)
2 FAIL: load/vemem-rand wrong 2 (early 2, stale 0), anomaly_lines 2. All other runs mixed/bad/wrong/full_bad/anomaly 0.
3 FAIL: B runs PASS. L: vemem-rand ok 598 + fence_errors 0 != flips 600, rc 1. Other L runs PASS.
4 PASS (late 0, forced 0 in all; kmsg-rand also 0)
5 PASS (flip_rate 60.003-60.004 for t-d0/d4/d12/rand; B seq_gaps 0)
6 PASS (events+events_now >= flips everywhere, events_got == flips, unheld 0, unflushed 0, no event_order_unavailable; t-d4 599, t-d12 599 outside blanking)
7 PASS (ve_irqs_delta 506/543/549 > 100; ve_leftover 0; no "Error opening input file"; VE load used drm_prime)
8 PASS (base and load dmesg_bad 0)
9 PASS (no STALL; chunk base done, chunk load done)
Verdict: FAIL. Two WRONG (early) captures in vemem-rand (VE decode + memcpy load): flip 560 captured tag 49, expected 48; flip 561 captured 50, expected 49 (one commit early, adjacent flips). No MIXED, so no torn frame.

## Per-run table (flips ok wrong mixed bad fence full_bad rate gaps | late deferred forced events events_now | got unheld unflushed | stale_cleared | wb_ovf wb_lost(timeout) | ve_irqs | line_max line_deadline)
base burst1-4 (each): 60 60 0 0 0 0 0 60.003 0 | 0 0 0 63 0 | 60 0 0 | 2 | 0 0 | 0 | 6 32
base t-d0: 600 600 0 0 0 0 0 60.003 0 | 0 0 0 603 0 | 600 0 0 | 2 | 0 0 | 0 | 6 32
base t-d4: 600 600 0 0 0 0 0 60.004 0 | 0 0 0 603 0 | 600 0 0 | 2 | 0 0 | 0 | 6 32
base t-d12: 600 600 0 0 0 0 0 60.004 0 | 0 0 0 603 0 | 600 0 0 | 2 | 0 0 | 0 | 6 32
base t-rand: 1200 1200 0 0 0 0 0 60.003 0 | 0 0 0 1203 0 | 1200 0 0 | 2 | 0 0 | 0 | 6 32
load ve-d4: 600 600 0 0 0 0 0 53.012 79 | 0 0 0 603 1 | 600 0 0 | 2 | 0 0 | 506 | 22 32
load ve-rand: 600 600 0 0 0 0 0 48.374 144 | 0 0 0 602 1 | 600 0 0 | 2 | 0 0 | 543 | 22 32
load mem-d4: 600 600 0 0 0 0 0 49.851 95 | 0 0 0 603 0 | 600 0 0 | 2 | 0 0 | 0 | 22 32
load mem-rand: 600 600 0 0 0 0 0 48.968 102 | 0 0 0 603 0 | 600 0 0 | 2 | 0 0 | 0 | 22 32
load vemem-rand: 600 598 2 0 0 0 0 48.244 121 | 0 0 0 602 1 | 600 0 0 | 2 | 0 0 | 549 | 27 32
load kmsg-rand: 600 600 0 0 0 0 0 60.004 0 | 0 0 0 603 0 | 600 0 0 | 2 | 0 0 | 0 | 27 32
(deferred delta is 0 in every run, so seq_gaps under load (79-144) are not covered by latch_deferred; check 5 only applies seq_gaps to base runs.)

## VE load lines
VE load started pid 5739 (-hwaccel_output_format drm_prime), 71 VE IRQs in 2 s
VE load started pid 6936 (-hwaccel_output_format drm_prime), 69 VE IRQs in 2 s
memload_GBps: mem-d4 2.366, mem-rand 2.382, vemem-rand 0.679
printk.txt: "1	4	1	7"
Anomalies: RESULT flip 560 WRONG tag_top 49 tag_bottom 49 ntags 1 expect 48 ; RESULT flip 561 WRONG tag_top 50 tag_bottom 50 ntags 1 expect 49
dmesg: nothing abnormal (dmesg_bad 0).
