# Job 42-de33-writeback summary
Kernel: c35, uname -v: #33 SMP PREEMPT Fri Nov  6 08:52:49 UTC 2026; DTB c35 fbb509889a4cba869d6985f4e549039a; writeback: present
Start 2026-11-06 09:31:18, end 09:35:47 (stock kernel restored). Exit 0. State: wb 
Results: harness/research/de33-writeback/logs/runner-wb42/results.txt

Checks: 0 PASS (mode available), 1 PASS, 2 PASS (formats XR24 AR24 XB24 AB24 RX24 RA24 BX24 BA24 RG24 BG24 XR30 NV12 NV21 YU12), 3 PASS (solid1: 0 mismatches, fence_ms 31.8/21.6/21.5), 4/5 not run (job 40 PASS), 6 PASS d0/d4/d12, 7 PASS (jobs=done=300, failed 0, busy_frames 0), 8 PASS (dmesg_bad 0, dmesg_iommu 0)

| run | flip_rate | seq_gaps | seq_gap_max | frames_wrong | full_mismatch | torn/bad/fence | commit_ioctl avg/max | fence_wait avg/max | check avg/max | late_flushes |
|---|---|---|---|---|---|---|---|---|---|---|
| d0 | 60.003 | 0 | 0 | 0 | 0 | 0/0/0 | 0.143/0.187 | 0.069/12.347 | 4.297/4.844 | 1 |
| d4 | 60.004 | 0 | 0 | 0 | 0 | 0/0/0 | 0.151/0.256 | 0.071/12.375 | 4.307/5.012 | 1 |
| d12 | 60.003 | 0 | 0 | 0 | 0 | 0/0/0 | 0.164/0.327 | 0.073/12.467 | 4.364/5.958 | 1 |
frames_captured 300 each; commits_outside_blanking d0 0, d4 299/299, d12 299/299; latch_line_max_after 339/367/367; cpufreq_trans 2/2/0.

dmesg: none abnormal. iommu/drm lines:
[   47.406409] sun4i-drm display-engine: [drm] fb0: sun4i-drmdrmfb frame buffer device
