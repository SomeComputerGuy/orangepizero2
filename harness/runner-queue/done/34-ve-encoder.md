# Job 34-ve-encoder (DEV-length, ~10 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault/engine timeout) = job 32 re-queued
Package: harness/research/ve-encoder/runner/ (script venc-job.sh, HANDOFF.md, checks 1-7 there).
Command: `bash harness/research/ve-encoder/runner/venc-job.sh venc`
Why again: job 32 (c27) stalled in `v4l2-ctl --all` on /dev/video1 and the board needed ~6 min to reboot. Root cause in
the encoder patch itself: a second v4l2_m2m_register_media_controller() call on the shared M2M device re-registered
the decoder's sink/proc entities and pads (the boot WARNING at mc-device.c:619 twice, cedrus_probe in the trace) and
left the media device's pad list linked to itself; every MEDIA_IOC_G_TOPOLOGY then spun forever in the kernel with the
graph mutex held (unkillable; the empty MEDIA line was the broken topology). Fixed by giving the encoder its own
entities/pads/interface: fix/sunxi-h616-venc ac009bb5b + c307dd053 (series.conf), merged into test-cumulative
3d88bb858 = c29. Package: sysfs node discovery, `STEP` lines + `timeout -k 5` per step, topology checks
(boot_warnings, media_node, media_info, dec_D_rc), stall diagnostics, restore through restore-kernel.sh (DTB too).
Kernel: the newest cumulative kernel, which must contain fix/sunxi-h616-venc c307dd053 (c29 or later; the script
blocks (exit 2) on an older one or when no encoder device is logged). The board must start on the stock image kernel.
HTTP server 10.56.0.1:8643 up.
Host: /usr/local/bin/ffmpeg (clips already generated in harness/research/ve-encoder/runner/clips/).
Tool: harness/research/ve-encoder/tools/out/h264enc-test (built 2026-11-06), shipped if the board copy differs.
Results: harness/research/ve-encoder/logs/runner-venc/ (results.txt has the values for the checks; the .h264 streams
are kept; chunk-venc.txt names the step on a stall). Summary per HANDOFF.md "Checks" (check 1 now includes the four
media-controller values).
Submitted by the g2d/venc stall agent, 2026-11-06.
