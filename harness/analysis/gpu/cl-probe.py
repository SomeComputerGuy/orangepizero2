#!/usr/bin/env python3
"""OpenCL functional + OpenCL 2.0 feature probe via ctypes (no headers/compiler needed on the board).
Runs a few correctness kernels, then tries each CL 2.0 feature and reports PASS/UNSUPPORTED."""
import ctypes as C, struct, sys, random, math
cl = C.CDLL("libOpenCL.so.1")
vp, u32, u64, sz = C.c_void_p, C.c_uint32, C.c_uint64, C.c_size_t
cl.clCreateContext.restype = vp; cl.clCreateCommandQueueWithProperties.restype = vp
cl.clCreateProgramWithSource.restype = vp; cl.clCreateKernel.restype = vp; cl.clCreateBuffer.restype = vp
cl.clSVMAlloc.restype = vp; cl.clSVMAlloc.argtypes = [vp, u64, u32, u32]
n = u32(); plats = (vp * 8)(); cl.clGetPlatformIDs(8, plats, C.byref(n))
dev = vp(); assert cl.clGetDeviceIDs(vp(plats[0]), u64(0xFFFFFFFF), 1, C.byref(dev), None) == 0
err = C.c_int()
ctx = vp(cl.clCreateContext(None, 1, C.byref(dev), None, None, C.byref(err))); assert err.value == 0, err.value
q = vp(cl.clCreateCommandQueueWithProperties(ctx, dev, None, C.byref(err))); assert err.value == 0
res = {}
def build(src, opts=b""):
    s = C.c_char_p(src.encode()); p = vp(cl.clCreateProgramWithSource(ctx, 1, C.byref(s), None, C.byref(err)))
    e = cl.clBuildProgram(p, 1, C.byref(dev), C.c_char_p(opts), None, None)
    if e != 0:
        logsz = sz(); cl.clGetProgramBuildInfo(p, dev, 0x1183, 0, None, C.byref(logsz))
        log = C.create_string_buffer(logsz.value); cl.clGetProgramBuildInfo(p, dev, 0x1183, logsz, log, None)
        return None, "build err %d: %s" % (e, log.value.decode(errors="replace").strip().splitlines()[:2])
    return p, None
def buf(nbytes, data=None):
    b = vp(cl.clCreateBuffer(ctx, u64(1 | (0x20 if data else 0)), sz(nbytes), data, C.byref(err))); assert err.value == 0; return b
def run(p, name, args, gsz, lsz=None):
    k = vp(cl.clCreateKernel(p, name.encode(), C.byref(err))); assert err.value == 0, (name, err.value)
    for i, (s, a) in enumerate(args): assert cl.clSetKernelArg(k, i, sz(s), C.byref(a) if a is not None else None) == 0
    g = (sz * 1)(gsz); l = (sz * 1)(lsz) if lsz else None
    e = cl.clEnqueueNDRangeKernel(q, k, 1, None, g, l, 0, None, None); cl.clFinish(q); return e
def read(b, nbytes):
    out = C.create_string_buffer(nbytes); assert cl.clEnqueueReadBuffer(q, b, 1, sz(0), sz(nbytes), out, 0, None, None) == 0; return out.raw
