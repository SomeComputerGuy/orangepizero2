# 05-gst-jpeg-gaps: FAIL (check 5)
Kernel (kernel.txt): #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 7.3.1-edge-sunxi64 
Start 2026-11-05 20:14:02 UTC, end 20:17:27 UTC. KSIZES=1.
Checks: 1 PASS (v4l2sljpegdec, scans: 1, component-tables shared/luma-chroma); 2 FAIL (SUMMARY 10 pass, 1 fail, 0 skipped); 3 PASS; 4 PASS; 5 FAIL; 6 PASS (0 rc=124/137); 7 PASS (DMESG: clean).
Case lines:
s420 [hw]: PASS | PSNR Y/U/V 51.30/51.40/51.34 dB max|d| 4/2/3 frames 1
crtq2 [hw]: PASS | PSNR Y/U/V 51.30/51.40/51.34 dB max|d| 4/2/3 frames 1
crtable [fallback]: PASS
crhuff [fallback]: PASS
noninter [fallback]: PASS
noninter2 [fallback]: PASS
dri7-noninter [fallback]: PASS
z4096x4096 [size]: FAIL(db,pb,db3) | db=[v4l2sljpegdec v4l2sljpegdec0 ] rc=1; pb=[v4l2sljpegdec v4l2sljpegdec0 ] rc=1; db3=[v4l2sljpegdec v4l2sljpegdec0 ] rc=1
mj-crhuff [fallback]: PASS
mj-noninter [fallback]: PASS
mj-crtq2 [hw]: PASS | PSNR Y/U/V 51.30/51.40/51.34 dB max|d| 4/2/3 frames 30
SUMMARY: 10 pass, 1 fail, 0 skipped
DMESG: clean
Results: build/gst-jpeg/results-gaps/
