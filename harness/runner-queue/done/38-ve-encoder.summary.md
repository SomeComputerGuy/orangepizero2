# Job 38-ve-encoder summary (runner, 2026-11-06)
Kernel: #31 SMP PREEMPT Fri Nov 6 08:21:32 UTC 2026 (c33, 342cfa31c); chunk 08:27:41-08:28:56; exit 0; stock kernel + DTB restored (7.3.1-edge-sunxi64 #17). No OOPS/BLOCKED. state: venc.
Encoder: Encoder registered as /dev/video1; controls 20; media /dev/media0.
1 probe PASS (probe_registered 1, encoder_node 1, boot_warnings 0, media_info 1, dec_D_rc 0)
2 compliance PASS (compliance_unexpected 0, compliance_failed 1 (known G/S_PARM), warnings 0, compliance_dec_fail 1 (known))
3 encode: r1-r6 PASS; r7 FAIL (rc 3: "open /root/venc/clips/testsrc2-854x480-10.nv12: No such file or directory"; package bug: the 854x480 clip was generated on host but never shipped to the board, only 720x480 was)
4 ffmpeg decode: r1-r6 PASS; r7 FAIL (no stream)
5 PSNR: r1-r6 PASS; r7 FAIL (no stream)
6 hwdec: r1-r4, r6 PASS; r5 FAIL (frames 5, md5 28209e62... vs ffmpeg edcc1ec6..., output 7879680 bytes vs 7868160 source; checks 3-5 PASS so decoder/GStreamer cropping at 1366x768, not the encoder); r7 SKIP
7 dmesg PASS (dmesg_bad 0, iommu 0, timeout 0, encode_failed 0; per run iommu 0 / timeout 0)
8 framing: r1-r6 PASS; r7 FAIL (no stream)
9 buffers: buffers_file 4 all; source_room 1 r1-r6 (r5 source 1607168 vs picture 1573632, the former fault fixed); r7 source_room 0 (source_bytes 529920 want 635904) because the run never ran (buffers.txt is a stale 720x480 one)
Results: harness/research/ve-encoder/logs/runner-venc/
