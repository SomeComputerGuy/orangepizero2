import sys, time, array; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void ka(__global uint *dst, uint fx, ulong sa, ulong ea)
{ unsigned long t = (unsigned long)get_global_id(1)*(unsigned long)fx + (unsigned long)get_global_id(0);
  if ((t >= sa) && (t < ea)) atom_add(&dst[t-sa], 1u); }
__kernel void kr(__global uint *dst, uint fx, ulong sa, ulong ea)
{ unsigned long t = (unsigned long)get_global_id(1)*(unsigned long)fx + (unsigned long)get_global_id(0);
  if ((t >= sa) && (t < ea)) { uint o = atom_add(&dst[t-sa], 1u); if (o == 77u) dst[0] = 99u; } }
__kernel void ks(__global uint *dst, uint fx, ulong sa, ulong ea)
{ unsigned long t = (unsigned long)get_global_id(1)*(unsigned long)fx + (unsigned long)get_global_id(0);
  if ((t >= sa) && (t < ea)) dst[t-sa] = 1u; }
__kernel void ku(__global uint *dst, uint fx, uint sa, uint ea)
{ uint t = get_global_id(1)*fx + get_global_id(0);
  if ((t >= sa) && (t < ea)) atom_add(&dst[t-sa], 1u); }
"""
p = build(src)
g, l = [16384, 4096], [256, 1]
for kn in ("ka", "kr", "ks", "ku"):
    for sa, ea in ((0, 1 << 22), (1 << 22, 2 << 22)):
        n = ea - sa
        d = buf(4 * n, b"\0" * (4 * n))
        a = [d, C.c_uint(g[0])] + ([C.c_uint(sa), C.c_uint(ea)] if kn == "ku" else [C.c_ulong(sa), C.c_ulong(ea)])
        run(p, kn, a, g, l)
        v = array.array("I"); v.frombytes(read(d, 4 * n))
        bad = [i for i in range(n) if v[i] != 1]
        time.sleep(1); v2 = array.array("I"); v2.frombytes(read(d, 4 * n))
        bad2 = sum(1 for i in range(n) if v2[i] != 1)
        print(kn, sa, "bad", len(bad), bad[:2], bad[-1:] if bad else "", "reread-bad", bad2, flush=True)
