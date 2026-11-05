# DE33 display-tearing runner job latch: handoff

Command: `bash harness/research/display-tearing/runner/tearing-job.sh latch`

Purpose: mechanical check of the kernel fix branch `fix/sunxi-h616-de33-vblank-latch` (armbian-build worktree
`wt-display-tearing`, commit b04527be4: the DE33 mixer and plane registers are staged in a shadow and written out from the
TCON vblank interrupt instead of from the commit worker, see harness/research/impl-display-tearing.md). The board has no
monitor: HDMI-A-1 is forced on (`echo on > status`), DRM then offers its built-in modes and the test runs at 1024x768@60.
Picture content cannot be judged; what is measured is WHERE in the frame the hardware registers are written, which is the
cause of the tearing: on the stock kernel the KMS client's commit phase (= register write time) lands in the active video;
on the fixed kernel the writes happen in the vblank interrupt and the kernel reports the TCON scan line of every write.

Precondition (coordinator): merge `fix/sunxi-h616-de33-vblank-latch` at b04527be4 into `test-cumulative`, build the next
cumulative kernel (c20 or later; c19 = 36e31fcb3 lacks it and is refused) and serve it as kernel-check/vdec-serve/Image.<tag>
+ modules-<tag>.tgz. The script installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt) via
harness/research/vdec-perf/install-kernel.sh with the one-shot fallback armed; the HTTP server on 10.56.0.1:8643 must be up.
It checks that b04527be4 is an ancestor of the tag's commit and that the booted kernel has
/sys/module/sun8i_mixer/parameters/de33_latch_flushes; otherwise it writes BLOCKED and exits 2 (report that, not a FAIL).
The client harness/afbc-kms-play/out/afbc-kms-play (built 2026-11-05 with --commit-delay) is shipped to /root/afbc/ if the
board copy differs. The board must start on the stock image kernel.

DEV or TEST: DEV-length, about 10 min: chunk `stock` (~2 min, stock image kernel, baseline) then chunk `fix` (install +
reboot + ~1 min of runs + restore, ~7 min). Each chunk runs three 10 s page-flip runs of 600 frames: d0 (commit right after
the flip event), d4 (commit 4 ms after it, inside the active video), d12 (12 ms after it). Resumable: re-running skips the
chunks in logs/runner-latch/state. The script restores the stock kernel vmlinuz-7.3.1-edge-sunxi64 at the end of chunk fix
and before every lock hand-over.

Fail fast: the serial log and the chunk's dmesg are watched for `Unable to handle|Oops|WARNING:|flip_done timed out|vblank
wait timed out|workqueue lockup`; a hit ends the job (exit 3, lines in logs/runner-latch/OOPS): report FAIL (OOPS) with
the OOPS content and the last 10 lines of runner.log.

Results: harness/research/display-tearing/logs/runner-latch/: runner.log, results.txt (one line per value: `<chunk> <run>
<key> <value>`), chunk-<c>.txt, files/<c>/{kernel.txt,connectors.txt,d0|d4|d12.txt,.csv,.params.before,.params.after,
dmesg-chunk.txt}, OOPS / BLOCKED only when they happened.

Exit codes: 0 = both chunks ran, judge with the checks below; 3 = Oops/WARN, FAIL; 2 = blocked (report BLOCKED and the
last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical, all on results.txt unless stated)
0. Display rule: if results.txt has `stock all mode_unavailable 1` or `fix all mode_unavailable 1`, that chunk is
   NOT TESTED (the forced connector offered no 1024x768 mode), never FAIL; report files/<c>/connectors.txt. Skip the
   chunk's other checks.
1. runner.log contains two `kernel: ` lines (stock chunk and fix chunk) and `kernel fix: present`. Report both.
2. Every run completed: for each of stock/fix x d0/d4/d12, `rc` is 0 and `flips` >= 590 (of 600) -> PASS, else FAIL
   (report the `grep -E "error|Error|failed" files/<c>/<run>.txt` lines, first 5).
3. Flip rate: each run's `flips_per_s` is between 58.5 and 61.5 and `seq_gaps` is 0 -> PASS (d4 and d12 included: the
   delayed commit still lands before the next vblank at 60 Hz). Else FAIL with the values.
4. Baseline (data, not pass/fail): report for stock d0/d4/d12 `commits_outside_blanking` of `commits_counted`. Expected
   from the 2026-11-03 4K runs: most or all commits outside the 0.72 ms blanking even for d0; d4 and d12 all outside.
   This is the stock behaviour the fix addresses (on the stock kernel the register write IS the commit).
5. Fix, frame-coherent writes (the actual tearing check), for fix d0, d4 AND d12:
   - `flushes_late_delta` == 0 -> PASS (every vblank-interrupt write found the beam before the active video).
   - `line_max` < `line_active` and `line_min` >= 0 -> PASS (TCON scan line of the writes inside the leading blanking;
     line_active is 35 for 1024x768@60).
   - `flushes_delta` >= `flips` - 2 -> PASS (one hardware write-out per flip).
   - `ns_max` < 500000 -> PASS (the write-out fits the 724 us blanking with margin).
   - `commits_outside_blanking` for d4 and d12 >= 590 (the client did commit in the active video, so the writes were
     really decoupled from the commit time) -> PASS.
   Any miss -> FAIL with the values. Also report `flushes_sync_delta`, `coalesced_delta`, `words_max`, `commits_delta`.
6. dmesg: `stock all dmesg_bad 0` and `fix all dmesg_bad 0` -> PASS; else FAIL, copy the matching lines from
   files/<c>/dmesg-chunk.txt exactly.
7. Residual (data): on the fix chunk, `grep -c . files/fix/dmesg-chunk.txt` and any `sun4i|sun8i|drm` lines (first 10).

The summary must list: both kernel lines, the per-run table (chunk, run, rc, flips, flips_per_s, seq_gaps,
commits_outside_blanking/commits_counted, and for fix: flushes_delta, flushes_late_delta, line_min, line_max, line_active,
ns_max, words_max, flushes_sync_delta, coalesced_delta), the dmesg counts, the state file content, and OOPS/BLOCKED verbatim
if they exist.
