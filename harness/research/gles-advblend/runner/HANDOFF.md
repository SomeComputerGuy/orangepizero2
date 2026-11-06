# GLES advanced-blend coherency runner job (job 50): handoff

Command: `bash harness/research/gles-advblend/runner/gles-advblend.sh`

Purpose: KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence. Job 48 (stock kernel #17) showed the
cause: the single fragment job of 44 fullscreen advanced-blend draws at 1024x1024 runs ~0.7 s, the 500 ms panfrost
watchdog resets the GPU (`gpu sched timeout ... status=0x8`) and the tiles not yet written stay 0. This job runs the
same chunks on the NEWEST cumulative kernel, which carries the panfrost soft-stop/resume series (e544ddb00, 0b7e3a208,
e17629bba): the long job should be soft-stopped and resumed instead of reset. Analysis:
harness/research/gles-advblend/RESULTS.md. The Mesa build is already done (mesa-work/build-cl, fork
panfrost-opencl-fixes, contains dc7266d584b); the script deploys it as `/root/opiz2-mesa/gl1` and checks the md5 of
lib/libgallium-26.2.4.so on the board (system Mesa and /root/opiz2-mesa/cl* untouched).

Kernel: the script installs the newest cumulative tag (kernel-check/cumulative-kernels.txt, c38 or later) with the
one-shot fallback armed, checks the Image md5 and that the board's panfrost.ko is that tag's module, and restores the
stock kernel (vdec-perf/restore-kernel.sh: Image, DTB, modules) at the end, before a lock hand-over and when blocked.
The board must be on the stock kernel at start.

Precondition: the board has the GLES CTS at /root/cts/deqp-gles (glcts, gles31, gles3, deqp-run.py) and /root/cts/lib.

DEV or TEST: TEST, about 15-25 min (job 48 took 5 min of tests) plus two reboots, 8 chunks of at most 15 min each.
Chunks run under `timeout 870`; the host kills a chunk after 870 s without output. Resumable: re-running the command
skips the chunks listed in logs/runner2/state (delete a line to rerun that chunk). `--print` prints the board scripts.

Results: harness/research/gles-advblend/logs/runner2/: runner.log, chunk-<c>.txt, dmesg-<c>.txt, trace-<c>.txt,
files/repro/repro-<tag>.txt, files/<c>/results.csv, compare-<c>.txt (last line `SUMMARY ...`), BLOCKED (only when
blocked). Job 48's results stay in logs/runner/.

Exit codes: 0 = all chunks ran, judge with the checks below; 2 = blocked (report BLOCKED and the last 10 lines of
runner.log); 1 = setup or lock error, including "stale build" / "lacks the soft-stop series" before the lock (report
the last 10 lines of runner.log; do not build anything yourself).

## Checks (mechanical)
1. runner.log has a `fork: ` line containing `(contains dc7266d584b)` (this is the commit check; the Mesa version
   string shows the fork HEAD, NOT dc7266d584b, and is not checked by you), `deployed gl1 ok`, a `kernel: ` line with
   `#38` or a later number, and `kernel fix: present`. Report the four lines. Missing one -> BLOCKED.
2. repro (chunk-repro.txt, lines starting `TAG `):
   - `TAG fork-mixed:`, `TAG fork-mixed-2:`, `TAG fork-mixed-3:`, `TAG fork-mixed-x8:`, `TAG fork-mixed-256:`,
     `TAG fork-multiply:`, `TAG fork-mixed-barrier:` each contain `RESULT PASS` -> PASS. Any `RESULT FAIL` -> FAIL;
     report that TAG line and the first 12 lines of files/repro/repro-<tag>.txt.
   - `TAG sys-mixed:`, `TAG sys-mixed-barrier:` (system Mesa) and the 8 `TAG knob-*:` lines are data: report all
     verbatim (they tell whether the Mesa change dc7266d584b is needed at all).
   - Every TAG line ends with `ms=<wall time> TO=<watchdog count so far>`: data, report as is.
3. khr-adv: compare-khr-adv.txt last line has `REGRESSIONS=0`, and files/khr-adv/results.csv has the row
   `KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence,Pass,...` -> PASS. Otherwise FAIL: report the
   mixedSequence row and every `REGRESSION` line. Report the `FIXED` lines (expected: mixedSequence).
4. deqp-fbfetch, deqp-ms, khr-ms, deqp-fbo, gles3-blend-a, gles3-blend-b: compare-<c>.txt last line has
   `REGRESSIONS=0` and `MISSING=0` -> PASS. Otherwise FAIL: report every `REGRESSION` and `MISSING` line (first 20).
   Report the SUMMARY line of each chunk and its `FIXED`/`CHANGED` lines (data; deqp-fbo may show
   `FIXED dEQP-GLES31.functional.fbo.no_attachments.maximums.all`).
5. dmesg: `grep -c -E "js fault|Soft-stop failed|Hard-stop|Page fault|Unhandled|Oops|Unable to handle" dmesg-*.txt`
   is 0 for every chunk -> PASS; any hit -> FAIL, copy the lines exactly. `grep -c "gpu sched timeout" dmesg-repro.txt
   dmesg-khr-adv.txt` is 0 for both -> PASS (with the series a long job is resumed without that message); otherwise
   FAIL, copy the lines. Report `grep -c "gpu sched timeout"` for the other chunks and the `TRACE: TIMEDOUT N` line of
   every trace-<c>.txt as numbers (data).
6. Every chunk-<c>.txt ends with `ROUND-DONE`; a chunk with `STALLED` or without ROUND-DONE is NOT FINISHED (delete
   its line from logs/runner2/state and rerun the command once; if it does not finish the second time, report NOT
   FINISHED with the last 10 lines of its chunk file).
7. runner.log has a `restored: ` line with `vmlinuz-7.3.1-edge-sunxi64` after the last chunk -> PASS; report it.

The summary must list: the lines of check 1, all TAG lines verbatim, the mixedSequence row, the SUMMARY line of each
CTS chunk with its REGRESSION/FIXED/CHANGED lines, the dmesg counts and TRACE lines per chunk, the restored line and
the state file content.
