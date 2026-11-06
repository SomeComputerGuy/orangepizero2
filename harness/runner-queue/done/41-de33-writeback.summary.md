# Job 41 summary (runner, 2026-11-06)
Job: de33-writeback wb41, kernel c35 (uname -v: #33 SMP PREEMPT Fri Nov  6 08:52:49 UTC 2026), run 09:13:59 - 09:19:13. Stock kernel restored, lock released.
Results: research/de33-writeback/logs/runner-wb41/ (results.txt, runner.log, files/wb/)
- 0 display: PASS (1024x768 mode available)
- 1 kernel lines: PASS (kernel #33..., dtb c35 fbb509889a4cba869d6985f4e549039a, writeback present card0-Writeback-1)
- 2 connector: PASS (formats XR24 AR24 XB24 AB24 RX24 RA24 BX24 BA24 RG24 BG24 XR30 NV12 NV21 YU12)
- 3 solid1: PASS (0 mismatches x3, fence_ms 31.8/21.5/21.5)
- 4, 5: not run (job 40 PASS)
- 6 tearing: FAIL on seq_gaps in d0, d4, d12 (all other keys pass)
  d0: flips_requested 300 frames_captured 300 torn 0 bad 0 fence_errors 0 seq_gaps 298 flip_rate 7.488 a/b 150/150 commits_outside_blanking 299/299 latch_late 0
  d4: 300 300 0 0 0 seq_gaps 298 flip_rate 7.353 150/150 outside 299/299 latch_flushes_late_delta 2
  d12: 300 300 0 0 0 seq_gaps 298 flip_rate 6.665 150/150 outside 299/299 latch_flushes_late_delta 1
  Note: flip_rate ~7 vs expected 29-31 (commit_phase mean 129 ms per flip in d0), so the client is slow, not tearing.
- 7 counters: PASS (jobs==done==300, failed 0 for all flips runs; busy_frames 0)
- 8 dmesg: PASS (dmesg_bad 0, dmesg_iommu 0; only drm line: sun4i-drm display-engine: [drm] fb0: sun4i-drmdrmfb frame buffer device)
No OOPS/BLOCKED. State: wb
