#!/usr/bin/env python3
"""host (shim): CTS kernel_read_write 3D read kernel, integer coords, int results (read_imagei), NEAREST,
UNNORMALIZED, on a 25x128x32 image (the job 28 img3d failure: CL_RGB SIGNED_INT32 CLAMP_TO_EDGE).
usage: t_rd3di.py [order=0x10B4] [type=0x10D9] [addr=0x1131] [w h d]
With PAN_MESA_DEBUG=trace PANDECODE_DUMP_FILE=... it dumps the descriptors + shader; nothing executes."""
import sys, random, struct
from hostclk import *
order = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x10B4
ctype = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0x10D9
addr = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x1131
W, H, D = (int(a) for a in sys.argv[4:7]) if len(sys.argv) > 6 else (25, 128, 32)
src = """
__kernel void sample_kernel( read_only image3d_t input, sampler_t imageSampler, __global float *xOffsets, __global float *yOffsets, __global float *zOffsets,  __global int4 *results  )
{
   int tidX = get_global_id(0), tidY = get_global_id(1), tidZ = get_global_id(2);
   int offset = tidZ*get_image_width(input)*get_image_height(input) + tidY*get_image_width(input) + tidX;
   int4 coords = (int4)( (int)xOffsets[offset], (int)yOffsets[offset], (int)zOffsets[offset], 0 );
   results[offset] = read_imagei( input, imageSampler, coords );
}"""
p = build(src)
f = Fmt(order, ctype); ps = pixsize(f); random.seed(3)
n = W * H * D
data = bytes(random.getrandbits(8) for _ in range(n * ps)); hb = C.create_string_buffer(data, n * ps)
img = image(IMAGE3D, f, W, H, D, flags=4)
write_image(img, (0, 0, 0), (W, H, D), hb)
smp = sampler(0, addr, 0x1140)
xs = buf(4 * n, struct.pack("%df" % n, *[float(i % W + 6) for i in range(n)]))
ys = buf(4 * n, struct.pack("%df" % n, *[float((i // W) % H) for i in range(n)]))
zs = buf(4 * n, struct.pack("%df" % n, *[float(i // (W * H)) for i in range(n)]))
res = buf(16 * n); write(res, b"\xff" * (16 * n))
e = run(p, "sample_kernel", [img, smp, xs, ys, zs, res], [W, H, D], finish=True)
print("enqueue", e, "image %dx%dx%d" % (W, H, D), fmtname(f), "ps", ps)
