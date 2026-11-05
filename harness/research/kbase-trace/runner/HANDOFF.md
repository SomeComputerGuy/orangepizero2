# kbase traces runner job (kbase-traces): handoff

Command: `bash harness/research/kbase-trace/runner/kbase-traces.sh`
Checks afterwards: `bash harness/research/kbase-trace/runner/kbase-traces.sh --check` (host only, prints one
`PASS`/`FAIL` line per check below; exit 0 = no FAIL).

Purpose: first board run of the Arm kbase trial for the GLES 3.2 reference traces (docs/status.md item 8 step 1,
notes harness/research/impl-gles32-arm-traces.md, BTF fix harness/research/impl-btf-dedup.md). The out-of-tree
`bifrost_kbase.ko` (built against kernel-check/work-cumul = the newest cumulative kernel; kernel-check/kbase-trial/,
git-ignored) must load on that kernel with panfrost unbound at runtime, its BTF must validate (the c3 run failed with
`failed to validate module [bifrost_kbase] BTF: -22`, fixed by bd60a159b, in c7+), `/dev/mali0` must appear, and the
gles32probe GS/tessellation cases must run on the Arm libmali g24p0 blob plain and under the kbtrace.so LD_PRELOAD.

Kernel: the script installs the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt, served as
kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz) via harness/research/vdec-perf/install-kernel.sh with the
one-shot fallback armed, as ocl-job.sh does; the HTTP server on 10.56.0.1:8643 must be up (install-kernel.sh and the
module/blob transfer use it). The board must be on the stock image kernel (vmlinuz-7.3.1-edge-sunxi64) at the start,
or already on that newest tag; anything else is BLOCKED. The stock kernel is restored at the end (also when blocked).
Before touching the board the script checks on the host that the tag contains bd60a159b, that kernel-check/work-cumul
is at that tag and that bifrost_kbase.ko is newer than its vmlinux; a stale .ko is rebuilt there automatically (ccache,
~1 min; `kernel-check/kbase-trial/port/build.sh`). If it exits 1 with "retry later" (a kernel build is running or the
tree is not at the served tag), run the command again after the next kernel build has finished; it is not a FAIL.

Nothing is installed into the system: the module, the blob (`/root/armblob/lib/libmali.so.1`, Arm EULA: reference only,
never in an image or a commit) and the tools live in /root/armblob on the board; the panfrost -> kbase switch is a
runtime unbind/insmod and is undone (rmmod + bind) before the stock-kernel reboot.

DEV or TEST: short TEST, about 10-15 min in one chunk: install + reboot ~2 min, module (34 MB) + blob (56 MB) transfer
~3 min the first time (skipped when the md5 already matches), load < 1 min, probe <= 2 min, trace <= 5 min, restore
reboot ~2 min. Every board step runs under a host timeout and a stall watchdog (kill after 60-300 s without output).
Resumable: re-running the command skips the steps listed in harness/research/arm-blob/traces/runner/state whose
output files are present (kbase is reloaded if the board rebooted in between).

Results: harness/research/arm-blob/traces/runner/ (git-ignored directory, do not move the files into the repo):
runner.log, step-<load|info|probe|trace>.txt, dmesg-<step>.txt, files/probe/ and files/trace/ (info.txt, <test>.rgba,
<test>.progbin, and kbtrace.bin for trace), files/trace/decoded/ (host kbdecode: index.txt, submit-NNNN.txt),
kbdecode.txt, BLOCKED (only when blocked).

Exit codes: 0 = the job ran, judge with `--check`; 2 = blocked (report BLOCKED and the last 10 lines of runner.log);
1 = setup error or "retry later" (report the last 5 lines of runner.log; retry once after the next kernel build if it
says retry later).

## Checks (mechanical; `--check` prints them, the greps are listed so the summary can quote the evidence)
1. runner.log has a `kernel: ` line (uname -v) and `kernel fix: present` -> PASS. Report the kernel line.
2. step-load.txt contains `PANFROST-UNBOUND` -> PASS (panfrost not bound); `PANFROST-STILL-BOUND` -> FAIL.
3. step-load.txt contains `INSMOD-RC 0` -> PASS; any other INSMOD-RC -> FAIL, copy the `insmod:` error line.
4. `grep -c -i -E "failed to validate module|BTF" dmesg-load.txt` is 0 -> PASS; any hit -> FAIL, copy the lines exactly.
5. step-load.txt contains `MALI0-PRESENT` -> PASS; `MALI0-MISSING` -> FAIL.
6. step-load.txt contains `MODULE-BTF-PRESENT` (/sys/kernel/btf/bifrost_kbase, the kernel accepted the module BTF)
   -> PASS; else FAIL.
7. dmesg-load.txt has a `Kernel DDK version` line -> PASS (kbase probed); report that line and the `sunxi glue` line.
   If checks 3-7 FAIL, the probe/trace steps were skipped: report "kbase load failed" with the last 20 DMESG lines.
8. probe and trace: step-<s>.txt ends with `STEP-DONE` and contains `PROBE-RC 0` / `TRACE-RC 0`; files/<s>/info.txt
   ends with `done`; each of the 10 readbacks basic, gs_pass, gs_amp, gs_inv, tess_tri, tess_gs, tess_quad, gs_xfb,
   gs_layer0, gs_layer1 exists as files/<s>/<name>.rgba and is non-empty; each of the 9 program binaries (same names,
   gs_layer instead of gs_layer0/1) exists as files/<s>/<name>.progbin and is non-empty -> PASS per file. A missing or
   empty file is FAIL for that file: list them; a non-zero RC means the blob crashed on the next case after the last
   file written (that is the result the analysis agent needs, copy the last 5 lines of files/<s>/info.txt).
9. files/trace/kbtrace.bin exists and is non-empty, and files/trace/decoded/index.txt exists -> PASS; report the
   kbtrace.bin size and the number of submit-NNNN.txt files.
10. dmesg: `grep -c -E "Unhandled|Oops|BUG:|WARNING:|Call trace|mali.*(fault|error)" dmesg-probe.txt dmesg-trace.txt`
    is 0 for both -> PASS; any hit -> FAIL, copy the lines exactly.
11. runner.log's last `restored: ` line mentions `7.3.1-edge-sunxi64` and `renderD128` -> PASS (stock kernel back,
    panfrost bound again); else FAIL, and BLOCKED if the board is unreachable.

The summary must list: the kernel line, checks 2-7 with their values (the `insmod:` line and every BTF/validate dmesg
line if any), the probe and trace RC lines, the list of missing/empty output files (or "all 19 + 19 present"), the
`lit pixels` lines of files/probe/info.txt (one per case, short), the kbtrace.bin size and submit count, the dmesg
counts of check 10, the restored line, and the state file content.
