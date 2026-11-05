import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void k(const __global char *src, __global char *dst, __local char *lb, int cpw, int cpi)
{
    int i;
    for (i = 0; i < cpi; i++) lb[get_local_id(0)*cpi+i] = src[get_global_id(0)*cpi+i];
    barrier(CLK_LOCAL_MEM_FENCE);
    event_t e = async_work_group_copy((__global char*)(dst+cpw*get_group_id(0)), (__local const char*)lb, (size_t)cpw, 0);
    wait_group_events(1, &e);
}
__kernel void k2(const __global char *src, __global char *dst, __local char *lb, int cpw, int cpi)
{
    int i;
    for (i = 0; i < cpi; i++) lb[get_local_id(0)*cpi+i] = src[get_global_id(0)*cpi+i];
    barrier(CLK_LOCAL_MEM_FENCE);
    for (i = get_local_id(0); i < cpw; i += get_local_size(0)) dst[cpw*get_group_id(0)+i] = lb[i];
}"""
p = build(src)
for kn in ("k", "k2"):
    k = vp(cl.clCreateKernel(p, kn.encode(), C.byref(err)))
    v = sz(); cl.clGetKernelWorkGroupInfo(k, dev, 0x11B0, sz(8), C.byref(v), None)
    pm = sz(); cl.clGetKernelWorkGroupInfo(k, dev, 0x11B3, sz(8), C.byref(pm), None)
    print(kn, "CL_KERNEL_WORK_GROUP_SIZE", v.value, "pref_mult", pm.value, flush=True)
