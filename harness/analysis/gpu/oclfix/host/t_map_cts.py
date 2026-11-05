#!/usr/bin/env python3
"""host (shim, CPU-only): exact replay of OpenCL-CTS basic/enqueue_map_image (test_enqueue_map.cpp), including its
MT19937 stream (init_genrand(0): host data = 8 MiB of kUChar, then random_region_coords 6 draws per map), the flag
sets (ALLOC_HOST_PTR, ALLOC|COPY, USE_HOST_PTR, COPY_HOST_PTR, 0; IMMUTABLE ones skipped like the CTS without the
extension), the image types/sizes and 4 maps per format. usage: t_map_cts.py [max_flag_sets=8] [stop_on_fail=1]"""
import sys, numpy as np
from hostclk import *
maxflags = int(sys.argv[1]) if len(sys.argv) > 1 else 8
stop = int(sys.argv[2]) if len(sys.argv) > 2 else 1
mt = np.random.MT19937(); mt._legacy_seeding(0)
def draw(n=1): return mt.random_raw(n).astype(np.uint64)
def rir(lo, hi): return int((int(draw()[0]) * (hi - lo + 1)) >> 32) + lo
MAXDATA = 64 * 64 * 64 * 32
raw = draw(MAXDATA // 4).astype(np.uint32)
hostdata = bytes(raw.view(np.uint8))  # generate_random_data(kUChar): 4 bytes per draw, low byte first
assert len(hostdata) == MAXDATA
hostbuf = bytearray(hostdata)
flag_sets = [0x10, 0x30, 0x08, 0x20, 0x08 | 0x400, 0x20 | 0x400, 0x30 | 0x400, 0]
names = ["ALLOC", "ALLOC|COPY", "USE", "COPY", "USE|IMM", "COPY|IMM", "COPY|ALLOC|IMM", "0"]
types = [(IMAGE2D, "2D"), (IMAGE3D, "3D"), (IMAGE2D_ARRAY, "2DA"), (IMAGE1D, "1D"), (IMAGE1D_ARRAY, "1DA")]
fails = 0
for fi, flags in enumerate(flag_sets[:maxflags]):
    if flags & 0x400: continue  # no cl_ext_immutable_memory_objects: the CTS skips without drawing
    has_host = bool(flags & 0x28)
    for itype, tname in types:
        for f in formats(itype, 1):
            ref = bytearray(hostbuf); ps = pixsize(f)  # memcpy(referenceData, hostPtrData)
            if itype == IMAGE1D: reg = (256, 1, 1); mk = lambda h: image(IMAGE1D, f, 256, flags=flags, host=h)
            elif itype == IMAGE2D: reg = (256, 256, 1); mk = lambda h: image(IMAGE2D, f, 256, 256, flags=flags, host=h)
            elif itype == IMAGE3D: reg = (64, 64, 64); mk = lambda h: image(IMAGE3D, f, 64, 64, 64, flags=flags, host=h)
            elif itype == IMAGE1D_ARRAY: reg = (256, 256, 1); mk = lambda h: image(IMAGE1D_ARRAY, f, 256, 0, 0, 256, flags=flags, host=h)
            else: reg = (64, 64, 64); mk = lambda h: image(IMAGE2D_ARRAY, f, 64, 64, 0, 64, flags=flags, host=h)
            hb = (C.c_ubyte * MAXDATA).from_buffer(hostbuf)  # hostPtrData: persistent, aliased by USE_HOST_PTR images
            img = mk(hb if has_host else None)
            W, H, D = reg
            if not has_host: write_image(img, (0, 0, 0), reg, hb)
            fail = None; maps = []
            for it in range(4):
                o = [0, 0, 0]; r = [1, 1, 1]
                for k in range(3):
                    o[k] = rir(0, reg[k] - 1); r[k] = rir(1, reg[k] - o[k])
                maps.append((tuple(o), tuple(r)))
                p, rp, sp = map_image(img, o, r)
                ypitch = sp if itype == IMAGE1D_ARRAY else rp
                mv = (C.c_ubyte * (sp * (r[2] - 1) + ypitch * (r[1] - 1) + r[0] * ps)).from_address(p.value)
                for z in range(r[2]):
                    for y in range(r[1]):
                        mo = z * sp + y * ypitch; ro = ((o[2] + z) * H + (o[1] + y)) * W * ps + o[0] * ps
                        got = bytes(mv[mo:mo + r[0] * ps]); exp = bytes(ref[ro:ro + r[0] * ps])
                        if got != exp and fail is None:
                            i = next(i for i in range(len(got)) if got[i] != exp[i])
                            fail = "map %d origin %s region %s pitches %d/%d at z=%d y=%d byte %d (sample %d): got %d exp %d" % (
                                it, o, r, rp, sp, z, y, i, (ro + i) // ps, got[i], exp[i])
                        mv[mo:mo + r[0] * ps] = bytes(r[0] * ps); ref[ro:ro + r[0] * ps] = bytes(r[0] * ps)
                unmap(img, p)
            if fail is None:
                out = read_image(img, (0, 0, 0), reg, W * H * D * ps)
                exp = bytes(ref[:W * H * D * ps])
                if out != exp:
                    i = next(i for i in range(len(out)) if out[i] != exp[i]); fail = "final readback byte %d got %d exp %d" % (i, out[i], exp[i])
            release(img)
            if fail:
                fails += 1; print("FAIL %-14s %-3s %-24s ps=%d: %s; maps so far %s" % (names[fi], tname, fmtname(f), ps, fail, maps)); sys.stdout.flush()
                if stop: raise SystemExit(1)
        print("done %-14s %-3s (%d formats)" % (names[fi], tname, len(formats(itype, 1)))); sys.stdout.flush()
print("FAILS", fails)
