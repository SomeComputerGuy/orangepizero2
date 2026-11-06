# GLES advanced-blend coherency runner job: handoff

Command: `bash harness/research/gles-advblend/runner/gles-advblend.sh`

Purpose: validate the fork fix for KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence (fork
`panfrost-opencl-fixes`, mesa-work/mesa-cl, commit dc7266d584b "panfrost: don't describe tilebuffer-reading fragments
as opaque (v6/v7)") with the KHR blend_equation_advanced group, a minimal repro program, and a GLES 3.1 / GLES 3
regression subset. Analysis: harness/research/gles-advblend/RESULTS.md. The build is already done (mesa-work/build-cl,
cross, ccache); the script deploys it to the board as `/root/opiz2-mesa/gl1` (rsync of a stripped staging copy; the
system Mesa and `/root/opiz2-mesa/cl*` are not touched) and checks the md5 of lib/libgallium-26.2.4.so (meson installs it next to the other libs, not under dri/).

Precondition: the board answers ssh and has the GLES CTS at /root/cts/deqp-gles (glcts/glcts, gles31/deqp-gles31,
gles3/deqp-gles3, deqp-run.py; it does) and /root/cts/lib. Any booted kernel (newest cumulative or stock; the job does
not install or restore a kernel, `uname -v` is recorded). It must not run at the same time as another board job (the
lock takes care of that).

DEV or TEST: TEST, about 45-60 min in 8 chunks of at most 15 min each (repro ~2, khr-adv ~2, deqp-fbfetch ~3, deqp-ms
~8, khr-ms ~6, deqp-fbo ~4, gles3-blend-a/-b ~6 each). Chunks run the board command under `timeout 870`; the host kills
a chunk after 870 s without output. Resumable: re-running the command skips the chunks listed in logs/runner/state
(delete a line from it to rerun that chunk). Between chunks the lock is handed over when another session waits (no
kernel to restore). `bash ... gles-advblend.sh --print` prints the board scripts without touching the board.

Results: harness/research/gles-advblend/logs/runner/: runner.log, chunk-<c>.txt, dmesg-<c>.txt, caselists/,
files/repro/repro-<tag>.txt (full output of every repro run, with the bad-tile map when it fails),
files/<c>/results.csv for the CTS chunks (copied from the board), compare-<c>.txt (board result vs the baseline
harness/analysis/gpu/cts/<suite>/results.csv, one line per differing case, last line `SUMMARY ...`), BLOCKED (only
when blocked).

Exit codes: 0 = all chunks ran, judge with the checks below; 2 = blocked (report BLOCKED and the last 10 lines of
runner.log); 1 = setup or lock error (report the last 10 lines of runner.log).

## Checks (mechanical)
1. runner.log contains `fork: ` (must mention `contains dc7266d584b`), `deployed gl1 ok` and a `kernel: ` line; no
   `note: ... stale build` line. Report the three lines.
2. repro (chunk-repro.txt, lines starting `TAG `):
   - `TAG fork-mixed:`, `TAG fork-mixed-2:`, `TAG fork-mixed-3:`, `TAG fork-mixed-x8:`, `TAG fork-mixed-256:`,
     `TAG fork-multiply:`, `TAG fork-mixed-barrier:` each end with `RESULT PASS` and contain `git-dc7266d584` in the
     version -> PASS. Any `RESULT FAIL` or missing `git-dc7266d584` -> FAIL; report that TAG line and the first 12
     lines of files/repro/repro-<tag>.txt.
   - `TAG sys-mixed:` is the control on the system Mesa (`Mesa 26.2.4-1ubuntu1`): expected `RESULT FAIL` (the bug).
     `TAG sys-mixed-barrier:` expected `RESULT PASS`. Report both lines as they are (a PASS of sys-mixed is data, not
     a failure of this job).
   - `TAG knob-*:` lines are data (which part of the fix matters): report all 8 lines as they are. Expected: knob-all
     and knob-all-2 `RESULT FAIL` (old descriptors restored).
3. khr-adv: compare-khr-adv.txt last line has `REGRESSIONS=0`, and files/khr-adv/results.csv has the row
   `KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence,Pass,...` -> PASS. Otherwise FAIL: report the
   mixedSequence row and every `REGRESSION` line. Report the `FIXED` lines (expected exactly one: mixedSequence).
4. deqp-fbfetch, deqp-ms, khr-ms, deqp-fbo, gles3-blend-a, gles3-blend-b: compare-<c>.txt last line has
   `REGRESSIONS=0` and `MISSING=0` -> PASS. Otherwise FAIL (regression): report every `REGRESSION` and `MISSING` line
   (first 20). Report the SUMMARY line of each chunk. `FIXED`/`CHANGED` lines are data: report them (first 10 each).
5. dmesg: `grep -c -E "js fault|Soft-stop failed|Page fault|Unhandled" dmesg-*.txt` is 0 for every chunk -> PASS;
   any hit -> FAIL, copy the lines exactly. Report `grep -c "gpu sched timeout" dmesg-*.txt` per chunk as a number
   (data, not FAIL).
6. Every chunk-<c>.txt ends with `ROUND-DONE`; a chunk with `STALLED` or without ROUND-DONE is NOT FINISHED (report
   it; delete its line from logs/runner/state and rerun the command once; if it does not finish the second time,
   report NOT FINISHED with the last 10 lines of its chunk file). `CHUNK-RC` is the test exit code (non-zero when a
   case failed; see the check for that chunk).

The summary must list: the three lines of check 1, all TAG lines of the repro chunk verbatim, the mixedSequence row,
the SUMMARY line of each CTS chunk with its REGRESSION/FIXED/CHANGED lines, the dmesg counts per chunk, and the state
file content.
