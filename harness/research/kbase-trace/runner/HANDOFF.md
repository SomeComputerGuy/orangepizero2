# kbase traces runner job v2 (runner job 64-kbase-traces2): handoff

Command: `bash harness/research/kbase-trace/runner/kbase-traces.sh`
Checks afterwards: `bash harness/research/kbase-trace/runner/kbase-traces.sh --check` (host only, prints one
`PASS`/`FAIL`/`INFO` line per check below; exit 0 = no FAIL; INFO lines never count as FAIL).

Purpose: GLES 3.2 reference traces from the Arm libmali g24p0 blob on the out-of-tree Arm kbase (docs/status.md item 8
step 1; notes harness/research/kbase-trace/RESULTS.md). Job 16 got kbase loaded and the plain probe running, but
(a) the trace step segfaulted (TRACE-RC 139: a kbtrace.so bug, fixed and host-tested), (b) every probe case rendered
nothing (glError 0x505, DATA_INVALID_FAULT on the fragment slot): this run samples the kbase per-context debugfs during
the probe and the trace records the job chains for that analysis, (c) the restore's rmmod + panfrost rebind made the
board reset and the old ssh then hung 1.5 h: the restore is now a plain reboot, the unload is a separate diagnostic
step at the very end, and every ssh call is bounded.

Kernel: the script installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt; c48 at
submission, kbase.ko already built for it: kernel-check/kbase-trial/.../bifrost_kbase.ko.tag) via
harness/research/vdec-perf/install-kernel.sh with the one-shot fallback armed; the HTTP server on 10.56.0.1:8643 must be
up. The board must be on the stock image kernel (vmlinuz-7.3.1-edge-sunxi64) at the start, or already on that newest
tag; anything else is BLOCKED. The stock kernel is restored at the end (also when blocked). If a newer cN exists by then,
the script rebuilds kbase.ko for it itself (~1 min) or exits 1 with "retry later" while a kernel build runs.

Nothing is installed into the system: module, blob (/root/armblob/lib/libmali.so.1, Arm EULA: reference only, never in
an image or a commit) and tools live in /root/armblob; panfrost is unbound at runtime; the final reboot undoes it.

DEV or TEST: short TEST, one chunk of about 15 min: install + reboot ~2 min, module (34 MB) transfer ~1 min (the blob is
already on the board, md5-skipped), load < 1 min, probe <= 3 min, trace <= 7 min, unload <= 2 min, restore reboot
~2 min. If the board resets during `unload` add ~6 min (it comes back by itself; see check 12). Board lock: taken and
released by the script. Every ssh is bounded (harness/ssh-opts.sh: keepalive 2 min, connect timeout, BatchMode; one-shot
calls max 90 s; steps: board-side timeout + host timeout + stall watchdog killing its own ssh by PID).
Resumable: re-running the command skips the steps listed in harness/research/arm-blob/traces/runner-j64/state whose
output files are present (kbase is reloaded if the board rebooted in between).

Results: harness/research/arm-blob/traces/runner-j64/ (git-ignored directory; do not move files into the repo):
runner.log, step-<load|info|probe|trace|unload>.txt, dmesg-<step>.txt, serial.txt (serial.log slice of this run),
files/probe/ (info.txt, <case>.rgba, <case>.progbin, kctx/: jitstats.txt, atoms, mem_allocs, mem_zones, mem_profile),
files/trace/ (same + kbtrace.bin), files/trace/decoded/ (host kbdecode: index.txt, submit-NNNN.txt), kbdecode.txt,
BLOCKED (only when blocked).

Exit codes: 0 = the job ran, judge with `--check`; 2 = blocked (report BLOCKED and the last 10 lines of runner.log);
1 = setup error or "retry later" (report the last 5 lines of runner.log; retry once after the running kernel build).
"Host key verification failed" anywhere = BLOCKED (the board has new host keys); do not edit any known_hosts file.

## Checks (mechanical; `--check` prints them)
1. runner.log has a `kernel: ` line and `kernel fix: present` -> PASS. Report the kernel line.
2. step-load.txt `PANFROST-UNBOUND` -> PASS.   3. `INSMOD-RC 0` -> PASS (else copy the insmod error line).
4. no `failed to validate module|BTF` line in dmesg-load.txt -> PASS.   5. `MALI0-PRESENT` -> PASS.
6. `MODULE-BTF-PRESENT` -> PASS.   7. dmesg-load.txt `Kernel DDK version` -> PASS (report it + the `sunxi glue` line).
   If 3-7 FAIL the probe/trace steps were skipped: report "kbase load failed" with the last 20 DMESG lines.
8. probe and trace each: `STEP-DONE`, `PROBE-RC 0` / `TRACE-RC 0`, info.txt ends with `done`, the 10 .rgba and 9
   .progbin files present and non-empty (list the missing ones; for a non-zero RC copy the last 5 lines of info.txt).
9. probe and trace each: the `basic: lit pixels` line shows more than 0 lit pixels -> PASS. Job 16 had 0 (expected to
   FAIL again unless the cause is gone: that is a result, not a package problem).
10. files/trace/kbtrace.bin non-empty and files/trace/decoded/index.txt present -> PASS; report the size and the number
    of submit-NNNN.txt files.
11. dmesg-probe.txt / dmesg-trace.txt without `Unhandled|Oops|BUG:|WARNING:|Call trace|mali.*(fault|error)` -> PASS;
    else FAIL: give the count per file and the first 5 lines (not all).
12. the last ` restored: ` line in runner.log mentions `7.3.1-edge-sunxi64` and `renderD128` -> PASS.
INFO lines (report verbatim, never FAIL): `INFO unload:` (RMMOD-RC, BIND-RC, DRI, or "no STEP-DONE: board hung or
reset"), `INFO unload <dmesg line>`, `INFO serial <line>` (oops/reset lines from serial.txt).

The summary must list: the kernel line; checks 2-7 values; probe and trace RC lines; missing/empty files (or "all
present"); the `lit pixels` line of each case of files/probe/info.txt (short); `KCTX-SAMPLES` from step-probe.txt and
the line counts of files/probe/kctx/*; kbtrace.bin size and submit count; check 11 counts; the restored line; every
INFO line; the state file content; the runner.log lines containing `STALL`, `ssh rc` or `UNREACHABLE` (or "none").
