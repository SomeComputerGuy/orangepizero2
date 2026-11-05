import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
body = r"""
    int oldValue, origValue, newValue;
    do {
        origValue = destMemory[0];
        newValue = origValue + tid + 2;
        oldValue = atomic_cmpxchg(&destMemory[0], origValue, newValue);
    } while (oldValue != origValue);
    oldValues[tid] = oldValue;
"""
src = r"""
__kernel void kl(__global int *finalDest, __global int *oldValues, volatile __local int *destMemory)
{
    int tid = get_global_id(0);
    if (get_local_id(0) == 0) destMemory[0] = finalDest[0];
    barrier(CLK_LOCAL_MEM_FENCE);
""" + body + r"""
    barrier(CLK_LOCAL_MEM_FENCE);
    if (get_local_id(0) == 0) finalDest[0] = destMemory[0];
}
__kernel void kls(__global int *finalDest, __global int *oldValues)
{
    volatile __local int destMemory[1];
    int tid = get_global_id(0);
    if (get_local_id(0) == 0) destMemory[0] = finalDest[0];
    barrier(CLK_LOCAL_MEM_FENCE);
""" + body + r"""
    barrier(CLK_LOCAL_MEM_FENCE);
    if (get_local_id(0) == 0) finalDest[0] = destMemory[0];
}
__kernel void kg(__global int *finalDest, __global int *oldValues)
{
    volatile __global int *destMemory = finalDest;
    int tid = get_global_id(0);
""" + body + r"""
}
"""
p = build(src)
for name, extra in (("kg", []), ("kls", []), ("kl", [local(4)])):
    for N in (1, 2, 4, 8, 64, 256):
        fd = buf(4, struct.pack("i", 1000)); ov = buf(4 * N)
        run(p, name, [fd, ov] + extra, N, N)
        got = struct.unpack("i", read(fd, 4))[0]; old = struct.unpack("%di" % N, read(ov, 4 * N))
        print(name, N, "final", got, "exp", 1000 + sum(t + 2 for t in range(N)), "dups", N - len(set(old)), old[:8])
