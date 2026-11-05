import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void k(__global float *p, __global half *f)
{
   __local ushort data[16*256];
   size_t i = get_global_id(0), lid = get_local_id(0), lsize = get_local_size(0);
   vstore_half(p[i], lid, (__local half *)(&data[0]));
   barrier(CLK_LOCAL_MEM_FENCE);
   event_t e = async_work_group_copy((__global ushort*)f + (i-lid), (__local ushort *)(&data[0]), lsize, 0);
   wait_group_events(1, &e);
}
__kernel void g(__global float *p, __global half *f)
{ size_t i = get_global_id(0); vstore_half(p[i], i, f); }
"""
p = build(src)
N = 4096
for L in (64, 256):
    for pos in (None, 0, 1, 5, 63):
        vals = [1.5 + (i % 7) for i in range(N)]
        if pos is not None:
            for b in range(0, N, L): vals[b + pos] = 2.0 ** -131
        pin = buf(4 * N, struct.pack("%df" % N, *vals))
        res = {}
        for kn in ("k", "g"):
            o = buf(2 * N, b"\xad\xde" * N)
            run(p, kn, [pin, o], N, L)
            res[kn] = struct.unpack("%dH" % N, read(o, 2 * N))
        bad = [i for i in range(N) if res["k"][i] != res["g"][i]]
        print("L", L, "denorm@", pos, "bad", len(bad), [(i, hex(res["k"][i]), hex(res["g"][i])) for i in bad[:4]])
