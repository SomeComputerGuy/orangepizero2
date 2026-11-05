import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void kstatic(__global int *fd, __global int *ov)
{
    __local int m[4];
    int tid = get_local_id(0);
    if (tid == 0) m[0] = fd[0];
    barrier(CLK_LOCAL_MEM_FENCE);
    ov[get_global_id(0)] = atomic_add(&m[0], 1);
    barrier(CLK_LOCAL_MEM_FENCE);
    if (tid == 0) fd[get_group_id(0)] = m[0];
}
__kernel void karg(__global int *fd, __global int *ov, __local int *m)
{
    int tid = get_local_id(0);
    if (tid == 0) m[0] = fd[0];
    barrier(CLK_LOCAL_MEM_FENCE);
    ov[get_global_id(0)] = atomic_add(&m[0], 1);
    barrier(CLK_LOCAL_MEM_FENCE);
    if (tid == 0) fd[get_group_id(0)] = m[0];
}
__kernel void kxchg(__global int *fd, __global int *ov, __local int *m)
{
    int tid = get_local_id(0);
    if (tid == 0) m[0] = fd[0];
    barrier(CLK_LOCAL_MEM_FENCE);
    ov[get_global_id(0)] = atomic_xchg(&m[0], 1);
    barrier(CLK_LOCAL_MEM_FENCE);
    if (tid == 0) fd[get_group_id(0)] = m[0];
}
"""
p = build(src)
for name, extra in (("kstatic", []), ("karg", [local(4)]), ("karg", [local(256)]), ("kxchg", [local(4)])):
    for N, L in ((1, 1), (64, 64), (256, 64)):
        fd = buf(16, struct.pack("4i", 100, 100, 100, 100)); ov = buf(4 * N)
        run(p, name, [fd, ov] + extra, N, L)
        print(name, extra and extra[0].n, N, L, "final", struct.unpack("4i", read(fd, 16))[:N // L], "old[:4]", struct.unpack("%di" % N, read(ov, 4 * N))[:4])
