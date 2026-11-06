# Job 34-ve-encoder summary: FAIL (OOPS-class abort exit 3: IOMMU page faults + engine timeouts)
Kernel c29: `#27 SMP PREEMPT Fri Nov 6 06:50:26 UTC 2026`; dtb c29 fbb509889a4cba869d6985f4e549039a; encoder at /dev/video1. Start ~07:03, end 07:06:44. Stock kernel+DTB restored. Job aborted exit 3.
Media-controller values (check 1): boot_warnings 0 (PASS), dec_D_rc 0 (PASS, topology hang gone), media_info 1, media_node none (/sys/class/media/media*/model missing).
probe: encoder_node 1, probe_registered 1, controls 21. compliance_failed 4, compliance_warnings 0 (FAIL).
Encodes: r1..r5 all rc 6, output .h264 files 0 bytes.
dmesg: dmesg_bad 10, dmesg_iommu 5, dmesg_timeout 5, dmesg_encode_failed 2 (all FAIL). Exact lines (logs/runner-venc/OOPS):
[   61.545794] sun50i-iommu 30f0000.iommu: Page fault for 0x0000000000000000 (master 3, dir rd, L1 page table, status 0x8)
[   63.550841] cedrus 1c0e000.video-codec: frame processing timed out!
(repeated 5x, last: 72.638779 timeout; faults at 63.735800, 66.092005, 68.341262, 70.635662)
state: ROUND-DONE
Results: harness/research/ve-encoder/logs/runner-venc/{results.txt,runner.log,OOPS,chunk-venc.txt,files/}
