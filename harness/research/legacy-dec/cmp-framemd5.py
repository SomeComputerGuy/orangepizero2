#!/usr/bin/env python3
# Usage: cmp-framemd5.py ref.framemd5 test.framemd5 -> "match=x/y first_bad=N" (per-frame md5 column, pts ignored)
import sys
def rd(p):
    try: return [l.rsplit(',', 1)[1].strip() for l in open(p) if l.strip() and not l.startswith('#')]
    except FileNotFoundError: return []
a, b = rd(sys.argv[1]), rd(sys.argv[2])
m = sum(x == y for x, y in zip(a, b)); bad = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), None)
ok = 'PASS' if a and len(a) == len(b) and m == len(a) else 'FAIL'
print(f"{ok}\tmatch={m}/{len(a)}\thw_frames={len(b)}\tfirst_bad={bad if bad is not None else '-'}")
