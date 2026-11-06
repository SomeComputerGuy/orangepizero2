# 12-gst-mpeg1: VERDICT FAIL (checks 1 and 9 FAIL; 0,2-8 PASS)
Start 2026-11-05 23:37:54 UTC, end 23:42:06 UTC.
```
stock 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026
cumulative c19 test-cumulative 36e31fcb3 2026-11-05 23:21:02 Image md5 e9581aab42b47c1f0bed977cc92dff0b
7.3.1 #19 SMP PREEMPT Thu Nov  5 23:14:46 UTC 2026
CHECK 0 kernels: PASS (stock 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 | cumulative c19 test-cumulative 36e31fcb3 2026-11-05 23:21:02 Image md5 e9581aab42b47c1f0bed977cc92dff0b 7.3.1 #19 SMP PREEMPT Thu Nov  5 23:14:46 UTC 2026)
CHECK 1 software fallback without MG1S: FAIL (stock MG1S lines=0; inspect: 0:00:00.057582954 3875 3875 INFO v4l2codecs-mpeg2dec gstv4l2codecmpeg2dec.c:1217:gst_v4l2_codec_mpeg2_dec_has_mpeg1: MPEG-1 not supported; mpegversion: 2 (gint);; ccm1 db: ccm1 db rc=1 d41d8cd98f00b204e9800998ecf8427e 0 irqs=0 picked=[])
CHECK 2 MG1S caps on the test kernel: PASS (	[1]: 'MG1S' (MPEG-1 Parsed Slice Data, compressed); 0:00:00.058253202 2914 2914 INFO v4l2codecs-mpeg2dec gstv4l2codecmpeg2dec.c:1212:gst_v4l2_codec_mpeg2_dec_has_mpeg1: MPEG-1 supported; mpegversion: 2 (gint); mpegversion: 1 (gint);)
CHECK 3 ccm1 hw md5: PASS (ccm1 hw rc=0 6b2806e022029f559b59ee5ca9e65d0d 49536 irqs=129 | simple: frames=129 exact=129 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0)
CHECK 4 tcela-18 D-pictures in hardware: PASS (tcela-18 hw rc=0 558727a58a5d67129eaf1f21f3792a7c 16070400 irqs=31 | tcela-18	720x480	dpic-ref: frames=31 exact=31 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0 | gstv4l2codecmpeg2dec.c:285:gst_v4l2_codec_mpeg2_dec_probe_d_pictures:<v4l2slmpeg2dec0> D-pictures are decoded by the device)
CHECK 5 IDCT envelope (MEI x2, tcela-16/19): PASS (MEI.stream16.long rc0=True frames=61/61 irqs=61 hw_max=2 env_max=2 ok; MEI.stream16v2 rc0=True frames=4/4 irqs=4 hw_max=2 env_max=2 ok; tcela-16 rc0=True frames=31/31 irqs=31 hw_max=2 env_max=3 ok; tcela-19 rc0=True frames=31/31 irqs=31 hw_max=2 env_max=2 ok)
CHECK 6 MPEG-2 regression: PASS (test: tcela-15 hw rc=0 4ba41b6b9cc4aa5d0cfe421d8a22db2c 31622400 irqs=61 | mcp10ccett hw rc=0 0706d9e882915d83a34c28308cb4a4c0 2488320 irqs=4; stock tcela-15: tcela-15 hw rc=0 4ba41b6b9cc4aa5d0cfe421d8a22db2c 31622400 irqs=61)
CHECK 7 autoplug picks v4l2slmpeg2dec: PASS (ccm1 db rc=0 6b2806e022029f559b59ee5ca9e65d0d 49536 irqs=129 picked=[v4l2slmpeg2dec0 ] | tcela-18 db rc=0 558727a58a5d67129eaf1f21f3792a7c 16070400 irqs=31 picked=[v4l2slmpeg2dec0 ] | tcela-15 db rc=0 4ba41b6b9cc4aa5d0cfe421d8a22db2c 31622400 irqs=61 picked=[v4l2slmpeg2dec0 ] | ccm1 pb3 rc=0 6b2806e022029f559b59ee5ca9e65d0d 49536 irqs=129 picked=[v4l2slmpeg2dec0 ])
CHECK 8 no hangs: PASS (no rc=124/137 in results.txt)
CHECK 9 dmesg: FAIL ([    0.001428] pid_max: default: 32768 minimum: 301
[    0.056269] NetLabel:  unlabeled traffic allowed by default
[    0.069680] PCI: CLS 0 bytes, default 64
[    0.195918] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
[    8.226326] systemd[1]: Queued start job for default target graphical.target.)
VERDICT: FAIL
--- out-stock/results.txt
ccm1 hw rc=1 d41d8cd98f00b204e9800998ecf8427e 0 irqs=0
tcela-15 hw rc=0 4ba41b6b9cc4aa5d0cfe421d8a22db2c 31622400 irqs=61
mcp10ccett hw rc=0 0706d9e882915d83a34c28308cb4a4c0 2488320 irqs=4
ccm1 db rc=1 d41d8cd98f00b204e9800998ecf8427e 0 irqs=0 picked=[]
tcela-18 db rc=1 d41d8cd98f00b204e9800998ecf8427e 0 irqs=0 picked=[]
tcela-15 db rc=0 4ba41b6b9cc4aa5d0cfe421d8a22db2c 31622400 irqs=61 picked=[v4l2slmpeg2dec0 ]
ccm1 pb3 rc=1   irqs=0 picked=[]
--- out-test/results.txt
ccm1 hw rc=0 6b2806e022029f559b59ee5ca9e65d0d 49536 irqs=129
tcela-18 hw rc=0 558727a58a5d67129eaf1f21f3792a7c 16070400 irqs=31
MEI.stream16.long hw rc=0 da9fcef3ce1e77ad48a294c3bc34ee36 7729920 irqs=61
MEI.stream16v2 hw rc=0 b41d28005d6e4652a0ddbad398c80555 506880 irqs=4
tcela-16 hw rc=0 bc0ada257db1b509b8bbd69fe81199c6 3928320 irqs=31
tcela-19 hw rc=0 e9f36ad0b98a9963873cf9bd6c61f28a 4571136 irqs=31
tcela-15 hw rc=0 4ba41b6b9cc4aa5d0cfe421d8a22db2c 31622400 irqs=61
mcp10ccett hw rc=0 0706d9e882915d83a34c28308cb4a4c0 2488320 irqs=4
ccm1 db rc=0 6b2806e022029f559b59ee5ca9e65d0d 49536 irqs=129 picked=[v4l2slmpeg2dec0 ]
tcela-18 db rc=0 558727a58a5d67129eaf1f21f3792a7c 16070400 irqs=31 picked=[v4l2slmpeg2dec0 ]
tcela-15 db rc=0 4ba41b6b9cc4aa5d0cfe421d8a22db2c 31622400 irqs=61 picked=[v4l2slmpeg2dec0 ]
ccm1 pb3 rc=0 6b2806e022029f559b59ee5ca9e65d0d 49536 irqs=129 picked=[v4l2slmpeg2dec0 ]
--- inspect MPEG-1/mpegversion
/home/aruni/orangepizero2/build/gst-mpeg1/results/out-stock/inspect.txt:0:00:00.057582954       3875       3875 INFO     v4l2codecs-mpeg2dec gstv4l2codecmpeg2dec.c:1217:gst_v4l2_codec_mpeg2_dec_has_mpeg1: MPEG-1 not supported
/home/aruni/orangepizero2/build/gst-mpeg1/results/out-stock/inspect.txt:            mpegversion: 2 (gint)
/home/aruni/orangepizero2/build/gst-mpeg1/results/out-test/inspect.txt:0:00:00.058253202       2914       2914 INFO     v4l2codecs-mpeg2dec gstv4l2codecmpeg2dec.c:1212:gst_v4l2_codec_mpeg2_dec_has_mpeg1: MPEG-1 supported
/home/aruni/orangepizero2/build/gst-mpeg1/results/out-test/inspect.txt:            mpegversion: 2 (gint)
/home/aruni/orangepizero2/build/gst-mpeg1/results/out-test/inspect.txt:            mpegversion: 1 (gint)
--- compare.tsv (200 cols)
ccm1	16x16	simple: frames=129 exact=129 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0	int: frames=129 exact=129 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 left
MEI.stream16.long	352x240	simple: frames=61 exact=0 maxdiff=2 psnrY_min=62.69 psnrY_mean=64.62 last_max=1 leftover_ref/test=0/0	int: frames=61 exact=0 maxdiff=3 psnrY_min=60.61 psnrY_mean=62.75 last_m
MEI.stream16v2	352x240	simple: frames=4 exact=0 maxdiff=2 psnrY_min=65.65 psnrY_mean=66.08 last_max=2 leftover_ref/test=0/0	int: frames=4 exact=0 maxdiff=2 psnrY_min=64.06 psnrY_mean=64.58 last_max=2 
tcela-16	352x240	simple: frames=31 exact=0 maxdiff=3 psnrY_min=60.88 psnrY_mean=62.94 last_max=1 leftover_ref/test=0/0	int: frames=31 exact=0 maxdiff=3 psnrY_min=58.84 psnrY_mean=61.04 last_max=1 left
tcela-19	768x128	simple: frames=31 exact=0 maxdiff=2 psnrY_min=62.42 psnrY_mean=64.17 last_max=2 leftover_ref/test=0/0	int: frames=31 exact=0 maxdiff=2 psnrY_min=60.66 psnrY_mean=62.46 last_max=2 left
tcela-15	720x480	simple: frames=61 exact=61 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0	int: frames=61 exact=61 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 le
mcp10ccett	720x576	simple: frames=4 exact=4 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0	int: frames=4 exact=4 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 left
tcela-18	720x480	dpic-ref: frames=31 exact=31 maxdiff=0 psnrY_min=99.00 psnrY_mean=99.00 last_max=0 leftover_ref/test=0/0
--- D-pictures
0:00:00.097553489       2933       2935 INFO     v4l2codecs-mpeg2dec gstv4l2codecmpeg2dec.c:285:gst_v4l2_codec_mpeg2_dec_probe_d_pictures:<v4l2slmpeg2dec0> D-pictures are decoded by the device
--- dmesg lines matching timed out|fault|Oops|WARNING|bug (grep -i): only boot lines pid_max/iommu/NetLabel/PCI/bridge/systemd (listed in CHECK 9), no real fault
```
Check 1 FAIL reason as printed: stock 'ccm1 db' rc=1 (hw/db/pb3 ccm1 and tcela-18 db rc=1 on stock, nothing decoded, picked=[]), expected rc=0 software fallback.
Results: build/gst-mpeg1/results/. Stock kernel restored, lock released.
