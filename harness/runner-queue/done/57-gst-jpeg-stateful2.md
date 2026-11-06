# Job 57-gst-jpeg-stateful2 (DEV, ~8-10 min incl. two reboots)
Package: harness/gst-jpeg/stateful/HANDOFF.md (command `harness/gst-jpeg/stateful/run-job.sh`, checks C0-C8 there).
Rerun of job 56 with the fixes for its FAILs: kernel "media: cedrus: change formats with CAPTURE buffers left while
stopped" (fix/sunxi-cedrus-jpeg-stop-drain fbba781aa, merged as c42 = test-cumulative 2658acbe4, Image md5
a33675cabd5e04a667475be57e51586c) for the v4l2sljpegdec EBUSY on resolution change, and the dev gst-plugins-good
video4linux2 plugin (patches/gst-plugins-good1.0 0101-0102) in the bundle for the stateful v4l2jpegdec caps bugs.
New case C8 (H.264 resolution change, v4l2slh264dec).
Kernel: the newest cumulative kernel (c42+), installed and restored by the script. Bundle build/gst-jpeg/bundle-stateful
(rebuilt). Exit 2 with build/gst-jpeg/results-stateful2/BLOCKED = blocked, report its text; exit 3 = paused (resumable).
Results: build/gst-jpeg/results-stateful2/; text logs to harness/runner-queue/done/57-logs/.
Submitted 2026-11-06 by the gst-jpeg-stateful agent.
