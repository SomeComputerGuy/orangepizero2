# 22-gst-jpeg-recheck2: PASS (checks 0-5, 8, 9 recorded; 6 and 7 only the norank16 line deviates, expected per check 9)
Start 2026-11-06 01:32:58 UTC, end 01:39:05 UTC.
```
cumulative c24 test-cumulative eb446f8cb 2026-11-06 00:50:11 Image md5 3de93f5e0a45c26e1be069814cd313a7
#23 SMP PREEMPT Fri Nov  6 00:46:05 UTC 2026
7.3.1
INSPECT: PASS | KSIZES=1; sink-range ok width=[1,4096] height=[1,2304]
SUMMARY: 8 pass, 0 fail, 0 skipped
NORANK: PASS | norank rc=0 picked=[v4l2sljpegdec v4l2sljpegdec0 ] dmesg +0 stateful-empty-caps=1
NORANK16: norank16 rc=124 picked=[v4l2jpegdec v4l2jpegdec0 ] dmesg +133 stateful-empty-caps=0 (recorded)
DMESG: 131 lines
s420 [still 420]: PASS | vs reference max|d| Y/U/V 1/1/1, PSNR 65.27/66.52/66.39 dB; hw vs jpegdec Y PSNR 51.30 dB (info)
z17x33-411 [still 411]: PASS | vs reference max|d| Y/U/V 1/1/0, PSNR 64.83/69.98/99.00 dB; hw vs jpegdec Y PSNR 48.36 dB (info)
z33x17-422 [still 422]: PASS | vs reference max|d| Y/U/V 1/1/1, PSNR 64.16/63.96/61.53 dB; hw vs jpegdec Y PSNR 48.04 dB (info)
z15x15-444 [still 444]: PASS | vs reference max|d| Y/U/V 1/1/1, PSNR 62.11/66.19/66.19 dB; hw vs jpegdec Y PSNR 47.01 dB (info)
z1x1 [still 420]: PASS | vs reference max|d| Y/U/V 0/0/0, PSNR 99.00/99.00/99.00 dB; hw vs jpegdec Y PSNR 99.00 dB (info)
z8x8 [still 420]: PASS | vs reference max|d| Y/U/V 1/1/0, PSNR 63.18/60.17/99.00 dB; hw vs jpegdec Y PSNR 48.63 dB (info)
z4096x4096 [size 420]: PASS | refused by the caps, decoded by jpegdec
mj-z33x17 [clip 33x17*30]: PASS | vs reference max|d| Y/U/V 1/1/1 over 30 frames; hw vs jpegdec min PSNR Y/U/V 47.48/50.34/50.44 dB (info)
--- restored
2026-11-06 01:39:02 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 
-rw-r--r-- 1 aruni aruni 8000000 Nov  6 01:37 /home/aruni/orangepizero2/build/gst-jpeg/results-recheck/out/norank16.gstdebug.txt
```
Checks 6/7: rc=124 and dmesg +133 occur only on the norank16 line (expected there per HANDOFF check 9); one cedrus line in the dmesg copy: [   92.137664] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
No BLOCKED. Results: build/gst-jpeg/results-recheck/
