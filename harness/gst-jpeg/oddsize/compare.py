#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host side of the odd-size package: the checks live in ../recheck/compare.py (same output format, plus an
INSPECT: line and a skipped count in SUMMARY). This file used to carry its own reference: ffmpeg's swscale
yuvj420p output for 4:2:2/4:4:4 images and jpegdec for clips, at a PSNR threshold. Both were test bugs seen in
job 06 (z33x17-422/z15x15-444 FAIL(c-ref), mj-z33x17 FAIL(psnr)): the hardware output was right. The shared
compare.py models the engine's chroma resampling exactly (MCU-padded ffmpeg decode, pair averages) and checks
max|d| <= 3 against it for stills and every clip frame; the hw vs jpegdec PSNR is only reported."""
import os, sys
os.execv(sys.executable, [sys.executable, '-I', os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                             '..', 'recheck', 'compare.py')] + sys.argv[1:])
