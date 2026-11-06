# Job 60-tearing-wb3 summary: FAIL (checks 2, 3a)
Kernel c45 (Image md5 751c43fc9fbcc188c93f8a20ee42daeb), fix 3e0255e2f present. Board uname -v during run: c45 trial; after restore: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 (stock, verified).
DTB: sun50i-h616-orangepi-zero2.dtb.vdec-c45 md5 aa4d5bbb33e171e32c349e413c68f12c
Start 2026-11-06 19:24:42, end 19:34:19, exit 0, chunks done: base load. Lock released.

## Checks
0 PASS (no mode_unavailable, no missing)
1 PASS (selftest pass, rc 0)
2 FAIL: WRONG captures (fence OK, stale/early, none MIXED/BAD/FULL_BAD): ve-rand 2, vemem-rand 1, vemem-rand3 3. All other runs 0.
3 base PASS; load 3a FAIL for ve-rand, vemem-rand, vemem-rand3 (ok+fence_errors != flips because of the WRONG captures); 3b,3c,3d,3e PASS all load runs
4 PASS (late=0, forced=0 all runs)
5 PASS (flip_rate 60.004-60.006 in t-*, seq_gaps<=deferred)
6 PASS (events>=flips, got==flips, unheld/unflushed 0, outside_blanking >=590 for t-d4/t-d12)
7 PASS (ve_irqs 504-570 >100, ve_leftover 0, no 'Error opening input file')
8 PASS (dmesg_bad 0 both chunks)
9 PASS (no STALL, both chunks done)

## Per run (columns in header row)
run|flips|ok|wrong|mixed|bad|fence_errors|full_bad|flip_rate|seq_gaps|latch_flushes_late_delta|latch_deferred_delta|latch_forced_delta|latch_events_delta|latch_events_now_delta|latch_coalesced_delta|events_got|events_unheld|events_unflushed|vblank_stale_cleared_delta|wb_failed_delta|wb_overflow_delta|wb_timeout_delta|wb_lost_delta|wb_busy_frames_delta|wb_deferred_delta|ve_irqs_delta|latch_line_max_after|latch_line_deadline_after|commits_outside_blanking|memload_GBps|rc|frames_checked|event_order_unavailable|anomaly_lines
base/t-d0|600|600|0|0|0|0|0|60.004|0|0|0|0|603|0|0|600|0|0|2|0|0|0|0|0|0|0|7|32|0|-|0|600|-|0
base/t-d4|600|600|0|0|0|0|0|60.004|0|0|0|0|603|0|0|600|0|0|2|0|0|0|0|0|0|0|7|32|599|-|0|600|-|0
base/t-d12|600|600|0|0|0|0|0|60.004|0|0|0|0|603|0|0|600|0|0|2|0|0|0|0|0|0|0|7|32|599|-|0|600|-|0
base/t-rand|1200|1200|0|0|0|0|0|60.004|0|0|0|0|1203|0|0|1200|0|0|2|0|0|0|0|0|0|0|7|32|1159|-|0|1200|-|0
base/burst1|60|60|0|0|0|0|0|60.004|0|0|0|0|63|0|0|60|0|0|2|0|0|0|0|0|0|0|7|32|59|-|0|60|-|0
base/burst2|60|60|0|0|0|0|0|60.004|0|0|0|0|63|0|0|60|0|0|2|0|0|0|0|0|0|0|7|32|59|-|0|60|-|0
base/burst3|60|60|0|0|0|0|0|60.006|0|0|0|0|63|0|0|60|0|0|2|0|0|0|0|0|0|0|7|32|59|-|0|60|-|0
base/burst4|60|60|0|0|0|0|0|60.004|0|0|0|0|63|0|0|60|0|0|2|0|0|0|0|0|0|0|7|32|59|-|0|60|-|0
load/ve-d4|600|600|0|0|0|0|0|53.169|77|0|0|0|604|0|0|600|0|0|2|0|0|0|0|0|0|504|22|32|599|-|0|600|-|0
load/ve-rand|600|596|2|0|0|2|0|46.258|151|0|0|0|601|2|0|600|0|0|2|2|0|0|2|2|0|561|28|32|597|-|1|598|-|2
load/mem-d4|600|600|0|0|0|0|0|49.034|106|0|0|0|603|0|0|600|0|0|2|0|0|0|0|0|0|0|28|32|599|2.358|0|600|-|0
load/mem-rand|600|600|0|0|0|0|0|49.169|105|0|0|0|603|0|0|600|0|0|2|0|0|0|0|0|0|0|28|32|585|2.352|0|600|-|0
load/vemem-rand|600|599|1|0|0|0|0|48.900|124|0|0|0|603|0|0|600|0|0|2|0|0|0|0|1|0|570|28|32|596|0.733|1|600|-|1
load/vemem-rand2|600|600|0|0|0|0|0|50.766|109|0|0|0|600|3|0|600|0|0|2|0|0|0|0|0|0|542|28|32|594|0.916|0|600|-|0
load/vemem-rand3|600|594|3|0|0|3|0|47.168|125|0|1|0|603|0|0|600|0|0|2|3|0|0|3|3|0|567|28|32|597|0.754|1|597|-|3
load/kmsg-rand|600|600|0|0|0|0|0|59.904|1|0|0|0|603|0|0|600|0|0|2|0|0|0|0|0|0|0|28|32|579|-|0|600|-|0

lost/busy_frames per load run (wb_lost_delta / wb_busy_frames_delta):
ve-d4 0/0, ve-rand 2/2, mem-d4 0/0, mem-rand 0/0, vemem-rand 0/1, vemem-rand2 0/0, vemem-rand3 3/3, kmsg-rand 0/0

## VE load started
VE load started pid 5928 (-hwaccel_output_format drm_prime), 71 VE IRQs in 2 s
VE load started pid 6948 (-hwaccel_output_format drm_prime), 64 VE IRQs in 2 s
memload_GBps: mem-d4 2.358, mem-rand 2.352, vemem-rand 0.733, vemem-rand2 0.916, vemem-rand3 0.754
printk.txt: 1	4	1	7

## WRONG lines
[ve-rand]
RESULT flip 17 WRONG tag_top 18 tag_bottom 18 ntags 1 boundary_row -1 bad_rows 0 first_bad_row -1 first_bad_px 000000 expect 17
RESULT flip 338 WRONG tag_top 83 tag_bottom 83 ntags 1 boundary_row -1 bad_rows 0 first_bad_row -1 first_bad_px 000000 expect 82
[vemem-rand]
RESULT flip 425 WRONG tag_top 170 tag_bottom 170 ntags 1 boundary_row -1 bad_rows 0 first_bad_row -1 first_bad_px 000000 expect 169
[vemem-rand3]
RESULT flip 14 WRONG tag_top 15 tag_bottom 15 ntags 1 boundary_row -1 bad_rows 0 first_bad_row -1 first_bad_px 000000 expect 14
RESULT flip 21 WRONG tag_top 22 tag_bottom 22 ntags 1 boundary_row -1 bad_rows 0 first_bad_row -1 first_bad_px 000000 expect 21
RESULT flip 511 WRONG tag_top 0 tag_bottom 0 ntags 1 boundary_row -1 bad_rows 0 first_bad_row -1 first_bad_px 000000 expect 255
vemem-rand2: latch_events_now_delta 3, latch_events 600; vemem-rand3: latch_deferred_delta 1
dmesg: none abnormal (dmesg_bad 0)
