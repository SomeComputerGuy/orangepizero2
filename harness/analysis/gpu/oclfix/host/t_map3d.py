#!/usr/bin/env python3
"""host (shim, CPU-only): CTS basic/enqueue_map_image pattern. usage: t_map3d.py [itype=3d] [flags=0x30] [iters=4] [maxfmt]
Creates the image with the given cl_mem_flags (default ALLOC_HOST_PTR|COPY_HOST_PTR) from random host data,
maps random regions READ|WRITE, checks them against the reference, zeroes them, unmaps, then reads the whole image back."""
import sys, random
from hostclk import *
targ = sys.argv[1] if len(sys.argv) > 1 else "3d"
flags = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x30
iters = int(sys.argv[3]) if len(sys.argv) > 3 else 4
maxfmt = int(sys.argv[4]) if len(sys.argv) > 4 else 999
itype = {"2d": IMAGE2D, "3d": IMAGE3D, "2da": IMAGE2D_ARRAY, "1d": IMAGE1D, "1da": IMAGE1D_ARRAY}[targ]
random.seed(1)
N = 64 if targ in ("3d", "2da") else 256
bad = 0
for f in formats(itype)[:maxfmt]:
    ps = pixsize(f)
    if itype == IMAGE3D: dims = (N, N, N); im = lambda h: image(IMAGE3D, f, N, N, N, flags=flags, host=h)
    elif itype == IMAGE2D_ARRAY: dims = (N, N, N); im = lambda h: image(IMAGE2D_ARRAY, f, N, N, 0, N, flags=flags, host=h)
    elif itype == IMAGE2D: dims = (N, N, 1); im = lambda h: image(IMAGE2D, f, N, N, flags=flags, host=h)
    elif itype == IMAGE1D: dims = (N, 1, 1); im = lambda h: image(IMAGE1D, f, N, flags=flags, host=h)
    else: dims = (N, N, 1); im = lambda h: image(IMAGE1D_ARRAY, f, N, 0, 0, N, flags=flags, host=h)
    W, H, D = dims; total = W * H * D * ps
    data = bytearray(random.getrandbits(8) for _ in range(total)); ref = bytearray(data)
    hb = (C.c_ubyte * total).from_buffer(data)
    img = im(hb if flags & 0x28 else None)
    if not flags & 0x28: write_image(img, (0, 0, 0), dims, hb)
    fail = None
    for it in range(iters):
        ox = random.randrange(W); rx = random.randrange(1, W - ox + 1)
        oy = random.randrange(H); ry = random.randrange(1, H - oy + 1)
        oz = random.randrange(D); rz = random.randrange(1, D - oz + 1)
        if itype == IMAGE1D_ARRAY: origin, region = (ox, oy, 0), (rx, ry, 1)
        else: origin, region = (ox, oy, oz), (rx, ry, rz)
        p, rp, sp = map_image(img, origin, region)
        ypitch = sp if itype == IMAGE1D_ARRAY else rp
        nz, ny = (1, ry) if itype == IMAGE1D_ARRAY else (rz, ry)
        mv = (C.c_ubyte * (sp * max(1, nz) + ypitch * ny + rx * ps)).from_address(p.value)
        for z in range(nz):
            for y in range(ny):
                mo = z * sp + y * ypitch; ro = ((oz + z) * H + (oy + y)) * W * ps + ox * ps
                got = bytes(mv[mo:mo + rx * ps]); exp = bytes(ref[ro:ro + rx * ps])
                if got != exp and fail is None:
                    i = next(i for i in range(len(got)) if got[i] != exp[i])
                    fail = "iter %d origin %s region %s pitches %d/%d: z=%d y=%d byte %d got %d exp %d" % (
                        it, origin, region, rp, sp, z, y, i, got[i], exp[i])
                mv[mo:mo + rx * ps] = bytes(rx * ps); ref[ro:ro + rx * ps] = bytes(rx * ps)
        unmap(img, p)
        if fail: break
    if not fail:
        out = read_image(img, (0, 0, 0), dims, total)
        if out != bytes(ref):
            i = next(i for i in range(total) if out[i] != ref[i]); fail = "final readback byte %d got %d exp %d" % (i, out[i], ref[i])
    print("%-24s ps=%d %s" % (fmtname(f), ps, fail or "ok")); bad += bool(fail)
    release(img)
print("BAD", bad)
