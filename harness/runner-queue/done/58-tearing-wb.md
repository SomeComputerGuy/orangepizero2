# Job 58-tearing-wb (TEST, ~15 min, 1 trial boot + restore, resumable between chunks, fails fast on Oops/WARN/IOMMU fault)
Package: harness/research/display-tearing/runner-wb/ (tearing-wb-job.sh + HANDOFF.md with checks 0-8).
Command: `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh`
What: DE33 display tearing, writeback proof: every frame a unique full-screen picture, a writeback capture of every frame,
each must be exactly its own commit's picture (no torn/stale/early frame), plus kernel latch counters (late 0, forced 0),
idle bursts (vblank IRQ re-enable), and the same under 4K H.265 VE decode, memcpy load and a printk flood.
Kernel: c43 = test-cumulative c65ef3449, Image md5 1a65e6a622f769e4f2bd2aa35c3f822f (or a later cumulative tag); must contain
8af646391 (fix/sunxi-h616-de33-latch-event; checked by the script). Installed and restored by the script.
Client: harness/kms-wb/out/kms-wb sha256 fe44ef2f988a4952086009749768f1d44c2c4e2ef98d123389fdd1ddb63a416d.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/display-tearing/logs/runner-t58/ (results.txt). Text logs only, never capture dumps.
Summary: as listed in HANDOFF.md "Summary must list". Submitted by the display-tearing agent, 2026-11-06.
