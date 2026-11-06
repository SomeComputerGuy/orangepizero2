# Job 60-tearing-wb3 (TEST, ~16 min, 1 trial boot + restore, resumable between chunks, fails fast on Oops/WARN/IOMMU fault)
Rerun of job 59 with the writeback own-snapshot fix (job 59's 2 "early" captures in vemem-rand were the writeback unit
starting a capture one frame late, not the display). Package: harness/research/display-tearing/runner-wb/
(tearing-wb-job.sh + HANDOFF.md with checks 0-9; check 3 for load runs is now exact, see HANDOFF).
Command: `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh`
What: DE33 display tearing, writeback proof (every frame a unique picture, a writeback capture of every frame, each must be
its own commit's picture), kernel latch counters, flip-event ordering, idle bursts, and the same under 4K H.265 VE decode,
memcpy load, both (vemem-rand, vemem-rand2, vemem-rand3) and a printk flood.
Kernel: c45 = test-cumulative 7a7ee8e23, Image md5 751c43fc9fbcc188c93f8a20ee42daeb (or a later cumulative tag); must contain
3e0255e2f (fix/sunxi-h616-de33-latch-event; checked by the script). Installed and restored by the script.
Client: harness/kms-wb/out/kms-wb sha256 2730ba1fe6cc374a8f3605b9afd8e8477295a472224fb889b86832c8625cf895 (unchanged, shipped by the script).
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/display-tearing/logs/runner-t60/ (results.txt). Text logs only, never capture dumps.
Summary: as listed in HANDOFF.md "Summary must list", to harness/runner-queue/done/60-tearing-wb3.summary.md.
Submitted by the display-tearing agent, 2026-11-06.
