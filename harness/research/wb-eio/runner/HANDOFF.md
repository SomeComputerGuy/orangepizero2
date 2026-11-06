# HANDOFF: job 55-wb-eio (DE33 writeback -EIO under a 4K H.265 decode; capture-repeat fix on c40)

Jobs 53/54: in case real-hevc8 (4K H.265 8-bit, linear NV12 pass) the first writeback capture after some plane flips
failed with fence status -5 (frames 2,6[,8]); everything else passed. c40 adds commit 20e682fc2
(fix/sunxi-h616-de33-wb-retry): a capture that ends with OVERFLOW/TIMEOUT is repeated on the next frame while the same
picture is on screen, a start with the beam already in active video is postponed, and new counters say which happened.

Type: TEST, ~20 min (2 reboots; 10 cases of < 1 min each). Resumable, pausable between cases (the script hands the lock
over when someone waits in harness/queue/board.wait and restores the stock kernel first).

## Command (host, from /home/aruni/orangepizero2)
`bash harness/research/wb-eio/runner/wb-eio-job.sh`
Run it as one background command and wait for it to exit. Re-running the same command resumes (skips the cases in
harness/research/afbc-wb/logs/runner-j55/state). Do not edit the scripts.

## What it needs (the script checks and BLOCKs otherwise)
- Board on the stock image kernel (vmlinuz-7.3.1-edge-sunxi64), HTTP server 10.56.0.1:8643 up.
- Kernel: the NEWEST cumulative tag in kernel-check/cumulative-kernels.txt (c40 or later) containing 30706dcc8,
  8b1f787fe and 20e682fc2. Installed by vdec-perf/install-kernel.sh (Image + modules + DTB, fallback armed), restored by
  vdec-perf/restore-kernel.sh.
- Client harness/afbc-wb/out/afbc-wb (unchanged since job 54), synthetic streams in kernel-check/vdec-serve/afbc-wb/,
  4K streams in /root/vdec-streams/ on the board (job 54 had them). HDMI-A-1 forced on at 1024x768@60, no sink.

## Exit codes
0 = cases ran (apply the checks); 2 = BLOCKED (logs/runner-j55/BLOCKED: report "blocked: <reason>"); 3 = Oops/WARN/
IOMMU fault (logs/runner-j55/OOPS: verdict FAIL (kernel), copy its first 20 lines); 1 = lock/setup error (runner.log tail).

## Cases
| case | stream | linear | AFBC | frames | kind |
|---|---|---|---|---|---|
| syn-hevc8, syn-hevc10, syn-vp9p0, syn-hevc8-xr24 | 1024x768 lossless synthetic | NV12/P010 | AS12/AS01 | 24 | regression |
| real-hevc8-r1 .. real-hevc8-r5 | hevc-main-2160p60.mkv, 1024x768 window at 1408,704 | NV12 | AS12 | 12 | the -EIO case, 5 repeats |
| real-hevc10 | hevc-main10-2160p60.mkv, same window | P010 | AS01 | 12 | load comparison |

## Checks (values from harness/research/afbc-wb/logs/runner-j55/results.txt, lines "<case> <pass> <key> <value>")
- **Check 0 (setup)**: exit 0 or 3, no BLOCKED file, runner.log has a `kernel:` line with `#40` or later. A case with
  `<case> all mode_unavailable 1` is NOT TESTED (never FAIL). A case with `all skipped_stream_missing 1`: NOT TESTED.
- **Check 1 (the fix, each real-hevc8-rN)**: `linear rc 0`, `linear frames 12`, `linear wb_errors 0`, `afbc rc` any
  (informational), `afbc wb_errors 0`, `all wb_failed_delta 0`, `all wb_jobs_delta` == `all wb_done_delta` (48),
  `all wb_lost_delta 0`, and no `wb_error_frame*` key for the case.
- **Check 2 (regression, each syn-* case)**: `linear rc 0`, `linear wb_errors 0`, `linear repeat_differ 0`,
  `linear src_md5_ok 24`, `afbc wb_errors 0`, `afbc interior_exact 24`, `afbc interior_mismatches 0`,
  `afbc rc 0`, `all wb_failed_delta 0`, `all wb_jobs_delta` == `all wb_done_delta` (96).
- **Check 3 (real-hevc10)**: `linear wb_errors 0`, `afbc wb_errors 0`, `all wb_failed_delta 0`.
- **Check 4 (kernel health, every case)**: `all dmesg_bad 0`, `all dmesg_iommu 0`.
- **Check 5 (report only, every case, one table row each)**: `all wb_overflow_delta`, `all wb_timeout_delta`,
  `all wb_retries_delta`, `all wb_deferred_delta`, `all wb_lost_delta`, `all wb_busy_frames_delta`,
  `all latch_flushes_late_delta`, `all wb_status_fail`, `all wb_start_line_max`, and the `linear fence_ms_mean`.

## Verdict (mechanical)
- PASS: checks 0-4 pass for all cases.
- FAIL (fix insufficient): check 1 fails on any real-hevc8-rN. List for that case:
  `grep -E 'wb_error' harness/research/afbc-wb/logs/runner-j55/files/<case>/linear.txt` and its params.after.
- FAIL (regression): check 2 or 3 fails; list the failing keys and values.
- FAIL (kernel): exit 3 or check 4 fails (copy the matched lines from files/<case>/dmesg-chunk.txt).
- NOT TESTED: check 0 says so for a case.
A case marked STALLED or without ROUND-DONE in runner.log: run the command once more (it resumes); if it stalls again,
report it as blocked with the last 20 lines of chunk-<case>.txt.

## Files (harness/research/afbc-wb/logs/runner-j55/)
runner.log, results.txt, state, chunk-<case>.txt, files/<case>/{linear,afbc,connector,kernel,mem}.txt,
files/<case>/{params.before,params.after,dmesg-chunk.txt}. Commit the text files only; never files/*/dump/*.cap.

## Summary must list
Kernel (`uname -v`), start/end time, verdict, checks 0-4 per case PASS/FAIL with values (table case x keys), the check 5
table, and any FAIL lines asked for above.

## Timeouts
As job 54: ssh step 120 s; client pass 180 s; case 420 s; stall watchdog 240 s; install 900 s; restore 600 s; scp 300 s.
