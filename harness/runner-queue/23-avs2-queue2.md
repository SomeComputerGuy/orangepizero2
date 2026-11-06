# Job 23-avs2-queue2 (DEV, ~10 min incl. two reboots)
Package: harness/research/vdec-perf/runner/ (script vdec-job.sh, HANDOFF.md section "Job avs2q").
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh avs2q`
Rerun of 12-avs2-queue: its 4 `download failed` lines (cut stream names) and the 10/18 md5 count were a script bug
(ffmpeg read the stream list from the md5 loop's stdin; fixed with -nostdin in board-queue-avs2q.sh); the 10 streams
that ran all passed. Job 12's logs are kept in logs/runner-avs2q-job12/, the state file is fresh.
Kernel: the newest cumulative kernel (kernel-check/cumulative-kernels.txt), installed and restored by the script. No debs:
the board fetches ffmpeg-avs2q and refs-8bit.md5 from the vdec-serve HTTP server (10.56.0.1:8643, must be up).
Checks: HANDOFF.md "Job avs2q" (18 md5 PASS, starved gaps <= 3, 0 timeouts, no `download failed`). Exit 2 +
logs/runner-avs2q/BLOCKED = blocked, report its text. Results: harness/research/vdec-perf/logs/runner-avs2q/.
Submitted 2026-11-06 by the runner-failures agent.
