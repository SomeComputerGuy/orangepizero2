#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host side: compare board-test.sh outputs (run with python3 -I).
  compare.py OUTDIR
For each still image: hw (v4l2sljpegdec) vs drv (jpegtest, same driver) md5, and
hw vs sw (jpegdec) per-plane PSNR / max |diff| on I420. MJPEG clips: per-frame
the same against sw over the whole file."""
import sys, os, re, math
import numpy as np

SIZES = {'s420': (1920, 1080), 's422': (1920, 1080), 's444': (1920, 1080), 's411': (1920, 1080),
         'dri7': (1920, 1080), 'nodht': (1920, 1080), 'opt420': (1920, 1080), 'z16x16': (16, 16),
         'z2049x64': (2049, 64), 'z4096x2304': (4096, 2304), 'z17x33': (17, 33), 'z17x33-411': (17, 33),
         'mj420': (640, 480), 'mj422': (640, 480), 'mj444': (640, 480)}

def r4(x): return (x + 3) & ~3

def planes_gst(d, w, h):
    # GstVideoInfo I420: strides rounded up to 4, chroma (w+1)/2 x (h+1)/2
    ys, cs = r4(w), r4((w + 1) // 2)
    cw, ch = (w + 1) // 2, (h + 1) // 2
    fr = ys * h + 2 * cs * ch
    n = len(d) // fr
    out = []
    for i in range(n):
        f = d[i * fr:(i + 1) * fr]
        y = f[:ys * h].reshape(h, ys)[:, :w]
        u = f[ys * h:ys * h + cs * ch].reshape(ch, cs)[:, :cw]
        v = f[ys * h + cs * ch:].reshape(ch, cs)[:, :cw]
        out.append((y, u, v))
    return out

def planes_drv(d, w, h):
    cw, ch = (w + 1) // 2, (h + 1) // 2
    y = d[:w * h].reshape(h, w); u = d[w * h:w * h + cw * ch].reshape(ch, cw)
    v = d[w * h + cw * ch:w * h + 2 * cw * ch].reshape(ch, cw)
    return [(y, u, v)]

def psnr(a, b):
    m = np.mean((a.astype(np.int32) - b.astype(np.int32)) ** 2)
    return 99.0 if m == 0 else 10 * math.log10(255 * 255 / m)

def load(p):
    return np.fromfile(p, np.uint8) if os.path.exists(p) else np.zeros(0, np.uint8)

o = sys.argv[1]
for n, (w, h) in SIZES.items():
    hw, sw = load(f'{o}/{n}.hw.yuv'), load(f'{o}/{n}.sw.yuv')
    if not len(hw):
        print(f'{n}: no hw output'); continue
    H, S = planes_gst(hw, w, h), planes_gst(sw, w, h)
    line = f'{n}: frames hw {len(H)} sw {len(S)}'
    if os.path.exists(f'{o}/{n}.drv.yuv'):
        D = planes_drv(load(f'{o}/{n}.drv.yuv'), w, h)
        same = all(np.array_equal(a, b) for a, b in zip(H[0], D[0]))
        line += f' | hw==drv {"EXACT" if same else "DIFF"}'
    if S and len(S) == len(H):
        ps = [min(psnr(a[i], b[i]) for a, b in zip(H, S)) for i in range(3)]
        mx = [max(int(np.max(np.abs(a[i].astype(int) - b[i].astype(int)))) for a, b in zip(H, S)) for i in range(3)]
        line += ' | vs jpegdec min PSNR Y/U/V %.2f/%.2f/%.2f dB, max|d| %d/%d/%d' % (*ps, *mx)
    print(line)
