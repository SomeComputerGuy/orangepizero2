# HANDOFF: job 53-afbc-wb (bit-exact cedrus AFBC check through the DE33 + writeback)

Type: TEST, ~20 min (2 reboots: trial kernel in, stock kernel back; 9 cases of < 1 min each). Resumable, pausable
between cases (lock hand-over when someone waits in harness/queue/board.wait; the script restores the stock kernel first).

## Command (host, from /home/aruni/orangepizero2)
`bash harness/research/afbc-wb/runner/afbc-wb-job.sh j53`
Run it as one background command and wait for it to exit. Re-running the same command resumes (skips cases in
logs/runner-j53/state). Do not edit the script.

## What it needs (all present when the job was queued; the script checks and BLOCKs otherwise)
- Board on the stock image kernel (vmlinuz-7.3.1-edge-sunxi64), HTTP server 10.56.0.1:8643 up.
- Kernel: the NEWEST cumulative tag in kernel-check/cumulative-kernels.txt (c38 = test-cumulative 76bd27766 when
  queued); it must contain the DE33 writeback commit 30706dcc8. Installed by vdec-perf/install-kernel.sh (Image +
  modules + DTB, fallback armed), restored by vdec-perf/restore-kernel.sh.
- Client harness/afbc-wb/out/afbc-wb (harness/afbc-wb/build.sh), synthetic streams + .srcmd5 in
  kernel-check/vdec-serve/afbc-wb/ (harness/afbc-wb/mkstreams.sh). Both are shipped by the script when the board copy
  differs. The 4K streams of the vdec jobs in /root/vdec-streams/ on the board (real-* cases; a missing one is skipped).
- Display: HDMI-A-1 is forced on at 1024x768@60 (no sink needed).

## Exit codes
0 = cases ran (apply the checks); 2 = BLOCKED (logs/runner-j53/BLOCKED has the reason: report "blocked: <reason>");
3 = Oops/WARN/IOMMU fault (logs/runner-j53/OOPS: verdict FAIL (kernel), copy its first 20 lines); 1 = lock/setup error
(report runner.log tail).

## Cases (each: linear decode pass -> captures, then AFBC decode pass -> compared with them)
| case | stream | linear | AFBC | frames | writeback | kind |
|---|---|---|---|---|---|---|
| syn-hevc8 | syn-hevc8.mkv (1024x768 lossless) | NV12 | AS12 (YU08) | 24 | XR30 | checked |
| syn-hevc10 | syn-hevc10.mkv | P010 | AS01 (YU10) | 24 | XR30 | checked |
| syn-vp9p0 | syn-vp9p0.webm | NV12 | AS12 | 24 | XR30 | checked |
| syn-vp9p2 | syn-vp9p2.webm | P010 | AS01 | 24 | XR30 | checked |
| syn-hevc8-xr24 | syn-hevc8.mkv | NV12 | AS12 | 24 | XR24 | checked |
| real-hevc10 / real-hevc8 / real-vp9p2 / real-vp9p0 | the 4K vdec streams, 1024x768 window at 1408,704 | P010/NV12 | AS01/AS12 | 12 | XR30 | informational |

## Checks (all values from logs/runner-j53/results.txt, lines "<case> <pass> <key> <value>")
- **Check 0 (setup)**: exit code 0 or 3, no BLOCKED file; runner.log has a `kernel:` line. If any case has
  `<case> all mode_unavailable 1`: that case is NOT TESTED (never FAIL).
- **Check 1 (linear pass, each syn-* case)**: `linear rc 0`, `linear frames 24`, `linear wb_errors 0`,
  `linear repeat_differ 0`, `linear wrong_buffer_kind 0`, `linear fbd_state_wrong 0`, `linear src_md5_ok 24`,
  `linear src_md5_mismatch 0`, `linear fb_format_modifier` = `NV12 0x0000000000000000` (hevc8, vp9p0, hevc8-xr24) or
  `P010 0x0000000000000000` (hevc10, vp9p2).
