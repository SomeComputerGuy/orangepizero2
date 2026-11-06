# Job 35-ve-encoder (DEV-length, ~10 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault/engine timeout) = job 34 re-queued on c30
Package: harness/research/ve-encoder/runner/ (script venc-job.sh, HANDOFF.md, checks 1-7 there).
Command: `bash harness/research/ve-encoder/runner/venc-job.sh venc`
Why again: job 34 (c29) probed fine (boot_warnings 0, topology OK) but every encode started with
`sun50i-iommu 30f0000.iommu: Page fault for 0x0000000000000000 (master 3, dir rd, L1 page table, status 0x8)` and ended
in `frame processing timed out!` (rc 6, 0-byte streams), and v4l2-compliance had 4 failures. Root cause in the encoder
patch: the engine reads through encoder address registers the driver (like the vendor library) left at 0 or never wrote
(motion vector buffer 0xb60, deblocking buffer 0xbc4, rate control buffer 0xb9c, temporal filter counts 0xbc8, second
reference); harmless without an IOMMU, a fault behind it. Fixed by fix/sunxi-h616-venc 201516cc5 (one auxiliary buffer
per context behind every address register, IOMMU on) + 4d9a200e8 (compliance: coded-size overflow, MIN_BUFFERS_FOR_OUTPUT
dropped -> 20 controls, G/S_PARM kept as the one justified failure), merged into test-cumulative 1d1c9e149 = c30.
Package: media node looked up in /sys/bus/media/devices (job 34's `media_node none` was a lookup bug), new value
`compliance_unexpected` (check 2), `dmesg_encode_failed` counted over the encode steps only (check 7), FIX=4d9a200e8.
Kernel: the newest cumulative kernel, which must contain fix/sunxi-h616-venc 4d9a200e8 (c30 or later; the script blocks
(exit 2) on an older one or when no encoder device is logged). The board must start on the stock image kernel.
HTTP server 10.56.0.1:8643 up.
Host: /usr/local/bin/ffmpeg (clips already in harness/research/ve-encoder/runner/clips/).
Tool: harness/research/ve-encoder/tools/out/h264enc-test (unchanged), shipped if the board copy differs.
Results: harness/research/ve-encoder/logs/runner-venc/ (results.txt has the values for the checks; the .h264 streams
are kept; chunk-venc.txt names the step on a stall). Summary per HANDOFF.md "Checks".
Submitted by the ve-encoder job-34 fix agent, 2026-11-06.
