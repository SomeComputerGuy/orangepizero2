# Job 61-tearing-wb4 (TEST, ~16 min, 1 trial boot + restore, resumable between chunks, fails fast on Oops/WARN/IOMMU fault)
Rerun of job 60 with the writeback "replaced while busy" fix (job 60's 6 "early" WRONG captures under VE load were the
RT-WB unit beginning a capture one frame after its start, not the display). Package: harness/research/display-tearing/runner-wb/
(tearing-wb-job.sh + HANDOFF.md with checks 0-9; check 3 L now also has (f) for de33_wb_replaced).
Command: `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh`
What: DE33 display tearing, writeback proof (every frame a unique picture, a writeback capture of every frame, each must be
its own commit's picture), kernel latch counters, flip-event ordering, idle bursts, and the same under 4K H.265 VE decode,
memcpy load, both (vemem-rand, vemem-rand2, vemem-rand3) and a printk flood.
Kernel: c46 = test-cumulative 266499b02, Image md5 7b46b2a92515f23d7c1db63bb6e7a5d1 (or a later cumulative tag); must contain
906968398 (fix/sunxi-h616-de33-latch-event; checked by the script). Installed and restored by the script.
Client: harness/kms-wb/out/kms-wb sha256 2730ba1fe6cc374a8f3605b9afd8e8477295a472224fb889b86832c8625cf895 (unchanged, shipped by the script).
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/display-tearing/logs/runner-t61/ (results.txt). Text logs only, never capture dumps.
Summary: as listed in HANDOFF.md "Summary must list", to harness/runner-queue/done/61-tearing-wb4.summary.md.
Submitted by the display-tearing agent, 2026-11-06.
