# Job 40 de33-writeback (wb40) summary
Kernel: `#33 SMP PREEMPT Fri Nov  6 08:52:49 UTC 2026` (c35, DTB c35 fbb509889a4cba869d6985f4e549039a, writeback: present card0-Writeback-1). Start 09:05:29, end 09:09:53 on 2026-11-06. Stock kernel restored (7.3.1-edge-sunxi64).
Results: harness/research/de33-writeback/logs/runner-wb40/ (results.txt, runner.log, files/wb/)
0 NOT applicable (mode available): PASS
1 kernel/dtb/writeback lines: PASS
2 probe: connectors 1, reaches_crtc 1, format_offered 1, probe ok, rc 0: PASS; formats XR24 AR24 XB24 AB24 RX24 RA24 BX24 BA24 RG24 BG24 XR30 NV12 NV21 YU12
3 solid1-4 + bars exact: PASS (all mismatches 0, captures_failed 0, fence 18.9-33.4 ms)
4 NV12: PASS (mismatches 0, max_dev 0)
5 XR30: PASS (no buffer errno, rc 0; mismatches 0, max_dev 0)
6 Tearing flips-d0/d4/d12: FAIL: rc 139 (kms-wb client SIGSEGV) in all three; files/wb/flips-*.txt contain only "RC 139"; no flips_requested/frames_captured keys. No kernel oops.
7 Counters: solid/bars/nv12/xr30 jobs==done, failed 0: PASS. flips runs jobs=done=1, failed 0 (client crashed after first capture). busy_frames 0, status_last 16.
8 dmesg_bad 0, dmesg_iommu 0: PASS. Only drm line: "sun4i-drm display-engine: [drm] fb0: sun4i-drmdrmfb frame buffer device".
OOPS/BLOCKED: none. State: wb
