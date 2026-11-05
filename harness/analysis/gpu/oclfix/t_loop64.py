import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
#define PRO __local uint lb[256]; lb[get_local_id(0)] = src[get_global_id(0)]; barrier(CLK_LOCAL_MEM_FENCE); \
  __global uint *d = dst + get_group_id(0)*get_local_size(0);
__kernel void a(__global uint *dst, __global const uint *src) { PRO
  event_t e = async_work_group_copy(d, lb, (size_t)get_local_size(0), 0); wait_group_events(1, &e); }
__kernel void b64(__global uint *dst, __global const uint *src) { PRO
  for (size_t i = get_local_id(0); i < get_local_size(0); i += get_local_size(0)) d[i] = lb[i];
  barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE); }
__kernel void b64nb(__global uint *dst, __global const uint *src) { PRO
  for (size_t i = get_local_id(0); i < get_local_size(0); i += get_local_size(0)) d[i] = lb[i]; }
__kernel void b32(__global uint *dst, __global const uint *src) { PRO
  for (uint i = get_local_id(0); i < get_local_size(0); i += get_local_size(0)) d[i] = lb[i];
  barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE); }
__kernel void s64(__global uint *dst, __global const uint *src) { PRO
  size_t i = get_local_id(0); if (i < get_local_size(0)) d[i] = lb[i];
  barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE); }
__kernel void g64(__global uint *dst, __global const uint *src) {
  __global uint *d = dst + get_group_id(0)*get_local_size(0); __global const uint *s = src + get_group_id(0)*get_local_size(0);
  for (size_t i = get_local_id(0); i < get_local_size(0); i += get_local_size(0)) d[i] = s[i];
  barrier(CLK_GLOBAL_MEM_FENCE); }
__kernel void g64nb(__global uint *dst, __global const uint *src) {
  __global uint *d = dst + get_group_id(0)*get_local_size(0); __global const uint *s = src + get_group_id(0)*get_local_size(0);
  for (size_t i = get_local_id(0); i < get_local_size(0); i += get_local_size(0)) d[i] = s[i]; }
__kernel void g64post(__global uint *dst, __global const uint *src) {
  __global uint *d = dst + get_group_id(0)*get_local_size(0); __global const uint *s = src + get_group_id(0)*get_local_size(0);
  for (size_t i = get_local_id(0); i < get_local_size(0); i += get_local_size(0)) d[i] = s[i];
  barrier(CLK_GLOBAL_MEM_FENCE); if (get_local_id(0) == 0) d[0] = s[0]; }
__kernel void midbar(__global uint *dst, __global const uint *src) {
  size_t g = get_global_id(0); dst[g] = 0u; barrier(CLK_GLOBAL_MEM_FENCE); dst[g] = src[g]; }
"""
p = build(src)
N = 1024
data = struct.pack("%dI" % N, *[0x10000 + i for i in range(N)])
s = buf(4 * N, data)
for kn in sys.argv[1:] or ("a", "b64", "b64nb", "b32", "s64", "g64", "g64nb", "g64post", "midbar"):
    for L in (64, 128, 256):
        tb = 0
        for rep in range(3):
            d = buf(4 * N, b"\xad" * (4 * N))
            run(p, kn, [d, s], N, L)
            r = struct.unpack("%dI" % N, read(d, 4 * N))
            bad = [i for i in range(N) if r[i] != 0x10000 + i]
            tb += len(bad)
            if rep == 0: ex = [(i, hex(r[i])) for i in bad[:3]]
        print(kn, "L", L, "bad(3 reps)", tb, ex, flush=True)
