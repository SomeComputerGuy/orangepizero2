#!/usr/bin/env python3
# Usage: rawdiff.py a.nv12 b.nv12 W H -> per frame: luma/chroma max abs diff, count of differing samples, first diff (x,y)
import sys
a, b = open(sys.argv[1], 'rb').read(), open(sys.argv[2], 'rb').read(); W, H = int(sys.argv[3]), int(sys.argv[4]); fs = W * H * 3 // 2
for n in range(min(len(a), len(b)) // fs):
    A, B = a[n*fs:(n+1)*fs], b[n*fs:(n+1)*fs]
    for name, lo, hi in (('Y', 0, W*H), ('UV', W*H, fs)):
        d = [(i, abs(A[i]-B[i])) for i in range(lo, hi) if A[i] != B[i]]
        if d:
            i = d[0][0] - lo; w = W
            print(f"frame {n} {name}: {len(d)} diffs, max {max(x for _, x in d)}, first at x={i%w} y={i//w}, hist<=1:{sum(1 for _,x in d if x<=1)}")
        else: print(f"frame {n} {name}: identical")
