#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""psnr.py W H truth.yuv test.yuv [maxshift]
Luma PSNR of each test frame (I420) against the truth, for the best frame
offset in [-maxshift, maxshift] (the deinterlacer output lags its input).
Prints per-offset mean PSNR and the best one."""
import sys
import numpy as np

W, H = int(sys.argv[1]), int(sys.argv[2])
fs = W * H * 3 // 2
def load(p):
    d = np.fromfile(p, np.uint8)
    n = len(d) // fs
    return d[: n * fs].reshape(n, fs)[:, : W * H].reshape(n, H, W).astype(np.float64)
T, X = load(sys.argv[3]), load(sys.argv[4])
ms = int(sys.argv[5]) if len(sys.argv) > 5 else 4
best = None
for s in range(-ms, ms + 1):
    ps = []
    for i in range(len(X)):
        j = i + s
        if 2 <= i < len(X) - 2 and 0 <= j < len(T):
            mse = np.mean((X[i] - T[j]) ** 2)
            ps.append(99.0 if mse == 0 else 10 * np.log10(255 ** 2 / mse))
    if ps:
        m = float(np.mean(ps))
        print(f"offset {s:+d}: mean luma PSNR {m:.2f} dB over {len(ps)} frames")
        if best is None or m > best[1]:
            best = (s, m)
print(f"best offset {best[0]:+d}: {best[1]:.2f} dB")
