#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare a jpegtest output with a reference decode (run with python3 -I).

  compare.py W H OUT FMT REF REFFMT

OUT is jpegtest's cropped output in FMT (nv12, nv21, yu12, yv12).
REF is a reference decode in REFFMT, one of ffmpeg's native planar
formats: yuvj420p, yuvj422p, yuvj444p, yuvj440p, yuvj411p, gray (write it
with "ffmpeg -idct int -i x.jpg -f rawvideo -pix_fmt REFFMT ref.yuv").

Luma is compared directly. Reference chroma that is not 4:2:0 is brought
to 4:2:0 two ways, by averaging and by dropping samples; both results are
printed since the engine's FORCE_420 filter is unknown. For gray the
output chroma must be 128.

Prints per plane: PSNR, max |diff|, count of differing samples, and
"EXACT" when identical.
"""
import sys
import numpy as np

SUB = {'yuvj420p': (2, 2), 'yuvj422p': (2, 1), 'yuvj444p': (1, 1),
       'yuvj440p': (1, 2), 'yuvj411p': (4, 1), 'gray': None}


def load_out(path, fmt, w, h):
    d = np.fromfile(path, np.uint8)
    cw, ch = (w + 1) // 2, (h + 1) // 2
    y = d[:w * h].reshape(h, w)
    c = d[w * h:]
    if fmt in ('nv12', 'nv21'):
        c = c[:cw * ch * 2].reshape(ch, cw, 2)
        u, v = c[:, :, 0], c[:, :, 1]
        if fmt == 'nv21':
            u, v = v, u
    else:
        u = c[:cw * ch].reshape(ch, cw)
        v = c[cw * ch:2 * cw * ch].reshape(ch, cw)
        if fmt == 'yv12':
            u, v = v, u
    return y, u, v


def load_ref(path, fmt, w, h):
    d = np.fromfile(path, np.uint8)
    y = d[:w * h].reshape(h, w)
    if SUB[fmt] is None:
        return y, None, None
    sx, sy = SUB[fmt]
    cw, ch = -(-w // sx), -(-h // sy)
    u = d[w * h:w * h + cw * ch].reshape(ch, cw)
    v = d[w * h + cw * ch:w * h + 2 * cw * ch].reshape(ch, cw)
    return y, u, v


def to420(p, sx, sy, w, h, how):
    # to full resolution, then to 4:2:0
    full = np.repeat(np.repeat(p.astype(np.int32), sy, 0), sx, 1)[:h, :w]
    hp, wp = -(-h // 2) * 2, -(-w // 2) * 2
    full = np.pad(full, ((0, hp - h), (0, wp - w)), mode='edge')
    if how == 'drop':
        return full[::2, ::2]
    s = full[0::2, 0::2] + full[1::2, 0::2] + full[0::2, 1::2] + full[1::2, 1::2]
    return (s + 2) // 4


def stats(name, a, b):
    a = a.astype(np.int32)
    b = b.astype(np.int32)
    d = np.abs(a - b)
    mse = float(np.mean(d * d))
    psnr = 99.0 if mse == 0 else 10 * np.log10(255 * 255 / mse)
    tag = 'EXACT' if mse == 0 else ''
    print('%-12s PSNR %6.2f dB  max %3d  diff %d/%d %s' %
          (name, psnr, d.max(), int(np.count_nonzero(d)), d.size, tag))


def main():
    w, h = int(sys.argv[1]), int(sys.argv[2])
    oy, ou, ov = load_out(sys.argv[3], sys.argv[4], w, h)
    ry, ru, rv = load_ref(sys.argv[5], sys.argv[6], w, h)
    stats('Y', oy, ry)
    if ru is None:
        stats('U (=128)', ou, np.full_like(ou, 128))
        stats('V (=128)', ov, np.full_like(ov, 128))
        return
    sx, sy = SUB[sys.argv[6]]
    if (sx, sy) == (2, 2):
        stats('U', ou, ru)
        stats('V', ov, rv)
        return
    for how in ('avg', 'drop'):
        stats('U %s' % how, ou, to420(ru, sx, sy, w, h, how))
        stats('V %s' % how, ov, to420(rv, sx, sy, w, h, how))


main()
