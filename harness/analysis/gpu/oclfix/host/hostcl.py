#!/usr/bin/env python3
"""host: compile+launch an OpenCL kernel on rusticl/panfrost under the drm-shim (no execution), calling
rusticl through its ICD dispatch table (no ICD loader needed).
usage: hostcl.py <file.cl> <kernel> [nargs=3] [build-opts] ; the shader dump goes to stderr (BIFROST_MESA_DEBUG)"""
import ctypes as C, sys, os
lib = C.CDLL(os.environ.get("RUSTICL_LIB") or os.environ["OCL_ICD_FILENAMES"])
vp, u32, u64, sz, i32 = C.c_void_p, C.c_uint32, C.c_uint64, C.c_size_t, C.c_int
n = u32(); plats = (vp * 8)()
assert lib.clIcdGetPlatformIDsKHR(8, plats, C.byref(n)) == 0 and n.value > 0, "no platform"
plat = plats[0]
disp = C.cast(C.cast(plat, C.POINTER(vp))[0], C.POINTER(vp))  # cl_icd_dispatch table
IDX = {"clGetDeviceIDs": 2, "clGetDeviceInfo": 3, "clCreateContext": 4, "clCreateCommandQueue": 9, "clCreateBuffer": 14,
       "clCreateProgramWithSource": 26, "clBuildProgram": 30, "clGetProgramBuildInfo": 33, "clCreateKernel": 34,
       "clSetKernelArg": 38, "clFinish": 47, "clEnqueueNDRangeKernel": 59}
PTR = {"clCreateContext", "clCreateCommandQueue", "clCreateBuffer", "clCreateProgramWithSource", "clCreateKernel"}
def fn(name):
    proto = C.CFUNCTYPE(vp if name in PTR else i32)
    f = proto(disp[IDX[name]])
    return f
err = i32()
dev = vp(); assert fn("clGetDeviceIDs")(vp(plat), u64(0xFFFFFFFF), 1, C.byref(dev), None) == 0
name = C.create_string_buffer(256); fn("clGetDeviceInfo")(dev, 0x102B, sz(256), name, None); print("device:", name.value.decode(), file=sys.stderr)
ctx = vp(fn("clCreateContext")(None, 1, C.byref(dev), None, None, C.byref(err))); assert err.value == 0, err.value
q = vp(fn("clCreateCommandQueue")(ctx, dev, u64(0), C.byref(err))); assert err.value == 0, err.value
src = open(sys.argv[1]).read(); s = C.c_char_p(src.encode())
p = vp(fn("clCreateProgramWithSource")(ctx, 1, C.byref(s), None, C.byref(err))); assert err.value == 0
opts = sys.argv[4].encode() if len(sys.argv) > 4 else b""
e = fn("clBuildProgram")(p, 1, C.byref(dev), C.c_char_p(opts), None, None)
if e != 0:
    logsz = sz(); fn("clGetProgramBuildInfo")(p, dev, 0x1183, sz(0), None, C.byref(logsz))
    log = C.create_string_buffer(logsz.value); fn("clGetProgramBuildInfo")(p, dev, 0x1183, logsz, log, None)
    raise SystemExit("build err %d: %s" % (e, log.value.decode(errors="replace")))
k = vp(fn("clCreateKernel")(p, sys.argv[2].encode(), C.byref(err))); assert err.value == 0, err.value
nargs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
bufs = []
for i in range(nargs):
    b = vp(fn("clCreateBuffer")(ctx, u64(1), sz(1 << 20), None, C.byref(err))); assert err.value == 0; bufs.append(b)
    assert fn("clSetKernelArg")(k, u32(i), sz(8), C.byref(b)) == 0
g = (sz * 1)(256); l = (sz * 1)(64)
e = fn("clEnqueueNDRangeKernel")(q, k, u32(1), None, g, l, u32(0), None, None); print("enqueue:", e, file=sys.stderr)
if os.environ.get("HOSTCL_FINISH"): fn("clFinish")(q)
print("done", file=sys.stderr)
