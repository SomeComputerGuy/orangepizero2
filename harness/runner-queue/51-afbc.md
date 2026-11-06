# Job 51-afbc (TEST, ~10 min if the GPU has no AFBC, ~40 min otherwise; 5 chunks + 2 reboots; follow-up of job 49)
Package: harness/research/vdec-perf/runner/ (script vdec-job.sh, HANDOFF.md section "Job afbc": check 0, the new
"Probe" block, then the per-chunk checks).
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh afbc`
Kernel: the NEWEST cumulative tag (c38 or later), installed and restored by the script (restore-kernel.sh).
Mesa: the script deploys mesa-work/build-arm64 (fork main 15bd751e896) to /root/opiz2-mesa/main and checks the md5.
Checker: kernel-check/vdec-serve/afbc/afbc-gpu-check (md5 85f7043c6c2a77ded0a639cba9b310f4) now prints `probe:` lines
(GPU AFBC_FEATURES and the EGL modifier lists). Job 49 failed every import with EGL 0x3009; the likely cause is that this
Mali-G31 has no AFBC. If so every chunk prints `afbc: NOT TESTABLE on the GPU` after a few seconds and the job verdict
is NOT TESTABLE (GPU has no AFBC), not FAIL.
Results: harness/research/vdec-perf/logs/runner-afbc/ (fresh; job 49's are in logs/runner-afbc-job49/). Commit the text
logs (chunk-*, dmesg-*, runner.log, files/*.txt); do NOT commit files/*.afbc-head or other binaries.
Summary must list: check 0 line, the probe lines verbatim (first chunk), the `[hevc8q] import-failed` and
`hdr frame 0 sb` lines, the verdict, and the per-case F/C/M/X table if the cases ran. Queued 2026-11-06.
