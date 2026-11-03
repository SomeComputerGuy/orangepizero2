#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Synthetic test material for di300test (NV12/I420/NV16/422P, 8-bit).

  gen.py moving W H N out_prefix [tff|bff]
      truth: out_prefix.truth.yuv  2N progressive frames at field rate
      input: out_prefix.in.yuv     N interlaced frames woven from them
             (field k of the truth frame k, alternating parity)
  gen.py telecine W H N out_prefix
      out_prefix.film.yuv          N progressive 24p frames
      out_prefix.in.yuv            3:2 pulldown interlaced frames (TFF)
Output is planar I420; convert with ffmpeg for other layouts.
"""
import sys
import numpy as np

def frame(W, H, t):
    y, x = np.mgrid[0:H, 0:W]
    # moving diagonal bars + a moving disc + static text-like stripes
    Y = (128 + 80 * np.sin((x + 2.5 * t) / 9.0 + y / 23.0)).astype(np.float64)
    cx, cy = (W * 0.2 + 6 * t) % W, H * 0.5 + H * 0.3 * np.sin(t / 15.0)
    Y[(x - cx) ** 2 + (y - cy) ** 2 < (H / 8) ** 2] = 235
    Y[:, : W // 16][(y[:, : W // 16] // 4) % 2 == 0] = 16
    Y = np.clip(Y, 16, 235).astype(np.uint8)
    cy_, cx_ = np.mgrid[0:H // 2, 0:W // 2]
    U = np.clip(128 + 60 * np.sin((cx_ + t) / 17.0), 16, 240).astype(np.uint8)
    V = np.clip(128 + 60 * np.cos((cy_ - t) / 13.0), 16, 240).astype(np.uint8)
    return Y, U, V

def weave(a, b):
    """top field lines from a, bottom field lines from b (all planes)."""
    out = []
    for pa, pb in zip(a, b):
        o = pa.copy()
        o[1::2] = pb[1::2]
        out.append(o)
    return out

def write(f, planes):
    for p in planes:
        f.write(np.ascontiguousarray(p).tobytes())

def main():
    kind, W, H, N, pre = sys.argv[1], *map(int, sys.argv[2:5]), sys.argv[5]
    if kind == "moving":
        bff = len(sys.argv) > 6 and sys.argv[6] == "bff"
        truth = [frame(W, H, t) for t in range(2 * N)]
        with open(pre + ".truth.yuv", "wb") as ft, open(pre + ".in.yuv", "wb") as fi:
            for t in truth:
                write(ft, t)
            for n in range(N):
                first, second = truth[2 * n], truth[2 * n + 1]
                write(fi, weave(second, first) if bff else weave(first, second))
    elif kind == "telecine":
        film = [frame(W, H, 3 * t) for t in range((N * 4 + 4) // 5 + 1)]
        fields = []  # (frame index, parity) in display order, TFF: 3:2
        for i, fr in enumerate(film):
            for k in range(3 if i % 2 == 0 else 2):
                fields.append(i)
        with open(pre + ".film.yuv", "wb") as ff, open(pre + ".in.yuv", "wb") as fi:
            for f in film:
                write(ff, f)
            for n in range(N):
                top, bot = film[fields[2 * n]], film[fields[2 * n + 1]]
                write(fi, weave(top, bot))
    else:
        sys.exit(__doc__)

main()
