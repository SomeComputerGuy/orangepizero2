# kbase traces runner job v4 (runner job 66-kbase-traces4): handoff

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
v3 (job 65), after job 64: job 64's trace held no GPU memory (kbtrace read it with process_vm_readv, which cannot read
kbase mappings), so the DATA_INVALID_FAULT could not be analysed: kbtrace.so v3 captures the memory and the JIT soft-job
payloads, kbdecode v3 decodes every faulting submit again from the memory after the fault. bifrost_kbase.ko v3 fixes the
unload (the glue now asserts the GPU reset and turns clocks + supply off at rmmod, like panfrost does) and logs one
`sunxi diag:` line per job fault. `unload` (rmmod) and `bind` (panfrost rebind) are two separate steps and are now real
checks (13-15 below). Checks 9 and 11 are still expected to FAIL in this run (no rendering fix yet: this run collects
the data for it).
v4 (job 66), after job 65: the fragment DATA_INVALID_FAULT is the blob writing AFBC colour render targets on a G31 that
has no AFBC (AFBC_FEATURES 0x10001): in job 65 every failing fragment job (18/18) had an AFBC RT and the GPU's
fault_ptr was exactly the RT descriptor; every fragment job with a linear RT (18/18) completed. New step `afbc` (after
`info`): the basic case alone under four blob config files in /root/armblob/cfg/ (v0 = empty control, v1 = AFBC off for
textures + surfaces, v2 = v1 + CRC off, v3 = v2 + forced linear textures), passed with MALI_PLATFORM_CONFIG and
MALI_DEBUG_CONFIG. The script picks the first of v1..v3 that renders (v3 if none) and runs probe + trace under it.
bifrost_kbase.ko v4 (md5 aa7e170386c6672fe001d95daff25f30): no `IRQ ... not found` errors, no workqueue WARNING at load,
no unbalanced regulator disable at unload. Expected: everything PASS except check 11 if a fault remains; v0 is expected
to show 0 lit pixels (control). If no variant renders, that is a result (report the VARIANT and BLOB lines), not a
package problem.

Kernel: the script installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt; c48 at
submission, kbase.ko v4 already built for it (md5 aa7e170386c6672fe001d95daff25f30): kernel-check/kbase-trial/.../bifrost_kbase.ko.tag) via
harness/research/vdec-perf/install-kernel.sh with the one-shot fallback armed; the HTTP server on 10.56.0.1:8643 must be
up. The board must be on the stock image kernel (vmlinuz-7.3.1-edge-sunxi64) at the start, or already on that newest
tag; anything else is BLOCKED. The stock kernel is restored at the end (also when blocked). If a newer cN exists by then,
the script rebuilds kbase.ko for it itself (~1 min) or exits 1 with "retry later" while a kernel build runs.

Nothing is installed into the system: module, blob (/root/armblob/lib/libmali.so.1, Arm EULA: reference only, never in
an image or a commit) and tools live in /root/armblob; panfrost is unbound at runtime; the final reboot undoes it.

DEV or TEST: short TEST, one chunk of about 17 min (afbc step <= 5 min, normally ~1 min): install + reboot ~2 min, module (34 MB) transfer ~1 min (the blob is
already on the board, md5-skipped), load < 1 min, probe <= 3 min, trace <= 7 min, unload <= 2 min, restore reboot
~2 min. If the board resets during `unload` or `bind` add ~6 min (it comes back by itself; see checks 12-15). The
trace is bigger now (memory snapshots, tens of MB): trace step <= 7 min still, fetch ~1 min. Board lock: taken and
released by the script. Every ssh is bounded (harness/ssh-opts.sh: keepalive 2 min, connect timeout, BatchMode; one-shot
calls max 90 s; steps: board-side timeout + host timeout + stall watchdog killing its own ssh by PID).
Resumable: re-running the command skips the steps listed in harness/research/arm-blob/traces/runner-j66/state whose
output files are present (kbase is reloaded if the board rebooted in between).

