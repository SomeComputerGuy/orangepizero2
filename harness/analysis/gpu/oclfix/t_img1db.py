import sys, random; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
cl.clCreateImage.restype = vp; cl.clCreateSampler.restype = vp
class Fmt(C.Structure): _fields_ = [("order", u32), ("type", u32)]
class Desc(C.Structure): _fields_ = [("type", u32), ("w", sz), ("h", sz), ("d", sz), ("as", sz), ("rp", sz), ("sp", sz), ("nml", u32), ("ns", u32), ("mem", vp)]
src = r"""
__kernel void k(read_only image1d_buffer_t a, read_only image1d_t b, sampler_t s, __global int *r, __global uint4 *ra, __global uint4 *rb)
{ int x = get_global_id(0); uint4 ca = read_imageui(a, x); uint4 cb = read_imageui(b, s, x);
  ra[x] = ca; rb[x] = cb; int4 t = (ca != cb); r[x] = (t.x||t.y||t.z||t.w) ? -1 : 0; }"""
p = build(src)
smp = vp(cl.clCreateSampler(ctx, 0, 0x1130, 0x1140, C.byref(err))); assert err.value == 0
for w in [int(a) for a in sys.argv[1:]] or [1, 7, 64, 1000, 4096, 16384, 65536, 65537, 100000]:
    data = bytes(random.randrange(256) for _ in range(w))
    b = buf(w, data); f = Fmt(0x10B0, 0x10DA)  # CL_R, CL_UNSIGNED_INT8
    d = Desc(0x10F6, w, 0, 0, 0, 0, 0, 0, 0, b)  # IMAGE1D_BUFFER
    ia = vp(cl.clCreateImage(ctx, u64(4), C.byref(f), C.byref(d), None, C.byref(err)))
    if err.value: print(w, "img1db err", err.value); continue
    d2 = Desc(0x10F4, w, 0, 0, 0, 0, 0, 0, 0, None)
    hb = C.create_string_buffer(data, w)
    ib = vp(cl.clCreateImage(ctx, u64(4 | 0x20), C.byref(f), C.byref(d2), hb, C.byref(err)))
    if err.value: print(w, "img1d err", err.value); continue
    r = buf(4 * w); ra = buf(16 * w); rb = buf(16 * w)
    e = run(p, "k", [ia, ib, smp, r, ra, rb], w)
    rv = struct.unpack("%di" % w, read(r, 4 * w)); A = struct.unpack("%dI" % (4*w), read(ra, 16 * w)); B = struct.unpack("%dI" % (4*w), read(rb, 16 * w))
    bad = [i for i in range(w) if rv[i]]
    print(w, "enq", e, "bad", len(bad), [(i, A[4*i:4*i+4], B[4*i:4*i+4], data[i]) for i in bad[:3]])
