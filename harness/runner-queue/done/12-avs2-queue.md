# Job 12-avs2-queue (DEV, ~10 min incl. two reboots)
Package: harness/research/vdec-perf/runner/ (script vdec-job.sh, HANDOFF.md section "Job avs2q").
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh avs2q`
Kernel: the newest cumulative kernel (kernel-check/cumulative-kernels.txt), installed and restored by the script. No debs:
the board fetches the dev binary ffmpeg-avs2q and refs-8bit.md5 from the vdec-serve HTTP server (10.56.0.1:8643, must be up).
Checks: FFmpeg AVS2 request queueing (patches/ffmpeg 0313): md5 of the 17 8-bit streams + cctv4k Main10 P010, starved VE
gaps on cctv4k <= 3 per run, 0 timeouts (HANDOFF.md "Job avs2q", mechanical). Exit 2 + logs/runner-avs2q/BLOCKED = blocked,
report its text. Results: harness/research/vdec-perf/logs/runner-avs2q/. Submitted 2026-11-05 by the vdec aq1-landing agent.
