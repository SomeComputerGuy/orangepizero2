import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
src = r"""
__kernel void k(__global int *finalDest, __global int *oldValues, volatile __local int *destMemory, int numDestItems)
{
    int tid = get_global_id(0);
    for (int i = 0; i < numDestItems; i++) destMemory[i] = finalDest[i];
    barrier(CLK_LOCAL_MEM_FENCE);
    int oldValue, origValue, newValue;
    do {
        origValue = destMemory[0];
        newValue = origValue + tid + 2;
        oldValue = atomic_cmpxchg(&destMemory[0], origValue, newValue);
    } while (oldValue != origValue);
    oldValues[tid] = oldValue;
    barrier(CLK_LOCAL_MEM_FENCE);
    for (int i = 0; i < numDestItems; i++) finalDest[i] = destMemory[i];
}"""
p = build(src)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 256
for it in range(int(sys.argv[1]) if len(sys.argv) > 1 else 5):
    fd = buf(4, struct.pack("i", 1000)); ov = buf(4 * N)
    run(p, "k", [fd, ov, local(4), C.c_int(1)], N, N)
    got = struct.unpack("i", read(fd, 4))[0]; old = struct.unpack("%di" % N, read(ov, 4 * N))
    exp = 1000 + sum(t + 2 for t in range(N))
    # chain check: sort olds; each next = prev + tid(prev)+2
    nxt = {o: o + t + 2 for t, o in enumerate(old)}
    dup = N - len(set(old))
    print("final", got, "exp", exp, "dup olds", dup, "max(old->new)", max(nxt.values()))
