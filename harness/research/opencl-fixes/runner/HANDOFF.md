# OpenCL runner job timeout-fix: handoff

Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh timeout-fix`

Purpose: validate the kernel fix `fix/sunxi-panfrost-softstop-resume` (armbian-build worktree `wt-panfrost-softstop`,
commit e544ddb00: drm/panfrost resumes a still-active job after the 500 ms watchdog instead of resetting the GPU) with
the OpenCL-CTS suites that lost work to the reset, plus a regression subset. Analysis: harness/research/impl-opencl-fixes.md
section "Root cause: panfrost job timeout".

Precondition (coordinator): merge `fix/sunxi-panfrost-softstop-resume` into `test-cumulative`, build the next cumulative
kernel (c11 or later) and serve it as kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz (as for c9/c10). The script
installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt) via
harness/research/vdec-perf/install-kernel.sh with the one-shot fallback armed, like the vdec jobs; the HTTP server on
10.56.0.1:8643 must be up. It checks that the installed panfrost module contains the string "soft-stopping it to
resume": the tag's commit must contain e544ddb00 and the board's panfrost.ko md5 must equal the tag's module (dev_dbg strings are compiled out). If not, it writes BLOCKED and exits 2: report that, it is not a FAIL.
The fork Mesa must be at /root/opiz2-mesa/cl on the board (it is, deployed 2026-11-05; nothing to install).

DEV or TEST: TEST, about 55 min in 6 chunks of at most 15 min each (intops ~5, tdim ~7, math-a ~8, math-b ~8, reg ~7,
img3d up to 14.5). Chunks run the board under `timeout 870`; the host kills a chunk after 870 s without output.
Resumable: re-running the command skips the chunks listed in logs/runner-timeout-fix/state. The script restores the
stock kernel vmlinuz-7.3.1-edge-sunxi64 at the end and before every lock hand-over.

Results: harness/research/opencl-fixes/logs/runner-timeout-fix/: runner.log, chunk-<c>.txt, dmesg-<c>.txt,
files/<c>/{binaries.csv,results.csv,logs/} (copy of the board's /root/oclfix/tofix/opencl-mesa after each chunk; the
CSVs are cumulative, the copy after the last CTS chunk has every suite), BLOCKED (only when blocked).

Exit codes: 0 = all chunks ran, judge with the checks below; 2 = blocked (report BLOCKED and the last 10 lines of
runner.log); 1 = setup or lock error.

## Checks (mechanical)
1. runner.log contains `kernel fix: present` and a `kernel: ` line. Report the `kernel:` line (uname -v).
2. intops: in files/intops/binaries.csv the row starting `Integer Ops,` is `Integer Ops,Pass,0,PASSED 59 of 59 tests.`
   -> PASS. Anything else -> FAIL; report the row and the lines containing `FAILED` or `Verification failed` from
   files/intops/logs/Integer_Ops.log (first 10).
3. tdim: row `Thread Dimensions,Pass,0,PASSED 6 of 6 tests.` -> PASS; else FAIL, report the row.
4. math-a and math-b (chunk-math-a.txt, chunk-math-b.txt): the last `PASSED n of n` / `FAILED k of n` line of each.
   PASS if `grep -c "0xffffdead" chunk-math-*.txt` is 0 for both (no stale output buffers) AND the FAILED count k is
   0. If k > 0 but no `0xffffdead`: report as PARTIAL with k and the names of the failing functions (lines matching
   `^[a-z_0-9]+ FAILED`); these are the fp16 ULP cases still under investigation, not a regression. Report the lines
   `ERROR: ` (first 10 per chunk) in either case.
5. reg: in files/reg/binaries.csv every row for these suites has verdict `Pass`: Atomics, C11 Atomics, Half Ops,
   Relationals, Events, Buffers, Compiler, Select, Common Functions, Geometric Functions, Compute Info, Workgroups,
   Subgroups, Profiling, Printf, Device Partitioning, Mem (Host Flags), Images (API Info), Images (Kernel Methods).
   All Pass -> PASS. Any other verdict -> FAIL (regression), report that row.
6. img3d: row `Images (Kernel 3D int),Pass,...` -> PASS (it never finished before: Timeout after 5000 s). If
   chunk-img3d.txt has no ROUND-DONE or the row says `Timeout` -> NOT FINISHED (report, this is data not FAIL).
7. dmesg: `grep -c -E "gpu sched timeout|js fault|Soft-stop failed|Page fault|Unhandled" dmesg-*.txt` is 0 for every
   chunk -> PASS. Any hit -> FAIL, copy the lines exactly.
8. Every chunk-<c>.txt ends with `ROUND-DONE` and contains `CHUNK-RC 0` for intops/tdim/reg (clcts-run.py exit) ->
   note; for math chunks CHUNK-RC is the CTS exit code (non-zero when any function failed, see check 4).

The summary must list: the kernel line, the six per-chunk verdicts with the exact binaries.csv rows / PASSED-FAILED
lines, the Math failing function names if any, the dmesg counts per chunk, and the state file content.
