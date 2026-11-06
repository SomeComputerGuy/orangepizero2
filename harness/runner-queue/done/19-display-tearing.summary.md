# 19-display-tearing: check 3 FAIL (seq_gaps 1 on stock d4, stock d12, fix d0, fix d12); checks 0,1,2,5,6 PASS
Start 2026-11-06 01:17:31 UTC, end 01:22:51 UTC. Kernels: stock '#17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026'; fix chunk c24 '#23 SMP PREEMPT Fri Nov  6 00:46:05 UTC 2026'; 'kernel fix: present (de33_latch_* parameters)'. state: stock, fix. No BLOCKED/OOPS.
0 mode available: PASS (no mode_unavailable). 2 rc 0 and flips 600 (>=590) all six runs: PASS. 3 flips_per_s all within 58.5-61.5 but seq_gaps !=0 in the four runs above: FAIL. 4 (data) stock commits_outside_blanking/counted: d0 363/599, d4 599/599, d12 599/599. 5 fix d0/d4/d12: flushes_late_delta 0, line_max (7/7/8) < 35, line_min 1, flushes_delta 602 >= 598, ns_max 15584/15584/15875 < 500000, d4/d12 outside-blanking 599 >= 590: PASS. 6 dmesg_bad 0 both: PASS. 7 fix dmesg-chunk lines: 0.
```
stock d0 commits_outside_blanking 363
stock d0 commits_counted 599
stock d0 flips 600
stock d0 flips_per_s 60.049
stock d0 seq_gaps 0
stock d0 rc 0
stock d4 commits_outside_blanking 599
stock d4 commits_counted 599
stock d4 flips 600
stock d4 flips_per_s 59.904
stock d4 seq_gaps 1
stock d4 rc 0
stock d12 commits_outside_blanking 599
stock d12 commits_counted 599
stock d12 flips 600
stock d12 flips_per_s 59.903
stock d12 seq_gaps 1
stock d12 rc 0
stock all dmesg_bad 0
0
fix d0 commits_outside_blanking 385
fix d0 commits_counted 599
fix d0 flips 600
fix d0 flips_per_s 59.900
fix d0 seq_gaps 1
fix d0 rc 0
fix d0 flushes_delta 602
fix d0 flushes_sync_delta 0
fix d0 flushes_late_delta 0
fix d0 coalesced_delta 0
fix d0 commits_delta 602
fix d0 words_max 21
fix d0 ns_max 15584
fix d0 line_min 1
fix d0 line_max 7
fix d0 line_active 35
fix d4 commits_outside_blanking 599
fix d4 commits_counted 599
fix d4 flips 600
fix d4 flips_per_s 60.004
fix d4 seq_gaps 0
fix d4 rc 0
fix d4 flushes_delta 602
fix d4 flushes_sync_delta 0
fix d4 flushes_late_delta 0
fix d4 coalesced_delta 0
fix d4 commits_delta 602
fix d4 words_max 21
fix d4 ns_max 15584
fix d4 line_min 1
fix d4 line_max 7
fix d4 line_active 35
fix d12 commits_outside_blanking 599
fix d12 commits_counted 599
fix d12 flips 600
fix d12 flips_per_s 59.904
fix d12 seq_gaps 1
fix d12 rc 0
fix d12 flushes_delta 602
fix d12 flushes_sync_delta 0
fix d12 flushes_late_delta 0
fix d12 coalesced_delta 0
fix d12 commits_delta 602
fix d12 words_max 21
fix d12 ns_max 15875
fix d12 line_min 1
fix d12 line_max 8
fix d12 line_active 35
fix all dmesg_bad 0
0
```
Results: harness/research/display-tearing/logs/runner-latch/. Stock kernel restored, lock released.
