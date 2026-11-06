# Job 61-tearing-wb4: handoff (writeback proof that no frame mixes two commits; rerun of jobs 58, 59, 60)

Command: `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh`

Purpose: board check of armbian-build `fix/sunxi-h616-de33-latch-event` 906968398 (in c46 = test-cumulative 266499b02):
on top of job 60's kernel (flip event only after the vblank latch flush, atomic snapshot, stale TCON vblank bit cleared,
no flush in active video, a writeback job starts only while its own snapshot is on screen), a capture that is still
busy at a vblank at which another snapshot is on screen now fails with -EIO (`de33_wb_lost` and `de33_wb_replaced`)
instead of completing with the later commit's picture (job 60: 6 "early" WRONG captures under VE load, each the only
busy capture of its run; the RT-WB unit sometimes begins one frame after its start, the scan-out was right). New
diagnostics `de33_wb_busy_start_line_min` / `de33_wb_quick_start_line_max` (start lines of captures that were busy /
finished at the next vblank). vemem-rand runs 3 times. State/background: harness/research/display-tearing/RESULTS.md.

Kernel: newest cumulative tag (c46 or later, Image.c46 md5 7b46b2a92515f23d7c1db63bb6e7a5d1), installed by the script
with Image+modules+DTB through harness/research/vdec-perf/install-kernel.sh (fallback armed), restored at the end
(restore-kernel.sh). The script refuses (BLOCKED) a kernel without 906968398, without the parameters
`de33_latch_deferred` / `sun4i_tcon vblank_stale_cleared` / `de33_wb_replaced`, or without the Writeback-1 connector. Board must start on the
stock image kernel. HTTP servers 10.56.0.1:8643 (kernel-check/vdec-serve) and :8644 (kernel-check/legacy-serve) must be up.

Client: harness/kms-wb/out/kms-wb (sha256 2730ba1fe6cc374a8f3605b9afd8e8477295a472224fb889b86832c8625cf895, built 2026-11-06 with `tear` incl. the
`RESULT event_order` line, `selftest`, `memload`),
shipped to /root/wb/kms-wb if the board copy differs.

Display: HDMI-A-1 forced on (`echo on > status`, no sink), 1024x768@60. If the mode is missing
(`<chunk> all mode_unavailable 1`) that chunk is NOT TESTED, never FAIL.

DEV or TEST: TEST, about 16 min (install+reboot ~5, chunk base ~2.5, chunk load ~5, restore ~3). Resumable: chunks
`base`, `load` are recorded in logs/runner-t61/state; re-running skips the done ones (the trial kernel is re-installed
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

Results: harness/research/display-tearing/logs/runner-t61/: runner.log, results.txt (`<chunk> <run> <key> <value>`),
chunk-<c>.txt, files/<c>/{<run>.txt,<run>.csv,<run>.params.before/after,selftest.txt,connectors.txt,printk.txt,
dmesg-chunk.txt,ve.err,memload.*.txt,dump-list.txt}. Raw captures of anomalies stay on the board (/root/tearwb/<c>/dump/),
never copied or committed.

Exit codes: 0 = chunks ran, judge with the checks; 2 = BLOCKED (report BLOCKED + last 10 lines of runner.log);
3 = Oops/WARN = FAIL (report OOPS content); 1 = setup/lock error (rerun later).

## Checks (mechanical, on results.txt)
"tear runs" = every run except `probe`. B = base chunk tear runs, L = load chunk tear runs.
0. Mode: `<chunk> all mode_unavailable 1` -> that chunk NOT TESTED. A `missing 1` line for a run = FAIL (run did not run).
1. `base selftest result pass` and `base selftest rc 0`.
2. All tear runs: `mixed 0`, `bad 0`, `wrong 0`, `full_bad 0`, `anomaly_lines 0` (no torn, stale, early or garbled capture).
3. B runs: `rc 0`, `fence_errors 0`, `ok` == `flips`, `frames_checked` == `flips`.
   L runs, all of: (a) `ok` + `fence_errors` == `flips`; (b) `fence_errors` == `wb_failed_delta`;
   (c) `fence_errors` <= `wb_overflow_delta` + `wb_timeout_delta` + `wb_lost_delta`;
   (d) `wb_lost_delta` <= `wb_busy_frames_delta` + `wb_deferred_delta` + `latch_coalesced_delta` + `wb_overflow_delta`
   + `wb_timeout_delta`; (e) `ok` >= 570 (coverage); (f) `wb_replaced_delta` <= `wb_busy_frames_delta` and
   `wb_replaced_delta` <= `wb_lost_delta`. A capture the unit could not make of its own frame (DRAM
   contention: previous write-out still busy, overflow) is not tearing; any other fence error = FAIL.
4. B runs and L runs except kmsg-rand: `latch_flushes_late_delta 0` and `latch_forced_delta 0`.
   kmsg-rand: report only.
5. B runs t-d0, t-d4, t-d12, t-rand: `flip_rate` within 58.5-61.5; for all B runs `seq_gaps` <= `latch_deferred_delta`.
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
  wb_failed/overflow/timeout/lost/busy_frames/deferred/replaced deltas, wb_start_line_max_after,
  wb_busy_start_line_min_after, wb_quick_start_line_max_after,
  ve_irqs_delta, latch_line_max_after, latch_line_deadline_after.
- the `VE load started` lines of chunk-load.txt; memload_GBps per mem run; printk.txt content; first 10 `RESULT flip ... (WRONG|MIXED|BAD|FULL_*)` lines if any.