- **Check 2 (AFBC pass ran on AFBC, each syn-* case)**: `afbc frames 24`, `afbc wb_errors 0`, `afbc repeat_differ 0`,
  `afbc wrong_buffer_kind 0`, `afbc fbd_state_wrong 0`, `afbc compare_frames 24`, `afbc compare_ref_missing 0`,
  `afbc fb_format_modifier` = `YU08 0x0800000000000061` (8-bit cases) or `YU10 0x0800000000000061` (10-bit cases).
- **Check 3 (bit-exact, each syn-* case)**: `afbc interior_exact 24` and `afbc interior_mismatches 0`.
  (`afbc rc` is 0 when checks 2 and the client's own checks pass; report it.)
- **Check 4 (report only, each syn-* case)**: `afbc compare_exact`, `afbc compare_mismatches`, `afbc compare_max_dev`,
  and the `afbc edge_dist_hist` line verbatim.
- **Check 5 (report only, each real-* case)**: `linear rc`, `afbc rc`, `afbc repeat_differ`, `afbc wrong_buffer_kind`,
  `afbc fb_format_modifier`, `afbc compare_frames`, `afbc compare_exact`, `afbc compare_mismatches`,
  `afbc compare_max_dev`, or `all skipped_stream_missing 1`.
- **Check 6 (kernel health, every case that ran)**: `all dmesg_bad 0`, `all dmesg_iommu 0`, `all wb_failed_delta 0`,
  `all wb_jobs_delta` == `all wb_done_delta`.
- Every client run also prints `fbd_readable` (1 = FBD_CTL read via /dev/mem). Report it once; if 0, the
  fbd_state_wrong values carry no information (they are 0) and the summary says so.

## Verdict (mechanical)
- PASS: checks 0, 1, 2, 3 and 6 pass for all five syn-* cases.
- FAIL (AFBC differs): a syn-* case passes check 1 but fails check 2 or 3. List for that case:
  `grep -E 'vs_linear.*interior_mismatches [1-9]|wrong_buffer_kind|fbd_' logs/runner-j53/files/<case>/afbc.txt | head -10`
  and the DUMP lines of logs/runner-j53/chunk-<case>.txt.
- INCONCLUSIVE: a syn-* case fails check 1 (the linear reference itself is wrong: decode not equal to the source,
  captures not repeatable, writeback errors). List the failing keys and
  `grep -E 'src_md5_mismatch|wb_error|DIFFER' logs/runner-j53/files/<case>/linear.txt | head -10`.
- FAIL (kernel): exit 3 or check 6 fails.
- NOT TESTED: mode unavailable (check 0).
A case marked STALLED or without ROUND-DONE in runner.log: run the command once more (it resumes); if it stalls
again, report it as blocked with the last 20 lines of chunk-<case>.txt.

## Files (logs/runner-j53/ = harness/research/afbc-wb/logs/runner-j53/)
runner.log, results.txt, state, chunk-<case>.txt, files/<case>/{linear,afbc,connector,kernel,mem}.txt,
files/<case>/{params.before,params.after,dmesg-chunk.txt}. Commit the text files. Do NOT commit files/<case>/dump/*.cap
(binary capture dumps, 3 MB each; keep them on the host for the code agent).

## Summary must list
Kernel (`uname -v` from runner.log), start/end time, the verdict, checks 0-6 per case as PASS/FAIL with the values
(table: case x keys), the check 4 and 5 values, fbd_readable, the FAIL/INCONCLUSIVE lines asked for above, and any
dmesg lines matched by check 6 (copy exactly from files/<case>/dmesg-chunk.txt).

## Timeouts
ssh step 120 s; each client pass 180 s; case 420 s; stall watchdog 240 s without output; install 900 s; restore 600 s;
scp 300 s; ship 600 s per file.
