# Job 57-gst-jpeg-stateful2: stateful v4l2jpegdec and resolution changes on cedrus (rerun of job 56)

DEV run, ~8-10 min (two reboots + ~2 min of tests). Kernel: the newest cumulative kernel (must be c42 or newer; c42 =
test-cumulative with "media: cedrus: change formats with CAPTURE buffers left while stopped" on top of c41's STOP
drain; Image md5 in kernel-check/cumulative-kernels.txt), installed and restored by the script.
No GStreamer install: the bundle carries dev plugins in a scratch plugin dir only (/root/gstjpeg-stateful, deleted
after): libgstv4l2codecs.so + libgstjpegformat.so (gst-plugins-bad 0101-0107, as in job 56) and
libgstvideo4linux2.so (gst-plugins-good 1.28.7 + patches/gst-plugins-good1.0 0101-0102: v4l2jpegdec takes
colorimetry 1:4:0:0, and offers system memory to a peer that answers ANY).

## Command
    harness/gst-jpeg/stateful/run-job.sh            (bundle: build/gst-jpeg/bundle-stateful, already built;
                                                     rebuild only if missing: harness/gst-jpeg/stateful/make-bundle.sh)
Exit 0 = ran, verdict in build/gst-jpeg/results-stateful2/compare.txt. Exit 2 = blocked (results-stateful2/BLOCKED
says why; report it). Exit 3 = paused.
Pause: `touch build/gst-jpeg/results-stateful2/PAUSE` -> stops at the next step, restores the stock kernel, releases
the lock. Resume: `rm` the PAUSE file and run the same command (steps done are kept in results-stateful2/state;
`RESET=1` starts over). Stall watchdog: no runner.log line for 15 min -> BLOCKED "stall", stock kernel restored.

## Checks (all mechanical, printed by check.sh into compare.txt, one line each)
- C0-references: the v4l2sljpegdec reference runs exit 0 with the expected sizes (mjmix/mjmixup 8640000: job 56 had
  rc=1, "set_sink_fmt() failed: Device or resource busy" at the 640x480 <-> 320x240 change).
- C1-still, C2-loop5, C3a-mjmix, C3b-mjmixup: the explicit stateful `v4l2jpegdec` runs (1920x1088 still, the still 5x
  in one stream, the two MJPEG clips with a 640x480 <-> 320x240 change) exit 0 (EOS reached, no timeout), give the
  expected size, the same md5 as v4l2sljpegdec, `cmdfail=0` (the kernel accepted V4L2_DEC_CMD_STOP), `stopwait>=1`
  and `dmesg=+0`.
- C4-norank16: without any rank override decodebin picks `v4l2jpegdec` for the 16-aligned picture, exits 0, same
  md5, `dmesg=+0` (job 56: rc=0 but size 0, DMA_DRM caps that videoconvert cannot take).
- C5-override: with `GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL` (the image's setting) decodebin picks
  `v4l2sljpegdec`, exits 0, same md5, `dmesg=+0`.
- C6-h264: stateless regression: v4l2slh264dec decodes all 30 frames (size 13824000), exit 0, `dmesg=+0`. Its md5
  vs host ffmpeg is printed as info only (not a check).
- C8-h264mix: stateless resolution change: v4l2slh264dec decodes 15 frames 640x480 + 15 frames 320x240 (size
  8640000), exit 0, `dmesg=+0`; md5 vs host ffmpeg is info only.
- C7-dmesg: no "Failed to setup decoding job", cedrus error/timeout, WARNING, Oops or BUG line in the run's kernel log.
PASS = `VERDICT: PASS` (every C line PASS).

## Copy / report
Results: build/gst-jpeg/results-stateful2/ (compare.txt, runner.log, kernel.txt, out/results.txt, out/dmesg.txt,
out/*.log, out/*.gstdebug.txt). Copy the text logs (out/*.log, out/results.txt, out/dmesg.txt, compare.txt,
runner.log, kernel.txt) to harness/runner-queue/done/57-logs/. The summary must list: kernel line from kernel.txt,
every C line of compare.txt verbatim, the VERDICT, the C6 and C8 md5 info, the dmesg line count, BLOCKED text if any,
and the restored kernel line.
