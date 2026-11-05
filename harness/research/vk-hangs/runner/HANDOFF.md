# Vulkan hangs runner job (vk-hangs): handoff

Command: `bash harness/research/vk-hangs/runner/vk-hangs.sh`

Purpose: board data for the Vulkan "Incomplete job or timeout" cases of impl-gpu-spec.md 4c
(`dEQP-VK.subgroups.basic.compute.subgroupelect`, the ballot_broadcast cases, 7 `spirv_assembly.type.vec4.*_frag`), with
the fork `panfrost-opencl-fixes` (mesa-work/mesa-cl, HEAD a516f2c3ddc; b7a705442bd = CLPER_OLD for read_invocation on the
G31) deployed side by side as `/root/opiz2-mesa/vk1` (system Mesa and `/root/opiz2-mesa/cl*` untouched), plus a Vulkan
subset regression, an OpenCL and a GLES regression chunk. Analysis: harness/research/vk-hangs/RESULTS.md. The cross
build is done (mesa-work/build-cl); the script deploys it (rsync of a stripped staging copy) and checks the md5 of
libvulkan_panfrost.so. It also copies a small Vulkan compute runner (`vkcomp`, aarch64) and 8 SPIR-V diagnostic shaders to
`/root/vkhangs/`.

Kernel: the script installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt, served as
kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz) via harness/research/vdec-perf/install-kernel.sh with the
one-shot fallback armed, exactly like harness/research/opencl-fixes/runner/ocl-job.sh; the HTTP server on
10.56.0.1:8643 must be up. The tag must carry the panfrost soft-stop/resume patch e544ddb00 (c15 or later: the 7 frag
cases are long jobs that the stock 500 ms watchdog kills); if it does not, the script exits 1 before touching the board
(report "package not ready: kernel lacks e544ddb00"). The board must be on the stock image kernel
(vmlinuz-7.3.1-edge-sunxi64) when the job starts, otherwise BLOCKED. The stock kernel is restored at the end and
before every lock hand-over; `uname -v` is recorded. It must not run at the same time as another board job (the
lock takes care of that).

DEV or TEST: TEST, about 40 min in 10 chunks of at most 15 min (diag ~3, cases-sg ~2, cases-frag-a/-b ~2-12 each,
subset1-4 together ~5-10 (later subset chunks end at once when the run is complete), ocl ~5, gles ~3). Chunks run the
board command under `timeout 870`; the host kills a chunk after 870 s without output. Resumable: re-running the command
skips the chunks listed in logs/runner/state (delete a line to rerun that chunk). Between chunks the lock is handed
over when another session waits (stock kernel restored first, trial kernel reinstalled after). Add ~3 min per
install/restore reboot pair. `bash ... vk-hangs.sh --print` prints the board scripts without touching the board.

Results: harness/research/vk-hangs/logs/runner/: runner.log, chunk-<c>.txt, dmesg-<c>.txt, files/diag/trace.tgz
(pandecode traces of every diag run), files/cases-*/<case>.{txt,qpa}, files/subset4/{results.csv,summary.txt,cmp.txt}
(the subset copy after each subset chunk; the last one is complete), files/ocl/{binaries.csv,results.csv,logs/},
files/gles/{results.csv,summary.txt}, BLOCKED (only when blocked).

Exit codes: 0 = all chunks ran, judge with the checks below; 2 = blocked (report BLOCKED and the last 10 lines of
runner.log); 1 = setup or lock error (report the last 10 lines of runner.log).

## Checks (mechanical)
1. runner.log contains `fork: ` (must mention `contains b7a705442bd`), `kernel fix: present`, `deployed vk1 ok`, a
   `kernel: ` line (uname -v of the installed cumulative kernel) and a `usage:` line (vkcomp runs on the board), and
   its last `restored: ` line mentions `7.3.1-edge-sunxi64`. Report the six lines.
2. diag (chunk-diag.txt): 36 lines starting `DIAG `. A line is OK when it has `rc=0` and its `excs=[...]` contains only
   `x0x1` entries (every job header COMPLETE). Report the full table of the 36 lines as is (they are short), and for
   every line that is not OK also its `DMESG <tag>:` lines. The 12 `sys-*` lines are the system-Mesa baseline (8-wide
   subgroups on a 4-wide GPU: faults expected for d2/d3/d6): data, never FAIL. For the 24 `fork-*` lines: all OK ->
   PASS; otherwise FAIL-DIAG with the list of the not-OK tags (this is the result the next agent needs).
3. cases-sg (chunk-cases-sg.txt): 7 `CASE ` lines. `result=[  Pass ...]` -> PASS for that case; anything else -> report
   the whole CASE line and its `DMESG <case>:` lines. `subgroupsize_compute` passed before (control). Report all 7 lines.
4. cases-frag-a, cases-frag-b: 4 + 3 `CASE ` lines. `Pass` -> PASS, report `t=` of each. Not Pass -> FAIL for that case;
   report the CASE line and its DMESG lines. If `grep -c "gpu sched timeout" chunk-cases-frag-*.txt` is non-zero, add
   "kernel resets long jobs (soft-stop fix missing?)" with the `kernel:` line.
5. subset1-4: files/subset4/cmp.txt (or the last subset chunk that produced one) starts with `NEW cases 5225:` and has
   `REGRESSIONS: 0` -> PASS. `REGRESSIONS: n` with n>0 -> FAIL, copy the `  REG ` lines. Report the `NEW cases` line, the
   `FIXED:` count with its `  FIX ` lines, and the `STILL-NONPASS:` count with the first 20 `  STILL ` lines. If no
   subset chunk printed `SUBSET-COMPLETE`, report NOT FINISHED with the last `SUBSET-INCOMPLETE` line (cases done).
6. ocl: in files/ocl/binaries.csv every row for Atomics, C11 Atomics, Half Ops, Relationals, Compute Info, Workgroups,
   Subgroups, Select has verdict `Pass` -> PASS. Any other verdict -> FAIL (regression), report the row and the `FAILED`
   lines of its files/ocl/logs/<suite>.log (first 10).
7. gles: files/gles/summary.txt reads `556 cases` and `Pass 556` (nothing else but possibly NotSupported) -> PASS;
   any Fail/Crash/Timeout -> FAIL, copy the lines from files/gles/results.csv whose status is not Pass (first 20).
8. dmesg: for subset*, ocl, gles: `grep -c -E "js fault|Soft-stop failed|Page fault|Unhandled" dmesg-<c>.txt` is 0 ->
   PASS; any hit -> FAIL, copy the lines exactly. For every chunk report `grep -c "gpu sched timeout" dmesg-<c>.txt`
   and `grep -c "js fault" dmesg-<c>.txt` as numbers (diag and cases chunks are expected to fault: data).
9. Every chunk-<c>.txt ends with `ROUND-DONE`; a chunk with `STALLED` or without ROUND-DONE is NOT FINISHED (report it;
   delete its line from logs/runner/state and rerun the command once; if it does not finish the second time, report
   NOT FINISHED with the last 10 lines of its chunk file). `CHUNK-RC` is the exit code of the chunk's test command.

The summary must list: the six lines of check 1, the 36 DIAG lines, the 14 CASE lines with their t= values, the cmp.txt
lines of check 5, the ocl rows, the gles summary, the dmesg counts per chunk, and the state file content.
