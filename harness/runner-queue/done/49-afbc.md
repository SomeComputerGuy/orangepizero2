# Job 49-afbc (TEST, ~40 min in 5 chunks + 2 reboots; requeue of the blocked job 47)
Package: harness/research/vdec-perf/runner/ (script vdec-job.sh, HANDOFF.md section "Job afbc", check 0 is new).
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh afbc`
Kernel: the NEWEST cumulative tag (c38 or later), installed and restored by the script (restore now uses
vdec-perf/restore-kernel.sh: Image, DTB and modules).
Job 47 was blocked because the Mesa fork was not on the board (/root/opiz2-mesa/main). The script now deploys it
itself after the kernel boots (mesa-work/build-arm64, Mesa 27.0.0-devel, rebuilt from mesa HEAD 15bd751e896) and checks
`deployed main ok` with the libgallium md5 on the board.
Results: harness/research/vdec-perf/logs/runner-afbc/ (stale BLOCKED is removed at start). Queued 2026-11-06.
