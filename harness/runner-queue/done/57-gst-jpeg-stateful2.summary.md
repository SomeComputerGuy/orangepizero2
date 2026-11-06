# Job 57-gst-jpeg-stateful2 summary

Start/end: see runner.log (end 2026-11-06 18:21:00). Kernel under test: cumulative c42 test-cumulative 2658acbe4 2026-11-06 18:07:36 Image md5 a33675cabd5e04a667475be57e51586c
#43 SMP PREEMPT Fri Nov  6 18:04:18 UTC 2026
7.3.1
Restored kernel (uname -v): #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 (7.3.1, stock image kernel)
BLOCKED: none. Exit 0. Board lock released. Run kernel dmesg lines: 0 matching; abnormal dmesg: none.

```
C0-references: PASS | sl-still rc=0 size=3133440; sl-loop5 rc=0 size=15667200; sl-mjmix rc=0 size=8640000; sl-mjmixup rc=0 size=8640000; 
C1-still: PASS | sf-still rc=0 md5=07bf2ea422e279b21fbd0bbdd145f743 size=3133440 dmesg=+0 cmdfail=0 stopwait=1 dmabuf=0 picked=[v4l2jpegdec v4l2jpegdec0 ] | ref md5=07bf2ea422e279b21fbd0bbdd145f743
C2-loop5: PASS | sf-loop5 rc=0 md5=54d0b425e4027cebd60321d8020422e2 size=15667200 dmesg=+0 cmdfail=0 stopwait=1 dmabuf=0 picked=[v4l2jpegdec v4l2jpegdec0 ] | ref md5=54d0b425e4027cebd60321d8020422e2
C3a-mjmix: PASS | sf-mjmix rc=0 md5=5f740f56cd207f0fafccd23331e864c5 size=8640000 dmesg=+0 cmdfail=0 stopwait=2 dmabuf=0 picked=[v4l2jpegdec v4l2jpegdec0 ] | ref md5=5f740f56cd207f0fafccd23331e864c5
C3b-mjmixup: PASS | sf-mjmixup rc=0 md5=8bdb981b1922f1ca6fd3fa8fccc2b019 size=8640000 dmesg=+0 cmdfail=0 stopwait=2 dmabuf=0 picked=[v4l2jpegdec v4l2jpegdec0 ] | ref md5=8bdb981b1922f1ca6fd3fa8fccc2b019
C4-norank16: PASS | nr16-db rc=0 md5=07bf2ea422e279b21fbd0bbdd145f743 size=3133440 dmesg=+0 cmdfail=0 stopwait=1 dmabuf=0 picked=[v4l2jpegdec v4l2jpegdec0 ]
C5-override: PASS | ov16-db rc=0 md5=07bf2ea422e279b21fbd0bbdd145f743 size=3133440 dmesg=+0 cmdfail=0 stopwait=0 dmabuf=0 picked=[v4l2sljpegdec v4l2sljpegdec0 ]
C6-h264: PASS | h264 rc=0 md5=84f81072e05e352aac552d86dc80aff2 size=13824000 dmesg=+0 cmdfail=0 stopwait=0 dmabuf=0 picked=[v4l2slh264dec v4l2slh264dec0 ] | md5 == ffmpeg
C8-h264mix: PASS | h264mix rc=0 md5=662e28ea07f37d3dc4432c87669d0251 size=8640000 dmesg=+0 cmdfail=0 stopwait=0 dmabuf=0 picked=[v4l2slh264dec v4l2slh264dec0 ] | md5 == ffmpeg
C7-dmesg: PASS | 0 kernel log lines, 0 matching errors
VERDICT: PASS
```

C6 md5 84f81072e05e352aac552d86dc80aff2 (== ffmpeg); C8 md5 662e28ea07f37d3dc4432c87669d0251 (== ffmpeg)
Logs: harness/runner-queue/done/57-logs/ ; full results build/gst-jpeg/results-stateful2/
