# GPU INSTR_INVALID_ENC runner job (invalid-enc): handoff

Command: `bash harness/research/gpu-invalid-enc/runner/invalid-enc.sh`

Purpose: board check of two Mesa fork fixes for the Mali-G31 "js fault ... status=INSTR_INVALID_ENC" faults of jobs 14
(Vulkan subgroup ballot/elect/vote) and 09 (OpenCL samplerless float CL_A UNORM_INT8 1Dbuffer), fork
`panfrost-opencl-fixes` (mesa-work/mesa-cl) HEAD 0e274280595: ab1caa7378f (ballot built from 4 CLPER_OLD reads instead
of WMASK on G31) and 0e274280595 (no A8_UNORM texel buffers, so rusticl stops offering CL_A UNORM_INT8 1D-buffer
images). The cross build is done (mesa-work/build-cl); the script deploys it as `/root/opiz2-mesa/vk2` (system Mesa and
/root/opiz2-mesa/vk1, cl* untouched) and checks the md5 of libvulkan_panfrost.so. It copies vkcomp + the 8 diag shaders
(from harness/research/vk-hangs/host/) to `/root/invenc/`. Analysis: harness/research/vk-hangs/RESULTS.md.

Kernel: the script installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt; c38 or later)
via harness/research/vdec-perf/install-kernel.sh with the one-shot fallback armed (HTTP server 10.56.0.1:8643 must be
up); the tag must contain e544ddb00, otherwise exit 1 before touching the board. The board must be on the stock image
kernel (vmlinuz-7.3.1-edge-sunxi64) at the start, otherwise BLOCKED. The stock kernel is restored at the end and
before every lock hand-over; `uname -v` is recorded. No kernel change in this job.

DEV or TEST: TEST, about 30 min in 9 chunks of at most 15 min (diag ~2, cases-sg ~3, sl ~2, subset1-4 together ~5-10,
ocl ~5, gles ~3), plus ~3 min per install/restore reboot pair. Every chunk runs under `timeout 870` on the board; the
host stall watchdog kills a chunk after 870 s without output. Resumable: re-running the command skips the chunks in
logs/runner/state (delete a line to rerun that chunk). Lock hand-over between chunks when another session waits.
`bash ... invalid-enc.sh --print` prints the board scripts without touching the board.

Results: harness/research/gpu-invalid-enc/logs/runner/: runner.log, chunk-<c>.txt, dmesg-<c>.txt, files/diag/trace.tgz,
files/cases-sg/<case>.{txt,qpa}, files/sl/{binaries.csv,results.csv,logs/}, files/subset<N>/{results.csv,cmp.txt},
files/ocl/, files/gles/, BLOCKED (only when blocked).

Exit codes: 0 = all chunks ran, judge with the checks; 2 = blocked (report BLOCKED + last 10 lines of runner.log);
1 = setup or lock error (report the last 10 lines of runner.log).

## Checks (mechanical)
1. runner.log has `fork: ` (with `contains 0e274280595`), `kernel fix: present`, `deployed vk2 ok`, a `kernel: ` line,
   a `usage:` line, and its last `restored: ` line mentions `7.3.1-edge-sunxi64`. Report the six lines.
2. diag (chunk-diag.txt): 24 lines starting `DIAG fork-`. OK = `rc=0` and `excs=[...]` holds only `x0x1` entries.
   All 24 OK -> 2a PASS, else FAIL with the not-OK tags and their `DMESG <tag>:` lines. 2b values: `out=[...]` must be
   exactly (16 numbers each):
   - fork-d1-plain-*, fork-d4-shared-*, fork-d5-ids-*, fork-d6-broadcast-*: identical to the same tag in
     harness/runner-queue/done/14-vk-hangs.summary.md (compare the out=[...] text);
   - fork-d2-ballot-1x1x1: sixteen `1`; fork-d2-ballot-4x1x1: sixteen `15`;
   - fork-d3-elect-1x1x1: sixteen `42`; fork-d3-elect-4x1x1: `42 13 13 13` four times;
   - fork-d7-vote-1x1x1: sixteen `7`; fork-d7-vote-4x1x1: sixteen `5`;
   - fork-d2/d3/d7-*-3x5x7 and fork-d8-*: data only (report them).
   All listed values match -> 2b PASS, else FAIL with the differing lines. Report all 24 DIAG lines.
3. cases-sg: 9 `CASE ` lines; each `result=[ Pass ...]` -> PASS for that case; anything else -> FAIL, report the CASE
   line and its `DMESG <case>:` lines. Report all 9 lines.
4. sl: files/sl/binaries.csv rows `Images (Samplerless int)`, `(Samplerless uint)`, `(Samplerless float)` all `Pass`
   -> PASS; else FAIL with the `FAILED` lines of files/sl/logs/<suite>.log (first 10).
5. subset1-4: the last files/subset<N>/cmp.txt starts with `NEW cases 5225:` and has `REGRESSIONS: 0` -> 5a PASS; any
   `REGRESSIONS: n>0` -> FAIL with the `  REG ` lines. 5b: `grep -c '^  STILL dEQP-VK.subgroups' cmp.txt` is 0 -> PASS,
   else FAIL with those lines. Report the `NEW cases` line, the FIXED count and its `  FIX ` lines, and all `  STILL `
   lines. No `SUBSET-COMPLETE` in any subset chunk -> NOT FINISHED with the last `SUBSET-INCOMPLETE` line.
6. ocl: files/ocl/binaries.csv rows Atomics, C11 Atomics, Half Ops, Relationals, Compute Info, Workgroups, Subgroups,
   Select all `Pass` -> PASS, else FAIL with the row and the first 10 `FAILED` lines of its log.
7. gles: files/gles/summary.txt reads `556 cases` and `Pass 556` -> PASS; else FAIL with the non-Pass rows (first 20).
8. dmesg: `grep -c INSTR_INVALID_ENC dmesg-<c>.txt` is 0 for EVERY chunk -> 8a PASS (this is the main result), else
   FAIL with the lines. 8b: `grep -c -E "js fault|Soft-stop failed|Page fault|Unhandled" dmesg-<c>.txt` for subset*,
   sl, ocl, gles is 0 -> PASS, else FAIL with the lines. Report both counts and `grep -c "gpu sched timeout"` per chunk.
9. Every chunk-<c>.txt ends with `ROUND-DONE`; a chunk with `STALLED` or without it is NOT FINISHED: delete its line
   from logs/runner/state and rerun the command once; still not finished -> report NOT FINISHED with its last 10 lines.

The summary must list: the six lines of check 1, the 24 DIAG lines with the 2a/2b verdicts, the 9 CASE lines, the sl
rows, the cmp.txt lines of check 5, the ocl rows, the gles summary, the dmesg counts per chunk, and the state file.
