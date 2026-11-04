#!/usr/bin/env python3
# Usage: mb-err.py W H ref.nv12 test.nv12 -> per stream: frames, frames with max>4, total luma/chroma MBs with max>4, MBs 0-6 of frame 24
import sys, numpy as np
W, H = int(sys.argv[1]), int(sys.argv[2]); fs = W * H * 3 // 2
a = np.fromfile(sys.argv[3], np.uint8).astype(np.int16); b = np.fromfile(sys.argv[4], np.uint8).astype(np.int16)
n = min(a.size, b.size) // fs; bf = ly = lc = 0; f24 = '-'
for i in range(n):
    Hm = H // 16 * 16
    y = np.abs(a[i*fs:i*fs+W*H] - b[i*fs:i*fs+W*H]).reshape(H, W)[:Hm].reshape(H // 16, 16, W // 16, 16).max(axis=(1, 3))
    c = np.abs(a[i*fs+W*H:(i+1)*fs] - b[i*fs+W*H:(i+1)*fs]).reshape(H // 2, W)[:Hm // 2].reshape(H // 16, 8, W // 16, 16).max(axis=(1, 3))
    if y.max() > 4 or c.max() > 4: bf += 1
    ly += int((y > 4).sum()); lc += int((c > 4).sum())
    if i == 24 and W == 1920 and H == 1080: f24 = ' '.join(str(int(v)) for v in y[0, :8])
print(f'frames={n} badframes={bf} lumaMBs>4={ly} chromaMBs>4={lc} f24_row0_max[0..7]={f24}')
