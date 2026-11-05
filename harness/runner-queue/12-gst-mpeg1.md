# Job 12-gst-mpeg1 (DEV, ~15-20 min incl. two reboots)
Package: harness/gst-mpeg1/HANDOFF.md (command `bash harness/gst-mpeg1/run-job.sh`, checks 0-9 there).
Kernel: newest cumulative; it must contain armbian-build 8140b4eeb (fix/sunxi-cedrus-mpeg1-mg1s), the same precondition
as job 11-mpeg1-mg1s. The script exits 2 with build/gst-mpeg1/results/BLOCKED until the coordinator has merged and built
it (report that verbatim, no checks then). The board must be on the stock image kernel at start (phase stock runs there
first); the script installs the cumulative kernel and restores the stock one. Results: build/gst-mpeg1/results/.
Tests: GStreamer v4l2slmpeg2dec dev build (patches/gstreamer 0001-0017 + 0101-0107 + 0201): MPEG-1 only offered on a
kernel that enumerates MG1S (decodebin falls back to software on the stock kernel); MPEG-1 hw md5 ccm1 129/129 and
tcela-18 31 D-pictures (TRY_EXT_CTRLS probe), IDCT envelope MEI x2/tcela-16/19, MPEG-2 regression tcela-15/mcp10ccett,
decodebin/playbin3 pick the hw decoder, dmesg clean.
Submitted 2026-11-05 by the gst-mpeg1 code agent.
