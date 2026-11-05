# 03-soak3 summary: PASS
Job: vdec-job.sh soak3, rc=0. Kernel c9: kernel 7.3.1 #12 SMP PREEMPT Thu Nov  5 17:30:51 UTC 2026 clk 624000000 gpu powersave 306000000 vdd-gpu-sys 900000 . Start 2026-11-05T18:57:24+00:00, end 2026-11-05T20:12:45+00:00.
Results: harness/research/vdec-perf/logs/runner-soak3/
## Per chunk
| chunk | N | I | O | X | T | V | Z | ROUND-DONE |
|---|---|---|---|---|---|---|---|---|
| 1 | 534 | 1 | 6 | 0 | 61217 | 900000 | 0 | 1 |
| 2 | 525 | 1 | 6 | 0 | 62351 | 900000 | 0 | 1 |
| 3 | 526 | 1 | 6 | 0 | 62189 | 900000 | 0 | 1 |
| 4 | 525 | 1 | 6 | 0 | 63080 | 900000 | 0 | 1 |
| 5 | 530 | 1 | 6 | 0 | 63161 | 900000 | 0 | 1 |
| 6 | 530 | 1 | 6 | 0 | 61946 | 900000 | 0 | 1 |
| 7 | 531 | 1 | 6 | 0 | 62513 | 900000 | 0 | 1 |
| 8 | 523 | 1 | 6 | 0 | 62918 | 900000 | 0 | 1 |
## Checks
- one [soak] line, ROUND-DONE, no download failed per chunk: PASS
- sum N = 4224 (>= 3600): PASS
- X = 0 every chunk: PASS; Z = 0 every chunk: PASS
- T < 85000 every chunk (max 63161): PASS; V = 900000 every chunk: PASS
- no [FAIL line: PASS
## dmesg IOMMU/timeout/fault lines
```
dmesg-8.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-8.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-8.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-8.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-8.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-8.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-8.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-8.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-8.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-8.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
dmesg-4.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-4.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-4.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-4.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-4.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-4.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-4.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-4.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-4.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-4.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
dmesg-5.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-5.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-5.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-5.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-5.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-5.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-5.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-5.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-5.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-5.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
dmesg-6.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-6.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-6.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-6.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-6.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-6.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-6.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-6.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-6.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-6.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
dmesg-1.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-1.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-1.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-1.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-1.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-1.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-1.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-1.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-1.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-1.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
dmesg-3.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-3.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-3.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-3.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-3.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-3.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-3.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-3.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-3.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-3.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
dmesg-7.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-7.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-7.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-7.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-7.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-7.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-7.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-7.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-7.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-7.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
dmesg-2.txt:[    0.001433] pid_max: default: 32768 minimum: 301
dmesg-2.txt:[    0.124451] iommu: Default domain type: Translated
dmesg-2.txt:[    0.124473] iommu: DMA domain TLB invalidation policy: strict mode
dmesg-2.txt:[    0.128975] NetLabel:  unlabeled traffic allowed by default
dmesg-2.txt:[    0.141677] PCI: CLS 0 bytes, default 64
dmesg-2.txt:[    0.201255] platform 1420000.deinterlace: Adding to iommu group 0
dmesg-2.txt:[    0.201346] platform 1c0e000.video-codec: Adding to iommu group 0
dmesg-2.txt:[    0.267997] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
dmesg-2.txt:[    0.309110] platform 1100000.planes: Adding to iommu group 0
dmesg-2.txt:[    8.289412] systemd[1]: Queued start job for default target graphical.target.
```
