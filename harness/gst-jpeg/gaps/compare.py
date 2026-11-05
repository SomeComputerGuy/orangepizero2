#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host side: mechanical checks of the gaps board-test.sh output (run with python3 -I).
  compare.py OUTDIR VECDIR
One line per case in VECDIR/cases.txt ending in PASS, FAIL(<checks>) or SKIPPED, then
"SUMMARY: P pass, F fail, S skipped" and "DMESG: clean|<n> lines". Checks per EXPECT:
  hw        hw rc=0 size>0; sw rc=0; md5(hw)==md5(drv) (stills); PSNR Y/U/V hw vs sw >= 48 dB;
            db, pb, db3/pb3 rc=0, picked v4l2sljpegdec, md5 == hw; caps as cases.txt
  fallback  hw rc not 0/124/137 and size 0 (refused by caps, no hang); sw rc=0;
            db, pb, db3/pb3 rc=0, picked jpegdec and not v4l2sljpegdec, md5 == sw; caps as cases.txt
  size      as fallback when the kernel enumerates frame sizes, else SKIPPED
Any rc=124/137 anywhere fails the case; dmesg lines with cedrus/Oops/WARNING are reported."""
import sys, os, re, math
import numpy as np

HANG = ('124', '137')

def r4(x): return (x + 3) & ~3
def r2(x): return (x + 1) & ~1

def planes_gst(d, w, h):
    # GstVideoInfo I420: strides rounded up to 4, the chroma planes start at
    # stride * ROUND_UP_2(height) and are ROUND_UP_2(w)/2 x ROUND_UP_2(h)/2
    ys, cs = r4(w), r4(r2(w) // 2)
    cw, ch = (w + 1) // 2, r2(h) // 2
    o1 = ys * r2(h); o2 = o1 + cs * ch; fr = o2 + cs * ch
    n = len(d) // fr
    out = []
    for i in range(n):
        f = d[i * fr:(i + 1) * fr]
        out.append((f[:ys * h].reshape(h, ys)[:, :w],
                    f[o1:o1 + cs * ch].reshape(ch, cs)[:(h + 1) // 2, :cw],
                    f[o2:o2 + cs * ch].reshape(ch, cs)[:(h + 1) // 2, :cw]))
    return out

def planes_drv(d, w, h):
    cw, ch = (w + 1) // 2, (h + 1) // 2
    return [(d[:w * h].reshape(h, w), d[w * h:w * h + cw * ch].reshape(ch, cw),
             d[w * h + cw * ch:w * h + 2 * cw * ch].reshape(ch, cw))]

def psnr(a, b):
    m = np.mean((a.astype(np.int32) - b.astype(np.int32)) ** 2)
    return 99.0 if m == 0 else 10 * math.log10(255 * 255 / m)

def load(p):
    return np.fromfile(p, np.uint8) if os.path.exists(p) else np.zeros(0, np.uint8)

o, v = sys.argv[1], sys.argv[2]
res = {}   # (name, tag) -> dict(rc, md5, size, picked, caps)
skipped = set()
for line in open(f'{o}/results.txt'):
    p = line.split()
    if len(p) < 2:
        continue
    if p[1] == 'SKIPPED':
        skipped.add(p[0]); continue
    r = {'rc': re.sub('rc=', '', p[2]) if len(p) > 2 else '?', 'line': line.strip()}
    if p[1] == 'caps':
        r['caps'] = ' '.join(p[3:])
    else:
        r['md5'] = p[3] if len(p) > 3 else ''
        if len(p) > 4:
            if p[4].startswith('picked='):
                r['picked'] = line.split('picked=[', 1)[1].rstrip(']\n')
            else:
                r['size'] = int(p[4])
    res[(p[0], p[1])] = r

npass = nfail = nskip = 0
for line in open(f'{v}/cases.txt'):
    p = line.split()
    if len(p) < 5 or p[0].startswith('#'):
        continue
    n, w, h, e, caps = p[0], int(p[1]), int(p[2]), p[3], p[4]
    if n in skipped:
        print(f'{n}: SKIPPED (kernel without ENUM_FRAMESIZES)'); nskip += 1; continue
    clip = n.startswith('mj-')
    autos = ['db', 'pb', 'pb3' if clip else 'db3']
    bad, info = [], []
    g = lambda t: res.get((n, t), {})
    for t in ['caps', 'hw', 'sw'] + autos + (['drv'] if e == 'hw' and not clip else []):
        if g(t).get('rc') in HANG:
            bad.append(f'{t}-hang')
    want_scans, want_tables = caps.split(':')
    if g('caps').get('caps', '') != f'scans=(int){want_scans} component-tables=(string){want_tables}':
        bad.append('caps'); info.append(f"caps={g('caps').get('caps', '-')}")
    if g('sw').get('rc') != '0':
        bad.append('sw')
    if e == 'hw':
        hw = g('hw')
        if hw.get('rc') != '0' or not hw.get('size'):
            bad.append('hw')
        if not clip:
            d = g('drv')
            if d.get('rc') != '0' or d.get('md5') != hw.get('md5'):
                bad.append('hw!=drv')
        for t in autos:
            a = g(t)
            if a.get('rc') != '0' or 'v4l2sljpegdec' not in a.get('picked', '') or a.get('md5') != hw.get('md5'):
                bad.append(t); info.append(f"{t}=[{a.get('picked', '-')}]")
        H = planes_gst(load(f'{o}/{n}.hw.yuv'), w, h)
        S = planes_gst(load(f'{o}/{n}.sw.yuv'), w, h)
        if H and len(H) == len(S):
            ps = [min(psnr(a[i], b[i]) for a, b in zip(H, S)) for i in range(3)]
            mx = [max(int(np.max(np.abs(a[i].astype(int) - b[i].astype(int)))) for a, b in zip(H, S)) for i in range(3)]
            info.append('PSNR Y/U/V %.2f/%.2f/%.2f dB max|d| %d/%d/%d frames %d' % (*ps, *mx, len(H)))
            if min(ps) < 48:
                bad.append('psnr')
        else:
            bad.append('frames'); info.append(f'frames hw {len(H)} sw {len(S)}')
    else:
        hw = g('hw')
        if hw.get('rc') in ('0',) + HANG or hw.get('size'):
            bad.append('hw-accepted'); info.append(hw.get('line', '-'))
        for t in autos:
            a = g(t)
            pk = a.get('picked', '')
            if a.get('rc') != '0' or 'jpegdec' not in pk or 'v4l2sljpegdec' in pk or a.get('md5') != g('sw').get('md5'):
                bad.append(t); info.append(f"{t}=[{pk}] rc={a.get('rc')}")
    tag = 'PASS' if not bad else 'FAIL(' + ','.join(bad) + ')'
    print(f"{n} [{e}]: {tag}" + (' | ' + '; '.join(info) if info else ''))
    if bad: nfail += 1
    else: npass += 1
print(f'SUMMARY: {npass} pass, {nfail} fail, {nskip} skipped')
dm = [l.rstrip() for l in open(f'{o}/dmesg.txt') if re.search(r'cedrus|Oops|WARNING', l)] if os.path.exists(f'{o}/dmesg.txt') else ['no dmesg.txt']
print('DMESG: ' + ('clean' if not dm else f'{len(dm)} lines'))
for l in dm:
    print('  ' + l)
