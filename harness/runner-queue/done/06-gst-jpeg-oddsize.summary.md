# 06-gst-jpeg-oddsize: FAIL (checks 2, 3, 4)
Kernel (kernel.txt): #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 7.3.1-edge-sunxi64 . Start 2026-11-05 20:34:25 UTC, end 20:36:39 UTC.
Checks: 1 FAIL (Rank primary + 1 (257)); 2 FAIL (9 pass, 3 fail); 3 FAIL (z33x17-422, z15x15-444 FAIL(c-ref)); 4 FAIL (mj-z33x17 FAIL(psnr)); 5 see results.txt; 6 see below; 7 picked contains v4l2jpegdec: PASS, dmesg +1055.
Case lines:
z17x33 [still 420]: PASS | vs ffmpeg max|d| Y/U/V 1/1/1, PSNR 64.83/69.98/65.21 dB; jpegdec Y PSNR 48.36 dB
z17x33-411 [still 411]: PASS | vs ffmpeg max|d| Y/U/V 1/1/0, PSNR 64.83/69.98/99.00 dB; jpegdec Y PSNR 48.36 dB
z33x17-422 [still 422]: FAIL(c-ref) | vs ffmpeg max|d| Y/U/V 1/47/33, PSNR 64.16/27.27/27.84 dB; jpegdec Y PSNR 48.04 dB
z15x15-444 [still 444]: FAIL(c-ref) | vs ffmpeg max|d| Y/U/V 1/66/114, PSNR 62.11/22.83/21.54 dB; jpegdec Y PSNR 47.01 dB
z1x1 [still 420]: PASS | vs ffmpeg max|d| Y/U/V 0/0/0, PSNR 99.00/99.00/99.00 dB; jpegdec Y PSNR 99.00 dB
z8x8 [still 420]: PASS | vs ffmpeg max|d| Y/U/V 1/1/0, PSNR 63.18/60.17/99.00 dB; jpegdec Y PSNR 48.63 dB
z1921x1081 [still 420]: PASS | vs ffmpeg max|d| Y/U/V 1/1/1, PSNR 65.28/66.54/66.40 dB; jpegdec Y PSNR 51.22 dB
z2049x64 [still 420]: PASS | vs ffmpeg max|d| Y/U/V 1/1/1, PSNR 65.31/65.97/65.62 dB; jpegdec Y PSNR 50.97 dB
z4095x2303 [still 420]: PASS | vs ffmpeg max|d| Y/U/V 1/1/1, PSNR 65.29/66.54/66.52 dB; jpegdec Y PSNR 51.29 dB
mjmix [clip 640x480*15,320x240*15]: PASS | hw vs jpegdec min PSNR Y/U/V 56.32/54.40/53.21 dB over 30 frames
mjmix-up [clip 320x240*15,640x480*15]: PASS | hw vs jpegdec min PSNR Y/U/V 56.32/54.40/53.21 dB over 30 frames
mj-z33x17 [clip 33x17*30]: FAIL(psnr) | hw vs jpegdec min PSNR Y/U/V 47.48/50.34/50.44 dB over 30 frames
SUMMARY: 9 pass, 3 fail
NORANK: norank rc=124 picked=[v4l2jpegdec v4l2jpegdec0 ] dmesg +1055
DMESG: 1055 lines
results.txt dmesg lines:
z17x33 dmesg +0
z17x33-411 dmesg +0
z33x17-422 dmesg +0
z15x15-444 dmesg +0
z1x1 dmesg +0
z8x8 dmesg +0
z1921x1081 dmesg +0
z2049x64 dmesg +0
z4095x2303 dmesg +0
mjmix dmesg +0
mjmix-up dmesg +0
mj-z33x17 dmesg +0
norank rc=124 picked=[v4l2jpegdec v4l2jpegdec0 ] dmesg +1055
Abnormal dmesg (first lines in compare.txt, see file for the rest):
  [  161.441034] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
  [  161.487059] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
  [  161.487092] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
  [  161.533056] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
Results: build/gst-jpeg/results-oddsize/
