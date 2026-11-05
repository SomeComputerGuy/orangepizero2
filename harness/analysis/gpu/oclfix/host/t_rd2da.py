#!/usr/bin/env python3
"""host (shim): the CTS kernel_read_write 2D-array float read kernel (read2DArrayKernelSourcePattern, float coords,
UNNORMALIZED, NEAREST) on a 21x32x14 image, written with clEnqueueWriteImage like the default CTS mode.
usage: t_rd2da.py [order=0x10B4 (RGB)] [type=0x10D2 (UNORM_INT8)] [normalized=0] [addr=0x1131] [w h a]
With PAN_MESA_DEBUG=trace PANDECODE_DUMP_FILE=... it dumps the texture/sampler descriptors + shader; nothing executes."""
import sys, random, struct
from hostclk import *
order = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x10B4
ctype = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x10D2
norm = int(sys.argv[3]) if len(sys.argv) > 3 else 0
addr = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x1131
W, H, A = (int(a) for a in sys.argv[5:8]) if len(sys.argv) > 7 else (21, 32, 14)
src = """
__kernel void sample_kernel( read_only image2d_array_t input, sampler_t imageSampler, __global float *xOffsets, __global float *yOffsets, __global float *zOffsets,  __global float4 *results  )
{
   int tidX = get_global_id(0), tidY = get_global_id(1), tidZ = get_global_id(2);
   int offset = tidZ*get_image_width(input)*get_image_height(input) + tidY*get_image_width(input) + tidX;
   float4 coords = (float4)( xOffsets[offset], yOffsets[offset], zOffsets[offset], 0.0f );
   results[offset] = read_imagef( input, imageSampler, coords );
}"""
p = build(src)
f = Fmt(order, ctype); ps = pixsize(f); random.seed(3)
n = W * H * A
data = bytes(random.getrandbits(8) for _ in range(n * ps)); hb = C.create_string_buffer(data, n * ps)
img = image(IMAGE2D_ARRAY, f, W, H, 0, A, flags=4)
write_image(img, (0, 0, 0), (W, H, A), hb)
smp = sampler(norm, addr, 0x1140)
xs = buf(4 * n, struct.pack("%df" % n, *[float(i % W) for i in range(n)]))
ys = buf(4 * n, struct.pack("%df" % n, *[float((i // W) % H) for i in range(n)]))
zs = buf(4 * n, struct.pack("%df" % n, *[float(i // (W * H)) for i in range(n)]))
res = buf(16 * n); write(res, b"\xff" * (16 * n))
e = run(p, "sample_kernel", [img, smp, xs, ys, zs, res], [W, H, A], finish=True)
print("enqueue", e, "image %dx%dx%d" % (W, H, A), fmtname(f), "ps", ps)
