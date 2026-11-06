# Job 56-gst-jpeg-stateful: stateful v4l2jpegdec on cedrus JPEG after the STOP-drain kernel fix

DEV run, ~8-10 min (two reboots + ~2 min of tests). Kernel: the newest cumulative kernel (must be c41 or newer;
c41 = test-cumulative 39b1dce3f, Image md5 13c7bb0046eed804e3e20da58518869d), installed and restored by the script.
No GStreamer rebuild: v4l2jpegdec is the image's own gst-plugins-good; the bundle carries the dev v4l2codecs /
jpegformat .so of the recheck (patches 0101-0107) in a scratch plugin dir only (/root/gstjpeg-stateful, deleted after).

## Command
    harness/gst-jpeg/stateful/run-job.sh            (bundle: build/gst-jpeg/bundle-stateful, already built;
                                                     rebuild only if missing: harness/gst-jpeg/stateful/make-bundle.sh)
Exit 0 = ran, verdict in build/gst-jpeg/results-stateful/compare.txt. Exit 2 = blocked (results-stateful/BLOCKED
says why; report it). Exit 3 = paused.
Pause: `touch build/gst-jpeg/results-stateful/PAUSE` -> stops at the next step, restores the stock kernel, releases
the lock. Resume: `rm` the PAUSE file and run the same command (steps done are kept in results-stateful/state;
`RESET=1` starts over). Stall watchdog: no runner.log line for 15 min -> BLOCKED "stall", stock kernel restored.

## Checks (all mechanical, printed by check.sh into compare.txt, one line each)
- C0-references: the v4l2sljpegdec reference runs exit 0 with the expected sizes.
- C1-still, C2-loop5, C3a-mjmix, C3b-mjmixup: the explicit stateful `v4l2jpegdec` runs (1920x1088 still, the still 5x
  in one stream, the two MJPEG clips with a 640x480 <-> 320x240 change) exit 0 (EOS reached, no timeout), give the
  expected size, the same md5 as v4l2sljpegdec, `cmdfail=0` (the kernel accepted V4L2_DEC_CMD_STOP), `stopwait>=1`
  and `dmesg=+0`.
- C4-norank16: without any rank override decodebin picks `v4l2jpegdec` for the 16-aligned picture, exits 0, same
  md5, `dmesg=+0` (job 22: rc=124 and dmesg +133 here).
- C5-override: with `GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL` (the image's setting) decodebin picks
  `v4l2sljpegdec`, exits 0, same md5, `dmesg=+0`.
- C6-h264: stateless regression: v4l2slh264dec decodes all 30 frames (size 13824000), exit 0, `dmesg=+0`. Its md5
  vs host ffmpeg is printed as info only (not a check).
- C7-dmesg: no "Failed to setup decoding job", cedrus error/timeout, WARNING, Oops or BUG line in the run's kernel log.
PASS = `VERDICT: PASS` (every C line PASS).

## Copy / report
Results: build/gst-jpeg/results-stateful/ (compare.txt, runner.log, kernel.txt, out/results.txt, out/dmesg.txt,
out/*.log, out/*.gstdebug.txt). The summary must list: kernel line from kernel.txt, every C line of compare.txt
verbatim, the VERDICT, the C6 md5 info, the dmesg line count, BLOCKED text if any, and the restored kernel line.
