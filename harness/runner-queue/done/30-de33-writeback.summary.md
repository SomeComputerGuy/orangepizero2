# 30-de33-writeback: FAIL
Kernel: c27, uname -v "#25 SMP PREEMPT Fri Nov  6 04:18:02 UTC 2026", DTB c27 md5 fbb509889a4cba869d6985f4e549039a. Start 04:56:25, end 04:59:35 (2026-11-06). Exit 0, state: wb (1 of 1 chunks).
- 0 mode: 1024x768 available (mode 1024x768 total 1344x806 clock 65000): tested
- 1 kernel lines: "kernel: #25 SMP PREEMPT Fri Nov  6 04:18:02 UTC 2026", "kernel dtb: c27 (fbb509889a4cba869d6985f4e549039a)", "kernel writeback: present (/sys/class/drm/card0-Writeback-1 )": PASS
- 2 connector: writeback_connectors 1, wb_reaches_crtc 1, wb_format_offered 1, probe ok, rc 0: PASS. wb_formats: XR24 AR24 XB24 AB24 RX24 RA24 BX24 BA24 RG24 BG24 XR30 NV12 NV21 YU12
- 3 exact captures solid1-4, bars: FAIL. each rc 1, captures 3, captures_failed 3, capture0..2_fence_error -1. files/wb/solid1.txt: "atomic commit (flip + writeback): Invalid argument" (x3), same for all five runs
- 4 nv12: FAIL rc 1, captures_failed 3, same "atomic commit (flip + writeback): Invalid argument"
- 5 xr30 (info): rc 2, "dumb buffer: Invalid argument"
- 6 tearing d0/d4/d12: FAIL rc 2 each, frames_a 0, frames_b 0, flip_rate 0.000 (frames_captured 300 line is mislabelled, nothing was captured), frames_torn 0, frames_bad 0, fence_errors 0, seq_gaps 0; files/wb/flips-d0.txt "atomic commit (flip + writeback): Invalid argument"
- 7 counters: wb_jobs_delta 0 == wb_done_delta 0, wb_failed_delta 0 for all runs: PASS (no job ever reached the driver)
- 8 dmesg: wb all dmesg_bad 0, dmesg_iommu 0: PASS. Only DMESG line: [   47.617545] sun4i-drm display-engine: [drm] fb0: sun4i-drmdrmfb frame buffer device
Restored: 7.3.1-edge-sunxi64 #17, DTB .stock. Results: harness/research/de33-writeback/logs/runner-wb/ (results.txt, runner.log, chunk-wb.txt, files/wb/)
