# Job 56-gst-jpeg-stateful (DEV, ~8-10 min incl. two reboots)
Package: harness/gst-jpeg/stateful/HANDOFF.md (command `harness/gst-jpeg/stateful/run-job.sh`, checks C0-C7 there).
Board check of the kernel fix "media: cedrus: jpeg: drain on V4L2_DEC_CMD_STOP" (fix/sunxi-cedrus-jpeg-stop-drain
950c46035, merged in c41 = test-cumulative 39b1dce3f): GStreamer's stateful v4l2jpegdec must now finish 16-aligned JPEG
stills and MJPEG clips (job 22 norank16 hung: STOP refused, empty-buffer fallback looped, rc=124, dmesg +133).
Kernel: the newest cumulative kernel (c41+), installed and restored by the script. Bundle build/gst-jpeg/bundle-stateful
(built). Exit 2 with build/gst-jpeg/results-stateful/BLOCKED = blocked, report its text; exit 3 = paused (resumable).
Results: build/gst-jpeg/results-stateful/. Submitted 2026-11-06 by the gst-jpeg-stateful agent.
