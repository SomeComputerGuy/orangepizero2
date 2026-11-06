# panfrost BO mapping under memcg pressure (job 63): handoff

Command: `bash harness/research/panfrost-map-enomem/runner/map-enomem.sh`

Purpose: the 2 dEQP-GLES31 draw_indirect compute_interop large drawelements 1000x1000 cases hit the memcg limit of
the CTS queue (600M); on the stock kernel #17 that printed `WARNING ... panfrost_mmu.c:478 at panfrost_mmu_map+0xcc`
5 times. The newest cumulative kernel (c48 or later) carries da59f9208 (no WARN when the pages cannot be allocated)
and a524d09da (fix/sunxi-panfrost-mmu-map-enomem: a failed map/heap-growth unwinds cleanly). This job runs the 2 cases
in 6 rounds under MemoryMax 600M (x3), 450M, 500M, 700M, checks the GPU still works after each round, then a short
GLES 3.1 + OpenCL regression subset. Analysis: harness/research/panfrost-map-enomem/RESULTS.md.

Kernel: the script installs the newest cumulative tag (kernel-check/cumulative-kernels.txt; it must contain
a524d09da) with the one-shot fallback armed, checks the Image md5 and that the board's panfrost.ko is that tag's
module, and restores the stock kernel (vdec-perf/restore-kernel.sh: Image, DTB, modules) at the end, before a lock
hand-over and when blocked. The board must be on the stock kernel at start. Mesa: GLES chunks use the system Mesa
(as the CTS queue did); the ocl chunk uses the fork build mesa-work/build-cl, deployed by the script to
/root/opiz2-mesa/pme (md5 checked; system Mesa untouched). Do not build anything yourself.

Precondition: the board has /root/cts/deqp-gles (glcts, gles31, deqp-run.py), /root/cts/lib and /root/cts/opencl-cts.

DEV or TEST: TEST, about 25-35 min plus two reboots: chunks oom (~5 min), gles31-di, gles31-compute, khr-compute,
ocl (~2 min each by the baselines, at most 15 min each: board `timeout 870`; the host kills a chunk after 870 s
without output). Resumable: re-running the command skips the chunks listed in logs/runner/state (delete a line to
rerun that chunk). `--print` prints the board scripts.

Results: harness/research/panfrost-map-enomem/logs/runner/: runner.log, state, chunk-<c>.txt, dmesg-<c>.txt
(filtered), rounds-oom.txt, compare-<c>.txt (last line `SUMMARY ...`), files/<c>/ (results.csv, dmesg-<c>.full = the
complete dmesg of the chunk, per-round oom-<tag>/ and oom-<tag>.log), BLOCKED (only when blocked).

Exit codes: 0 = all chunks ran, judge with the checks; 2 = blocked (report BLOCKED and the last 10 lines of
runner.log); 1 = setup or lock error (report the last 10 lines of runner.log).

## Checks (mechanical)
1. runner.log has a `kernel: ` line with `#48` or a later number, `kernel fix: present` and `deployed pme ok`.
   Report the three lines. Missing one -> BLOCKED.
2. WARN/oops (the main result): `grep -c -E "WARNING|cut here|Oops|BUG:|Unable to handle|refcount_t" files/*/dmesg-*.full`
   is 0 for EVERY chunk -> PASS. Any hit -> FAIL: copy the hit lines and the 30 lines after the first hit exactly
   (`grep -A30 -m1 -E "WARNING|cut here|Oops|BUG:|Unable to handle|refcount_t" files/<c>/dmesg-<c>.full`).
3. No hang: rounds-oom.txt has 6 `ROUND ` lines (600M-1, 600M-2, 600M-3, 450M, 500M, 700M), chunk-oom.txt has no
   `HANG ` line, and every ROUND line has `rows=2` -> PASS. Otherwise FAIL: report the ROUND/HANG lines.
   No ROUND line contains `Timeout` and no ROUND line has `rc=124` -> PASS, else FAIL with the line. Other statuses
   (Pass, Fail, OOM, Crash, DeviceLost, ResourceError, ...) are data: Mesa may abort after an err=12, which is the
   error reaching userspace. Report all 6 ROUND lines verbatim.
4. Exercised: at least one ROUND line shows `OOM` or `err12=` > 0, or `grep -c "Memory cgroup out of memory"
   files/oom/dmesg-oom.full` > 0 -> EXERCISED; else report NOT EXERCISED (not a FAIL; the limit was not reached).
   Report the count.
5. GPU alive after each round: rounds-oom.txt has 6 `GPU-ALIVE ` lines, each containing
   `ubo_to_ssbo_single_invocation,Pass` -> PASS; else FAIL with the line.
6. gles31-di, gles31-compute, khr-compute: compare-<c>.txt last line has `REGRESSIONS=0` and `MISSING=0` -> PASS.
   Otherwise FAIL: report every `REGRESSION` and `MISSING` line (first 20). Report the SUMMARY line of each and its
   FIXED/CHANGED lines (gles31-di may show FIXED for the 2 drawcount_5000 cases: no memcg limit there).
7. ocl: files/ocl/binaries.csv rows Atomics, C11 Atomics, Half Ops, Compute Info, Workgroups, Subgroups, Select all
   `Pass` -> PASS, else FAIL with the row and the first 10 `FAILED` lines of its log (files/ocl/logs/<suite>.log).
8. dmesg of the regression chunks: `grep -c -E "js fault|Page fault|Unhandled|gpu sched timeout|Hard-stop"
   dmesg-<c>.txt` for gles31-di, gles31-compute, khr-compute, ocl is 0 -> PASS, else FAIL with the lines. For the oom
   chunk report the same count and `grep -c -E "oom-kill|Killed process" dmesg-oom.txt` as data only (a heap that
   cannot grow under the limit may fault the job; that is the error reaching userspace, not a failure).
9. Every chunk-<c>.txt ends with `ROUND-DONE`; a chunk with `STALLED` or without it is NOT FINISHED: delete its line
   from logs/runner/state and rerun the command once; still not finished -> report NOT FINISHED with its last 10 lines.
10. runner.log has a `restored: ` line with `vmlinuz-7.3.1-edge-sunxi64` after the last chunk -> PASS; report it.

The summary must list: the lines of check 1, the check 2 counts per chunk (and hit lines), the 6 ROUND and 6
GPU-ALIVE lines, the check 4 count, the SUMMARY line of each GLES chunk with REGRESSION/FIXED/CHANGED lines, the ocl
rows, the check 8 counts per chunk, the restored line and the state file content.
