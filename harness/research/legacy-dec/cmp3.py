#!/usr/bin/env python3
# Usage: cmp3.py W H a.yuv b.yuv [nframes] (I420 or .nv12 by extension) -> per frame: luma/chroma MBs with max|diff|>4, max diff
import sys, numpy as np
W, H = int(sys.argv[1]), int(sys.argv[2]); fs = W*H*3//2; N = int(sys.argv[5]) if len(sys.argv) > 5 else 10**9
def frames(p):
    f = open(p, 'rb'); i = 0
    while i < N:
        b = f.read(fs)
        if len(b) < fs: return
        a = np.frombuffer(b, np.uint8).astype(np.int16); y = a[:W*H].reshape(H, W)
        if p.endswith('.nv12'): c = a[W*H:].reshape(H//2, W//2, 2).transpose(2, 0, 1)
        else: c = a[W*H:].reshape(2, H//2, W//2)
        yield y, c; i += 1
tl = tc = 0; mx = 0
for i, ((ya, ca), (yb, cb)) in enumerate(zip(frames(sys.argv[3]), frames(sys.argv[4]))):
    dy = np.abs(ya-yb).reshape(H//16, 16, W//16, 16).max(axis=(1, 3)); dc = np.abs(ca-cb).reshape(2, H//16, 8, W//16, 8).max(axis=(0, 2, 4))
    tl += int((dy > 4).sum()); tc += int((dc > 4).sum()); mx = max(mx, int(dy.max()), int(dc.max()))
    n = i + 1
print(f'frames={n} lumaMBs>4={tl} chromaMBs>4={tc} max={mx}')
