#!/usr/bin/env python3
# Usage: fldchroma.py W H sw.nv12 hw.nv12 fmv.txt frame -> for field-predicted P MBs of <frame> (display = decode order, P only),
# which chroma vector derivation from the qpel luma field MVs reproduces the HW chroma (FFmpeg's is 'ff').
import sys, numpy as np, collections
W, H = int(sys.argv[1]), int(sys.argv[2]); fs = W*H*3//2; fr = int(sys.argv[6])
sw = np.fromfile(sys.argv[3], np.uint8).astype(np.int32); hw = np.fromfile(sys.argv[4], np.uint8).astype(np.int32)
UV = lambda a, f: a[f*fs+W*H:(f+1)*fs].reshape(H//2, W//2, 2)
ref, cur, hwc = UV(sw, fr-1), UV(sw, fr), UV(hw, fr)
mbs = [l.split()[1:] for l in open(sys.argv[5]) if l.startswith('FMV')]
nmb = (W//16)*(H//16); mbs = [list(map(int, m)) for m in mbs[(fr-1)*nmb: fr*nmb]]
t2 = lambda v: int(v/2); f2 = lambda v: v >> 1; r = lambda v: (v >> 1) | (v & 1)
C = {
 'ff':      lambda x, y: (r(t2(x)), r(f2(y))),
 'floor':   lambda x, y: (r(f2(x)), r(f2(y))),
 'trunc':   lambda x, y: (r(t2(x)), r(t2(y))),
 'rr':      lambda x, y: (r(r(x)), r(r(y))),
 'm1y':     lambda x, y: (r(t2(x)), r(y) >> 1),
 'm2y':     lambda x, y: (r(r(x)), r(y) >> 1),
 'm1yr':    lambda x, y: (r(t2(x)), r(r(2*y)) >> 1),
 'fyr':     lambda x, y: (r(t2(x)), (r(t2(2*y)) >> 1)),
}
def pred(field, par, cx, cy, mbx, mby, rnd):
    F = field[par::2].astype(np.int32); hy, hx = cy & 1, cx & 1
    y0 = mby*4 + (cy >> 1); x0 = mbx*8 + (cx >> 1)
    ys = np.clip(np.arange(y0, y0+5), 0, F.shape[0]-1); xs = np.clip(np.arange(x0, x0+9), 0, W//2-1)
    B = F[ys][:, xs]
    a, b, c, d = B[:4, :8], B[:4, 1:9], B[1:5, :8], B[1:5, 1:9]
    if hx and hy: return (a+b+c+d+2-rnd) >> 2
    if hx: return (a+b+1-rnd) >> 1
    if hy: return (a+c+1-rnd) >> 1
    return a
score = collections.Counter(); nbad = 0
for mbx, mby, s0, x0, y0, s1, x1, y1, nr in mbs:
    blk = (slice(mby*8, mby*8+8), slice(mbx*8, mbx*8+8))
    if np.abs(hwc[blk] - cur[blk]).max() <= 4: continue
    nbad += 1
    for name, fn in C.items():
        ok = True; err = 0
        for i, (s, x, y) in enumerate(((s0, x0, y0), (s1, x1, y1))):
            cff = C['ff'](x, y); cc = fn(x, y)
            for f, par in ((ref, s),):
                pf = pred(f, par, *cff, mbx, mby, nr); pc = pred(f, par, *cc, mbx, mby, nr)
                rec = np.clip(cur[blk][i::2] + pc - pf, 0, 255)
                err = max(err, int(np.abs(rec - hwc[blk][i::2]).max()))
        if err <= 2: score[name] += 1
print('bad chroma MBs', nbad, 'explained (max<=2) per candidate:', dict(score))
