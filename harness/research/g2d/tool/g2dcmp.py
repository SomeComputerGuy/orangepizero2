#!/usr/bin/env python3
"""Compare two tightly packed frames of the same format, channel by channel.

    g2dcmp.py FOURCC WxH got.raw ref.raw [--tol N] [--border N] [--tag name]

Prints one RESULT line: max/mean deviation per channel (over the interior,
excluding --border pixels), the share of pixels over the tolerance, whether a
U/V-swapped reference would match (uvswap 1), the alpha/X byte range of the
result, and pass 0/1 (all colour channels within the tolerance). Exit 0 = pass.
"""
import argparse
import sys

import numpy as np

# name -> (bpp, planes, cbpp, hsub, vsub, yuv, swap_uv, byte offsets r g b a)
FMTS = {
    'XR24': (4, 1, 0, 1, 1, 0, 0, (2, 1, 0, 3)),
    'AR24': (4, 1, 0, 1, 1, 0, 0, (2, 1, 0, 3)),
    'BX24': (4, 1, 0, 1, 1, 0, 0, (1, 2, 3, 0)),
    'BA24': (4, 1, 0, 1, 1, 0, 0, (1, 2, 3, 0)),
    'XB24': (4, 1, 0, 1, 1, 0, 0, (0, 1, 2, 3)),
    'AB24': (4, 1, 0, 1, 1, 0, 0, (0, 1, 2, 3)),
    'RX24': (4, 1, 0, 1, 1, 0, 0, (3, 2, 1, 0)),
    'RA24': (4, 1, 0, 1, 1, 0, 0, (3, 2, 1, 0)),
    'BGR3': (3, 1, 0, 1, 1, 0, 0, (2, 1, 0, None)),
    'RGB3': (3, 1, 0, 1, 1, 0, 0, (0, 1, 2, None)),
    'RGBP': (2, 1, 0, 1, 1, 0, 0, None),
    'NV12': (1, 2, 2, 2, 2, 1, 0, None),
    'NV21': (1, 2, 2, 2, 2, 1, 1, None),
    'YU12': (1, 3, 1, 2, 2, 1, 0, None),
    'YV12': (1, 3, 1, 2, 2, 1, 1, None),
    'NV16': (1, 2, 2, 2, 1, 1, 0, None),
    'NV61': (1, 2, 2, 2, 1, 1, 1, None),
    '422P': (1, 3, 1, 2, 1, 1, 0, None),
}


def decode(name, w, h, data):
    """Return (channels dict name -> int16 2-D array, alpha array or None)."""
    bpp, planes, cbpp, hsub, vsub, yuv, swap, offs = FMTS[name]
    buf = np.frombuffer(data, dtype=np.uint8)
    if not yuv:
        px = buf[:w * h * bpp].reshape(h, w, bpp).astype(np.int16)
        if name == 'RGBP':
            v = px[..., 0] | (px[..., 1] << 8)
            r5, g6, b5 = (v >> 11) & 0x1f, (v >> 5) & 0x3f, v & 0x1f
            return {'R': (r5 << 3) | (r5 >> 2), 'G': (g6 << 2) | (g6 >> 4),
                    'B': (b5 << 3) | (b5 >> 2)}, None
        r, g, b, a = offs
        ch = {'R': px[..., r], 'G': px[..., g], 'B': px[..., b]}
        return ch, (px[..., a] if a is not None else None)
    cw, chh = w // hsub, h // vsub
    y = buf[:w * h].reshape(h, w).astype(np.int16)
    c = buf[w * h:]
    if planes == 2:
        uv = c[:cw * chh * 2].reshape(chh, cw, 2).astype(np.int16)
        u, v = (uv[..., 1], uv[..., 0]) if swap else (uv[..., 0], uv[..., 1])
    else:
        p1 = c[:cw * chh].reshape(chh, cw).astype(np.int16)
        p2 = c[cw * chh:2 * cw * chh].reshape(chh, cw).astype(np.int16)
        u, v = (p2, p1) if swap else (p1, p2)
    return {'Y': y, 'U': u, 'V': v}, None


def stats(got, ref, border, tol):
    out = {}
    worst = 0
    over = 0
    count = 0
    for k in got:
        g, r = got[k], ref[k]
        b = border if k in ('R', 'G', 'B', 'Y') else max(1, border // 2)
        if g.shape[0] > 2 * b and g.shape[1] > 2 * b and b > 0:
            g, r = g[b:-b, b:-b], r[b:-b, b:-b]
        d = np.abs(g - r)
        out[k] = (int(d.max()), float(d.mean()))
        worst = max(worst, int(d.max()))
        over += int((d > tol).sum())
        count += d.size
    return out, worst, over / count if count else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('fmt')
    ap.add_argument('size')
    ap.add_argument('got')
    ap.add_argument('ref')
    ap.add_argument('--tol', type=int, default=6)
    ap.add_argument('--border', type=int, default=0)
    ap.add_argument('--tag', default='cmp')
    a = ap.parse_args()
    w, h = (int(x) for x in a.size.lower().split('x'))
    gd = open(a.got, 'rb').read()
    rd = open(a.ref, 'rb').read()
    try:
        got, alpha = decode(a.fmt, w, h, gd)
        ref, _ = decode(a.fmt, w, h, rd)
    except ValueError as e:
        print(f'RESULT {a.tag} pass 0 reason short_file got {len(gd)} ref {len(rd)} ({e})')
        return 1
    per, worst, frac = stats(got, ref, a.border, a.tol)
    uvswap = 0
    if 'U' in ref and worst > a.tol:
        sw = dict(ref)
        sw['U'], sw['V'] = ref['V'], ref['U']
        _, w2, _ = stats(got, sw, a.border, a.tol)
        uvswap = int(w2 <= a.tol)
    fields = ' '.join(f'{k}_max {v[0]} {k}_mean {v[1]:.2f}' for k, v in per.items())
    al = f' alpha_min {int(alpha.min())} alpha_max {int(alpha.max())}' if alpha is not None else ''
    ok = int(worst <= a.tol)
    print(f'RESULT {a.tag} pass {ok} max_dev {worst} tol {a.tol} over_tol {frac:.5f} '
          f'uvswap {uvswap} {fields}{al}')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
