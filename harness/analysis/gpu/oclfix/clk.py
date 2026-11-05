#!/usr/bin/env python3
"""Tiny ctypes OpenCL kernel runner for repro tests on the board.
from clk import *; p = build(src); run(p, "k", [buf_arg, local(nbytes), scalar(...)], gsz, lsz); read(buf, n)"""
import ctypes as C, struct, sys
cl = C.CDLL("libOpenCL.so.1")
vp, u32, u64, sz = C.c_void_p, C.c_uint32, C.c_uint64, C.c_size_t
for f in ("clCreateContext", "clCreateCommandQueueWithProperties", "clCreateProgramWithSource", "clCreateKernel", "clCreateBuffer"):
    getattr(cl, f).restype = vp
n = u32(); plats = (vp * 8)(); cl.clGetPlatformIDs(8, plats, C.byref(n))
dev = vp(); assert cl.clGetDeviceIDs(vp(plats[0]), u64(0xFFFFFFFF), 1, C.byref(dev), None) == 0
err = C.c_int()
ctx = vp(cl.clCreateContext(None, 1, C.byref(dev), None, None, C.byref(err))); assert err.value == 0, err.value
q = vp(cl.clCreateCommandQueueWithProperties(ctx, dev, None, C.byref(err))); assert err.value == 0
def build(src, opts=b""):
    s = C.c_char_p(src.encode()); p = vp(cl.clCreateProgramWithSource(ctx, 1, C.byref(s), None, C.byref(err)))
    e = cl.clBuildProgram(p, 1, C.byref(dev), C.c_char_p(opts), None, None)
    if e != 0:
        logsz = sz(); cl.clGetProgramBuildInfo(p, dev, 0x1183, 0, None, C.byref(logsz))
        log = C.create_string_buffer(logsz.value); cl.clGetProgramBuildInfo(p, dev, 0x1183, logsz, log, None)
        raise RuntimeError("build err %d: %s" % (e, log.value.decode(errors="replace")))
    return p
def buf(nbytes, data=None):
    b = vp(cl.clCreateBuffer(ctx, u64(1 | (0x20 if data else 0)), sz(nbytes), data, C.byref(err))); assert err.value == 0; return b
class local:
    def __init__(s, n): s.n = n
def run(p, name, args, gsz, lsz=None):
    k = vp(cl.clCreateKernel(p, name.encode(), C.byref(err))); assert err.value == 0, (name, err.value)
    for i, a in enumerate(args):
        if isinstance(a, local): r = cl.clSetKernelArg(k, i, sz(a.n), None)
        elif isinstance(a, vp): r = cl.clSetKernelArg(k, i, sz(8), C.byref(a))
        else: r = cl.clSetKernelArg(k, i, sz(C.sizeof(a)), C.byref(a))
        assert r == 0, (i, r)
    gsz = gsz if isinstance(gsz, (list, tuple)) else [gsz]
    g = (sz * len(gsz))(*gsz); l = None
    if lsz: lsz = lsz if isinstance(lsz, (list, tuple)) else [lsz]; l = (sz * len(lsz))(*lsz)
    e = cl.clEnqueueNDRangeKernel(q, k, len(gsz), None, g, l, 0, None, None); cl.clFinish(q); return e
def read(b, nbytes):
    out = C.create_string_buffer(nbytes); assert cl.clEnqueueReadBuffer(q, b, 1, sz(0), sz(nbytes), out, 0, None, None) == 0; return out.raw
