# Summary job 55-wb-eio

Kernel (uname -v): #41 SMP PREEMPT Fri Nov  6 17:20:09 UTC 2026 (c40, Image md5 d950e7ed64c3620b1983fc5217a99a7c)
Start 2026-11-06 17:24:44, end 2026-11-06 17:31:08. Exit 0, no BLOCKED/OOPS. Stock kernel restored (7.3.1-edge-sunxi64 #17). Board lock released.

**Verdict: PASS** (checks 0-4 pass for all 10 cases). No wb_error_frame key anywhere; no mode_unavailable / skipped cases.

## Checks 0-4
| case | lin rc | lin frames | lin wb_err | afbc wb_err | failed | jobs=done | lost | dmesg_bad | iommu | extra | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| syn-hevc8 | 0 | 24 | 0 | 0 | 0 | 96=96 | 0 | 0 | 0 | repeat_differ 0, src_md5_ok 24, interior_exact 24, interior_mism 0, afbc rc 0 | PASS |
| syn-hevc10 | 0 | 24 | 0 | 0 | 0 | 96=96 | 0 | 0 | 0 | repeat_differ 0, src_md5_ok 24, interior_exact 24, interior_mism 0, afbc rc 0 | PASS |
| syn-vp9p0 | 0 | 24 | 0 | 0 | 0 | 96=96 | 0 | 0 | 0 | repeat_differ 0, src_md5_ok 24, interior_exact 24, interior_mism 0, afbc rc 0 | PASS |
| syn-hevc8-xr24 | 0 | 24 | 0 | 0 | 0 | 96=96 | 0 | 0 | 0 | repeat_differ 0, src_md5_ok 24, interior_exact 24, interior_mism 0, afbc rc 0 | PASS |
| real-hevc8-r1 | 0 | 12 | 0 | 0 | 0 | 48=48 | 0 | 0 | 0 | afbc rc 0 | PASS |
| real-hevc8-r2 | 0 | 12 | 0 | 0 | 0 | 48=48 | 0 | 0 | 0 | afbc rc 0 | PASS |
| real-hevc8-r3 | 0 | 12 | 0 | 0 | 0 | 48=48 | 0 | 0 | 0 | afbc rc 0 | PASS |
| real-hevc8-r4 | 0 | 12 | 0 | 0 | 0 | 48=48 | 0 | 0 | 0 | afbc rc 0 | PASS |
| real-hevc8-r5 | 0 | 12 | 0 | 0 | 0 | 48=48 | 0 | 0 | 0 | afbc rc 0 | PASS |
| real-hevc10 | 0 | 12 | 0 | 0 | 0 | 48=48 | 0 | 0 | 0 | afbc rc 0 | PASS |

## Check 5 (report only)
| case | overflow | timeout | retries | deferred | lost | busy_frames | latch_flushes_late | status_fail | start_line_max | lin fence_ms_mean |
|---|---|---|---|---|---|---|---|---|---|---|
| syn-hevc8 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 8 | 27.9 |
| syn-hevc10 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 11 | 28.3 |
| syn-vp9p0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 11 | 28.0 |
| syn-hevc8-xr24 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 11 | 28.0 |
| real-hevc8-r1 | 4 | 0 | 4 | 0 | 0 | 0 | 0 | 32 | 13 | 30.5 |
| real-hevc8-r2 | 3 | 0 | 3 | 0 | 0 | 0 | 0 | 32 | 13 | 29.8 |
| real-hevc8-r3 | 4 | 0 | 4 | 0 | 0 | 0 | 0 | 32 | 13 | 30.3 |
| real-hevc8-r4 | 5 | 0 | 5 | 0 | 0 | 0 | 0 | 32 | 13 | 31.2 |
| real-hevc8-r5 | 2 | 0 | 2 | 0 | 0 | 0 | 0 | 32 | 13 | 29.0 |
| real-hevc10 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 32 | 13 | 27.8 |

dmesg: nothing abnormal (dmesg_bad 0, dmesg_iommu 0 in all cases).

Results: harness/research/afbc-wb/logs/runner-j55/ (results.txt, runner.log, chunk-*.txt, files/*/{linear,afbc,connector,kernel,mem}.txt, params.*, dmesg-chunk.txt). Dumps not committed.
