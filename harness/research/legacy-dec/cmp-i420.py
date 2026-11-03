#!/usr/bin/env python3
# Usage: cmp-i420.py W H a.yuv b.yuv [perframe-out]  -> summary of per-frame |diff| (Y,U,V) between two I420 files
import sys, numpy as np
W, H = int(sys.argv[1]), int(sys.argv[2]); fs = W * H * 3 // 2
a = np.memmap(sys.argv[3], np.uint8, 'r') if __import__('os').path.getsize(sys.argv[3]) else np.zeros(0, np.uint8)
b = np.memmap(sys.argv[4], np.uint8, 'r') if __import__('os').path.getsize(sys.argv[4]) else np.zeros(0, np.uint8)
na, nb = a.size // fs, b.size // fs; n = min(na, nb); bad = 0; mx = 0; worst = (99.0, -1); pf = []
for i in range(n):
    d = np.abs(a[i*fs:(i+1)*fs].astype(np.int16) - b[i*fs:(i+1)*fs].astype(np.int16)); m = int(d.max())
    y = d[:W*H].astype(np.float64); mse = (y * y).mean(); p = 99.0 if mse == 0 else 10 * np.log10(255 * 255 / mse)
    big = np.argwhere(d[:W*H].reshape(H, W) > 4); mbs = len({(r // 16, c // 16) for r, c in big})
    pf.append(f'{i} max={m} psnrY={p:.2f} mbs>4={mbs}')
    if m > 4: bad += 1
    mx = max(mx, m); worst = min(worst, (p, i))
if len(sys.argv) > 5: open(sys.argv[5], 'w').write('\n'.join(pf) + '\n')
print(f'frames ff={na} xvid={nb}\tbad(>4)={bad}\tmax={mx}\tminPSNR={worst[0]:.2f}@{worst[1]}')
