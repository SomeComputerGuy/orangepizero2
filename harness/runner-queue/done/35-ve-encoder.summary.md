# Job 35-ve-encoder: FAIL (OOPS, exit 3)
Kernel: c31 `#29 SMP PREEMPT Fri Nov 6 07:41:56 UTC 2026`; start 07:45:40, end 07:49:38; stock kernel restored (7.3.1-edge-sunxi64 #17).
OOPS file: `[88.351829] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000fff83000 (master 3, dir rd, L2 page table, status 0x8)` then `[90.352755] cedrus 1c0e000.video-codec: frame processing timed out!`
Checks: 1 probe PASS (probe_registered 1, encoder_node 1, controls 20, boot_warnings 0, media_node /dev/media0, media_info 1, dec_D_rc 0; encoder /dev/video1).
2 compliance FAIL: compliance_failed 1, compliance_unexpected 1, warnings 0; unexpected line `fail: v4l2-test-codecs.cpp(161): ret` (plus the justified G/S_PARM fail).
3 encode FAIL: r1 rc 0 frames 30 bytes 993509 keyframes 30 avg_us 3228 max_us 3275 but ffmpeg_errors 16, decoded 0, hwdec_frames 0 (md5 of empty). r2+ aborted by fail-fast.
7 dmesg FAIL: dmesg_bad 2, dmesg_iommu 1, dmesg_timeout 1, dmesg_encode_failed 0.
Results: harness/research/ve-encoder/logs/runner-venc/ (OOPS, results.txt, files/venc/).
