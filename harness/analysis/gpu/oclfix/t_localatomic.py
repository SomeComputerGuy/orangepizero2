import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void k(__global int *finalDest, __global int *oldValues, volatile __local int *destMemory, int numDestItems)
{
    int tid = get_global_id(0);
    for (int i = 0; i < numDestItems; i++) destMemory[i] = finalDest[i];
    barrier(CLK_LOCAL_MEM_FENCE);
    oldValues[tid] = atomic_add(&destMemory[0], tid + 3);
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int i = 0; i < numDestItems; i++) finalDest[i] = destMemory[i];
}"""
p = build(src)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 256
fd = buf(4, struct.pack("i", 7)); ov = buf(4 * N)
run(p, "k", [fd, ov, local(4), C.c_int(1)], N, N)
got = struct.unpack("i", read(fd, 4))[0]; old = struct.unpack("%di" % N, read(ov, 4 * N))
print("final", got, "expect", 7 + sum(t + 3 for t in range(N)), "olds sorted ok:", sorted(old)[:4])
