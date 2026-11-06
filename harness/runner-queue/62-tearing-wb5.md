# Job 62-tearing-wb5 (TEST, ~16 min, 1 trial boot + restore, resumable between chunks, fails fast on Oops/WARN/IOMMU fault)
Rerun of job 61 with the writeback "stop an overtaken capture" fix and exact accounting (job 61: display clean; each
late RT-WB begin cost two captures, and one t-rand flip whose commit reached the latch after its vblank was not accounted).
Package: harness/research/display-tearing/runner-wb/ (tearing-wb-job.sh + HANDOFF.md with checks 0-9; check 3 L is now
exact per failure reason, check 5 accounts every vblank between flips).
Command: `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh`
What: DE33 display tearing, writeback proof (every frame a unique picture, a writeback capture of every frame, each must be
its own commit's picture), kernel latch counters, flip-event ordering, idle bursts, and the same under 4K H.265 VE decode,
memcpy load, both (vemem-rand, vemem-rand2, vemem-rand3) and a printk flood.
Kernel: c47 = test-cumulative 2dc70409e, Image md5 b3938b2633e1bcc7cf9d5262fa66b5d1 (or a later cumulative tag); must contain
825596b48 (fix/sunxi-h616-de33-latch-event; checked by the script). Installed and restored by the script.
Client: harness/kms-wb/out/kms-wb sha256 4970f3b2f4b8102099b6f75390b1db17efcac8a99e8bc4a763f8043e56bf0b12 (new, shipped by the script).
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/display-tearing/logs/runner-t62/ (results.txt). Text logs only, never capture dumps or marker files.
Summary: as listed in HANDOFF.md "Summary must list", to harness/runner-queue/done/62-tearing-wb5.summary.md.
Submitted by the display-tearing agent, 2026-11-06.
