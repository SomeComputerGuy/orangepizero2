# Job 22-gst-jpeg-recheck2 (DEV, ~8-10 min incl. two reboots)
Package: harness/gst-jpeg/recheck/HANDOFF.md (command `harness/gst-jpeg/recheck/run-job.sh`, checks 0-9 there).
Rerun of 11-gst-jpeg-recheck after the analysis of 2026-11-06 (harness/research/gst-jpeg/RESULTS.md "Job 11 analysed"):
checks 1 (INSPECT: the element is proven by `gst-inspect-1.0 --exists`, gst-inspect's `Name` is the plugin name) and
8 (norank: on a kernel with ENUM_FRAMESIZES the stateful v4l2jpegdec declines 1921x1081 and v4l2sljpegdec decodes it)
had wrong expectations; new check 9 records the 16-aligned `norank16` run (stateful decoder, hang expected) with its
GST_DEBUG log. Bundle build/gst-jpeg/bundle-recheck rebuilt (same dev .so 0101-0107, + z1920x1088.jpg).
Kernel: the newest cumulative kernel (kernel-check/cumulative-kernels.txt), installed and restored by the script.
Exit 2 with build/gst-jpeg/results-recheck/BLOCKED = blocked, report its text. Results: build/gst-jpeg/results-recheck/
(job 11's kept as results-recheck-job11/). Submitted 2026-11-06 by the runner-failures agent.
