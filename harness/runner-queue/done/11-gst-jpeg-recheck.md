# Job 11-gst-jpeg-recheck (DEV, ~8-10 min incl. two reboots)
Package: harness/gst-jpeg/recheck/HANDOFF.md (command `harness/gst-jpeg/recheck/run-job.sh`, checks 0-8 there).
Kernel: the newest cumulative kernel (kernel-check/cumulative-kernels.txt, c15 fa73c3e5e or later; needs
fix/sunxi-cedrus-enum-framesizes, in since c11), installed and restored by the script. Exit 2 with
build/gst-jpeg/results-recheck/BLOCKED = blocked, report its text. Results: build/gst-jpeg/results-recheck/.
Recheck of jobs 05 (z4096x4096: test bug, KSIZES probe) and 06 (c-ref/psnr: test bug, reference model) with the
dev plugins at patches 0101-0107 (0107: sub-macroblock pictures stay on the hardware path with frame sizes).
Submitted 2026-11-05 by the gst-jpeg recheck agent.
