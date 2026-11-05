# OpenCL runner job mesa2: handoff

Command: `bash harness/research/opencl-fixes/runner-mesa2/ocl-mesa2.sh`

Purpose: validate three Mesa-side fixes of the fork `panfrost-opencl-fixes` (mesa-work/mesa-cl, HEAD a0a4534b14d:
ec376a8ee7e nir/lower_cl_images texture_buffers = Bifrost texel-buffer attributes for `read_image(image1d_buffer_t)`;
a0a4534b14d rusticl sw_copy/copy_rect/write_rect whole-slice fast path = clEnqueueMapImage/ReadImage/WriteImage and the
rect buffer copies) with the OpenCL-CTS suites they affect, plus a regression subset. Analysis:
harness/research/impl-opencl-fixes.md section "Mesa-side fixes (agent opencl-mesa2)". The build is already done
(mesa-work/build-cl, cross, ccache); the script deploys it to the board as `/root/opiz2-mesa/cl2` (rsync of a stripped
staging copy; `/root/opiz2-mesa/cl` and the system Mesa are not touched) and checks the md5 of libRusticlOpenCL.

Precondition: none beyond the board answering ssh with the OpenCL CTS at /root/cts/opencl-cts (it is). Any booted
kernel: the job does not install or restore a kernel (stock image kernel expected; `uname -v` is recorded). It must not
run at the same time as another board job (the lock takes care of that).

DEV or TEST: TEST, about 2 h in 14 chunks of at most 15 min each (sl ~5, basic-a..d ~5-10 each, f2d-r2d/r2da ~7 each,
f2d-w/rw ~5 each, imgA ~11, imgB ~9, imgC ~9, imgD ~9, reg ~7). Chunks run the board command under `timeout 870`; the
host kills a chunk after 870 s without output. Resumable: re-running the command skips the chunks listed in
logs/runner-mesa2/state (delete a line from it to rerun that chunk). Between chunks the lock is handed over when
another session waits (no kernel to restore). `bash ... ocl-mesa2.sh --print` prints the board scripts without
touching the board.

Results: harness/research/opencl-fixes/logs/runner-mesa2/: runner.log, chunk-<c>.txt, dmesg-<c>.txt,
files/<c>/{binaries.csv,results.csv,logs/} for the clcts chunks sl, imgA-D, reg (copy of the board's
/root/oclfix/mesa2/opencl-mesa after each of those chunks; the CSVs are cumulative, the copy after `reg` has every suite
of this job), BLOCKED (only when blocked).

Exit codes: 0 = all chunks ran, judge with the checks below; 2 = blocked (report BLOCKED and the last 10 lines of
runner.log); 1 = setup or lock error (report the last 10 lines of runner.log).

## Checks (mechanical)
1. runner.log contains `fork: ` (must mention `contains a0a4534b14d`), `deployed cl2 ok` and a `kernel: ` line. Report
   the three lines.
2. sl: in files/sl/binaries.csv the rows starting `Images (Samplerless int),`, `Images (Samplerless uint),` and
   `Images (Samplerless float),` each read `...,Pass,0,PASSED 6 of 6 tests.` -> PASS (baseline was FAILED 1 of 6, the
   1Dbuffer test). Anything else -> FAIL; report the row and the lines containing `FAILED` or `differ` from
   files/sl/logs/Images_Samplerless_<t>_.log (first 10).
3. basic-a, basic-b, basic-c, basic-d (chunk-basic-<x>.txt): the last line matching `^(PASSED|FAILED) [0-9]+ of
   [0-9]+ tests` is `PASSED n of n tests.` -> PASS. `FAILED` -> FAIL; report that line and the lines matching
   `^[a-z_0-9]+ FAILED` and `ERROR:` (first 10). In addition `grep -c "^enqueue_map_image passed" chunk-basic-b.txt`
   must be 1 (this was the failing test, "Sample 168218 (coord 0,4,0) did not validate! Got 0, expected 126").
4. f2d-r2d, f2d-r2da, f2d-w, f2d-rw (chunk-f2d-<x>.txt): the last `^(PASSED|FAILED) [0-9]+ of [0-9]+ tests` line is
   `PASSED` -> PASS; `FAILED` -> FAIL, report that line, the `FAILED n of m sub-tests` line and the lines matching
   `^FAILED: \[CL_` (first 10) plus the first 6 lines after the first `did not validate`. f2d-r2da covers the
   baseline failure (CL_RGB SNORM_INT8/UNORM_INT8 2Darray, integer coords: one sample `(-nan,-nan,-nan,-nan)` per
   subtest); it was never rerun on the fork, so a FAIL here is data for the next agent, not a regression.
5. imgA, imgB, imgC, imgD: in files/imgD/binaries.csv (cumulative) every row for these suites has verdict `Pass`:
   Images (clCopyImage 1D), Images (clReadWriteImage), Images (clFillImage int), Images (clFillImage uint),
   Images (API Info), Images (Kernel Methods), Images (clFillImage float), Images (Kernel 1D int),
   Images (Kernel 1D uint), Images (Kernel 1D float), Images (clCopyImage 3D). All Pass -> PASS. Any other verdict ->
   FAIL (regression), report the row and the `FAILED` lines of its files/imgD/logs/<suite>.log (first 10).
6. reg: in files/reg/binaries.csv every row for these suites has verdict `Pass`: Atomics, C11 Atomics, Half Ops,
   Relationals, Events, Buffers, Compiler, Select, Common Functions, Geometric Functions, Compute Info, Workgroups,
   Subgroups, Profiling, Printf, Device Partitioning, Mem (Host Flags). All Pass -> PASS. Any other verdict -> FAIL
   (regression), report that row.
7. dmesg: `grep -c -E "js fault|Soft-stop failed|Page fault|Unhandled" dmesg-*.txt` is 0 for every chunk -> PASS;
   any hit -> FAIL, copy the lines exactly. Report `grep -c "gpu sched timeout" dmesg-*.txt` per chunk as a number
   (the stock kernel still resets on the 500 ms watchdog; a non-zero count is data, not FAIL for this job).
8. Every chunk-<c>.txt ends with `ROUND-DONE`; a chunk with `STALLED` or without ROUND-DONE is NOT FINISHED (report
   it; delete its line from logs/runner-mesa2/state and rerun the command once; if it does not finish the second time,
   report NOT FINISHED with the last 10 lines of its chunk file). `CHUNK-RC` is the test exit code (non-zero when a
   test failed, see the check for that chunk).

The summary must list: the three lines of check 1, the 14 per-chunk verdicts with the exact binaries.csv rows /
PASSED-FAILED lines, the enqueue_map_image count, the f2d failing-format lines if any, the dmesg counts per chunk,
and the state file content.
