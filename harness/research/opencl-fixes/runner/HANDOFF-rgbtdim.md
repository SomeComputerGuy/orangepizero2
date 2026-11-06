# OpenCL/GPU runner job rgbtdim (runner job 46): handoff

Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh rgbtdim`

Purpose: (1) A/B the Mesa fork fix 02df5721016 "pan/layout: leave a cache line of slack after 24/96-bit images" against
the CL_RGB GPU page faults (job 09 f2d-r2da: `Unhandled Page fault in AS0 at VA 0x000000000A016000`, JOB_BUS_FAULT; job 28
img3d: VA 0xB2F8000). `board/t_rgbedge.py` reads the last texel of 6 MiB linear RGB images whose data ends on a 2 MiB
boundary, so nothing is mapped right after the image BO: A = old build /root/opiz2-mesa/cl2 (dc7266d584b, job 09),
B = new build /root/opiz2-mesa/cl3 (deployed by the script). Then the CTS 2Darray RGB8 reads A/B and the 3D RGB32I read on
B. (2) Thread Dimensions quick 2D x3 and quick 3D with gpu_scheduler run/done tracepoints and a progress line per minute
(job 45: one lost job in tdim2, tdim3 cut at 800 s). Analysis: harness/research/impl-opencl-fixes.md section
"Job 45 / job 09 RGB faults and tdim".

Kernel: the script installs the NEWEST cumulative tag (c38 or later) via harness/research/vdec-perf/install-kernel.sh with
the one-shot fallback armed (HTTP server on 10.56.0.1:8643 must be up); fa9d166f6 (fault BO names) must be in it, else
BLOCKED (exit 2). The board must start on the stock image kernel; it restores vmlinuz-7.3.1-edge-sunxi64 at the end and
before every lock hand-over. Mesa: needs /root/opiz2-mesa/cl2 (deployed by job 09) on the board; deploys cl3 itself from
mesa-work/build-cl (must contain 02df5721016, checked on the host).

DEV or TEST: TEST, about 1.5-2.5 h in 12 chunks: edgeA edgeB edgeA2 edgeB2 (~2 min each), ctsA ctsB ctsA2 ctsB2 (2 x up
to 400 s each), s32B (up to 800 s), tdim2x (3 x up to 400 s), tdim3e and tdim3i (up to 1800 s each, board limit 1900 s;
the host stall watchdog is the same limit, PROG lines come every 60 s). Others: `timeout 870`. Resumable: re-running the
command skips the chunks listed in logs/runner-rgbtdim/state. Fail fast on an Oops (exit 3) as in HANDOFF.md.

Results: harness/research/opencl-fixes/logs/runner-rgbtdim/: runner.log, chunk-<c>.txt, dmesg-<c>.txt,
files/<c>/ (edge: <case>-A.log / <case>-B.log; cts: <c>-CL_*.log; s32B.log; tdim: tdim-<i>-<test>.log, tdim-trace.txt.gz).

Exit codes: 0 = all chunks ran, judge with the checks; 3 = Oops (report OOPS verbatim + last 10 lines of runner.log);
2 = blocked (report BLOCKED + last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical)
1. runner.log has `kernel fix: present`, a `kernel: ` line and `deployed cl3 ok`. Report the kernel line and the
   `deployed cl3 ok` line.
2. edgeA, edgeB, edgeA2, edgeB2: report every `EDGE <A|B> <case> RC n FAULTS n` line (6 cases per chunk: rgb8 rgb32i
   rgba8 rgba32i rgb8s rgb32is) as a table, and copy every `EDGE ... DMESG:` line VERBATIM. Also report any
   `EDGE ...: RESULT` line whose `stored` is not `64 of 64`, and any line with `Error` or `assert`.
3. ctsA, ctsB, ctsA2, ctsB2: report every `RGBCTS <c> <type> RC n t=..s FAULTS n` line and every `RGBCTS ...: FAILED`
   line. Per line: RC 0 and FAULTS 0 and a `PASSED` line and no `FAILED` -> PASS; FAULTS > 0 -> FAULT; RC 124 -> NOT
   FINISHED; else FAIL.
4. s32B: `IMG-RC` line and the `IMG:` lines; F = `grep -c "Unhandled Page fault" dmesg-s32B.txt`. IMG-RC 0, IMG: PASSED,
   no IMG: FAILED, F = 0 -> PASS; F > 0 -> FAULT; IMG-RC 124 -> NOT FINISHED; else FAIL.
5. tdim2x, tdim3e, tdim3i: report every `TDIM <i> <test> RC n t=..s` line with its `TDIM <i> <test>:` lines, every
   `PROG` line, and the `TDIM-TRACE` line. Per test: RC 0 and a `passed` line -> PASS; RC 124 -> NOT FINISHED; else FAIL.
   Copy every `gpu sched timeout` / `Soft-stop` / `Hard-stop` / `resetting` line of dmesg-<c>.txt verbatim.
6. Every chunk-<c>.txt has `ROUND-DONE`; a `CUT-OFF` -> report the chunk and its last 5 non-DMESG lines.

Verdicts (mechanical, all of them go in the summary):
- RGB-OVERFETCH: CONFIRMED if edgeA or edgeA2 has FAULTS > 0 for rgb8 or rgb32i AND edgeB and edgeB2 have FAULTS 0 for
  all cases; NOT REPRODUCED if edgeA and edgeA2 have FAULTS 0 for every case; otherwise MIXED (list the cases).
- RGB-FIX: PASS if edgeB, edgeB2, ctsB, ctsB2 and s32B are all FAULTS 0 / F 0 and ctsB, ctsB2, s32B are PASS; else FAIL.
- TDIM: PASS if all 5 tests PASS; else list per test.
The summary must list: kernel line, the EDGE table, the verbatim EDGE DMESG lines, the RGBCTS and s32B verdicts, the TDIM
lines with PROG/TDIM-TRACE lines, the dmesg lines of check 5, the three verdicts, and the state file content.
