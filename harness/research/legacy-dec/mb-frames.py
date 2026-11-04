#!/usr/bin/env python3
# Usage: mb-frames.py W H ref.nv12 test.nv12 -> one line per frame with luma/chroma MBs whose max abs error > 4 (streams frame by frame)
import sys, numpy as np
W, H = int(sys.argv[1]), int(sys.argv[2]); fs = W * H * 3 // 2; Hm = H // 16 * 16
fa, fb = open(sys.argv[3], 'rb'), open(sys.argv[4], 'rb'); i = 0
while True:
    a, b = fa.read(fs), fb.read(fs)
    if len(a) < fs or len(b) < fs: break
    d = np.abs(np.frombuffer(a, np.uint8).astype(np.int16) - np.frombuffer(b, np.uint8).astype(np.int16))
    y = d[:W*H].reshape(H, W)[:Hm].reshape(Hm // 16, 16, W // 16, 16).max(axis=(1, 3))
    c = d[W*H:].reshape(H // 2, W)[:Hm // 2].reshape(Hm // 16, 8, W // 16, 16).max(axis=(1, 3))
    if y.max() > 4 or c.max() > 4:
        first = np.argwhere(y > 4)[:3].tolist()
        print(i, int((y > 4).sum()), int((c > 4).sum()), first)
    i += 1
print('frames', i)
