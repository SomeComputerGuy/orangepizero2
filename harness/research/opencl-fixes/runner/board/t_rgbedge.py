#!/usr/bin/env python3
"""board: read the LAST texel of a linear image whose data ends exactly on a 2 MiB boundary, so that (with the
kernel's best-fit VA allocator) nothing is mapped right after the image BO. Tests the hypothesis that the Mali-G31
texture unit reads the cache line after a 24/96-bit texel (job 09 / job 28 page faults on CL_RGB images).
usage: t_rgbedge.py <case>   cases: rgb8 rgb32i rgba8 rgba32i (6 MiB images) | rgb8s rgb32is (the CTS sizes)
Prints CASE/BO/RESULT lines; the caller diffs dmesg around each run (a fault = 'Unhandled Page fault').
Needs: . /root/opiz2-mesa/<build>/env.sh (OCL_ICD_FILENAMES = rusticl), hostclk.py next to this file."""
import sys, struct
from hostclk import *
RGB, RGBA = 0x10B4, 0x10B5
UNORM8, SINT32 = 0x10D2, 0x10D9
CASES = {  # name: (order, type, image type, W, H, D/layers); W*bpp is a multiple of 64 (no row padding)
    "rgb8":    (RGB,  UNORM8, IMAGE2D_ARRAY, 1024, 64, 32),   # 3072 B rows, 6 MiB
    "rgb32i":  (RGB,  SINT32, IMAGE3D,        256, 64, 32),   # 3072 B rows, 6 MiB
    "rgba8":   (RGBA, UNORM8, IMAGE2D_ARRAY, 1024, 64, 24),   # control: 4096 B rows, 6 MiB
    "rgba32i": (RGBA, SINT32, IMAGE3D,        256, 64, 24),   # control: 4096 B rows, 6 MiB
    "rgb8s":   (RGB,  UNORM8, IMAGE2D_ARRAY,   21, 32, 14),   # job 09 f2d-r2da size (28672 B)
    "rgb32is": (RGB,  SINT32, IMAGE3D,         25, 128, 32),  # job 28 img3d size (0x140000 B)
}
name = sys.argv[1]; order, ctype, itype, W, H, D = CASES[name]
f = Fmt(order, ctype); ps = pixsize(f)
isint = ctype == SINT32
img_t = "image2d_array_t" if itype == IMAGE2D_ARRAY else "image3d_t"
rd = "read_imagei" if isint else "read_imagef"
vt = "int4" if isint else "float4"
src = """
__constant sampler_t edge = CLK_NORMALIZED_COORDS_FALSE | CLK_ADDRESS_CLAMP_TO_EDGE | CLK_FILTER_NEAREST;
__kernel void k(read_only %(img)s im, __global %(vt)s *res, int w, int h, int d)
{
   int i = get_global_id(0);
   int4 c;
   if (i < 16)      c = (int4)(w - 1 - i, h - 1, d - 1, 0);     /* last row of the last layer/slice */
   else if (i < 32) c = (int4)(w + i, h + i, d + i, 0);         /* out of range, clamps to the last texel */
   else             c = (int4)(w - 1, h - 1, d - 1, 0);
   %(vt)s v = (i < 48) ? %(rd)s(im, edge, c) : %(rd)s(im, c);   /* sampled and sampler-less (texel fetch) */
   res[i] = v;
}""" % {"img": img_t, "vt": vt, "rd": rd}
p = build(src)
N = 64
res = buf(16 * N); write(res, b"\xff" * (16 * N))
# warm-up on a small image of the same format: compiles the kernel, fills the BO cache with the pools/descriptors
small = image(itype, f, 8, 8, 4 if itype == IMAGE3D else 0, 4 if itype == IMAGE2D_ARRAY else 0)
args = lambda im: [im, res, C.c_int(W), C.c_int(H), C.c_int(D)]
assert run(p, "k", args(small), [N], [16]) == 0
finish()
# the target: allocated last, larger than any hole, 2 MiB aligned by the kernel (noexec >= 2 MiB)
big = image(itype, f, W, H, D if itype == IMAGE3D else 0, D if itype == IMAGE2D_ARRAY else 0)
row = (W * ps + 63) // 64 * 64; data = row * H * D   # panfrost linear layout: 64 B aligned rows, no layer padding here
print("CASE %s %s %s %dx%dx%d texel %d B row %d B data 0x%x B, last texel at 0x%x" % (
    name, fmtname(f), "2Darray" if itype == IMAGE2D_ARRAY else "3D", W, H, D, ps, row, data, data - row + (W - 1) * ps))
sys.stdout.flush()
for rep in range(3):
    write(res, b"\xff" * (16 * N))
    e = run(p, "k", args(big), [N], [16]); fe = finish()
    out = read(res, 16 * N)
    stored = sum(1 for i in range(N) if out[16 * i:16 * i + 16] != b"\xff" * 16)
    print("RESULT %s rep %d enqueue %d finish %d stored %d of %d" % (name, rep, e, fe, stored, N)); sys.stdout.flush()
