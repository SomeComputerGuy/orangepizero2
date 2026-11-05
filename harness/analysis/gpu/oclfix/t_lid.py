import sys, array; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void k(__global uint *o)
{
  size_t g = get_global_id(0);
  size_t id = get_local_size(1)*get_local_size(2)*get_local_id(0) + get_local_size(2)*get_local_id(1) + get_local_id(2);
  size_t id2 = get_local_id(0) + get_local_size(0)*get_local_id(1) + get_local_size(0)*get_local_size(1)*get_local_id(2);
  __global uint *p = o + g*12;
  p[0] = get_local_id(0); p[1] = get_local_id(1); p[2] = get_local_id(2);
  p[3] = get_local_size(0); p[4] = get_local_size(1); p[5] = get_local_size(2);
  p[6] = (uint)id; p[7] = (uint)(id >> 32); p[8] = (uint)id2; p[9] = (uint)(id2 >> 32);
  p[10] = get_group_id(0); p[11] = (uint)get_global_id(0);
}
__kernel void c(__global ushort *dst, __global const ushort *src, uint n)
{
  __local ushort lb[256];
  lb[get_local_id(0)] = src[get_global_id(0)];
  barrier(CLK_LOCAL_MEM_FENCE);
  event_t e = async_work_group_copy(dst + get_group_id(0)*get_local_size(0), lb, (size_t)get_local_size(0), 0);
  wait_group_events(1, &e);
}
__kernel void c32(__global uint *dst, __global const uint *src, uint n)
{
  __local uint lb[256];
  lb[get_local_id(0)] = src[get_global_id(0)];
  barrier(CLK_LOCAL_MEM_FENCE);
  event_t e = async_work_group_copy(dst + get_group_id(0)*get_local_size(0), lb, (size_t)get_local_size(0), 0);
  wait_group_events(1, &e);
}
"""
p = build(src)
for N, L in ((256, 64), (512, 256)):
    o = buf(4 * 12 * N, b"\xee" * (48 * N)); run(p, "k", [o], N, L)
    v = array.array("I"); v.frombytes(read(o, 48 * N))
    bad = [i for i in range(N) if list(v[12*i:12*i+12]) != [i % L, 0, 0, L, 1, 1, i % L, 0, i % L, 0, i // L, i]]
    print("lid N", N, "L", L, "bad", len(bad), [(i, list(v[12*i:12*i+12])) for i in bad[:3]], flush=True)
for kn, es in (("c", 2), ("c32", 4)):
    for N, L in ((256, 64), (1024, 256)):
        data = bytes((i * 37 + 11) & 0xff for i in range(N * es))
        s = buf(N * es, data); d = buf(N * es, b"\xad" * (N * es))
        run(p, kn, [d, s, C.c_uint(N)], N, L)
        r = read(d, N * es)
        bad = [i for i in range(N) if r[i*es:(i+1)*es] != data[i*es:(i+1)*es]]
        print(kn, N, L, "bad", len(bad), bad[:12], flush=True)
