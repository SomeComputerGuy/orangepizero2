#!/usr/bin/env python3
"""order-check.py <ref> <reference ref>: active series.conf lines of ref must appear in the same relative
order as in reference (lines missing from reference are reported)."""
import subprocess, sys
S='patch/kernel/archive/sunxi-7.3/series.conf'
def act(r):
    t=subprocess.run(['git','-C','/home/aruni/orangepizero2/armbian-build','show',f'{r}:{S}'],capture_output=True,text=True).stdout
    out=[]
    for l in t.splitlines():
        l=l.split('#')[0].strip()
        if l and not l.startswith('-'): out.append(l)
    return out
a,ref=act(sys.argv[1]),act(sys.argv[2])
idx={l:i for i,l in enumerate(ref)}
missing=[l for l in a if l not in idx]
seq=[idx[l] for l in a if l in idx]
bad=[(a_,b_) for a_,b_ in zip(seq,seq[1:]) if b_<a_]
print(f"{sys.argv[1]}: {len(a)} active, missing-from-ref {len(missing)}, order inversions {len(bad)}")
for m in missing: print('  not in ref:', m)
for x,y in bad[:5]: print('  inversion:', ref[x], '>', ref[y])
