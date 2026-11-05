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
 "fin_loop_all": "for (int i = 0; i < n; i++) finalDest[i] = destMemory[i];",
 "fin_store_all": "finalDest[0] = destMemory[0];",
 "fin_loop_t0": "if (get_local_id(0)==0) for (int i = 0; i < n; i++) finalDest[i] = destMemory[i];",
 "fin_loop_nobar": "NOBAR",
}
src = ""
for k, fin in V.items():
    bar = "barrier(CLK_LOCAL_MEM_FENCE);"
    if fin == "NOBAR": bar = ""; fin = "for (int i = 0; i < n; i++) finalDest[i+1] = destMemory[i];"
    src += "__kernel void %s(__global int *finalDest, __global int *oldValues, volatile __local int *destMemory, int n)\n{ int tid = get_global_id(0);\nif (get_local_id(0)==0) destMemory[0] = finalDest[0];\nbarrier(CLK_LOCAL_MEM_FENCE);\n%s\n%s\n%s}\n" % (k, body, bar, fin)
p = build(src)
for name in V:
    for N in (4, 64):
        fd = buf(8, struct.pack("2i", 1000, 0)); ov = buf(4 * N, b"\xff" * (4 * N))
        run(p, name, [fd, ov, local(4), C.c_int(1)], N, N)
        got = struct.unpack("i", read(fd, 4))[0]; old = struct.unpack("%di" % N, read(ov, 4 * N))
        print(name, N, "final", got, "exp", 1000 + sum(t + 2 for t in range(N)), old[:8])
