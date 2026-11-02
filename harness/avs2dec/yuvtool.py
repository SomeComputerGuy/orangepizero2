#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Small planar 4:2:0 YUV helper for the AVS2 reference runs (own code).

  yuvtool.py md5 W H BPS file            per-frame md5s ("frame N md5 X") + total
  yuvtool.py md5pipe W H BPS file keep N copy  frame md5s from a pipe/file and keep
                                           the first N frames in `copy`
  yuvtool.py half W H BPS in out         2x2 box downscale (for 4K -> 1080p)
  yuvtool.py to8 W H in out              16-bit LE 10-bit samples -> 8-bit (>>2, rounded)
  yuvtool.py to10 W H in out             8-bit -> 16-bit LE 10-bit (<<2 plus a fixed
                                           2-bit ordered dither, so the low bits vary)
  yuvtool.py up2 W H BPS in out          2x upscale by pixel repetition (1080p -> 4K)
  yuvtool.py head W H BPS N in out       keep the first N frames

BPS is bytes per sample: 1 (8-bit) or 2 (16-bit little endian, 10-bit values).
"""
import hashlib
import sys


def frame_size(w, h, bps):
    return (w * h + 2 * ((w + 1) // 2) * ((h + 1) // 2)) * bps


def md5(w, h, bps, path, keep=0, copy=None):
    fs = frame_size(w, h, bps)
    total = hashlib.md5()
    out = open(copy, 'wb') if copy else None
    n = 0
    with open(path, 'rb') as f:
        while True:
            buf = f.read(fs)
            if not buf:
                break
            if len(buf) != fs:
                sys.exit(f'truncated frame {n}: {len(buf)} of {fs} bytes')
            total.update(buf)
            print(f'frame {n} md5 {hashlib.md5(buf).hexdigest()}')
            if out and n < keep:
                out.write(buf)
            n += 1
    print(f'{n} frames, md5 {total.hexdigest()}')


def half(w, h, bps, src, dst):
    import numpy as np
    dt = np.uint8 if bps == 1 else np.dtype('<u2')
    fs = frame_size(w, h, bps)
    cw, ch = (w + 1) // 2, (h + 1) // 2
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        while True:
            buf = f.read(fs)
            if len(buf) < fs:
                break
            a = np.frombuffer(buf, dtype=dt)
            planes = [a[:w * h].reshape(h, w),
                      a[w * h:w * h + cw * ch].reshape(ch, cw),
                      a[w * h + cw * ch:].reshape(ch, cw)]
            for p in planes:
                ph, pw = p.shape[0] // 2 * 2, p.shape[1] // 2 * 2
                q = p[:ph, :pw].astype(np.uint32)
                r = (q[0::2, 0::2] + q[1::2, 0::2] + q[0::2, 1::2] + q[1::2, 1::2] + 2) >> 2
                o.write(r.astype(dt).tobytes())


def to8(w, h, src, dst):
    import numpy as np
    fs = frame_size(w, h, 2)
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        while True:
            buf = f.read(fs)
            if len(buf) < fs:
                break
            a = np.frombuffer(buf, dtype='<u2').astype(np.uint32)
            o.write(np.minimum((a + 2) >> 2, 255).astype(np.uint8).tobytes())


def to10(w, h, src, dst):
    import numpy as np
    fs = frame_size(w, h, 1)
    cw, ch = (w + 1) // 2, (h + 1) // 2

    def dither(pw, ph):
        y, x = np.mgrid[0:ph, 0:pw]
        return ((x + 2 * y) & 3).astype(np.uint16)
    dy, dc = dither(w, h), dither(cw, ch)
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        while True:
            buf = f.read(fs)
            if len(buf) < fs:
                break
            a = np.frombuffer(buf, dtype=np.uint8).astype(np.uint16)
            y = (a[:w * h].reshape(h, w) << 2) | dy
            u = (a[w * h:w * h + cw * ch].reshape(ch, cw) << 2) | dc
            v = (a[w * h + cw * ch:].reshape(ch, cw) << 2) | dc
            for p in (y, u, v):
                o.write(p.astype('<u2').tobytes())


def up2(w, h, bps, src, dst):
    import numpy as np
    dt = np.uint8 if bps == 1 else np.dtype('<u2')
    fs = frame_size(w, h, bps)
    cw, ch = (w + 1) // 2, (h + 1) // 2
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        while True:
            buf = f.read(fs)
            if len(buf) < fs:
                break
            a = np.frombuffer(buf, dtype=dt)
            for p in (a[:w * h].reshape(h, w), a[w * h:w * h + cw * ch].reshape(ch, cw),
                      a[w * h + cw * ch:].reshape(ch, cw)):
                o.write(np.repeat(np.repeat(p, 2, axis=0), 2, axis=1).tobytes())


def head(w, h, bps, n, src, dst):
    fs = frame_size(w, h, bps)
    with open(src, 'rb') as f, open(dst, 'wb') as o:
        for _ in range(n):
            buf = f.read(fs)
            if len(buf) < fs:
                sys.exit('source has fewer frames than requested')
            o.write(buf)


def main(a):
    if a[0] == 'md5':
        md5(int(a[1]), int(a[2]), int(a[3]), a[4])
    elif a[0] == 'md5pipe':
        md5(int(a[1]), int(a[2]), int(a[3]), a[4], int(a[6]), a[7])
    elif a[0] == 'half':
        half(int(a[1]), int(a[2]), int(a[3]), a[4], a[5])
    elif a[0] == 'to8':
        to8(int(a[1]), int(a[2]), a[3], a[4])
    elif a[0] == 'to10':
        to10(int(a[1]), int(a[2]), a[3], a[4])
    elif a[0] == 'up2':
        up2(int(a[1]), int(a[2]), int(a[3]), a[4], a[5])
    elif a[0] == 'head':
        head(int(a[1]), int(a[2]), int(a[3]), int(a[4]), a[5], a[6])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
