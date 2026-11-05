#!/usr/bin/env python3
"""host (shim): the CTS samplerless 1Dbuffer kernel, exactly as test_read_1D_buffer.cpp sets it up
(READ_ONLY|COPY_HOST_PTR parent buffer of rowPitch bytes, READ_ONLY 1D buffer image on it, READ_ONLY|COPY_HOST_PTR
1D image, sampler NONE/NEAREST, results pre-filled with 0xff). usage: t_sl1db.py [width=329] [int|uint|float] [order] [type]
Run with PAN_MESA_DEBUG=trace PANDECODE_DUMP_FILE=... to get the descriptors + shader; nothing executes."""
import sys, random
from hostclk import *
w = int(sys.argv[1]) if len(sys.argv) > 1 else 329
kind = sys.argv[2] if len(sys.argv) > 2 else "int"
order = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x10B0
ctype = int(sys.argv[4], 0) if len(sys.argv) > 4 else {"int": 0x10D7, "uint": 0x10DA, "float": 0x10DE}[kind]
dt, rf = {"int": ("int4", "i"), "uint": ("uint4", "ui"), "float": ("float4", "f")}[kind]
swap = os.environ.get("SWAP")  # SWAP=1: the plain 1D image comes first, so the buffer image is texture 1
src = """__kernel void sample_kernel( %s, sampler_t sampler, __global int *results )
{
   int tidX = get_global_id(0);
   int offset = tidX;
   %s clr = read_image%s( inputA, tidX );
   int4 test = (clr != read_image%s( inputB, sampler, tidX ));
   if ( test.x || test.y || test.z || test.w )
      results[offset] = -1;
   else
      results[offset] = 0;
}""" % ("read_only image1d_t inputB, read_only image1d_buffer_t inputA" if swap else "read_only image1d_buffer_t inputA, read_only image1d_t inputB", dt, rf, rf)
p = build(src)
f = Fmt(order, ctype); ps = pixsize(f); random.seed(2)
data = bytes(random.getrandbits(8) for _ in range(w * ps)); hb = C.create_string_buffer(data, w * ps)
parent = buf(w * ps, hb, flags=int(os.environ.get("PARENT_FLAGS", "4"), 0))
ia = image(IMAGE1D_BUFFER, f, w, flags=4, mem=parent)
ib = image(IMAGE1D, f, w, flags=4 | 0x20, host=hb)
smp = sampler(0, 0x1130, 0x1140)
res = buf(4 * w, flags=0); write(res, b"\xff" * (4 * w))
e = run(p, "sample_kernel", [ib, ia, smp, res] if swap else [ia, ib, smp, res], w, finish=True)
print("enqueue", e, "width", w, fmtname(f), "ps", ps)
