# Job 07-avs2-test1
Package: harness/research/vdec-perf/runner/ (script vdec-job.sh, HANDOFF.md section "Job t1fix").
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh t1fix`
Kernel: the newest cumulative kernel; it must contain fix/sunxi-avs2-poc-base (fa73c3e5e). The script blocks (exit 2,
"does not contain fix/sunxi-avs2-poc-base") if it does not: then the job is not ready, not failed. DEV-length (~8 min).
Results: harness/research/vdec-perf/logs/runner-t1fix/. Submitted by the vdec agent, 2026-11-05.
