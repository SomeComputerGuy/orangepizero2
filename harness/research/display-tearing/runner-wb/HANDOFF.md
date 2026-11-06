# Job 62-tearing-wb5: handoff (writeback proof that no frame mixes two commits; rerun of jobs 58-61)

Command: `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh`

Purpose: board check of armbian-build `fix/sunxi-h616-de33-latch-event` 825596b48 (in c47): on top of job 61's kernel
(flip event only after the vblank latch flush, atomic snapshot, stale TCON vblank bit cleared, no flush in active video,
a writeback job captures only its own snapshot), (1) a capture still busy at the vblank at which the next snapshot goes
on screen is now stopped there, so the next job still starts on its own snapshot (job 61: each such capture also cost
the next one); (2) every failed writeback job has exactly one reason, as its fence error and as a kernel counter
(-EIO `de33_wb_fail_error`, -ENODATA `de33_wb_fail_missed`, -ESTALE `de33_wb_replaced`, -ETIMEDOUT `de33_wb_fail_timeout`,
-ECANCELED `de33_wb_fail_cancelled`); the client prints the reason per failed flip; (3) the latch records the vblank count
at which each snapshot was taken and written out (`de33_latch_snap_vbl`, `de33_latch_flush_vbl`, `de33_latch_snap_ns`), so
the client explains every vblank between two flips (late commit vs held back by the latch). State/background:
harness/research/display-tearing/RESULTS.md.

Kernel: newest cumulative tag (c47 or later, Image.c47 md5 b3938b2633e1bcc7cf9d5262fa66b5d1), installed by the script
with Image+modules+DTB through harness/research/vdec-perf/install-kernel.sh (fallback armed), restored at the end
(restore-kernel.sh). The script refuses (BLOCKED) a kernel without 825596b48, without the parameters
`de33_latch_deferred` / `sun4i_tcon vblank_stale_cleared` / `de33_wb_fail_missed` / `de33_latch_snap_vbl`, or without the Writeback-1 connector. Board must start on the
stock image kernel. HTTP servers 10.56.0.1:8643 (kernel-check/vdec-serve) and :8644 (kernel-check/legacy-serve) must be up.

Client: harness/kms-wb/out/kms-wb (sha256 4970f3b2f4b8102099b6f75390b1db17efcac8a99e8bc4a763f8043e56bf0b12, built 2026-11-06 with `tear` incl. the
`RESULT event_order`, `RESULT wb_fail_reasons`, `RESULT seq_gap_account` lines, `selftest`, `memload`),
shipped to /root/wb/kms-wb if the board copy differs.

Display: HDMI-A-1 forced on (`echo on > status`, no sink), 1024x768@60. If the mode is missing
(`<chunk> all mode_unavailable 1`) that chunk is NOT TESTED, never FAIL.

DEV or TEST: TEST, about 16 min (install+reboot ~5, chunk base ~2.5, chunk load ~5, restore ~3). Resumable: chunks
`base`, `load` are recorded in logs/runner-t62/state; re-running skips the done ones (the trial kernel is re-installed
then). Pauses between chunks for a waiting session (restore + lock hand-over). Stall watchdog: 150 s without chunk output
kills the chunk; serial log and dmesg watched for Oops/WARN/flip_done timeout/IOMMU fault (exit 3).

What runs (all `kms-wb tear N`: every frame a different full-screen picture, row-tagged, a writeback capture of every
frame; each capture is classified OK / WRONG (stale or early) / MIXED (two commits in one frame = torn) / BAD):
- base: `selftest` (classifier on synthetic torn/stale/shifted/poisoned frames), probe, t-d0 (600 flips, commit right
  after the flip event), t-d4 (4 ms later), t-d12 (12 ms later), t-rand (1200 flips, random commit phase), burst1-4
  (60 flips each after 7 s idle, so the vblank IRQ is off and gets re-enabled: the old late-flush trigger).
- load: ve-d4, ve-rand (600 flips under a looping 4K H.265 cedrus decode into drm_prime frames, no download
  to system RAM; falls back to system-memory frames if the drm_prime rate is < 20 IRQs/2 s; `VE load started ... N VE
  IRQs in 2 s` in chunk-load.txt), mem-d4, mem-rand (4-thread memcpy load),
  vemem-rand, vemem-rand2, vemem-rand3 (both, 3 runs), kmsg-rand (printk flood 50 lines/s, IRQ latency stress).

Results: harness/research/display-tearing/logs/runner-t62/: runner.log, results.txt (`<chunk> <run> <key> <value>`),
chunk-<c>.txt, files/<c>/{<run>.txt,<run>.csv,<run>.params.before/after,selftest.txt,connectors.txt,printk.txt,
dmesg-chunk.txt,ve.err,memload.*.txt,dump-list.txt}. Raw captures of anomalies stay on the board (/root/tearwb/<c>/dump/),
never copied or committed; the VE loop marker ve.stop is not copied either.

Exit codes: 0 = chunks ran, judge with the checks; 2 = BLOCKED (report BLOCKED + last 10 lines of runner.log);
3 = Oops/WARN = FAIL (report OOPS content); 1 = setup/lock error (rerun later).

