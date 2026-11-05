# Job 11-mpeg1-mg1s (TEST, ~25-35 min, 7 chunks of <= 10 min, resumable)
Package: harness/mpeg1-mg1s/HANDOFF.md (command `bash harness/mpeg1-mg1s/run-job.sh`, checks 0-9 there).
Kernel: newest cumulative; it must contain armbian-build 8140b4eeb (fix/sunxi-cedrus-mpeg1-mg1s, pushed to fork, NOT yet
merged into test-cumulative). The script exits 2 with logs/runner/BLOCKED until the coordinator has merged and built it
(report that verbatim, no checks then). The board must be on the stock image kernel at start (chunk `stock` runs there
first). Results: harness/mpeg1-mg1s/logs/runner/.
Tests: MG1S enumerated on cedrus; MPEG-1 hwaccel falls back to software on a kernel without MG1S; v4l2-compliance;
FFmpeg MPEG-1 md5 (ccm1 129/129, tcela-18 31/31 D-pictures in hardware, MEI/tcela-16/19/1080p30 in the IDCT
envelope); MPEG-2 regression.
Submitted 2026-11-05 by the mpeg1-mg1s code agent.
