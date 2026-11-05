import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void k(__global int *fd, __global int *ov, volatile __local int *m, int n)
{
    int tid = get_global_id(0);
    for (int i = 0; i < n; i++) m[i] = fd[i];
    barrier(CLK_LOCAL_MEM_FENCE);
    ov[tid] = atomic_add(&m[0], 1);
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int i = 0; i < n; i++) fd[i] = m[i];
}
__kernel void k2(__global int *fd, __global int *ov, volatile __local int *m, int n)
{
    int tid = get_global_id(0);
    m[0] = fd[0];
    barrier(CLK_LOCAL_MEM_FENCE);
    ov[tid] = atomic_add(&m[0], 1);
    barrier(CLK_LOCAL_MEM_FENCE);
    fd[0] = m[0];
}
"""
p = build(src)
kq = vp(cl.clCreateKernel(p, b"k", C.byref(err))); wg = sz()
cl.clGetKernelWorkGroupInfo(kq, dev, 0x11B0, 8, C.byref(wg), None); print("CL_KERNEL_WORK_GROUP_SIZE", wg.value)
for name in ("k", "k2"):
    for N in (4, 16, 32, 64, 128, 256):
        fd = buf(4, struct.pack("i", 1000)); ov = buf(4 * N)
        run(p, name, [fd, ov, local(4), C.c_int(1)], N, N)
        print(name, N, "final", struct.unpack("i", read(fd, 4))[0], "exp", 1000 + N)
