# OpenCL/GPU runner job softstop2: handoff

Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh softstop2`

Purpose: validate the kernel branch `fix/sunxi-panfrost-softstop-budget` (armbian-build worktree `wt-panfrost-softstop2`,
HEAD e17629bba = the third patch of the panfrost soft-stop/resume series on top of e544ddb00 and 0b7e3a208: 5 s soft-stop
budget as in Arm's kbase, hard stop of a job that does not stop, GPU reset only if that fails too, a soft-stopped job is
failed instead of resumed when the GPU was reset since, AS reference leak of the cancelled _NEXT jobs fixed). Analysis:
harness/research/impl-opencl-fixes.md section "Job 18 on c25: why the soft-stop failed (agent panfrost-softstop2)".

Precondition (coordinator): merge `fix/sunxi-panfrost-softstop-budget` (e17629bba) into `test-cumulative`, build the next
cumulative kernel and serve it as kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz. The script installs the NEWEST
cumulative tag (last line of kernel-check/cumulative-kernels.txt) via harness/research/vdec-perf/install-kernel.sh with the
one-shot fallback armed; the HTTP server on 10.56.0.1:8643 must be up. It checks that the kernel carries the fix: e17629bba
must be an ancestor of the tag's commit and the board's panfrost.ko md5 must equal the tag's module. If not, it writes
BLOCKED and exits 2: report that, it is not a FAIL. The fork Mesa must be at /root/opiz2-mesa/cl on the board with its
panvk (it is), and deqp-vk at /root/cts/deqp-vk. The board must start on the stock image kernel.

DEV or TEST: TEST, about 60-100 min in 9 chunks of at most 15 min each (stress ~5, vk ~3, vklong up to 14, intops up to 14,
tdim up to 14, math-a ~8, math-b ~8, reg ~7, img3d up to 14.5). Chunks run the board under `timeout 870`; the host kills a
chunk after 870 s without output. Resumable: re-running the command skips the chunks listed in
logs/runner-softstop2/state. The script restores the stock kernel vmlinuz-7.3.1-edge-sunxi64 at the end and before every
lock hand-over. Each chunk's board script first kills the previous chunk's leftover process group (exact pgid), then
clears ftrace and traces `panfrost_job_timedout` (one hit per 500 ms watchdog expiry = one soft-stop/resume cycle or
one reset). dmesg and the trace count are collected by the host AFTER the chunk, so a chunk that was cut off still has
dmesg-<c>.txt and trace-<c>.txt.

Fail fast: during every chunk the script watches harness/serial.log (new lines only) and afterwards the chunk's dmesg for
`Unable to handle|Oops|workqueue lockup|panfrost_dequeue_job`. On a hit it kills the chunk, writes the lines to
logs/runner-softstop2/OOPS, restores the stock kernel, releases and exits 3. Report FAIL (OOPS) with the content of OOPS
and the last 10 lines of runner.log; no further chunk runs. If the restore cannot reach the board, runner.log says
"BOARD UNREACHABLE" and BLOCKED is written too: report it (power-cycling is the coordinator's call, AGENT-RULES).

Results: harness/research/opencl-fixes/logs/runner-softstop2/: runner.log, chunk-<c>.txt (ends with the DMESG: and
TRACE: lines), dmesg-<c>.txt, trace-<c>.txt (`TRACE: TIMEDOUT n`), files/<c>/{binaries.csv,results.csv,logs/} (copy of
the board's /root/oclfix/softstop2/opencl-mesa after each chunk; the CSVs are cumulative, the copy after the last CTS
chunk has every suite), files/vk*/vklogs/ (deqp-vk logs), OOPS (only on an Oops), BLOCKED (only when blocked).

Exit codes: 0 = all chunks ran, judge with the checks below; 3 = Oops, FAIL (see above); 2 = blocked (report BLOCKED and
the last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical)
1. runner.log contains `kernel fix: present` and a `kernel: ` line. Report the `kernel:` line (uname -v).
2. dmesg (every chunk): `grep -c -E "gpu sched timeout|js fault|Soft-stop failed|Hard-stop failed|resetting the GPU|Page fault|Unhandled|Unable to handle|Oops|workqueue lockup|panfrost_dequeue_job|WARNING" dmesg-*.txt`
   is 0 for every chunk -> PASS. Any hit -> FAIL for that chunk, copy the lines exactly. (`Soft-stop failed after 5000 ms`
   = a job did not reach a task boundary in 5 s and was hard-stopped, i.e. failed with an error; `resetting the GPU` = the
   hard stop did not take effect either. Both are data for the fix agent.) Also report, per chunk, the `TRACE: TIMEDOUT n`
   line of trace-<c>.txt (n = 500 ms watchdog hits; `?` means ftrace was unavailable, report TRACE-OFF if chunk-<c>.txt
   says so).
3. stress (chunk-stress.txt): PASS when both `INTOPS 1:` and `INTOPS 2:` blocks contain `PASSED 2 of 2 tests.` and the
   `TDIM:` block contains `PASSED test.` (or `PASSED 1 of 1 tests.`). Else FAIL: report every INTOPS/TDIM line with
   FAILED or Verification failed or ERROR. Report the `t=` times of the INTOPS/TDIM lines.
4. vk (chunk-vk.txt, 10 `VK ` lines): all `rc=0` and `result=[  Pass` -> PASS. A line with rc=124 -> NOT FINISHED for that
   case (data). Any other rc or a result other than Pass, or `Incomplete job`/`DEVICE_LOST` in msg=[] -> FAIL; copy the
   line. Report all 10 lines' rc and t=.
5. vklong (chunk-vklong.txt, 2 `VK ` lines, 400 s each): same rule as check 4. rc=124 here means the count64 fragment job
   did not finish in 400 s even with resume: NOT FINISHED (data), report the line and the chunk's TIMEDOUT count and
   dmesg count.
6. intops: in files/intops/binaries.csv the row starting `Integer Ops,` is `Integer Ops,Pass,0,PASSED 59 of 59 tests.`
   -> PASS. `Timeout` in the row -> NOT FINISHED (data): report the row, the last 3 `integer_` lines of
   files/intops/logs/Integer_Ops.log and the chunk's TIMEDOUT count. Anything else -> FAIL; report the row and the lines
   containing `FAILED` or `Verification failed` from files/intops/logs/Integer_Ops.log (first 10).
7. tdim (chunk-tdim.txt): both `TDIM: quick_2d passed` and `TDIM: quick_3d passed` present and `TDIM-RC 0` -> PASS.
   `TDIM-RC 124` -> NOT FINISHED (data, report the TDIM: lines). Any `failed`/`FAILED`/`ERROR` TDIM line -> FAIL, copy it.
8. math-a and math-b (chunk-math-a.txt, chunk-math-b.txt): the last `PASSED n of n` / `FAILED k of n` line of each.
   k = 0 -> PASS. Otherwise count S = `grep -c -E "0xffffdead|at index: 0" chunk-math-<x>.txt` (stale output buffers) and
   take T from trace-math-<x>.txt:
   - S > 0 and T = 0 -> MESA-RACE (not a kernel verdict): the known rusticl multi-queue race of the default multi-threaded
     Math run (impl-opencl-fixes.md section 7); report k, S and the failing function names (lines `^[a-z_0-9]+ FAILED`).
   - S > 0 and T > 0 -> FAIL (stale buffers with watchdog hits in the same chunk; the fix agent separates them).
   - S = 0 and k > 0 -> PARTIAL: the fp16 ULP cases still under investigation; report k and the names.
   In every case report the first 10 `ERROR: ` lines of the chunk. A chunk whose only ERROR line says
   `did not match any test names` is a package bug: report it as PACKAGE-BUG with the line.
9. reg: in files/reg/binaries.csv every row for these suites has verdict `Pass`: Atomics, C11 Atomics, Half Ops,
   Relationals, Events, Buffers, Compiler, Select, Common Functions, Geometric Functions, Compute Info, Workgroups,
   Subgroups, Profiling, Printf, Device Partitioning, Mem (Host Flags), Images (API Info), Images (Kernel Methods).
   All Pass -> PASS. Any other verdict -> FAIL (regression), report that row.
10. img3d: row `Images (Kernel 3D int),Pass,...` -> PASS (it never finished before). `Timeout` in the row or no ROUND-DONE
    -> NOT FINISHED (data, report the row and the TIMEDOUT count).
11. Every chunk-<c>.txt ends with `ROUND-DONE` (after the DMESG:/TRACE: lines) -> note; `CUT-OFF` -> report which chunk
    and its last 5 non-DMESG lines. `LEFTOVER pgid ... killed` lines -> report (the previous chunk left a process behind).

The summary must list: the kernel line, the nine per-chunk verdicts with the exact binaries.csv rows / PASSED-FAILED /
VK lines, the INTOPS/TDIM times, the Math failing function names if any, the dmesg counts and TIMEDOUT counts per chunk,
the state file content, and OOPS verbatim if it exists.
