import sys; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
# out[i] = in[i] ^ 0x5a5a5a5a over large 1D grids: detect misplaced/unwritten items.
src = r"""__kernel void k(__global uint *o, __global const uint *in) { size_t i = get_global_id(0); o[i] = in[i] ^ 0x5a5a5a5au; }
__kernel void kg(__global uint *o) { size_t i = get_global_id(0); o[i] = (uint)i; }"""
p = build(src)
import array
for N, L in ((1 << 16, None), (1 << 20, None), (1 << 22, None), (1 << 24, None), (1 << 24, 256), (1 << 24, 64)):
    a = array.array("I", range(N))
    i = buf(4 * N, a.tobytes()); o = buf(4 * N, b"\xad\xde" * (2 * N))
    run(p, "k", [o, i], N, L)
    r = array.array("I"); r.frombytes(read(o, 4 * N))
    bad = [j for j in range(N) if r[j] != j ^ 0x5a5a5a5a]
    o2 = buf(4 * N, b"\xad\xde" * (2 * N)); run(p, "kg", [o2], N, L)
    r2 = array.array("I"); r2.frombytes(read(o2, 4 * N))
    bad2 = [j for j in range(N) if r2[j] != j]
    print(N, L, "bad", len(bad), [(j, hex(r[j] ^ 0x5a5a5a5a)) for j in bad[:4]], "gid-bad", len(bad2), [(j, hex(r2[j])) for j in bad2[:4]], flush=True)
