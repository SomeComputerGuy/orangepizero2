import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void k(__global uint *dst, uint fx, uint fy, uint fz, ulong sa, ulong ea)
{
    uint error = 0;
    if (get_global_id(0) >= fx) error = 64;
    if (get_global_id(1) >= fy) error = 128;
    if (get_global_id(2) >= fz) error = 256;
    unsigned long t = (unsigned long)get_global_id(2)*(unsigned long)fy*(unsigned long)fx +
                      (unsigned long)get_global_id(1)*(unsigned long)fx + (unsigned long)get_global_id(0);
    if ((t >= sa) && (t < ea)) atom_add(&dst[t-sa], 1u);
    if (error) atom_or(&dst[t-sa], error);
}"""
p = build(src)
for g, l, sa, ea in (([1024, 64, 1], [256, 1, 1], 0, 65536), ([16384, 64, 1], [256, 1, 1], 0, 1 << 20),
                     ([16384, 4096, 1], [256, 1, 1], 0, 1 << 22), ([16384, 4096, 1], [256, 1, 1], 1 << 22, 2 << 22),
                     ([16384, 4096, 1], [256, 1, 1], 48 << 20, (48 << 20) + (1 << 22))):
    n = ea - sa
    d = buf(4 * n, b"\0" * (4 * n))
    e = run(p, "k", [d, C.c_uint(g[0]), C.c_uint(g[1]), C.c_uint(g[2]), C.c_ulong(sa), C.c_ulong(ea)], g, l)
    v = struct.unpack("%dI" % n, read(d, 4 * n))
    bad = [i for i in range(n) if v[i] != 1]
    print(g, l, sa, ea, "enq", e, "bad", len(bad), bad[:4], [hex(v[i]) for i in bad[:4]])
