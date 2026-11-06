# OpenCL/GPU runner job img3d (runner job 45): handoff

Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh img3d`

Purpose: job 28 (c27) saw one GPU page fault during the OpenCL-CTS 3D image read of format CL_RGB CL_SIGNED_INT32
(`Unhandled Page fault in AS0 at VA 0x000000000B2F8000`, `js fault, js=1, status=JOB_BUS_FAULT`, no job timeout before
it). This job repeats that format (and the two other 96-bit RGB formats, and a 128-bit control) on a kernel whose fault
report now names the BOs around the faulting address (`fault bo:` lines, commit fa9d166f6 on
fix/sunxi-panfrost-fault-bo-info), so the next agent can see which buffer was overrun. It also reruns Thread Dimensions
quick tests under their real names (job 28's tdim chunk was a package bug). Analysis: harness/research/impl-opencl-fixes.md
section "Job 28 on c27".

Kernel: the script installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt, c38 or later) via
harness/research/vdec-perf/install-kernel.sh with the one-shot fallback armed (HTTP server on 10.56.0.1:8643 must be up).
fa9d166f6 must be an ancestor of the tag's commit and the board's panfrost.ko md5 must equal the tag's module, else it
writes BLOCKED and exits 2 (report BLOCKED, not FAIL). Mesa: the fork at /root/opiz2-mesa/cl (same as job 28). The board
must start on the stock image kernel. It restores vmlinuz-7.3.1-edge-sunxi64 at the end and before every lock hand-over.

DEV or TEST: TEST, about 30-120 min in 10 chunks of at most 14.5 min each (tdim2, tdim3, s32-1..s32-4, u32-1, u32-2,
f32-1, ctl). Board side `timeout 870` per chunk, the host kills a chunk after 870 s without output (stall watchdog).
Resumable: re-running the command skips the chunks listed in logs/runner-img3d/state. Fail fast on an Oops (exit 3) as in
HANDOFF.md.

Results: harness/research/opencl-fixes/logs/runner-img3d/: runner.log, chunk-<c>.txt (ends with the DMESG: and TRACE:
lines), dmesg-<c>.txt, trace-<c>.txt, files/<c>/<c>.log (full CTS log of the image chunks), OOPS / BLOCKED if any.

Exit codes: 0 = all chunks ran, judge with the checks; 3 = Oops (FAIL, report OOPS verbatim + last 10 lines of runner.log);
2 = blocked (report BLOCKED + last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical)
1. runner.log contains `kernel fix: present` and a `kernel: ` line. Report the `kernel:` line.
2. Per chunk: F = `grep -c "Unhandled Page fault" dmesg-<c>.txt`. Report F for every chunk. If F > 0 for any chunk, copy
   that chunk's dmesg-<c>.txt VERBATIM into the summary (all lines: the Reason/raw fault status/access type/source id lines
   and the `fault bo:` lines are what the next agent needs). Also report every other dmesg line of any chunk that contains
   `js fault`, `gpu sched timeout`, `Soft-stop`, `Hard-stop`, `resetting the GPU`, `Purging` or `WARNING`.
3. Image chunks s32-1..s32-4, u32-1, u32-2, f32-1, ctl (chunk-<c>.txt): the `IMG-RC n t=..s` line and every `IMG:` line.
   Verdict per chunk: `IMG-RC 0` and an `IMG: PASSED` line and no `IMG: FAILED` line and F = 0 -> PASS. F > 0 -> FAULT.
   `IMG-RC 124` -> NOT FINISHED (report t=). Otherwise FAIL (copy the IMG: lines).
4. tdim2 / tdim3 (chunk-<c>.txt): `TDIM-RC 0` and every `TDIM: quick_...` result line says `passed` -> PASS. `TDIM-RC 124`
   -> NOT FINISHED (report the TDIM: lines). A `did not match any test names` line -> PACKAGE-BUG (copy it). Anything
   else -> FAIL (copy the TDIM: lines).
5. TRACE: report the `TRACE: TIMEDOUT n` line of every chunk.
6. Every chunk-<c>.txt has `ROUND-DONE`; `CUT-OFF` -> report the chunk and its last 5 non-DMESG lines; `LEFTOVER pgid`
   lines -> report.

Overall: PASS if every chunk is PASS; FAULT if any chunk is FAULT (that is the data this job exists for, not a runner
problem); else FAIL / NOT FINISHED as found. The summary must list: kernel line, the 10 per-chunk verdicts with IMG-RC /
TDIM-RC, t= and F, the verbatim dmesg of every faulting chunk, the TIMEDOUT counts, and the state file content.
