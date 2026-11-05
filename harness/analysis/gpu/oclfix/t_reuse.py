import sys, array; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
# CTS math pattern: reuse in/out buffers, prefill out with 0xdead via WriteBuffer, run, read. Look for stale elements.
src = r"""__kernel void k(__global uint *o, __global const uint *in, uint c) { size_t i = get_global_id(0); o[i] = in[i] ^ c; }"""
p = build(src)
N = int(sys.argv[1]) if len(sys.argv) > 1 else (1 << 22)
i = buf(4 * N); o = buf(4 * N)
fill = b"\xad\xde" * (2 * N)
def wr(b, data): assert cl.clEnqueueWriteBuffer(q, b, 1, sz(0), sz(len(data)), data, 0, None, None) == 0
tot = 0
for it in range(12):
    a = array.array("I", ((j * 2654435761 + it) & 0xffffffff for j in range(N)))
    wr(i, a.tobytes()); wr(o, fill)
    c = 0x1000 * it + 7
    run(p, "k", [o, i, C.c_uint(c)], N)
    r = array.array("I"); r.frombytes(read(o, 4 * N))
    bad = [j for j in range(N) if r[j] != a[j] ^ c]
    tot += len(bad)
    print("iter", it, "bad", len(bad), [(j, hex(r[j]), hex(a[j] ^ c)) for j in bad[:4]], flush=True)
print("total bad", tot)
