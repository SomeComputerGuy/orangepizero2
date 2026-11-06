# Job 56 gst-jpeg-stateful summary
Run 2026-11-06 17:47:31 - 17:50:56. Kernel: cumulative c41 test-cumulative 39b1dce3f 2026-11-06 17:42:06 Image md5 13c7bb0046eed804e3e20da58518869d
Running kernel: #42 SMP PREEMPT Fri Nov 6 17:38:38 UTC 2026 (7.3.1). Restored stock kernel (ssh via harness/ssh.sh): #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026

```
C0-references: FAIL | sl-still rc=0 size=3133440; sl-loop5 rc=0 size=15667200; sl-mjmix rc=1 size=6912000; sl-mjmixup rc=1 size=1728000; 
C1-still: PASS | sf-still rc=0 md5=07bf2ea422e279b21fbd0bbdd145f743 size=3133440 dmesg=+0 cmdfail=0 stopwait=1 picked=[v4l2jpegdec v4l2jpegdec0 ] | ref md5=07bf2ea422e279b21fbd0bbdd145f743
C2-loop5: PASS | sf-loop5 rc=0 md5=54d0b425e4027cebd60321d8020422e2 size=15667200 dmesg=+0 cmdfail=0 stopwait=1 picked=[v4l2jpegdec v4l2jpegdec0 ] | ref md5=54d0b425e4027cebd60321d8020422e2
C3a-mjmix: FAIL | sf-mjmix rc=1 md5=d41d8cd98f00b204e9800998ecf8427e size=0 dmesg=+0 cmdfail=0 stopwait=0 picked=[] | ref md5=f947132e4760d332b56f4b3a70213945
C3b-mjmixup: FAIL | sf-mjmixup rc=1 md5=d41d8cd98f00b204e9800998ecf8427e size=0 dmesg=+0 cmdfail=0 stopwait=0 picked=[] | ref md5=7f731378f122fc047276ce1dd22c20f5
C4-norank16: FAIL | nr16-db rc=0 md5=d41d8cd98f00b204e9800998ecf8427e size=0 dmesg=+0 cmdfail=0 stopwait=1 picked=[v4l2jpegdec v4l2jpegdec0 ]
C5-override: PASS | ov16-db rc=0 md5=07bf2ea422e279b21fbd0bbdd145f743 size=3133440 dmesg=+0 cmdfail=0 stopwait=0 picked=[v4l2sljpegdec v4l2sljpegdec0 ]
C6-h264: PASS | h264 rc=0 md5=84f81072e05e352aac552d86dc80aff2 size=13824000 dmesg=+0 cmdfail=0 stopwait=0 picked=[v4l2slh264dec v4l2slh264dec0 ] | md5 == ffmpeg
C7-dmesg: PASS | 0 kernel log lines, 0 matching errors
VERDICT: FAIL
```

dmesg lines in run: 0 (out/dmesg.txt empty). C6 md5 == ffmpeg.
Failure causes: sl-mjmix/sl-mjmixup (reference) and sf-mjmix/sf-mjmixup fail with matroskademux not-negotiated (-4), rc=1; C4 nr16-db rc=0 but size=0 (EOS in 1.4ms, no output, picked v4l2jpegdec, stopwait=1).
Note: plain ssh to 10.56.0.107 gives host-key-changed warning; harness/ssh.sh works.
Copied logs: harness/runner-queue/done/56-logs/
