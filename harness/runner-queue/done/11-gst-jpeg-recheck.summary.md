# 11-gst-jpeg-recheck: FAIL on checks 1 and 8 (checks 0,2-7 PASS)
Start 2026-11-05 23:07:26 UTC, end 23:11:19 UTC.
kernel.txt:
```
cumulative c17 test-cumulative 7897dec08 2026-11-05 22:09:58 Image md5 22330a4caccc513b757e743934c2700f
#18 SMP PREEMPT Thu Nov  5 22:07:30 UTC 2026
7.3.1
```
0 not blocked: PASS (cumulative c17)
1 INSPECT: FAIL (tag is FAIL(name), not PASS; KSIZES=1 and sink-range ok present)
```
INSPECT: FAIL(name) | KSIZES=1; sink-range ok width=[1,4096] height=[1,2304]
SUMMARY: 8 pass, 0 fail, 0 skipped
NORANK: norank rc=0 picked=[v4l2sljpegdec v4l2sljpegdec0 ] dmesg +0
DMESG: clean
```
2 cases: PASS (8 pass, 0 fail, 0 skipped); 3,4,5 PASS; 6 no rc=124/137: PASS; 7 all dmesg +0: PASS
8 norank: FAIL against expectation: picked=[ does not contain v4l2jpegdec (picked v4l2sljpegdec v4l2sljpegdec0), rc=0, dmesg +0; out/norank.gstdebug.txt 442 bytes (recorded only).
Case lines:
```
s420 [still 420]: PASS | vs reference max|d| Y/U/V 1/1/1, PSNR 65.27/66.52/66.39 dB; hw vs jpegdec Y PSNR 51.30 dB (info)
z17x33-411 [still 411]: PASS | vs reference max|d| Y/U/V 1/1/0, PSNR 64.83/69.98/99.00 dB; hw vs jpegdec Y PSNR 48.36 dB (info)
z33x17-422 [still 422]: PASS | vs reference max|d| Y/U/V 1/1/1, PSNR 64.16/63.96/61.53 dB; hw vs jpegdec Y PSNR 48.04 dB (info)
z15x15-444 [still 444]: PASS | vs reference max|d| Y/U/V 1/1/1, PSNR 62.11/66.19/66.19 dB; hw vs jpegdec Y PSNR 47.01 dB (info)
z1x1 [still 420]: PASS | vs reference max|d| Y/U/V 0/0/0, PSNR 99.00/99.00/99.00 dB; hw vs jpegdec Y PSNR 99.00 dB (info)
z8x8 [still 420]: PASS | vs reference max|d| Y/U/V 1/1/0, PSNR 63.18/60.17/99.00 dB; hw vs jpegdec Y PSNR 48.63 dB (info)
z4096x4096 [size 420]: PASS | refused by the caps, decoded by jpegdec
mj-z33x17 [clip 33x17*30]: PASS | vs reference max|d| Y/U/V 1/1/1 over 30 frames; hw vs jpegdec min PSNR Y/U/V 47.48/50.34/50.44 dB (info)
```
runner.log: 2026-11-05 23:11:18 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64; no BLOCKED
Results: build/gst-jpeg/results-recheck/
