# OpenCL runner job timeout-fix: handoff

Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh timeout-fix`

Purpose: validate the kernel fix branch `fix/sunxi-panfrost-softstop-resume` (armbian-build worktree `wt-panfrost-softstop`,
two commits: e544ddb00 drm/panfrost resumes a still-active job after the 500 ms watchdog instead of resetting the GPU, and
0b7e3a208 on top, which waits for the soft-stopped slots on the live JS_STATUS and fixes the NULL dereference in
panfrost_dequeue_job that e544ddb00 alone produced on cumulative kernel c14) with a soft-stop stress chunk, the
OpenCL-CTS suites that lost work to the reset, and a regression subset. Analysis: harness/research/impl-opencl-fixes.md
section "Root cause: panfrost job timeout" (sub-section "Oops on c14 and the follow-up 0b7e3a208").

Precondition (coordinator): merge `fix/sunxi-panfrost-softstop-resume` at 0b7e3a208 into `test-cumulative`, build the next
cumulative kernel (c18 or later; c17 = 7897dec08 has only e544ddb00 and is refused) and serve it as
kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz (as for c9/c10). The script installs the NEWEST cumulative tag
(last line of kernel-check/cumulative-kernels.txt) via harness/research/vdec-perf/install-kernel.sh with the one-shot
fallback armed, like the vdec jobs; the HTTP server on 10.56.0.1:8643 must be up. It checks that the kernel carries the
whole fix: 0b7e3a208 must be an ancestor of the tag's commit and the board's panfrost.ko md5 must equal the tag's module
(dev_dbg strings are compiled out). If not, it writes BLOCKED and exits 2: report that, it is not a FAIL.
The fork Mesa must be at /root/opiz2-mesa/cl on the board with its panvk (it is, deployed 2026-11-05; nothing to install),
and deqp-vk at /root/cts/deqp-vk.

DEV or TEST: TEST, about 65 min in 7 chunks of at most 15 min each (stress ~8-10, intops ~5, tdim ~7, math-a ~8, math-b ~8,
reg ~7, img3d up to 14.5). Chunks run the board under `timeout 870`; the host kills a chunk after 870 s without output.
Resumable: re-running the command skips the chunks listed in logs/runner-timeout-fix/state. The script restores the
stock kernel vmlinuz-7.3.1-edge-sunxi64 at the end and before every lock hand-over.

Fail fast: during every chunk the script watches harness/serial.log (new lines only) and afterwards the chunk's dmesg for
`Unable to handle|Oops|workqueue lockup|panfrost_dequeue_job`. On a hit it kills the chunk, writes the lines to
logs/runner-timeout-fix/OOPS, restores the stock kernel, releases and exits 3. Report FAIL (OOPS) with the content of OOPS
and the last 10 lines of runner.log; no further chunk runs. If the restore cannot reach the board, runner.log says
"BOARD UNREACHABLE" and BLOCKED is written too: report it (power-cycling is the coordinator's call, AGENT-RULES).

Results: harness/research/opencl-fixes/logs/runner-timeout-fix/: runner.log, chunk-<c>.txt, dmesg-<c>.txt,
files/<c>/{binaries.csv,results.csv,logs/} (copy of the board's /root/oclfix/tofix/opencl-mesa after each chunk; the
CSVs are cumulative, the copy after the last CTS chunk has every suite), files/stress/vklogs/ (deqp-vk logs), OOPS (only
on an Oops), BLOCKED (only when blocked).

Exit codes: 0 = all chunks ran, judge with the checks below; 3 = Oops, FAIL (see above); 2 = blocked (report BLOCKED and
the last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical)
1. runner.log contains `kernel fix: present` and a `kernel: ` line. Report the `kernel:` line (uname -v).
2. stress (chunk-stress.txt): PASS when all of: both `INTOPS 1:` and `INTOPS 2:` blocks contain `PASSED 2 of 2 tests.`;
   the `TDIM:` block contains `PASSED 1 of 1 tests.`; all 14 `VK ` lines have `rc=0` and `result=[  Pass`; `grep -c
   "Incomplete job" chunk-stress.txt` is 0. Else FAIL: report every INTOPS/TDIM line with FAILED or Verification failed
   and every VK line without rc=0 (first 10). Report the `t=` times of the INTOPS/TDIM lines (they show the long jobs
   ran, 500 ms watchdog soft-stops and all).
3. intops: in files/intops/binaries.csv the row starting `Integer Ops,` is `Integer Ops,Pass,0,PASSED 59 of 59 tests.`
   -> PASS. Anything else -> FAIL; report the row and the lines containing `FAILED` or `Verification failed` from
   files/intops/logs/Integer_Ops.log (first 10).
4. tdim: row `Thread Dimensions,Pass,0,PASSED 6 of 6 tests.` -> PASS; else FAIL, report the row.
5. math-a and math-b (chunk-math-a.txt, chunk-math-b.txt): the last `PASSED n of n` / `FAILED k of n` line of each.
   PASS if `grep -c "0xffffdead" chunk-math-*.txt` is 0 for both (no stale output buffers) AND the FAILED count k is
   0. If k > 0 but no `0xffffdead`: report as PARTIAL with k and the names of the failing functions (lines matching
   `^[a-z_0-9]+ FAILED`); these are the fp16 ULP cases still under investigation, not a regression. Report the lines
   `ERROR: ` (first 10 per chunk) in either case.
6. reg: in files/reg/binaries.csv every row for these suites has verdict `Pass`: Atomics, C11 Atomics, Half Ops,
   Relationals, Events, Buffers, Compiler, Select, Common Functions, Geometric Functions, Compute Info, Workgroups,
   Subgroups, Profiling, Printf, Device Partitioning, Mem (Host Flags), Images (API Info), Images (Kernel Methods).
   All Pass -> PASS. Any other verdict -> FAIL (regression), report that row.
7. img3d: row `Images (Kernel 3D int),Pass,...` -> PASS (it never finished before: Timeout after 5000 s). If
   chunk-img3d.txt has no ROUND-DONE or the row says `Timeout` -> NOT FINISHED (report, this is data not FAIL).
8. dmesg: `grep -c -E "gpu sched timeout|js fault|Soft-stop failed|Page fault|Unhandled|Unable to handle|Oops|workqueue lockup|panfrost_dequeue_job|WARNING" dmesg-*.txt`
   is 0 for every chunk -> PASS. Any hit -> FAIL, copy the lines exactly. (`Soft-stop failed` means a job did not stop
   within 100 ms and was reset: report it as FAIL with the line, it is data for the fix agent.)
9. Every chunk-<c>.txt ends with `ROUND-DONE` and contains `CHUNK-RC 0` for stress/intops/tdim/reg (clcts-run.py exit)
   -> note; for math chunks CHUNK-RC is the CTS exit code (non-zero when any function failed, see check 5).

The summary must list: the kernel line, the seven per-chunk verdicts with the exact binaries.csv rows / PASSED-FAILED /
VK lines, the INTOPS/TDIM times, the Math failing function names if any, the dmesg counts per chunk, the state file
content, and OOPS verbatim if it exists.
