import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
# Basic async_copy_local_to_global, char, 256 x 13 per WG
for ty, sz_ in (("char", 1), ("int", 4)):
    src = r"""
__kernel void k(const __global %(t)s *src, __global %(t)s *dst, __local %(t)s *lb, int cpw, int cpi)
{
    int i;
    for (i = 0; i < cpi; i++) lb[get_local_id(0)*cpi+i] = (%(t)s)0;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (i = 0; i < cpi; i++) lb[get_local_id(0)*cpi+i] = src[get_global_id(0)*cpi+i];
    barrier(CLK_LOCAL_MEM_FENCE);
    event_t e = async_work_group_copy((__global %(t)s*)(dst+cpw*get_group_id(0)), (__local const %(t)s*)lb, (size_t)cpw, 0);
    wait_group_events(1, &e);
}
__kernel void k2(const __global %(t)s *src, __global %(t)s *dst, __local %(t)s *lb, int cpw, int cpi)
{
    int i;
    for (i = 0; i < cpi; i++) lb[get_local_id(0)*cpi+i] = src[get_global_id(0)*cpi+i];
    barrier(CLK_LOCAL_MEM_FENCE);
    for (i = get_local_id(0); i < cpw; i += get_local_size(0)) dst[cpw*get_group_id(0)+i] = lb[i];
}
""" % {"t": ty}
    p = build(src)
    for L, G in ((256, 256), (256, 1024), (64, 64)):
        cpi = 13; cpw = L * cpi; n = G * cpi
        data = bytes((i * 7 + 3) & 0xff or 1 for i in range(n * sz_))
        s = buf(n * sz_, data)
        for kn in ("k", "k2"):
            d = buf(n * sz_, b"\0" * (n * sz_))
            run(p, kn, [s, d, local(cpw * sz_), C.c_int(cpw), C.c_int(cpi)], G, L)
            out = read(d, n * sz_)
            bad = [i for i in range(n) if out[i*sz_:(i+1)*sz_] != data[i*sz_:(i+1)*sz_]]
            print(ty, kn, L, G, "bad", len(bad), bad[:8])
