# Job 69-image-check (DEV, ~70-90 min; run FIRST, before resuming 68)
Package: harness/research/image-check/runner/HANDOFF.md (command `bash harness/research/image-check/runner/image-check.sh`,
then `... image-check.sh --check` prints CHECK 0-17 + VERDICT).
Start only after the coordinator says the user's `./build-all.sh OPIZ2_WIFI_REGDOM=US` has finished. It reflashes the
SERVER image `Armbian-unofficial_26.11.0-trunk_Orangepizero2_stonking_edge_*.img.xz` (newest, no _minimal/_desktop suffix)
over netboot itself (harness/reflash.sh, REFLASH.md rules scripted) and checks: kernel/boot, verify-board.sh (CUPS, sane),
gst-inspect v4l2sljpegdec/v4l2jpegdec/v4l2codecs + JPEG decodes, gst-libav (job 24 check 1), the Vulkan env var
system-wide, vulkaninfo panvk 1.0.x, vkcube (NOT-TESTED without HDMI), dEQP-VK smoke, GLES and OpenCL regressions.
Kernel: the image's own (7.3.3 for this build); no trial kernel.
AFTER THIS JOB: the stock kernel on the board is the image's 7.3.3, not 7.3.1. Then resume job 68 (paused) with its
usual command `bash harness/research/vk11/runner/vk11-main.sh`; its kernel scripts no longer hardcode 7.3.1 (fixed
2026-11-07), and /root/cts (which the reflash wipes) was restaged by this job (check 16). If check 16 FAILED, run
`bash harness/analysis/gpu/cts-restage.sh` once before job 68.
Submitted 2026-11-07 by the image-integration agent.