Results: harness/research/arm-blob/traces/runner-j66/ (git-ignored directory; do not move files into the repo):
runner.log, step-<load|info|afbc|probe|trace|unload|bind>.txt, dmesg-<step>.txt, serial.txt (serial.log slice of this run),
files/afbc/ (SELECTED, v0..v3/: info.txt, run.txt, basic.rgba), files/probe/ (info.txt, <case>.rgba, <case>.progbin, kctx/: jitstats.txt, atoms, mem_allocs, mem_zones, mem_profile),
files/trace/ (same + kbtrace.bin), files/trace/decoded/ (host kbdecode: index.txt, submit-NNNN.txt, submit-NNNN-post.txt
for every submit with a fault), kbdecode.txt,
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
9. probe and trace each: the `basic: lit pixels` line shows more than 0 lit pixels -> PASS. Jobs 16-65 had 0; v4 expects
   PASS (AFBC off). A FAIL is a result, not a package problem.
10. files/trace/kbtrace.bin non-empty and files/trace/decoded/index.txt present -> PASS; report the size and the number
    of submit-NNNN.txt files.
11. dmesg-probe.txt / dmesg-trace.txt without `Unhandled|Oops|BUG:|WARNING:|Call trace|mali.*(fault|error)` -> PASS;
    else FAIL: give the count per file and the first 5 lines (not all).
12. the last ` restored: ` line in runner.log mentions `7.3.1-edge-sunxi64` and `renderD128` -> PASS.
13. the trace holds the GPU memory: at least one files/trace/decoded/submit-*.txt decodes a `Type: Fragment` job -> PASS
    (job 64: FAIL, every job header read as zero). Report the count.
14. unload: step-unload.txt `RMMOD-RC 0` and `STEP-DONE`, and dmesg-unload.txt has the `sunxi glue: reset asserted ...`
    line -> PASS (two lines). FAIL = no STEP-DONE (board hung/reset) or the line is missing.
15. bind: step-bind.txt `BIND-RC 0`, `STEP-DONE` and a `DRI:` line with renderD128 -> PASS. If the board reset at the
    rebind (as in jobs 16 and 64) this FAILs with "no STEP-DONE": a result, not a package problem.
16. (v4) load: no `IRQ (JOB|MMU|GPU) not found` line and no `WARNING:`/`Call trace` in dmesg-load.txt -> PASS (two lines).
17. (v4) afbc: step-afbc.txt `STEP-DONE` -> PASS; `SELECTED v1|v2|v3 renders` -> PASS (FAIL = `SELECTED v3 none-rendered`).
18. (v4) trace: no `Writeback Block Format: AFBC` in files/trace/decoded/submit-*.txt -> PASS (FAIL gives the count).
19. (v4) unload: no `WARNING:`/`unbalanced` line in dmesg-unload.txt -> PASS.
INFO lines (report verbatim, never FAIL): `INFO post:` (job headers after the fault: exception_status, fault_ptr),
`INFO jit:` / `INFO jitaddr:` (JIT requests and what the kernel wrote), `INFO diag:` (`sunxi diag` fault lines),
`INFO unload ...` / `INFO bind ...` (PM/GENPD/CLK state before/after, dmesg lines), `INFO serial: U-Boot SPL count`,
`INFO serial <line>` (oops/reset lines from serial.txt), (v4) `INFO afbc: VARIANT ...` (per variant: rc, DATA_INVALID
fault count, config, basic line), `INFO afbc BLOB: ...`, `INFO probe blob CONFIG ...` / `INFO trace blob CONFIG ...`,
`INFO probe case: ...` (every case), `INFO rt: ...` (fragment RT format by job status).

The summary must list: the kernel line; checks 2-7 values; probe and trace RC lines; missing/empty files (or "all
present"); the `lit pixels` line of each case of files/probe/info.txt (short); `KCTX-SAMPLES` from step-probe.txt and
the line counts of files/probe/kctx/*; kbtrace.bin size and submit count; check 11 counts; the restored line; every
INFO line (all of them, verbatim); checks 13-19; the state file content; the runner.log lines containing `STALL`, `ssh rc` or `UNREACHABLE` (or "none").
