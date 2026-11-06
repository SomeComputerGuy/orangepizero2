# 32-ve-encoder: STALLED
Kernel c27 (uname -v #25 SMP PREEMPT Fri Nov  6 04:18:02 UTC 2026). Start 05:05:29, end 05:16:17 (2026-11-06). Job exit rc=2 (BLOCKED file: "board unreachable after restore"); state: STALLED.
- 1 probe: probe_registered 1, encoder_node 1: PASS. "kernel encoder: Encoder registered as /dev/video1"; controls 0 (expected 21): not reached. nodes: ENC /dev/video1 DEC /dev/video0
  dmesg-probe.txt also holds "[    0.244654]  cedrus_probe+0x398/0x440" and "[    0.244803]  cedrus_driver_init+0x28/0x38" (twice, trace lines after the Encoder registered line).
- 2 compliance: compliance_failed missing (not run): FAIL/not reached
- 3-6 encode r1..r5: all "venc rN missing 1" (no output): FAIL/not reached
- 7 dmesg: dmesg_bad 0, dmesg_iommu 0, dmesg_timeout 0, dmesg_encode_failed 0 (chunk dmesg only covers boot)
runner.log: "05:10:58 STALL: chunk venc no output for 180 s, killing ssh 2595678", "chunk venc ended without ROUND-DONE", "05:16:17 BOARD UNREACHABLE after restore reboot". Board answered ssh again ~5 min later on the stock kernel #17 with stock DTB symlink, no power cycle used.
Results: harness/research/ve-encoder/logs/runner-venc/
