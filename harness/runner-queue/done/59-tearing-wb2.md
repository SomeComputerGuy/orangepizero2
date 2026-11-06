# Job 59-tearing-wb2 (TEST, ~15 min, 1 trial boot + restore, resumable between chunks, fails fast on Oops/WARN/IOMMU fault)
Rerun of job 58 with the event-hold fix and the fixed VE load. Package: harness/research/display-tearing/runner-wb/
(tearing-wb-job.sh + HANDOFF.md with checks 0-9).
Command: `bash harness/research/display-tearing/runner-wb/tearing-wb-job.sh`
What: DE33 display tearing, writeback proof (every frame a unique picture, a writeback capture of every frame, each must be
its own commit's picture), kernel latch counters, and now the flip-event ordering (`RESULT event_order`: every flip event
sent after its latch flush), idle bursts, and the same under 4K H.265 VE decode, memcpy load and a printk flood.
Kernel: c44 = test-cumulative cf976bccc, Image md5 a471ce426a7389b518b5420835b01f95 (or a later cumulative tag); must contain
93b00281a (fix/sunxi-h616-de33-latch-event; checked by the script). Installed and restored by the script.
Client: harness/kms-wb/out/kms-wb sha256 2730ba1fe6cc374a8f3605b9afd8e8477295a472224fb889b86832c8625cf895 (shipped by the script).
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/display-tearing/logs/runner-t59/ (results.txt). Text logs only, never capture dumps.
Summary: as listed in HANDOFF.md "Summary must list", to harness/runner-queue/done/59-tearing-wb2.summary.md.
Submitted by the display-tearing agent, 2026-11-06.
