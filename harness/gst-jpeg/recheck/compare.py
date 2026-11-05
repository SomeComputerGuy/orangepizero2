#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host side: mechanical checks of the recheck board-test.sh output (run with python3 -I; needs ffmpeg, numpy).
  compare.py OUTDIR VECDIR
Prints an "INSPECT:" line, one line per case in VECDIR/cases.txt ending in PASS, FAIL(<checks>) or SKIPPED,
"SUMMARY: P pass, F fail, S skipped", the "NORANK:" line (recorded, not judged) and "DMESG: clean|<n> lines".

Reference for every hardware output: ffmpeg (-idct int) decodes the image in its own chroma layout with the SOF
size rounded up to whole MCUs, so the padding pixels the engine really averages are known, then the chroma is
resampled to 4:2:0 exactly as the hardware does it (4:2:2: rows averaged in pairs, rounded; 4:4:4: columns then
rows; 4:1:1: the driver's cedrus_jpeg_post_process() formula) and cropped to the picture. Verified exact to +-1 on
the 02 (1080p 4:2:2/4:4:4) and 06 (33x17 4:2:2, 15x15 4:4:4) dumps.
Checks:
  INSPECT  inspect.txt names v4l2sljpegdec, Rank primary + 1; with KSIZES=1 the SINK template width/height
           ranges start at 1 (patch 0107), else "sink-range BAD".
  still    hw rc=0, one frame of the GStreamer I420 size for WxH; visible pixels equal the driver's own output
           (jpegtest, hw!=drv); vs the reference max|d| <= 3 on Y, U and V (y-ref, c-ref); db, pb, db3 rc=0,
           picked v4l2sljpegdec, pixels equal to hw; jpegparse caps WxH; sw rc=0; no kernel log line (dmesg).
  size     a picture the hardware cannot take: SKIPPED on a kernel without ENUM_FRAMESIZES (results.txt says so);
           else hw must fail without output (hw-accepted), db/pb/db3 rc=0 picked jpegdec (not v4l2sljpegdec) with
           the jpegdec (sw) pixels, no kernel log line.
  clip     hw and sw output exactly the frames of SEQ (sizes add up); every hw frame vs the reference max|d| <= 3
           (ref); db, pb, pb3 rc=0, picked v4l2sljpegdec, same output as hw; jpegparse caps went through exactly
           the sizes of SEQ; no kernel log line. hw vs jpegdec PSNR is reported, not judged (IDCTs differ).
Any rc=124/137 in a case fails it. Comparisons use the visible pixels only: padding bytes differ."""
import sys, os, re, math, subprocess, tempfile
import numpy as np

HANG = ('124', '137')
TOL = 3

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

def sof_info(data):
    """(offset of the SOF0/SOF1 payload, width, height, [(h, v), ...]) of a JPEG, or None."""
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            return None
        m = data[i + 1]
        if m == 0xFF:
            i += 1; continue
        if m == 0xD8 or 0xD0 <= m <= 0xD7 or m == 0x01:
            i += 2; continue
        ln = (data[i + 2] << 8) | data[i + 3]
        if m in (0xC0, 0xC1):
            p = i + 4
            h = (data[p + 1] << 8) | data[p + 2]; w = (data[p + 3] << 8) | data[p + 4]
            nf = data[p + 5]
            hv = [(data[p + 6 + 3 * k + 1] >> 4, data[p + 6 + 3 * k + 1] & 15) for k in range(nf)]
            return p, w, h, hv
        if m == 0xDA:
            return None
        i += 2 + ln
    return None

SAMP = {(2, 2): '420', (2, 1): '422', (1, 1): '444', (4, 1): '411'}
PIXFMT = {'420': 'yuvj420p', '422': 'yuvj422p', '444': 'yuvj444p', '411': 'yuvj411p'}

def avg_h(a):
    a = a.astype(np.int32); return (a[:, 0::2] + a[:, 1::2] + 1) >> 1

def avg_v(a):
    a = a.astype(np.int32); return (a[0::2] + a[1::2] + 1) >> 1

def engine_ref(jpeg):
    """(Y, U, V) the hardware path must produce for this JPEG (bytes), as 4:2:0 planes cropped to the picture,
    or (None, reason)."""
    info = sof_info(jpeg)
    if not info:
        return None, 'no SOF'
    p, w, h, hv = info
    if len(hv) != 3 or hv[1] != (1, 1) or hv[2] != (1, 1) or hv[0] not in SAMP:
        return None, f'sampling {hv}'
    samp = SAMP[hv[0]]
    mw, mh = 8 * hv[0][0], 8 * hv[0][1]
    W, H = -(-w // mw) * mw, -(-h // mh) * mh
    d = bytearray(jpeg)
    d[p + 1], d[p + 2], d[p + 3], d[p + 4] = H >> 8, H & 255, W >> 8, W & 255
    r = subprocess.run(['ffmpeg', '-v', 'error', '-idct', 'int', '-f', 'mjpeg', '-i', '-', '-f', 'rawvideo',
                        '-pix_fmt', PIXFMT[samp], '-'], input=bytes(d), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    out = np.frombuffer(r.stdout, np.uint8)
    cW = {'420': W // 2, '422': W // 2, '444': W, '411': W // 4}[samp]
    cH = H // 2 if samp == '420' else H
    if len(out) != W * H + 2 * cW * cH:
        return None, f'ffmpeg gave {len(out)} B for {W}x{H} {samp}'
    y, u, v = planes_tight(out, W, H, cW, cH)
    if samp == '444':
        u, v = avg_h(u), avg_h(v)
    if samp == '411':
        u, v = np.repeat(u, 2, axis=1), np.repeat(v, 2, axis=1)
    if samp != '420':
        u, v = avg_v(u), avg_v(v)
    cw, ch = (w + 1) // 2, (h + 1) // 2
    return (y[:h, :w], u[:ch, :cw].astype(np.uint8), v[:ch, :cw].astype(np.uint8)), samp

def clip_frames(path, tmp):
    """The JPEG images of an MJPEG Matroska clip, in order (stream copy)."""
    d = tempfile.mkdtemp(dir=tmp)
    subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-c', 'copy', '-f', 'image2', f'{d}/f%04d.jpg'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return [open(f'{d}/{f}', 'rb').read() for f in sorted(os.listdir(d))]

def psnr(a, b):
    m = np.mean((a.astype(np.int32) - b.astype(np.int32)) ** 2)
    return 99.0 if m == 0 else 10 * math.log10(255 * 255 / m)

def maxd(a, b):
    return int(np.max(np.abs(a.astype(np.int32) - b.astype(np.int32))))

def same(A, B):
    return all(a.shape == b.shape and np.array_equal(a, b) for a, b in zip(A, B))

def load(p):
    return np.fromfile(p, np.uint8) if os.path.exists(p) else np.zeros(0, np.uint8)

o, v = sys.argv[1], sys.argv[2]
tmp = tempfile.mkdtemp(prefix='gstjpeg-cmp.')

# ---- inspect.txt
ins = open(f'{o}/inspect.txt').read() if os.path.exists(f'{o}/inspect.txt') else ''
ksizes = re.search(r'^KSIZES=(\d)', ins, re.M)
ksizes = ksizes.group(1) if ksizes else '?'
sink = ins.split('SRC template')[0] if 'SRC template' in ins else ''
ibad, iinfo = [], [f'KSIZES={ksizes}']
if not re.search(r'^\s*Name\s+v4l2sljpegdec\s*$', ins, re.M):
    ibad.append('name')
if not re.search(r'Rank\s+primary \+ 1 \(257\)', ins):
    ibad.append('rank')
if ksizes == '1':
    rw = re.search(r'width: \[ (\d+), (\d+) \]', sink); rh = re.search(r'height: \[ (\d+), (\d+) \]', sink)
    if rw and rh and rw.group(1) == '1' and rh.group(1) == '1':
        iinfo.append(f'sink-range ok width=[1,{rw.group(2)}] height=[1,{rh.group(2)}]')
    else:
        ibad.append('sink-range'); iinfo.append(f"sink-range BAD width={rw.groups() if rw else '-'} height={rh.groups() if rh else '-'}")
elif ksizes == '0':
    iinfo.append('sink-range not applicable (kernel without ENUM_FRAMESIZES)')
else:
    ibad.append('ksizes')
print('INSPECT: ' + ('PASS' if not ibad else 'FAIL(' + ','.join(ibad) + ')') + ' | ' + '; '.join(iinfo))

# ---- results.txt
res, norank, skipped = {}, '', set()
for line in open(f'{o}/results.txt'):
    p = line.split()
    if len(p) < 2:
        continue
    if p[0] == 'norank':
        norank = line.strip(); continue
    if p[1] == 'SKIPPED':
        skipped.add(p[0]); continue
    r = {'line': line.strip()}
    if p[1] == 'dmesg':
        r['dmesg'] = int(p[2])
    else:
        r['rc'] = p[2][3:] if p[2].startswith('rc=') else '?'
        if p[1] == 'caps':
            r['sizes'] = line.split('sizes=[', 1)[1].rstrip(']\n').split() if 'sizes=[' in line else None
        else:
            r['md5'] = p[3] if len(p) > 3 else ''
            r['size'] = int(p[4]) if len(p) > 4 and p[4].isdigit() else 0
            if 'picked=[' in line:
                r['picked'] = line.split('picked=[', 1)[1].rstrip(']\n')
    res[(p[0], p[1])] = r

npass = nfail = nskip = 0
for line in open(f'{v}/cases.txt'):
    p = line.split()
    if len(p) < 5 or p[0].startswith('#'):
        continue
    n, w, h, kind, spec = p[0], int(p[1]), int(p[2]), p[3], p[4]
    if n in skipped:
        print(f'{n} [{kind} {spec}]: SKIPPED | kernel without ENUM_FRAMESIZES'); nskip += 1; continue
    g = lambda t: res.get((n, t), {})
    bad, info = [], []
    clip = kind == 'clip'
    autos = ['db', 'pb', 'pb3' if clip else 'db3']
    for t in ['caps', 'hw', 'sw'] + autos + (['drv'] if kind == 'still' else []):
        if g(t).get('rc') in HANG:
            bad.append(f'{t}-hang')
    if g('sw').get('rc') != '0':
        bad.append('sw')
    if g('dmesg').get('dmesg', -1) != 0:
        bad.append('dmesg'); info.append(f"dmesg {g('dmesg').get('dmesg', '?')}")
    if kind == 'size':
        hw = g('hw')
        if hw.get('rc') in ('0',) + HANG or hw.get('size'):
            bad.append('hw-accepted'); info.append(hw.get('line', '-'))
        for t in autos:
            a = g(t); pk = a.get('picked', '')
            if a.get('rc') != '0' or 'jpegdec' not in pk or 'v4l2sljpegdec' in pk or a.get('md5') != g('sw').get('md5'):
                bad.append(t); info.append(f"{t}=[{pk}] rc={a.get('rc')}")
        if not bad:
            info.append('refused by the caps, decoded by jpegdec')
    elif clip:
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
        if H:
            jpgs = clip_frames(f'{v}/{n}.mkv', tmp)
            if len(jpgs) != len(seq):
                bad.append('ref'); info.append(f'{len(jpgs)} images in the clip, want {len(seq)}')
            else:
                md = [0, 0, 0]
                for fr, jp in zip(H, jpgs):
                    R, why = engine_ref(jp)
                    if R is None:
                        bad.append('ref'); info.append(f'reference: {why}'); break
                    for i in range(3):
                        md[i] = max(md[i], maxd(fr[i], R[i]))
                else:
                    info.append('vs reference max|d| Y/U/V %d/%d/%d over %d frames' % (*md, len(H)))
                    if max(md) > TOL:
                        bad.append('ref')
        if H and S:
            ps = [min(psnr(a[i], b[i]) for a, b in zip(H, S)) for i in range(3)]
            info.append('hw vs jpegdec min PSNR Y/U/V %.2f/%.2f/%.2f dB (info)' % tuple(ps))
        for t in autos:
            a = g(t)
            A = frames_gst(load(f'{o}/{n}.{t}.yuv'), seq)
            if a.get('rc') != '0' or 'v4l2sljpegdec' not in a.get('picked', '') or A is None or H is None \
                    or not all(same(x, y) for x, y in zip(A, H)):
                bad.append(t); info.append(f"{t} rc={a.get('rc')} picked=[{a.get('picked', '-')}] {a.get('size', 0)} B")
    else:
        if g('caps').get('sizes') != [f'{w}x{h}']:
            bad.append('caps'); info.append(f"caps sizes {g('caps').get('sizes', '-')}")
        hw = g('hw')
        H = frames_gst(load(f'{o}/{n}.hw.yuv'), [(w, h)])
        if hw.get('rc') != '0' or H is None:
            bad.append('hw'); info.append(f"hw rc={hw.get('rc')} {hw.get('size', 0)} B, want {gst_size(w, h)}")
        cw, ch = (w + 1) // 2, (h + 1) // 2
        D = load(f'{o}/{n}.drv.yuv')
        if g('drv').get('rc') != '0' or len(D) != w * h + 2 * cw * ch:
            bad.append('drv'); info.append(f"drv rc={g('drv').get('rc')} {len(D)} B"); D = None
        else:
            D = planes_tight(D, w, h, cw, ch)
        if H and D and not same(H[0], D):
            bad.append('hw!=drv')
        R, why = engine_ref(open(f'{v}/{n}.jpg', 'rb').read())
        if R is None:
            bad.append('ref'); info.append(f'reference: {why}')
        elif H:
            if why != spec:
                info.append(f'sampling in the file is {why}, cases.txt says {spec}')
            md = [maxd(H[0][i], R[i]) for i in range(3)]
            ps = [psnr(H[0][i], R[i]) for i in range(3)]
            info.append('vs reference max|d| Y/U/V %d/%d/%d, PSNR %.2f/%.2f/%.2f dB' % (*md, *ps))
            if md[0] > TOL:
                bad.append('y-ref')
            if max(md[1], md[2]) > TOL:
                bad.append('c-ref')
        for t in autos:
            a = g(t)
            A = frames_gst(load(f'{o}/{n}.{t}.yuv'), [(w, h)])
            if a.get('rc') != '0' or 'v4l2sljpegdec' not in a.get('picked', '') or A is None or H is None \
                    or not same(A[0], H[0]):
                bad.append(t); info.append(f"{t} rc={a.get('rc')} picked=[{a.get('picked', '-')}] {a.get('size', 0)} B")
        S = frames_gst(load(f'{o}/{n}.sw.yuv'), [(w, h)])
        if H and S:
            info.append('hw vs jpegdec Y PSNR %.2f dB (info)' % psnr(H[0][0], S[0][0]))
    tag = 'PASS' if not bad else 'FAIL(' + ','.join(bad) + ')'
    print(f'{n} [{kind} {spec}]: {tag}' + (' | ' + '; '.join(info) if info else ''))
    if bad: nfail += 1
    else: npass += 1
print(f'SUMMARY: {npass} pass, {nfail} fail, {nskip} skipped')
print('NORANK: ' + (norank or 'missing'))
dm = [l.rstrip() for l in open(f'{o}/dmesg.txt') if re.search(r'cedrus|Oops|WARNING', l)] if os.path.exists(f'{o}/dmesg.txt') else ['no dmesg.txt']
print('DMESG: ' + ('clean' if not dm else f'{len(dm)} lines'))
for l in dm[:20]:
    print('  ' + l)
subprocess.run(['rm', '-rf', tmp])
