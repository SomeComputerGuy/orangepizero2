# 11-mpeg1-mg1s: VERDICT FAIL (only check 9 FAIL; checks 0-8 PASS)
Start 2026-11-06 02:17:00 UTC, end 02:24:05 UTC.
```
cumulative c25 test-cumulative 04964f921 2026-11-06 01:52:16 Image md5 de8e87b28a1cb43b3b96d83c69f3577e
7.3.1 #24 SMP PREEMPT Fri Nov  6 01:50:06 UTC 2026
stock 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026
CHECK 0 kernel: PASS (cumulative c25 test-cumulative 04964f921 2026-11-06 01:52:16 Image md5 de8e87b28a1cb43b3b96d83c69f3577e 7.3.1 #24 SMP PREEMPT Fri Nov  6 01:50:06 UTC 2026)
CHECK 1 stock formats: PASS (stock kernel stock 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 has no MG1S: 19 formats listed)
CHECK 2 software fallback without MG1S: PASS (2/2 streams same=1 irqs=0)
CHECK 3 MG1S enumerated on cedrus: PASS (== /dev/video0 cedrus driver=cedrus :: 	[1]: 'MG1S' (MPEG-1 Parsed Slice Data, compressed); framesizes: ioctl: VIDIOC_ENUM_FRAMESIZES 	Size: Stepwise 16x16 - 4096x2304 with step 16/16 -- MG2S )
CHECK 4 v4l2-compliance: PASS (test: Total for cedrus device /dev/video0: 49, Succeeded: 48, Failed: 1, Warnings: 0; stock: Total for cedrus device /dev/video0: 49, Succeeded: 43, Failed: 6, Warnings: 0)
CHECK 5 ccm1 md5 in hardware: PASS (m1-ccm1	mpeg2/ccm1.mpg	rc=0	irqs=129	PASS	match=129/129	hw_frames=129	first_bad=-)
CHECK 6 tcela-18 D-pictures in hardware: PASS (m1-tcela-18	mpeg2/tcela-18.bits	720x480	rc=0	irqs=31	vs-dpic-ref: frames=31 exact=31 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0 [mpeg1video @ 0xaaaad50129d0] D-pictures are decoded by the device )
CHECK 7 IDCT envelope (MEI x2, tcela-16/19, 1080p30): PASS (m1-MEI.stream16 frames=61/61 irqs=61 hw_max=2 env_max=2 ok; m1-MEI frames=4/4 irqs=4 hw_max=2 env_max=2 ok; m1-tcela-16 frames=31/31 irqs=31 hw_max=2 env_max=3 ok; m1-tcela-19 frames=31/31 irqs=31 hw_max=2 env_max=2 ok; g-mpeg1-1080p30 frames=300/300 irqs=300 hw_max=3 env_max=4 ok)
CHECK 8 MPEG-2 regression: PASS (m2-tcela-15	mpeg2/tcela-15.bits	rc=0	irqs=61	PASS	match=61/61	hw_frames=61	first_bad=- | m2-mcp10ccett	mpeg2/mcp10ccett.bits	rc=0	irqs=4	PASS	match=4/4	hw_frames=4	first_bad=-)
CHECK 9 dmesg: FAIL ([    0.001432] pid_max: default: 32768 minimum: 301
[    0.128741] NetLabel:  unlabeled traffic allowed by default
[    0.141557] PCI: CLS 0 bytes, default 64
[    0.267250] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
[    8.293402] systemd[1]: Queued start job for default target graphical.target.)
VERDICT: FAIL
--- swfb-stock.tsv
m1-ccm1	hwaccel_md5=6b2806e022029f559b59ee5ca9e65d0d	sw_md5=6b2806e022029f559b59ee5ca9e65d0d	same=1	irqs=0
m1-tcela-16	hwaccel_md5=5854d5fadf7251a78b8ff5e15d2ad193	sw_md5=5854d5fadf7251a78b8ff5e15d2ad193	same=1	irqs=0
--- fmts-test.txt
== /dev/video0 cedrus driver=cedrus
	[0]: 'MG2S' (MPEG-2 Parsed Slice Data, compressed)
	[1]: 'MG1S' (MPEG-1 Parsed Slice Data, compressed)
	[2]: 'S264' (H.264 Parsed Slice Data, compressed)
	[3]: 'S265' (HEVC Parsed Slice Data, compressed)
	[4]: 'VP8F' (VP8 Frame, compressed)
	[5]: 'VP9F' (VP9 Frame, compressed)
	[6]: 'JPEG' (JFIF JPEG, compressed)
	[7]: 'AVS2' (AVS2 Frame, compressed)
	[8]: 'AVSF' (AVS1/AVS+ Frame, compressed)
	[9]: 'SVC1' (VC-1 Parsed Slice Data, compressed)
	[10]: 'MG4S' (MPEG-4 Part 2 Parsed VOP Data, compressed)
	[11]: 'S263' (H.263 Parsed Picture Data, compressed)
	[12]: 'SPKS' (Sorenson Spark Parsed Data, compressed)
== /dev/video1 sun50i-di300 driver=sun50i-di300
	[0]: 'NV12' (Y/UV 4:2:0)
	[1]: 'NV21' (Y/VU 4:2:0)
	[2]: 'YU12' (Planar YUV 4:2:0)
	[3]: 'YV12' (Planar YVU 4:2:0)
	[4]: 'NV16' (Y/UV 4:2:2)
	[5]: 'NV61' (Y/VU 4:2:2)
	[6]: '422P' (Planar YUV 4:2:2)
--- Total for
../mpeg1-mg1s/logs/runner/compliance-test.txt:Total for cedrus device /dev/video0: 49, Succeeded: 48, Failed: 1, Warnings: 0
../mpeg1-mg1s/logs/runner/compliance-stock.txt:Total for cedrus device /dev/video0: 49, Succeeded: 43, Failed: 6, Warnings: 0
--- dpic.txt
m1-tcela-18	mpeg2/tcela-18.bits	720x480	rc=0	irqs=31	vs-dpic-ref: frames=31 exact=31 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0
[mpeg1video @ 0xaaaad50129d0] D-pictures are decoded by the device
--- raw.tsv (200 cols)
m1-MEI.stream16	mpeg2/MEI.stream16.long	352x240	rc=0	irqs=61	simple: frames=61 exact=0 maxdiff=2 psnrY_min=62.69 psnrY_mean=64.62 last_max=1 leftover_ref/test=0/0	int: frames=61 exact=0 maxdiff=3 psnr
m1-MEI	mpeg2/MEI.stream16v2	352x240	rc=0	irqs=4	simple: frames=4 exact=0 maxdiff=2 psnrY_min=65.65 psnrY_mean=66.08 last_max=2 leftover_ref/test=0/0	int: frames=4 exact=0 maxdiff=2 psnrY_min=64.06 psn
m1-tcela-16	mpeg2/tcela-16.bits	352x240	rc=0	irqs=31	simple: frames=31 exact=0 maxdiff=3 psnrY_min=60.88 psnrY_mean=62.94 last_max=1 leftover_ref/test=0/0	int: frames=31 exact=0 maxdiff=3 psnrY_min=58
m1-tcela-19	mpeg2/tcela-19.bits	768x128	rc=0	irqs=31	simple: frames=31 exact=0 maxdiff=2 psnrY_min=62.42 psnrY_mean=64.17 last_max=2 leftover_ref/test=0/0	int: frames=31 exact=0 maxdiff=2 psnrY_min=60
g-mpeg1-1080p30	gen/mpeg1-1080p30.m1v	1920x1080	rc=0	irqs=300	simple: frames=300 exact=0 maxdiff=3 psnrY_min=64.04 psnrY_mean=69.67 last_max=1 leftover_ref/test=0/0	int: frames=300 exact=0 maxdiff=4 p
--- md5/summary.tsv
m1-ccm1	mpeg2/ccm1.mpg	rc=0	irqs=129	PASS	match=129/129	hw_frames=129	first_bad=-
--- mpeg2/summary.tsv
m2-tcela-15	mpeg2/tcela-15.bits	rc=0	irqs=61	PASS	match=61/61	hw_frames=61	first_bad=-
m2-mcp10ccett	mpeg2/mcp10ccett.bits	rc=0	irqs=4	PASS	match=4/4	hw_frames=4	first_bad=-
--- dmesg lines matched by the check (boot lines only: pid_max, NetLabel, PCI, bridge, systemd as listed in CHECK 9; no timed out/fault/Oops/WARNING)
```
FFmpeg deb out/debs-media/ffmpeg_8.1.2-2ubuntu2+opiz2.3_arm64.deb: does not exist (fact only).
Results: harness/mpeg1-mg1s/logs/runner/. Stock kernel restored.
