#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Host side: summarise probe.sh results (run with python3 -I).

  analyze-probe.py VECTORDIR OUTDIR

For every run: rc, decode time, STATUS / VLD offset / MCU registers after
the job (from the cedrus dump), share of luma and chroma bytes the engine
wrote (the capture was pre-filled with 0x5a), luma PSNR against the
reference, and for colour pictures the chroma PSNR under several layout
hypotheses: NV12 4:2:0 by averaging or dropping, 4:2:2 interleaved
(full-height chroma rows), raw 4:1:1 interleaved. IOMMU faults are placed
against the source and capture buffer ranges of the same run.
"""
import os
import re
import sys
import numpy as np

FILL = 0x5a
SUB = {'yuvj420p': (2, 2), 'yuvj411p': (4, 1), 'gray': None}


def psnr(a, b):
    d = (a.astype(float) - b.astype(float)) ** 2
    m = d.mean() if d.size else 0
    return 99.0 if m == 0 else 10 * np.log10(255 * 255 / m)


def detile(p, w, h):
    tw, th = (w + 31) // 32, (h + 31) // 32
    t = p[:tw * th * 1024].reshape(th, tw, 32, 32)
    return t.transpose(0, 2, 1, 3).reshape(th * 32, tw * 32)


def jpeg_info(path):
    d = open(path, 'rb').read()
    i = 2
    while i < len(d):
        m, ln = d[i + 1], d[i + 2] << 8 | d[i + 3]
        if m in (0xc0, 0xc1):
            h, w, nf = d[i + 5] << 8 | d[i + 6], d[i + 7] << 8 | d[i + 8], d[i + 9]
            return w, h, nf, d[i + 11]
        i += 2 + ln
    raise SystemExit('no SOF in ' + path)


def ref_planes(path, w, h, nf, hv):
    r = np.fromfile(path, np.uint8)
    y = r[:w * h].reshape(h, w)
    if nf == 1:
        return y, None, None
    sx, sy = {0x22: (2, 2), 0x41: (4, 1), 0x21: (2, 1), 0x11: (1, 1)}[hv]
    cw, ch = -(-w // sx), -(-h // sy)
    u = r[w * h:w * h + cw * ch].reshape(ch, cw)
    v = r[w * h + cw * ch:w * h + 2 * cw * ch].reshape(ch, cw)
    return y, (u, v), (sx, sy)


def resample(p, sx, sy, w, h, tx, ty, how):
    """chroma subsampled by (sx, sy) -> subsampled by (tx, ty)."""
    full = np.repeat(np.repeat(p.astype(float), sy, 0), sx, 1)[:h, :w]
    hh, ww = -(-h // ty), -(-w // tx)
    pad = np.pad(full, ((0, hh * ty - h), (0, ww * tx - w)), mode='edge')
    if how == 'avg':
        return pad.reshape(hh, ty, ww, tx).mean(axis=(1, 3)).round()
    return pad[::ty, ::tx]


def main():
    vd, od = sys.argv[1], sys.argv[2]
    rows = []
    labels = {}
    vt = os.path.join(od, 'variants.txt')
    if os.path.exists(vt):  # probe-grey.sh: run number -> parameters
        for ln in open(vt):
            k, _, rest = ln.strip().partition(' ')
            labels[k] = rest.split(' ', 2)[2] if rest.count(' ') >= 2 else rest
    dirs = [x for x in os.listdir(od) if os.path.isdir(os.path.join(od, x))]
    for var in sorted(dirs, key=lambda s: int(s, 0)):
        for f in sorted(os.listdir(os.path.join(od, var))):
            if not f.endswith('.log'):
                continue
            base = f[:-4]
            name, fmt = base.rsplit('.', 1)
            p = os.path.join(od, var, base)
            log = open(p + '.log').read()
            dm = open(p + '.dmesg').read() if os.path.exists(p + '.dmesg') else ''
            rc = re.search(r'rc (\d+)', log)
            ms = re.search(r'([\d.]+) ms each', log)
            cap = re.search(r'bpl (\d+) size (\d+)', log)
            out = '%-6s %-11s %-5s rc %s %8s ms' % (var, name, fmt, rc.group(1) if rc else '?',
                                                ms.group(1) if ms else '-')
            if var in labels:
                out += ' [%s]' % labels[var]
            done = re.findall(r'jpeg done.*?\n.*?mpeg\+00: (.*?)\n', dm)
            m00 = re.findall(r'mpeg\+00: ([0-9a-f ]+)', dm)
            mc0 = re.findall(r'mpeg\+20: ([0-9a-f ]+)', dm)
            ma0 = re.findall(r'mpeg\+a0: ([0-9a-f ]+)', dm)
            if len(m00) >= 2:
                # second dump of the job = "done"
                st = m00[1].split()[7]
                vo = mc0[1].split()[3] if len(mc0) >= 2 else '?'
                mcu = ma0[1].split()[7] if len(ma0) >= 2 else '?'
                vo0 = mc0[0].split()[3]
                out += ' | STATUS %s VLDOFF %s->%s MCU %s' % (st, vo0, vo, mcu)
            elif m00:
                out += ' | no done dump (no IRQ)'
            e00 = re.findall(r'e00\+[0-9a-f]{2}: ([0-9a-f ]+)', dm)
            if e00 and any(int(x, 16) for x in ' '.join(e00).split()):
                out += ' | E00 nonzero'
            for flt in re.findall(r'Page fault for (0x[0-9a-f]+) \(master (\d+), dir (\w+)\)', dm):
                a = int(flt[0], 16)
                s = re.search(r'src (0x[0-9a-f]+)\+(\d+) \(plane (\d+)\) dst luma (0x[0-9a-f]+) chroma (0x[0-9a-f]+) size (\d+)', dm)
                where = ''
                if s:
                    sb, sp = int(s.group(1), 16), int(s.group(3))
                    db, dsz = int(s.group(4), 16), int(s.group(6))
                    where = ' src[%#x..%#x) dst[%#x..%#x): fault-src_end %+d fault-dst_end %+d' % (
                        sb, sb + sp, db, db + dsz, a - (sb + sp), a - (db + dsz))
                out += '\n        IOMMU fault %s master %s %s%s' % (flt[0], flt[1], flt[2], where)
            if 'timed out' in dm:
                out += ' | WATCHDOG'
            if not cap or not os.path.exists(p + '.raw'):
                rows.append(out)
                continue
            bpl, size = int(cap.group(1)), int(cap.group(2))
            w, h, nf, hv = jpeg_info(os.path.join(vd, name + '.jpg'))
            raw = np.fromfile(p + '.raw', np.uint8)
            ah = (h + 15) & ~15
            if fmt == 'tiled':
                aw = (w + 31) & ~31
                ysz = aw * ((h + 31) & ~31)
                Y = detile(raw, aw, h)[:h, :w]
                C = detile(raw[ysz:], aw, (h + 1) // 2)
                Cfull = None
            else:
                Y = raw[:bpl * h].reshape(h, bpl)[:, :w]
                Cbuf = raw[bpl * ah:size]
                C = Cbuf[:bpl * ((h + 1) // 2)].reshape(-1, bpl)
                Cfull = Cbuf[:(len(Cbuf) // bpl) * bpl].reshape(-1, bpl)
            ry, rc_, sub = ref_planes(os.path.join(vd, name + '.ref.yuv'), w, h, nf, hv)
            out += ' | Y written %.0f%% psnr %.1f' % (100 * np.mean(Y != FILL), psnr(Y, ry))
            cw = (w + 1) // 2
            Cu, Cv = C[:(h + 1) // 2, 0:2 * cw:2], C[:(h + 1) // 2, 1:2 * cw:2]
            out += ' | C written %.0f%%' % (100 * np.mean(C[:(h + 1) // 2, :2 * cw] != FILL))
            if rc_ is None:
                out += ' C==128 %.0f%%' % (100 * np.mean(C[:(h + 1) // 2, :2 * cw] == 128))
            else:
                u, v = rc_
                sx, sy = sub
                for how in ('avg', 'drop'):
                    tu = resample(u, sx, sy, w, h, 2, 2, how)
                    tv = resample(v, sx, sy, w, h, 2, 2, how)
                    out += ' 420%s %.1f/%.1f' % (how, psnr(Cu, tu), psnr(Cv, tv))
                if Cfull is not None and Cfull.shape[0] >= h:
                    ku, kv = Cfull[:h, 0:2 * cw:2], Cfull[:h, 1:2 * cw:2]
                    tu = resample(u, sx, sy, w, h, 2, 1, 'avg')
                    tv = resample(v, sx, sy, w, h, 2, 1, 'avg')
                    out += ' 422rows %.1f/%.1f' % (psnr(ku, tu), psnr(kv, tv))
                    if sx == 4:
                        qw = -(-w // 4)
                        out += ' 411raw %.1f/%.1f' % (psnr(Cfull[:h, 0:2 * qw:2], u[:h, :qw]),
                                                      psnr(Cfull[:h, 1:2 * qw:2], v[:h, :qw]))
            rows.append(out)
    print('\n'.join(rows))


main()
