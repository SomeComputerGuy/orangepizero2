#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host side: mechanical checks of the odd-size board-test.sh output (run with python3 -I; needs ffmpeg, numpy).
  compare.py OUTDIR VECDIR
One line per case in VECDIR/cases.txt ending in PASS or FAIL(<checks>), then "SUMMARY: P pass, F fail",
the "NORANK:" line (recorded, not judged) and "DMESG: clean|<n> lines". Checks:
  still  hw rc=0 and one frame of the GStreamer I420 size for WxH; its visible pixels equal the driver's
         own output (jpegtest, hw!=drv); against ffmpeg (-idct int): Y max|d| <= 3; chroma max|d| <= 3 for
         4:2:0 and 4:1:1 (the 4:1:1 reference is ffmpeg's 4:1:1 resampled like the driver does), PSNR >= 30 dB
         for 4:2:2 and 4:4:4 (the engine downsamples these to 4:2:0 its own way); db, pb, db3 rc=0, picked
         v4l2sljpegdec, pixels equal to hw; jpegparse caps WxH; sw rc=0; the case added no kernel log line.
  clip   hw and sw output exactly the frames of SEQ (sizes add up); db, pb, pb3 rc=0, picked v4l2sljpegdec,
         same output as hw; jpegparse caps went through exactly the sizes of SEQ (no container height);
         hw vs sw Y and chroma PSNR >= 48 dB per frame; no kernel log line.
Any rc=124/137 in a case fails it. Comparisons use the visible pixels only: padding bytes differ."""
import sys, os, re, math, subprocess
import numpy as np

HANG = ('124', '137')

def r2(x): return (x + 1) & ~1
def r4(x): return (x + 3) & ~3

def gst_size(w, h):
    return r4(w) * r2(h) + 2 * r4(r2(w) // 2) * (r2(h) // 2)

def planes_gst(f, w, h):
    """One GStreamer I420 frame (bytes of gst_size(w, h)) -> visible Y, U, V."""
    ys, cs = r4(w), r4(r2(w) // 2)
    cw, ch, chv = (w + 1) // 2, r2(h) // 2, (h + 1) // 2
    o1 = ys * r2(h); o2 = o1 + cs * ch
    return (f[:ys * h].reshape(h, ys)[:, :w], f[o1:o1 + cs * ch].reshape(ch, cs)[:chv, :cw],
            f[o2:o2 + cs * ch].reshape(ch, cs)[:chv, :cw])

def frames_gst(d, seq):
    """Split a dump into the frames of seq [(w, h), ...]; None if the size does not add up."""
    if len(d) != sum(gst_size(w, h) for w, h in seq):
        return None
    out, p = [], 0
    for w, h in seq:
        n = gst_size(w, h)
        out.append(planes_gst(d[p:p + n], w, h)); p += n
    return out

def planes_tight(d, w, h, cw, ch):
    y = d[:w * h].reshape(h, w)
    return y, d[w * h:w * h + cw * ch].reshape(ch, cw), d[w * h + cw * ch:w * h + 2 * cw * ch].reshape(ch, cw)

def ffmpeg_ref(path, w, h, samp):
    """Reference I420 planes of a still: ffmpeg -idct int, 4:1:1 resampled like cedrus_jpeg_post_process()."""
    fmt = 'yuvj411p' if samp == '411' else 'yuvj420p'
    r = subprocess.run(['ffmpeg', '-v', 'error', '-idct', 'int', '-i', path, '-f', 'rawvideo', '-pix_fmt', fmt, '-'],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    d = np.frombuffer(r.stdout, np.uint8)
    cw, ch = (w + 1) // 2, (h + 1) // 2
    if samp != '411':
        return planes_tight(d, w, h, cw, ch) if len(d) == w * h + 2 * cw * ch else None
    cw4 = (w + 3) // 4
    if len(d) != w * h + 2 * cw4 * h:
        return None
    y, u4, v4 = planes_tight(d, w, h, cw4, h)
    u, v = np.zeros((ch, cw), np.uint8), np.zeros((ch, cw), np.uint8)
    for yy in range(ch):
        r0, r1 = 2 * yy, min(2 * yy + 1, h - 1)
        for x in range(cw):
            k = x // 2
            u[yy, x] = (int(u4[r0, k]) + int(u4[r1, k]) + 1) >> 1
            v[yy, x] = (int(v4[r0, k]) + int(v4[r1, k]) + 1) >> 1
    return y, u, v

def psnr(a, b):
    m = np.mean((a.astype(np.int32) - b.astype(np.int32)) ** 2)
    return 99.0 if m == 0 else 10 * math.log10(255 * 255 / m)

def maxd(a, b):
    return int(np.max(np.abs(a.astype(np.int32) - b.astype(np.int32))))

def same(A, B):
    return all(np.array_equal(a, b) for a, b in zip(A, B))

def load(p):
    return np.fromfile(p, np.uint8) if os.path.exists(p) else np.zeros(0, np.uint8)

o, v = sys.argv[1], sys.argv[2]
res = {}      # (name, tag) -> dict
norank = ''
for line in open(f'{o}/results.txt'):
    p = line.split()
    if len(p) < 2:
        continue
    if p[0] == 'norank':
        norank = line.strip(); continue
    r = {'line': line.strip()}
    if p[1] == 'dmesg':
        r['dmesg'] = int(p[2])
    else:
        r['rc'] = p[2][3:] if p[2].startswith('rc=') else '?'
        if p[1] == 'caps':
            r['sizes'] = line.split('sizes=[', 1)[1].rstrip(']\n').split()
        else:
            r['md5'] = p[3] if len(p) > 3 else ''
            r['size'] = int(p[4]) if len(p) > 4 and p[4].isdigit() else 0
            if 'picked=[' in line:
                r['picked'] = line.split('picked=[', 1)[1].rstrip(']\n')
    res[(p[0], p[1])] = r

npass = nfail = 0
for line in open(f'{v}/cases.txt'):
    p = line.split()
    if len(p) < 5 or p[0].startswith('#'):
        continue
    n, w, h, kind, spec = p[0], int(p[1]), int(p[2]), p[3], p[4]
    g = lambda t: res.get((n, t), {})
    bad, info = [], []
    clip = kind == 'clip'
    autos = ['db', 'pb', 'pb3' if clip else 'db3']
    for t in ['caps', 'hw', 'sw'] + autos + ([] if clip else ['drv']):
        if g(t).get('rc') in HANG:
            bad.append(f'{t}-hang')
    if g('sw').get('rc') != '0':
        bad.append('sw')
    if g('dmesg').get('dmesg', -1) != 0:
        bad.append('dmesg'); info.append(f"dmesg {g('dmesg').get('dmesg', '?')}")
    if clip:
        seq = []
        for part in spec.split(','):
            wh, cnt = part.split('*')
            seq += [tuple(int(x) for x in wh.split('x'))] * int(cnt)
        want_sizes = []
        for wh in seq:
            s = f'{wh[0]}x{wh[1]}'
            if s not in want_sizes:
                want_sizes.append(s)
        if g('caps').get('sizes') != want_sizes:
            bad.append('caps'); info.append(f"caps sizes {g('caps').get('sizes', '-')}")
        H = frames_gst(load(f'{o}/{n}.hw.yuv'), seq)
        S = frames_gst(load(f'{o}/{n}.sw.yuv'), seq)
        if g('hw').get('rc') != '0' or H is None:
            bad.append('hw-size'); info.append(f"hw {g('hw').get('size', 0)} B, want {sum(gst_size(*x) for x in seq)}")
        if S is None:
            bad.append('sw-size'); info.append(f"sw {g('sw').get('size', 0)} B")
        if H and S:
            ps = [min(psnr(a[i], b[i]) for a, b in zip(H, S)) for i in range(3)]
            info.append('hw vs jpegdec min PSNR Y/U/V %.2f/%.2f/%.2f dB over %d frames' % (*ps, len(H)))
            if min(ps) < 48:
                bad.append('psnr')
        for t in autos:
            a = g(t)
            A = frames_gst(load(f'{o}/{n}.{t}.yuv'), seq)
            if a.get('rc') != '0' or 'v4l2sljpegdec' not in a.get('picked', '') or A is None or H is None \
                    or not all(same(x, y) for x, y in zip(A, H)):
                bad.append(t); info.append(f"{t} rc={a.get('rc')} picked=[{a.get('picked', '-')}] {a.get('size', 0)} B")
    else:
        samp = spec
        if g('caps').get('sizes') != [f'{w}x{h}']:
            bad.append('caps'); info.append(f"caps sizes {g('caps').get('sizes', '-')}")
        hw = g('hw')
        H = frames_gst(load(f'{o}/{n}.hw.yuv'), [(w, h)])
        if hw.get('rc') != '0' or H is None:
            bad.append('hw'); info.append(f"hw rc={hw.get('rc')} {hw.get('size', 0)} B, want {gst_size(w, h)}")
        cw, ch = (w + 1) // 2, (h + 1) // 2
        D = load(f'{o}/{n}.drv.yuv')
        if g('drv').get('rc') != '0' or len(D) != w * h + 2 * cw * ch:
            bad.append('drv'); info.append(f"drv rc={g('drv').get('rc')} {len(D)} B")
            D = None
        else:
            D = planes_tight(D, w, h, cw, ch)
        if H and D and not same(H[0], D):
            bad.append('hw!=drv')
        R = ffmpeg_ref(f'{v}/{n}.jpg', w, h, samp)
        if R is None:
            bad.append('ref')
        elif H:
            md = [maxd(H[0][i], R[i]) for i in range(3)]
            ps = [psnr(H[0][i], R[i]) for i in range(3)]
            info.append('vs ffmpeg max|d| Y/U/V %d/%d/%d, PSNR %.2f/%.2f/%.2f dB' % (*md, *ps))
            if md[0] > 3:
                bad.append('y-ref')
            if samp in ('420', '411') and max(md[1], md[2]) > 3:
                bad.append('c-ref')
            if samp in ('422', '444') and min(ps[1], ps[2]) < 30:
                bad.append('c-ref')
        for t in autos:
            a = g(t)
            A = frames_gst(load(f'{o}/{n}.{t}.yuv'), [(w, h)])
            if a.get('rc') != '0' or 'v4l2sljpegdec' not in a.get('picked', '') or A is None or H is None \
                    or not same(A[0], H[0]):
                bad.append(t); info.append(f"{t} rc={a.get('rc')} picked=[{a.get('picked', '-')}] {a.get('size', 0)} B")
        S = frames_gst(load(f'{o}/{n}.sw.yuv'), [(w, h)])
        if H and S:
            info.append('jpegdec Y PSNR %.2f dB' % psnr(H[0][0], S[0][0]))
    tag = 'PASS' if not bad else 'FAIL(' + ','.join(bad) + ')'
    print(f'{n} [{kind} {spec}]: {tag}' + (' | ' + '; '.join(info) if info else ''))
    if bad: nfail += 1
    else: npass += 1
print(f'SUMMARY: {npass} pass, {nfail} fail')
print('NORANK: ' + (norank or 'missing'))
dm = [l.rstrip() for l in open(f'{o}/dmesg.txt') if re.search(r'cedrus|Oops|WARNING', l)] if os.path.exists(f'{o}/dmesg.txt') else ['no dmesg.txt']
print('DMESG: ' + ('clean' if not dm else f'{len(dm)} lines'))
for l in dm[:40]:
    print('  ' + l)
