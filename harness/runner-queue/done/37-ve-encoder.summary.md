# Job 37-ve-encoder summary (c32, exit 3 OOPS)
Kernel: #30 SMP PREEMPT Fri Nov 6 08:04:57 UTC 2026 (c32); run 08:09-08:13 UTC 2026-11-06. Stock kernel 7.3.1-edge-sunxi64 #17 restored 08:13:18.
Encoder registered as /dev/video1.
Check 1 PASS (probe 1, encoder_node 1, controls 20, boot_warnings 0, media_node /dev/media0, media_info 1, dec_D_rc 0)
Check 2 PASS (compliance_unexpected 0, compliance_failed 1 [formats.cpp(1445), justified], warnings 0, compliance_dec_fail 1 [codecs.cpp(161), known])
Checks 3-6, 8: r1-r4 PASS; r5 FAIL (frame 0: timeout waiting for the encoder, rc 6, 0 frames, no stream; hwdec SKIP)
Check 7 FAIL: dmesg_bad 2, dmesg_iommu 1, dmesg_timeout 1 (all r5), encode_failed 0:
[   97.158212] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000fff83000 (master 3, dir rd, L2 page table, status 0x8)
[   99.183443] cedrus 1c0e000.video-codec: frame processing timed out!
Same address 0xfff83000 as job 35: not fixed for 1366x768.
| run | frames | keyf | bytes | avg_us | decoded | psnr_avg/min | hwdec md5 | sps/idr/p |
| r1 | 30 | 30 | 994139 | 3229 | 30 | 49.20/49.11 | match | 30/30/0 |
| r2 | 30 | 3 | 653763 | 3164 | 30 | 47.64/47.42 | match | 3/3/27 |
| r3 | 10 | 10 | 870745 | 7065 | 10 | 53.86/53.77 | match | 10/10/0 |
| r4 | 10 | 1 | 326899 | 6810 | 10 | 44.46/44.29 | match | 1/1/9 |
| r5 | 0 | 0 | 0 | 0 | - | - | SKIP | - |
r1 head_hex 000000016742c028965402802dd08000...
Results: harness/research/ve-encoder/logs/runner-venc/
