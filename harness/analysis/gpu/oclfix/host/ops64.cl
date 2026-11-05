__kernel void add_l16(__global long16 *srcA, __global long16 *srcB, __global long16 *dst)
{ int tid = get_global_id(0); dst[tid] = srcA[tid] + srcB[tid]; }
__kernel void mul_l16(__global long16 *srcA, __global long16 *srcB, __global long16 *dst)
{ int tid = get_global_id(0); dst[tid] = srcA[tid] * srcB[tid]; }
__kernel void div_l8(__global long8 *srcA, __global long8 *srcB, __global long8 *dst)
{ int tid = get_global_id(0); dst[tid] = srcA[tid] / srcB[tid]; }
__kernel void div_ul16(__global ulong16 *srcA, __global ulong16 *srcB, __global ulong16 *dst)
{ int tid = get_global_id(0); dst[tid] = srcA[tid] / srcB[tid]; }
