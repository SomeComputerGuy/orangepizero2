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
V = {
 "allstore": "destMemory[0] = finalDest[0];",
 "loopinit": "for (int i = 0; i < n; i++) destMemory[i] = finalDest[i];",
 "loopinit_t0": "if (get_local_id(0) == 0) for (int i = 0; i < n; i++) destMemory[i] = finalDest[i];",
}
src = ""
for k, init in V.items():
    src += "__kernel void %s(__global int *finalDest, __global int *oldValues, volatile __local int *destMemory, int n)\n{ int tid = get_global_id(0);\n%s\nbarrier(CLK_LOCAL_MEM_FENCE);\n%s\nbarrier(CLK_LOCAL_MEM_FENCE);\nif (get_local_id(0)==0) finalDest[0] = destMemory[0];}\n" % (k, init, body)
p = build(src)
for name in V:
    for N in (4, 8, 64):
        fd = buf(4, struct.pack("i", 1000)); ov = buf(4 * N, b"\xff" * (4 * N))
        run(p, name, [fd, ov, local(4), C.c_int(1)], N, N)
        got = struct.unpack("i", read(fd, 4))[0]; old = struct.unpack("%di" % N, read(ov, 4 * N))
        print(name, N, "final", got, "exp", 1000 + sum(t + 2 for t in range(N)), old[:8])
