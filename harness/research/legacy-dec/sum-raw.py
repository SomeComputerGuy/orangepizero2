#!/usr/bin/env python3
# Usage: sum-raw.py raw.tsv... -> per stream: best reference, HW max|diff| / min PSNR vs it, envelope max|diff| / min PSNR, verdict
# Verdict: OK if HW frames == ref frames and HW max|diff| (closest IDCT) <= envelope max|diff| (two FFmpeg IEEE-1180 IDCTs)
# or <= 2 (pure IDCT rounding); FAIL otherwise; NOHW if no frames (SW fallback refused by hwdownload).
import sys, re
def kv(s): return dict(re.findall(r'(\w+(?:/\w+)?)=([-\w./]+)', s))
for fn in sys.argv[1:]:
    for l in open(fn):
        f = l.rstrip('\n').split('\t')
        if len(f) < 9: continue
        tag, wh, rc, irq = f[0], f[2], f[3], f[4]
        refs = {}
        for c in f[5:8]:
            name, rest = c.split(':', 1); refs[name] = kv(rest)
        env = kv(f[8].split(':', 1)[1])
        best = min(refs, key=lambda k: (int(refs[k]['maxdiff']), -float(refs[k]['psnrY_min'])))
        b = refs[best]; fr = int(b['frames']); lo = b['leftover_ref/test'].split('/')
        if fr == 0: v = 'NOHW'
        elif lo[0] != '0' or lo[1] != '0': v = 'FAIL(frames)'
        elif int(b['maxdiff']) <= max(2, int(env['maxdiff'])): v = 'OK'
        else: v = 'FAIL'
        print(f"{tag}\t{wh}\t{irq}\tframes={fr}\texact={b['exact']}\tbest={best}\tmax={b['maxdiff']}\tpsnr_min={b['psnrY_min']}\tenv_max={env['maxdiff']}\tenv_psnr_min={env['psnrY_min']}\t{v}")
