#!/usr/bin/env python3
# Usage: cmp-raw.py <W> <H> <ref.nv12 pipe/file> <test.nv12 pipe/file>
# Per-frame comparison of two NV12 raw streams: max |diff|, fraction of differing samples, Y PSNR.
# Prints one summary line: frames, bit-exact frames, worst max|diff|, min/mean Y PSNR, last-frame max (drift indicator),
# and the per-GOP-end trend is in the optional per-frame dump (env PERFRAME=file).
import sys, os, numpy as np
W, H = int(sys.argv[1]), int(sys.argv[2]); fs = W * H * 3 // 2
a, b = open(sys.argv[3], 'rb'), open(sys.argv[4], 'rb')
pf = open(os.environ['PERFRAME'], 'w') if os.environ.get('PERFRAME') else None
n = ex = 0; worst = 0; psn = []; maxes = []
while True:
    x, y = a.read(fs), b.read(fs)
    if len(x) < fs or len(y) < fs: break
    X = np.frombuffer(x, np.uint8).astype(np.int16); Y = np.frombuffer(y, np.uint8).astype(np.int16)
    d = np.abs(X - Y); m = int(d.max()); maxes.append(m); worst = max(worst, m); ex += (m == 0)
    mse = float((d[:W*H].astype(np.float64) ** 2).mean()); p = 99.0 if mse == 0 else 10 * np.log10(255 * 255 / mse); psn.append(p)
    if pf: pf.write(f"{n} max={m} ndiff={int((d>0).sum())} psnrY={p:.2f}\n")
    n += 1
rest = (len(a.read()) // fs, len(b.read()) // fs)
print(f"frames={n} exact={ex} maxdiff={worst} psnrY_min={min(psn) if psn else 0:.2f} psnrY_mean={np.mean(psn) if psn else 0:.2f} "
      f"last_max={maxes[-1] if maxes else -1} leftover_ref/test={rest[0]}/{rest[1]}")