## Checks (mechanical, on results.txt)
"tear runs" = every run except `probe`. B = base chunk tear runs, L = load chunk tear runs.
0. Mode: `<chunk> all mode_unavailable 1` -> that chunk NOT TESTED. A `missing 1` line for a run = FAIL (run did not run).
1. `base selftest result pass` and `base selftest rc 0`.
2. All tear runs: `mixed 0`, `bad 0`, `wrong 0`, `full_bad 0`, `anomaly_lines 0` (no torn, stale, early or garbled capture).
3. B runs: `rc 0`, `fence_errors 0`, `ok` == `flips`, `frames_checked` == `flips`.
   L runs, all of: (a) `ok` + `fence_errors` == `flips`; (b) `fence_errors` == `wb_failed_delta`;
   (c) per reason, client == kernel: `client_fail_error` == `wb_fail_error_delta`, `client_fail_missed` ==
   `wb_fail_missed_delta`, `client_fail_replaced` == `wb_replaced_delta`, `client_fail_timeout` == `wb_fail_timeout_delta`,
   `client_fail_cancelled` == `wb_fail_cancelled_delta`, and `client_fail_wait 0`, `client_fail_other 0`;
   (d) `wb_failed_delta` == `wb_fail_error_delta` + `wb_fail_missed_delta` + `wb_replaced_delta` + `wb_fail_timeout_delta`
   + `wb_fail_cancelled_delta`, and `wb_fail_cancelled_delta 0`, `wb_fail_timeout_delta 0`;
   (e) `ok` >= 570 (coverage);
   (f) causes: `wb_replaced_delta` <= `wb_busy_frames_delta`; `wb_fail_error_delta` <= `wb_overflow_delta` +
   `wb_timeout_delta`; `wb_fail_missed_delta` <= `wb_deferred_delta` + `latch_coalesced_delta`.
   A capture the unit could not make of its own frame (DRAM contention: late begin, overflow) is not tearing; any fence
   error outside these reasons = FAIL.
4. B runs and L runs except kmsg-rand: `latch_flushes_late_delta 0` and `latch_forced_delta 0`.
   kmsg-rand: report only.
5. Flip timing. Every tear run (B and L; kmsg-rand: the acct_* conditions are report only, a vblank interrupt delayed by more
   than a frame is counted once by the latch but twice by DRM): no `seq_gap_account_unavailable` line, `acct_unexplained 0`,
   `acct_gap_flips` == `seq_gaps`, `acct_gap_vblanks` == `acct_late_vblanks` + `acct_deferred_vblanks`,
   `acct_deferred_vblanks` <= `latch_deferred_delta`. B runs t-d0, t-d4, t-d12, t-rand: `flip_rate` within 58.5-61.5;
   B runs t-d0, t-d4, t-d12, burst1-4: `seq_gaps` <= `latch_deferred_delta`. t-rand (random commit phase, up to ~1.8 ms
   before the vblank): gaps with `acct_late_vblanks` (the commit reached the latch after the vblank it was meant for) are
   allowed; report `acct_client_late`, `acct_commit_slow`, `snapshot_latency_mean_ms` / `_max_ms`.
6. Event after latch: every tear run (B and L) has `latch_events_delta` + `latch_events_now_delta` >= `flips`,
   `events_got` == `flips`, `events_unheld 0` and `events_unflushed 0`. A run with `event_order_unavailable 1` = FAIL.
   t-d4 and t-d12: `commits_outside_blanking` >= 590 (commits really land in active video).
7. VE load valid: ve-d4, ve-rand, vemem-rand, vemem-rand2, vemem-rand3 need `ve_irqs_delta` > 100 and no `load all ve_download_failed 1`;
   otherwise those runs are NOT TESTED for VE load (still judged by 2-4 as plain runs). `load all ve_leftover 0` (else FAIL:
   package bug). ve.err lines "Immediate exit requested" / "Read error at pos" are the kill at ve_stop (expected); any
   "Error opening input file" line = FAIL (package bug).
8. `base all dmesg_bad 0` and `load all dmesg_bad 0`.
9. runner.log has no `STALL:` line and both chunks end with ROUND-DONE (`chunk <c> done`).
PASS = 1-9 hold (with NOT TESTED parts named). Anything else = FAIL, name the check and the run.

## Summary must list
- kernel tag + uname -v, DTB md5 line from runner.log, start/end time, exit code, chunks done.
- the check verdicts 0-9.
- one table row per tear run: flips, ok, wrong (stale/early), mixed, bad, fence_errors, full_bad, flip_rate, seq_gaps,
  latch_late/deferred/forced/events/events_now/coalesced deltas, events_got/unheld/unflushed, vblank_stale_cleared_delta,
  wb_failed/overflow/timeout/retries/lost/busy_frames/deferred/replaced/fail_error/fail_missed/fail_timeout/fail_cancelled
  deltas, client_fail_* values, acct_* values, snapshot_latency_mean_ms/max_ms, wb_start_line_max_after,
  wb_busy_start_line_min_after, wb_quick_start_line_max_after,
  ve_irqs_delta, latch_line_max_after, latch_line_deadline_after.
- per L run with fence errors: the `RESULT flip N fence_error status=S reason R` lines (first 12) and the client_fail_*
  values next to the kernel wb_fail_error/fail_missed/replaced/fail_timeout/fail_cancelled deltas.
- per run with seq_gaps > 0: the acct_* values, snapshot_latency mean/max, and for B runs every `RESULT flip N seq_gap ...`
  line of files/base/<run>.txt (first 10 per L run).
- the `VE load started` lines of chunk-load.txt; memload_GBps per mem run; printk.txt content; first 10 `RESULT flip ... (WRONG|MIXED|BAD|FULL_*)` lines if any.
