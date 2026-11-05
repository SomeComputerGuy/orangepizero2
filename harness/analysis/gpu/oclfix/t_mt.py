import sys, threading, array; sys.path.insert(0, "/root/opiz2-mesa")
from clk import *
# CTS math pattern: T threads, each its own queue + kernel, out = sub-buffer of one parent (or own buffer),
# FillBuffer(0xdead) -> kernel -> MapBuffer(read) -> verify.
cl.clCreateSubBuffer.restype = vp; cl.clEnqueueMapBuffer.restype = vp
src = r"""__kernel void k(__global uint *o, __global const uint *in, uint c) { size_t i = get_global_id(0); o[i] = in[i] ^ c; }"""
p = build(src)
T = 4; NE = 1 << 18; BS = 4 * NE; ITERS = 24
mode = sys.argv[1] if len(sys.argv) > 1 else "sub"
class Reg(C.Structure): _fields_ = [("origin", sz), ("size", sz)]
inp = buf(BS * T, array.array("I", (j * 2654435761 & 0xffffffff for j in range(NE * T))).tobytes())
parent = buf(BS * T)
res = [0] * T; first = [None] * T
def worker(t):
    e = C.c_int()
    qq = vp(cl.clCreateCommandQueueWithProperties(ctx, dev, None, C.byref(e))); assert e.value == 0
    k = vp(cl.clCreateKernel(p, b"k", C.byref(e))); assert e.value == 0
    if mode in ("sub", "cts"):
        r = Reg(t * BS, BS); o = vp(cl.clCreateSubBuffer(parent, u64(1), 0x1220, C.byref(r), C.byref(e))); assert e.value == 0
    else:
        o = vp(cl.clCreateBuffer(ctx, u64(1), sz(BS), None, C.byref(e)))
    r2 = Reg(t * BS, BS); i = vp(cl.clCreateSubBuffer(inp, u64(4), 0x1220, C.byref(r2), C.byref(e))); assert e.value == 0
    pat = u32(0xffffdead)
    for it in range(ITERS):
        c = (t << 16) | it
        if mode == "cts":
            # new input every iteration, written into this thread's slice of the shared input parent
            cur = array.array("I", ((j * 2654435761 + it * 7919 + t) & 0xffffffff for j in range(NE)))
            hin = C.create_string_buffer(cur.tobytes(), BS)
            assert cl.clEnqueueWriteBuffer(qq, i, 0, sz(0), sz(BS), hin, 0, None, None) == 0
        if mode == "write":
            hb = C.create_string_buffer(b"\xad\xde\xff\xff" * NE, BS)
            assert cl.clEnqueueWriteBuffer(qq, o, 0, sz(0), sz(BS), hb, 0, None, None) == 0
        else:
            assert cl.clEnqueueFillBuffer(qq, o, C.byref(pat), sz(4), sz(0), sz(BS), 0, None, None) == 0
        cl.clSetKernelArg(k, 0, sz(8), C.byref(o)); cl.clSetKernelArg(k, 1, sz(8), C.byref(i)); cc = u32(c); cl.clSetKernelArg(k, 2, sz(4), C.byref(cc))
        assert cl.clEnqueueNDRangeKernel(qq, k, 1, None, C.byref(sz(NE)), None, 0, None, None) == 0
        cl.clFlush(qq)
        m = cl.clEnqueueMapBuffer(qq, o, 1, u64(1), sz(0), sz(BS), 0, None, None, C.byref(e)); assert e.value == 0 and m
        got = array.array("I"); got.frombytes(C.string_at(m, BS))
        cl.clEnqueueUnmapMemObject(qq, o, vp(m), 0, None, None); cl.clFinish(qq)
        exp_in = cur if mode == "cts" else inbytes[t * NE:(t + 1) * NE]
        bad = [j for j in range(NE) if got[j] != exp_in[j] ^ c]
        res[t] += len(bad)
        if bad and first[t] is None: first[t] = (it, bad[0], len(bad), hex(got[bad[0]]), hex(exp_in[bad[0]] ^ c))
inbytes = array.array("I"); inbytes.frombytes(read(inp, BS * T))
ths = [threading.Thread(target=worker, args=(t,)) for t in range(T)]
[x.start() for x in ths]; [x.join() for x in ths]
print("mode", mode, "bad per thread", res, "first", first, flush=True)
