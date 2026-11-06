# Job 54-afbc-wb-rerun summary
Verdict: PASS (checks 0,1,2,3,6,7 pass for all five syn-* cases). Informational: real-hevc8 had 2 writeback errors (check 6 fails for that informational case).
Kernel: #39 SMP PREEMPT Fri Nov 6 16:52:41 UTC 2026 (c39, Image md5 b74f1af0...). Stock restored: 7.3.1-edge-sunxi64 #17. Start 2026-11-06 16:59:08, end 17:06:19. Exit 0. Lock released.
Results: harness/research/afbc-wb/logs/runner-j54/ (results.txt).

## syn-* (all PASS)
| case | linear frames/src_md5_ok/errs | afbc frames/cmp_frames | fmt mod | interior_exact/mism | afbc pic_offset | check6 |
|---|---|---|---|---|---|---|
| syn-hevc8 | 24/24/0 | 24/24 | YU08 0x0800000000000061 | 24/0 | 0,4 | ok (96/96, 0) |
| syn-hevc10 | 24/24/0 | 24/24 | YU10 ... | 24/0 | 0,4 | ok |
| syn-vp9p0 | 24/24/0 | 24/24 | YU08 | 24/0 | 0,0 | ok |
| syn-vp9p2 | 24/24/0 | 24/24 | YU10 | 24/0 | 0,0 | ok |
| syn-hevc8-xr24 | 24/24/0 | 24/24 | YU08 | 24/0 | 0,4 | ok |
All: linear pic_offset 0,0; linear fmt NV12/P010 modifier 0; repeat_differ 0, wrong_buffer_kind 0, fbd_state_wrong 0, compare_ref_missing 0, afbc rc 0, dmesg_bad 0, dmesg_iommu 0, wb_failed_delta 0. fbd_readable 1.

## Check 4 (compare_exact / mismatches / max_dev / edge_dist_hist)
- syn-hevc8: 0 / 2844406 / 296 / 1080268 1022148 741990 then zeros
- syn-hevc10: 0 / 2855512 / 313 / 1081374 1027213 746925 then zeros
- syn-vp9p0: 0 / 2844406 / 296 / 1080268 1022148 741990 then zeros
- syn-vp9p2: 0 / 2855512 / 313 / 1081374 1027213 746925 then zeros
- syn-hevc8-xr24: 0 / 2707228 / 74 / 1074552 944280 688396 then zeros

## Check 5/7 real-* (informational; compare_exact 0 everywhere)
| case | linear rc | afbc rc | repeat_differ | wrong_kind | fmt | cmp_frames | mismatches | max_dev | afbc pic_offset |
|---|---|---|---|---|---|---|---|---|---|
| real-hevc10 | 0 | 0 | 0 | 0 | YU10 | 12 | 2807147 | 319 | 0,4 |
| real-hevc8 | 1 | 1 | 0 | 0 | YU08 | 10 (ref_missing 2) | 2670864 | 327 | 0,4 |
| real-vp9p2 | 0 | 0 | 0 | 0 | YU10 | 12 | 2147762 | 325 | 0,0 |
| real-vp9p0 | 0 | 0 | 0 | 0 | YU08 | 12 | 2081714 | 332 | 0,0 |
| real-vp9p0-y4 | 0 | 0 | 0 | 0 | YU08 | 12 | 2079701 | 319 | 0,0 |
real-hevc8: linear wb_errors 2 (frame 2 and 6 wb_error -5), all wb_jobs_delta 48, wb_done_delta 46, wb_failed_delta 2; dmesg_bad 0, dmesg_iommu 0, no dmesg lines matched.
