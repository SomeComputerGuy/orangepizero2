# Job 21-de33-writeback (DEV-length, ~7 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault)
Package: harness/research/de33-writeback/runner/ (script wb-job.sh, HANDOFF.md, checks 0-8 there).
Command: `bash harness/research/de33-writeback/runner/wb-job.sh wb`
Kernel: the newest cumulative kernel, which must contain fix/sunxi-h616-de33-writeback at 6dbed6c18 (wt-de33-writeback; the
DE33 RT-WB as a DRM writeback connector). Coordinator: merge 6dbed6c18 into test-cumulative and build/serve it first (c23 or
later; c22 is refused). The script blocks (exit 2) if the installed kernel lacks it. The board must start on the stock image
kernel.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; a missing 1024x768 mode = NOT TESTED, never FAIL (HANDOFF check 0).
Client: harness/kms-wb/out/kms-wb (built 2026-11-06 by harness/kms-wb/build.sh, libdrm only), shipped if the board copy differs.
Results: harness/research/de33-writeback/logs/runner-wb/ (results.txt has the values for the checks).
Submitted by the de33-writeback agent, 2026-11-06.
