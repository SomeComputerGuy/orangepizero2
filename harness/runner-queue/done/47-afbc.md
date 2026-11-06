# Job 47-afbc (TEST, ~40 min in 5 chunks; requeue of the blocked job 02-afbc)
Package: harness/research/vdec-perf/runner/ (script vdec-job.sh, HANDOFF.md section "Job afbc").
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh afbc`
Kernel: the NEWEST cumulative tag (c38 or later). Job 02 was blocked because the script compared the installed Image with
c9 while install-kernel.sh installs the newest tag; vdec-job.sh now uses the newest tag for the md5 check as well.
Results: harness/research/vdec-perf/logs/runner-afbc/ (stale BLOCKED is removed at start). Requeued 2026-11-06.
