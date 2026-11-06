# 17-iommu-faults: fixed chunk ALL PASS; stock control scanout N=0 (INCONCLUSIVE for scanout trigger), decode M=214
Start 2026-11-05 23:25:36 UTC, end 23:33:01 UTC.
stock: ROUND-DONE=1 PASS; scanout N=0 (trigger did not fire: INCONCLUSIVE per HANDOFF); decode M=214 (page faults seen on stock).
fixed: ROUND-DONE=1 PASS; [scanout] faults-new 0 PASS; [decode] faults-new 0 PASS; Page fault count chunk-fixed.txt 0 + dmesg-fixed.txt 0 PASS; timeouts 0 and no 'timed out' PASS.
```
kernel 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 faults-at-start 0
[scanout] status connected enabled disabled mode 1024x768 faults-new 0
[decode] h264-high-2160p30 x3 rc=0 rc=0 rc=0 faults-new 214 timeouts 0
kernel 7.3.1 #19 SMP PREEMPT Thu Nov  5 23:14:46 UTC 2026 faults-at-start 0
[scanout] status connected enabled disabled mode 1024x768 faults-new 0
[decode] h264-high-2160p30 x3 rc=0 rc=0 rc=0 faults-new 0 timeouts 0
--- [dmesg] lines stock (first 11 as in chunk)
[dmesg] [  163.314302] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  163.330917] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  163.430932] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  163.447700] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  163.464289] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  163.564307] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  163.580967] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  168.513862] sun50i_iommu_report_fault: 74 callbacks suppressed
[dmesg] [  168.513892] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  168.530540] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  168.547205] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[dmesg] [  168.563877] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
--- [dmesg] lines fixed
[dmesg] [    0.124328] iommu: Default domain type: Translated
[dmesg] [    0.124350] iommu: DMA domain TLB invalidation policy: strict mode
[dmesg] [    0.194179] platform 1420000.deinterlace: Adding to iommu group 0
[dmesg] [    0.194271] platform 1c0e000.video-codec: Adding to iommu group 0
[dmesg] [    0.302208] platform 1100000.planes: Adding to iommu group 0
--- dmesg-stock.txt (27 lines, all Page fault / suppressed-callback lines)
[  153.331685] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  153.348271] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  153.448326] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.081307] sun50i_iommu_report_fault: 69 callbacks suppressed
[  158.081360] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.097951] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.214637] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.231286] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.331238] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.447981] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.464610] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.564662] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.581250] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  158.681278] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.097557] sun50i_iommu_report_fault: 73 callbacks suppressed
[  163.097590] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.197631] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.214339] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.314302] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.330917] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.430932] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.447700] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.464289] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.564307] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  163.580967] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  168.513862] sun50i_iommu_report_fault: 74 callbacks suppressed
[  168.513892] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  168.530540] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  168.547205] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
[  168.563877] sun50i-iommu 30f0000.iommu: Page fault for 0x00000000f2300000 (master -1, dir rd)
--- dmesg-fixed.txt
[    0.001433] pid_max: default: 32768 minimum: 301
[    0.124328] iommu: Default domain type: Translated
[    0.124350] iommu: DMA domain TLB invalidation policy: strict mode
[    0.129015] NetLabel:  unlabeled traffic allowed by default
[    0.141567] PCI: CLS 0 bytes, default 64
[    0.194179] platform 1420000.deinterlace: Adding to iommu group 0
[    0.194271] platform 1c0e000.video-codec: Adding to iommu group 0
[    0.260690] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
[    0.302208] platform 1100000.planes: Adding to iommu group 0
[    8.268532] systemd[1]: Queued start job for default target graphical.target.
```
Results: harness/research/iommu-faults/logs/runner-iommu-faults/. Stock kernel restored, lock released.