N = 1 << 20
# 1. vector FMA, float
A = [random.random() for _ in range(N)]; B = [random.random() for _ in range(N)]
ba = buf(4*N, struct.pack("%df" % N, *A)); bb = buf(4*N, struct.pack("%df" % N, *B)); bo = buf(4*N)
p, e = build("__kernel void f(__global const float*a,__global const float*b,__global float*o){size_t i=get_global_id(0);o[i]=fma(a[i],b[i],a[i]);}")
run(p, "f", [(8, ba), (8, bb), (8, bo)], N, 256)
o = struct.unpack("%df" % N, read(bo, 4*N)); bad = sum(1 for i in range(N) if abs(o[i] - (A[i]*B[i]+A[i])) > 1e-5)
res["vector fma 1M floats"] = "PASS" if bad == 0 else "FAIL %d" % bad
# 2. local memory reduction + barrier + global atomics
p, e = build("""__kernel void r(__global const uint*a,__global uint*s){__local uint t[256];uint l=get_local_id(0);
t[l]=a[get_global_id(0)];barrier(CLK_LOCAL_MEM_FENCE);for(uint k=128;k>0;k>>=1){if(l<k)t[l]+=t[l+k];barrier(CLK_LOCAL_MEM_FENCE);}
if(l==0)atomic_add(s,t[0]);}""")
U = [random.randrange(1000) for _ in range(N)]; bu = buf(4*N, struct.pack("%dI" % N, *U)); bs = buf(4, struct.pack("I", 0))
run(p, "r", [(8, bu), (8, bs)], N, 256); got = struct.unpack("I", read(bs, 4))[0]
res["local reduction + barrier + global atomic_add"] = "PASS" if got == sum(U) & 0xffffffff else "FAIL %d != %d" % (got, sum(U))
# 3. fp16 + int64
p, e = build("""#pragma OPENCL EXTENSION cl_khr_fp16 : enable
__kernel void h(__global float*o,__global ulong*u){size_t i=get_global_id(0);half x=(half)(i&255);o[i]=(float)(x*(half)0.5f);u[i]=((ulong)i<<33)|i;}""")
bo2 = buf(4*4096); bu2 = buf(8*4096); run(p, "h", [(8, bo2), (8, bu2)], 4096, 64)
o = struct.unpack("4096f", read(bo2, 16384)); uu = struct.unpack("4096Q", read(bu2, 32768))
res["fp16 arithmetic + 64-bit integers"] = "PASS" if all(o[i] == (i & 255) * 0.5 and uu[i] == (i << 33) | i for i in range(4096)) else "FAIL"
# 4. math builtins: build each alone (libclc linkage) then accuracy vs python
X = list(struct.unpack("65536f", struct.pack("65536f", *[random.uniform(0.01, 10) for _ in range(65536)])))  # refs from the exact f32 inputs
bx = buf(4*65536, struct.pack("65536f", *X)); by = buf(4*65536)
for fn, ref in [("sqrt", math.sqrt), ("sin", math.sin), ("cos", math.cos), ("exp", math.exp), ("log", math.log),
                ("native_sin", math.sin), ("half_exp", math.exp), ("pow", lambda v: v ** 1.5), ("atan", math.atan), ("tanh", math.tanh)]:
    arg = "v,1.5f" if fn == "pow" else "v"
    p, e = build("__kernel void m(__global const float*x,__global float*y){size_t i=get_global_id(0);float v=x[i];y[i]=%s(%s);}" % (fn, arg))
    if not p: res["builtin %s" % fn] = "FAIL (" + e + ")"; continue
    run(p, "m", [(8, bx), (8, by)], 65536, 64); Y = struct.unpack("65536f", read(by, 4*65536))
    ulp32 = lambda r: 2.0 ** (math.frexp(r)[1] - 24) if r != 0 else 2.0 ** -149
    worst = max(abs(Y[i] - ref(v)) / ulp32(ref(v)) for i, v in enumerate(X))
    # OpenCL 1.2 full-profile ULP limits (sec 7.4): sqrt 3, sin/cos/exp/log 4/4/3/3, pow 16, atan 5, tanh 5
    lim = {"sqrt": 3, "sin": 4, "cos": 4, "exp": 3, "log": 3, "pow": 16, "atan": 5, "tanh": 5, "half_exp": 8192}.get(fn)
    res["builtin %s (max %.1f ulp%s)" % (fn, worst, "" if lim else ", impl-defined")] = ("PASS" if worst <= lim else "FAIL") if lim else "INFO"
# --- OpenCL 2.0 features ---
p, e = build("__kernel void g(__global int*a){int*p=a;p[get_global_id(0)]=1;}", b"-cl-std=CL2.0")
res["CL2.0: -cl-std=CL2.0 + generic address space"] = "PASS" if p else "UNSUPPORTED (" + e + ")"
p, e = build("__kernel void g(__global int*a){int*p=a;p[get_global_id(0)]=1;}", b"-cl-std=CL3.0")
res["CL3.0: generic pointer under -cl-std=CL3.0"] = "PASS" if p else "UNSUPPORTED (" + e + ")"
p, e = build("__global int gv=42;__kernel void g(__global int*a){a[0]=gv++;}", b"-cl-std=CL3.0")
res["CL2.0: program-scope global variables"] = "PASS" if p else "UNSUPPORTED (" + e + ")"
p, e = build("__kernel void g(__write_only pipe int pp){int v=1;write_pipe(pp,&v);}", b"-cl-std=CL3.0")
res["CL2.0: pipes"] = "PASS" if p else "UNSUPPORTED (" + e + ")"
p, e = build("__kernel void g(__global int*a){queue_t qq=get_default_queue();}", b"-cl-std=CL3.0")
res["CL2.0: device-side enqueue"] = "PASS" if p else "UNSUPPORTED (" + e + ")"
p, e = build("__kernel void g(__global int*a){a[get_global_id(0)]=work_group_reduce_add(a[get_global_id(0)]);}", b"-cl-std=CL3.0")
res["CL2.0: work-group collective functions"] = "PASS" if p else "UNSUPPORTED (" + e + ")"
p, e = build("__kernel void g(__global atomic_int*a){atomic_fetch_add_explicit(a,1,memory_order_seq_cst,memory_scope_device);}", b"-cl-std=CL3.0")
res["CL2.0: C11 atomics seq_cst/device scope"] = "PASS" if p else "UNSUPPORTED (" + e + ")"
s = cl.clSVMAlloc(ctx, 1, 4096, 0)
res["CL2.0: clSVMAlloc coarse-grain SVM"] = "PASS" if s else "UNSUPPORTED (clSVMAlloc returned NULL)"
p, e = build("__kernel void f(__global int*a){a[get_global_id(0)]=get_local_size(0);}")
bn = buf(4*1000); e2 = run(p, "f", [(8, bn)], 1000, 64)
res["CL2.0: non-uniform work-groups (1000 items, local 64)"] = "PASS" if e2 == 0 else "UNSUPPORTED (enqueue err %d)" % e2
for k, v in res.items(): print("%-60s %s" % (k, v))
