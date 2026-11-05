# 02-gst-jpeg summary: FAIL (checks 4 and 7)
Job: harness/gst-jpeg/run-job.sh, rc=0. Kernel: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 7.3.1-edge-sunxi64 . Start 2026-11-05T18:53:45+00:00, end 2026-11-05T18:57:03+00:00.
Results: build/gst-jpeg/results/ (compare.txt, out/results.txt, out/dmesg.txt, out/inspect.txt)
## Checks
1. inspect: PASS (v4l2sljpegdec present, Rank primary + 1 (257))
2. hw decode rc=0 and size>0 (11 names): PASS
3. hw==drv EXACT (s420 s422 s444 s411 dri7 nodht opt420): PASS
4. quality: FAIL. Y PSNR >= 48 holds (s420 dri7 nodht opt420 51.30, mj420 59.25) but Y max|d| <= 2 does not: s420 4, dri7 4, nodht 4, opt420 4, mj420 3.
5. autoplug hw: PASS
6. autoplug fallback: PASS (picked jpegdec0 for grey prog s440 mjpeg422 mj422 mj444)
7. no hangs: FAIL by the literal check: out/results.txt line "norank s420 rc=124 picked=[v4l2jpegdec v4l2jpegdec0 ]" has rc=124 (no other rc=124/137).
8. errors clean (crtable hw rc=0, trunc hw rc=0): PASS
9. mjmix hw rc=0: PASS
10. norank picked contains v4l2jpegdec: PASS
11. perf mj1080: v4l2sljpegdec 10741 ms, jpegdec 4871 ms
## Other lines worth noting (not part of the checks)
- compare.txt: z17x33 and z17x33-411 "hw==drv DIFF"; mj422 and mj444 "no hw output"; z4096x4096 hw rc=1.
## compare.txt
```
s420: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.30/51.40/51.34 dB, max|d| 4/2/3
s422: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.30/43.91/43.55 dB, max|d| 4/17/25
s444: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.30/41.30/40.89 dB, max|d| 4/54/44
s411: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.30/4.41/4.28 dB, max|d| 4/255/255
dri7: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.30/51.40/51.34 dB, max|d| 4/2/3
nodht: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.30/51.40/51.34 dB, max|d| 4/2/3
opt420: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.30/51.40/51.34 dB, max|d| 4/2/3
z16x16: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 46.67/51.01/52.39 dB, max|d| 4/2/1
z2049x64: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 50.97/51.37/51.11 dB, max|d| 4/2/3
z4096x2304: frames hw 1 sw 1 | hw==drv EXACT | vs jpegdec min PSNR Y/U/V 51.29/51.40/51.35 dB, max|d| 4/2/3
z17x33: frames hw 1 sw 1 | hw==drv DIFF | vs jpegdec min PSNR Y/U/V 48.36/11.42/13.23 dB, max|d| 3/246/175
z17x33-411: frames hw 1 sw 1 | hw==drv DIFF | vs jpegdec min PSNR Y/U/V 48.36/6.84/5.45 dB, max|d| 3/251/253
mj420: frames hw 30 sw 30 | vs jpegdec min PSNR Y/U/V 59.25/57.23/56.23 dB, max|d| 3/3/3
mj422: no hw output
mj444: no hw output
```
## dmesg cedrus/Oops/WARNING lines (verbatim, out/dmesg.txt)
```
[  222.834324] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.834371] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.851183] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.851292] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.868161] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.868205] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.885109] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.885153] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.902025] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.902070] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.918961] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.919005] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.936033] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.936076] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.952942] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.952986] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.969891] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.969934] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  222.986852] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  222.986895] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.003863] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.003907] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.020815] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.020858] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.037768] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.037814] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.054637] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.054682] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.071548] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.071592] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.088495] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.088539] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.105417] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.105461] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.122301] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.122347] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.139252] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.139299] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.156167] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.156211] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.173100] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.173144] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.190052] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.190093] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.206980] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.207023] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.223986] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.224033] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.240947] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.240991] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.257871] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.257914] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.274805] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.274847] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.291825] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.291867] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.308780] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.308825] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
[  223.325717] cedrus 1c0e000.video-codec: failed to parse JPEG header: -22
[  223.325760] cedrus 1c0e000.video-codec: Failed to setup decoding job: -22
```
