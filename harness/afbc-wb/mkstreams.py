#!/usr/bin/env python3
"""Synthetic lossless test streams for the AFBC-vs-linear writeback check (afbc-wb).

Writes <out>/<name>.yuv (planar yuv420p / yuv420p10le, removed by mkstreams.sh after
encoding) and <out>/<name>.srcmd5: one "<frame> <md5>" line per frame over the frame in
the layout cedrus exports linearly (NV12: Y rows then interleaved CbCr rows, W bytes each;
P010: the same with little-endian 16-bit samples, value << 6). The streams are coded
lossless, so the decoded frame equals the source and the md5s check the linear decode.

Content (W x H, N frames, 60 fps):
  luma   = a textured panorama (gradients, sharp edges, noise) panned by (+2, +1) px per
           frame, so every frame has detail everywhere and inter prediction is exercised;
  chroma = a static grid of TILE x TILE (luma px) tiles, each tile one flat (Cb, Cr) pair;
           the colours of all tiles change every frame.
The chroma is flat inside each tile: the DE33 scaler's chroma phase differs between the
AFBC and the linear path (sun8i_vi_scaler_setup(): AFBC -0.125/-0.125, linear 0/-0.25),
which only changes pixels near a chroma edge. Pixels farther than BAND luma px from a tile
edge must therefore be identical (afbc-wb --tile/--band).
"""
import hashlib, sys
import numpy as np

def frames(w, h, n, bits, tile):
    rng = np.random.default_rng(20261106 + bits)
    pw, ph = w + 2 * n + 64, h + n + 64
    yy, xx = np.mgrid[0:ph, 0:pw]
    hi = (1 << bits) - 1
    lo_y, hi_y = (16, 235) if bits == 8 else (64, 940)
    span = hi_y - lo_y
    # smooth part, sharp checker edges, fine noise (all in units of the full luma span)
    smooth = (np.sin(xx / 37.0) * 0.25 + np.cos(yy / 23.0) * 0.2 + (xx + yy) / (pw + ph) * 0.3)
    check = (((xx // 24) + (yy // 16)) % 2) * 0.15
    noise = rng.random((ph, pw)) * 0.1
    pano = lo_y + np.clip((smooth + 0.45) * 0.6 + check + noise, 0, 1) * span
    pano = np.clip(np.rint(pano), lo_y, hi_y).astype(np.uint16)
    lo_c, hi_c = (16, 240) if bits == 8 else (64, 960)
    pal = rng.integers(lo_c, hi_c + 1, size=(64, 2))
    cw, ch = w // 2, h // 2
    ty, tx = np.mgrid[0:ch, 0:cw]
    ty //= tile // 2; tx //= tile // 2
    for t in range(n):
        y = pano[t:t + h, 2 * t:2 * t + w]
        idx = (tx * 5 + ty * 3 + t * 7) % 64
        u = pal[idx, 0].astype(np.uint16)
        v = pal[(idx * 11 + t) % 64, 1].astype(np.uint16)
        assert y.max() <= hi and u.max() <= hi and v.max() <= hi
        yield y, u, v

def main():
    out, name, w, h, n, bits, tile = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:8])
    dt = np.uint8 if bits == 8 else np.dtype('<u2')
    with open(f"{out}/{name}.yuv", "wb") as raw, open(f"{out}/{name}.srcmd5", "w") as md:
        for t, (y, u, v) in enumerate(frames(w, h, n, bits, tile)):
            raw.write(y.astype(dt).tobytes()); raw.write(u.astype(dt).tobytes()); raw.write(v.astype(dt).tobytes())
            uv = np.empty((h // 2, w), dtype=np.uint16); uv[:, 0::2] = u; uv[:, 1::2] = v
            if bits == 8:
                lin = y.astype(np.uint8).tobytes() + uv.astype(np.uint8).tobytes()
            else:
                lin = (y << 6).astype('<u2').tobytes() + (uv << 6).astype('<u2').tobytes()
            md.write(f"{t} {hashlib.md5(lin).hexdigest()}\n")

if __name__ == "__main__":
    main()
