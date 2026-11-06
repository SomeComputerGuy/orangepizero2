# Job 55-wb-eio (TEST, ~20 min, 10 cases + 2 reboots, resumable between cases, fails fast on Oops/WARN/IOMMU fault)
Package: harness/research/wb-eio/runner/ (wrapper wb-eio-job.sh -> harness/research/afbc-wb/runner/afbc-wb-job.sh j55;
HANDOFF.md with checks 0-5 and the verdict rules).
Command: `bash harness/research/wb-eio/runner/wb-eio-job.sh`
What: DE33 writeback -EIO fix check. Jobs 53/54 had `wb_error -5` on the first capture of frames 2,6(,8) in real-hevc8
(4K H.265 linear NV12). c40 repeats a capture that ended with OVERFLOW/TIMEOUT on the next frame (commit 20e682fc2).
real-hevc8 runs 5 times (0 wb_error required), plus real-hevc10 and 4 synthetic regression cases.
Kernel: c40 = test-cumulative 6d124e150, Image md5 d950e7ed64c3620b1983fc5217a99a7c (or a later cumulative tag); must
contain 30706dcc8, 8b1f787fe and 20e682fc2 (checked by the script). Installed and restored by the script.
Client: harness/afbc-wb/out/afbc-wb, unchanged since job 54 (sha256 10ccf7c0cb028a0228e5d61c05ca3ff1e83e109cf67dffb528a22fc6749b209a).
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/afbc-wb/logs/runner-j55/ (results.txt). Commit text logs only, never files/*/dump/*.cap.
Summary: as listed in harness/research/wb-eio/runner/HANDOFF.md "Summary must list". Submitted by the wb-eio agent, 2026-11-06.
