#!/usr/bin/env python3
"""host: clk.py-compatible ctypes OpenCL runner that talks to rusticl through its ICD dispatch table
(the shim build exports no cl* symbols; needs `. shim-env.sh`). Dispatch indices were resolved from the
table's function pointers against `nm` of libRusticlOpenCL (see impl-opencl-fixes.md).
On the panfrost drm-shim nothing executes on a GPU: kernels only compile/submit (PAN_MESA_DEBUG=trace dumps
the job chain + shader), but every CPU-side path (image upload, map/unmap, read/write, copies) really runs."""
import ctypes as C, struct, sys, os
vp, u32, u64, sz, i32 = C.c_void_p, C.c_uint32, C.c_uint64, C.c_size_t, C.c_int
lib = C.CDLL(os.environ.get("RUSTICL_LIB") or os.environ["OCL_ICD_FILENAMES"])
IDX = {"clGetDeviceIDs": 2, "clGetDeviceInfo": 3, "clCreateContext": 4, "clCreateCommandQueue": 9,
       "clCreateBuffer": 14, "clReleaseMemObject": 18, "clGetSupportedImageFormats": 19, "clGetMemObjectInfo": 20,
       "clGetImageInfo": 21, "clCreateSampler": 22, "clReleaseSampler": 24, "clReleaseProgram": 29,
       "clBuildProgram": 30, "clGetProgramBuildInfo": 33, "clCreateKernel": 34, "clReleaseKernel": 37,
       "clSetKernelArg": 38, "clWaitForEvents": 41, "clReleaseEvent": 44, "clFlush": 46, "clFinish": 47,
       "clEnqueueReadBuffer": 48, "clEnqueueWriteBuffer": 49, "clEnqueueCopyBuffer": 50, "clEnqueueReadImage": 51,
       "clEnqueueWriteImage": 52, "clEnqueueCopyImage": 53, "clEnqueueMapBuffer": 56, "clEnqueueMapImage": 57,
       "clEnqueueUnmapMemObject": 58, "clEnqueueNDRangeKernel": 59, "clCreateProgramWithSource": 26,
       "clCreateImage": 96, "clEnqueueFillBuffer": 102, "clEnqueueFillImage": 103}
PTR = {"clCreateContext", "clCreateCommandQueue", "clCreateBuffer", "clCreateProgramWithSource", "clCreateKernel",
       "clCreateImage", "clCreateSampler", "clEnqueueMapBuffer", "clEnqueueMapImage"}
_n = u32(); _plats = (vp * 8)()
assert lib.clIcdGetPlatformIDsKHR(8, _plats, C.byref(_n)) == 0 and _n.value > 0, "no platform"
plat = _plats[0]
_disp = C.cast(C.cast(plat, C.POINTER(vp))[0], C.POINTER(vp))

class _CL:
    def __getattr__(self, name):
        f = C.CFUNCTYPE(vp if name in PTR else i32)(_disp[IDX[name]])
        setattr(self, name, f); return f
cl = _CL()

err = i32()
dev = vp(); assert cl.clGetDeviceIDs(vp(plat), u64(0xFFFFFFFF), 1, C.byref(dev), None) == 0
ctx = vp(cl.clCreateContext(None, 1, C.byref(dev), None, None, C.byref(err))); assert err.value == 0, err.value
q = vp(cl.clCreateCommandQueue(ctx, dev, u64(0), C.byref(err))); assert err.value == 0, err.value

def devname():
    b = C.create_string_buffer(256); cl.clGetDeviceInfo(dev, 0x102B, sz(256), b, None); return b.value.decode()

def build(src, opts=b""):
    s = C.c_char_p(src.encode()); p = vp(cl.clCreateProgramWithSource(ctx, 1, C.byref(s), None, C.byref(err)))
    assert err.value == 0, err.value
    e = cl.clBuildProgram(p, 1, C.byref(dev), C.c_char_p(opts), None, None)
    if e != 0:
        logsz = sz(); cl.clGetProgramBuildInfo(p, dev, 0x1183, sz(0), None, C.byref(logsz))
        log = C.create_string_buffer(logsz.value); cl.clGetProgramBuildInfo(p, dev, 0x1183, logsz, log, None)
        raise RuntimeError("build err %d: %s" % (e, log.value.decode(errors="replace")))
    return p

def buf(nbytes, data=None, flags=1):
    b = vp(cl.clCreateBuffer(ctx, u64(flags | (0x20 if data is not None else 0)), sz(nbytes), data, C.byref(err)))
    assert err.value == 0, err.value; return b

class Fmt(C.Structure): _fields_ = [("order", u32), ("type", u32)]
class Desc(C.Structure):
    _fields_ = [("type", u32), ("w", sz), ("h", sz), ("d", sz), ("asz", sz), ("rp", sz), ("sp", sz),
                ("nml", u32), ("ns", u32), ("mem", vp)]
IMAGE2D, IMAGE3D, IMAGE2D_ARRAY, IMAGE1D, IMAGE1D_ARRAY, IMAGE1D_BUFFER = 0x10F1, 0x10F2, 0x10F3, 0x10F4, 0x10F5, 0x10F6
ORDER = {0x10B0: "R", 0x10B1: "A", 0x10B2: "RG", 0x10B3: "RA", 0x10B4: "RGB", 0x10B5: "RGBA", 0x10B6: "BGRA",
         0x10B7: "ARGB", 0x10B8: "INTENSITY", 0x10B9: "LUMINANCE", 0x10BD: "DEPTH", 0x10BF: "sRGB", 0x10C0: "sRGBx",
         0x10C1: "sRGBA", 0x10C2: "sBGRA", 0x10C3: "ABGR", 0x10BA: "Rx", 0x10BB: "RGx", 0x10BC: "RGBx"}
TYPE = {0x10D0: "SNORM_INT8", 0x10D1: "SNORM_INT16", 0x10D2: "UNORM_INT8", 0x10D3: "UNORM_INT16",
        0x10D4: "UNORM_SHORT_565", 0x10D5: "UNORM_SHORT_555", 0x10D6: "UNORM_INT_101010", 0x10D7: "SIGNED_INT8",
        0x10D8: "SIGNED_INT16", 0x10D9: "SIGNED_INT32", 0x10DA: "UNSIGNED_INT8", 0x10DB: "UNSIGNED_INT16",
        0x10DC: "UNSIGNED_INT32", 0x10DD: "HALF_FLOAT", 0x10DE: "FLOAT", 0x10E0: "UNORM_INT_101010_2", 0x10E5: "UNORM_INT_2_101010_EXT"}
NCH = {"R": 1, "A": 1, "RG": 2, "RA": 2, "RGB": 3, "RGBA": 4, "BGRA": 4, "ARGB": 4, "INTENSITY": 1, "LUMINANCE": 1,
       "DEPTH": 1, "sRGB": 3, "sRGBx": 4, "sRGBA": 4, "sBGRA": 4, "ABGR": 4, "Rx": 2, "RGx": 3, "RGBx": 4}
TSZ = {"SNORM_INT8": 1, "SNORM_INT16": 2, "UNORM_INT8": 1, "UNORM_INT16": 2, "UNORM_SHORT_565": 2,
       "UNORM_SHORT_555": 2, "UNORM_INT_101010": 4, "SIGNED_INT8": 1, "SIGNED_INT16": 2, "SIGNED_INT32": 4,
       "UNSIGNED_INT8": 1, "UNSIGNED_INT16": 2, "UNSIGNED_INT32": 4, "HALF_FLOAT": 2, "FLOAT": 4,
       "UNORM_INT_101010_2": 4, "UNORM_INT_2_101010_EXT": 4}
def fmtname(f): return "%s %s" % (ORDER.get(f.order, hex(f.order)), TYPE.get(f.type, hex(f.type)))
def pixsize(f):
    o, t = ORDER[f.order], TYPE[f.type]
    if t in ("UNORM_SHORT_565", "UNORM_SHORT_555", "UNORM_INT_101010", "UNORM_INT_101010_2", "UNORM_INT_2_101010_EXT"): return TSZ[t]
    return NCH[o] * TSZ[t]

def formats(itype, flags=1):
    n = u32(); assert cl.clGetSupportedImageFormats(ctx, u64(flags), u32(itype), u32(0), None, C.byref(n)) == 0
    arr = (Fmt * n.value)(); assert cl.clGetSupportedImageFormats(ctx, u64(flags), u32(itype), n, arr, None) == 0
    return list(arr)

def image(itype, fmt, w, h=0, d=0, asz=0, flags=1, host=None, rp=0, sp=0, mem=None):
    desc = Desc(itype, w, h, d, asz, rp, sp, 0, 0, mem)
    im = vp(cl.clCreateImage(ctx, u64(flags), C.byref(fmt), C.byref(desc), host, C.byref(err)))
    if err.value: raise RuntimeError("clCreateImage %d" % err.value)
    return im

def sampler(normalized=0, addr=0x1130, filt=0x1140):
    s = vp(cl.clCreateSampler(ctx, u32(normalized), u32(addr), u32(filt), C.byref(err))); assert err.value == 0; return s

def s3(a): return (sz * 3)(*(list(a) + [0] * (3 - len(a))))

def map_image(im, origin, region, flags=3):
    rp, sp = sz(), sz()
    p = vp(cl.clEnqueueMapImage(q, im, u32(1), u64(flags), s3(origin), s3(region), C.byref(rp), C.byref(sp),
                                u32(0), None, None, C.byref(err)))
    if err.value: raise RuntimeError("clEnqueueMapImage %d" % err.value)
    return p, rp.value, sp.value

def unmap(mem, p):
    assert cl.clEnqueueUnmapMemObject(q, mem, p, u32(0), None, None) == 0

def write_image(im, origin, region, data, rp=0, sp=0):
    assert cl.clEnqueueWriteImage(q, im, u32(1), s3(origin), s3(region), sz(rp), sz(sp), data, u32(0), None, None) == 0

def read_image(im, origin, region, nbytes, rp=0, sp=0):
    out = C.create_string_buffer(nbytes)
    assert cl.clEnqueueReadImage(q, im, u32(1), s3(origin), s3(region), sz(rp), sz(sp), out, u32(0), None, None) == 0
    return out.raw

def write(b, data, offset=0):
    assert cl.clEnqueueWriteBuffer(q, b, u32(1), sz(offset), sz(len(data)), data, u32(0), None, None) == 0

def read(b, nbytes, offset=0):
    out = C.create_string_buffer(nbytes)
    assert cl.clEnqueueReadBuffer(q, b, u32(1), sz(offset), sz(nbytes), out, u32(0), None, None) == 0
    return out.raw

class local:
    def __init__(s, n): s.n = n

def kernel(p, name):
    k = vp(cl.clCreateKernel(p, name.encode(), C.byref(err))); assert err.value == 0, (name, err.value); return k

def setargs(k, args):
    for i, a in enumerate(args):
        if isinstance(a, local): r = cl.clSetKernelArg(k, u32(i), sz(a.n), None)
        elif isinstance(a, vp): r = cl.clSetKernelArg(k, u32(i), sz(8), C.byref(a))
        else: r = cl.clSetKernelArg(k, u32(i), sz(C.sizeof(a)), C.byref(a))
        assert r == 0, (i, r)

def run(p, name, args, gsz, lsz=None, finish=True):
    k = kernel(p, name); setargs(k, args)
    gsz = gsz if isinstance(gsz, (list, tuple)) else [gsz]
    g = (sz * len(gsz))(*gsz); l = None
    if lsz: lsz = lsz if isinstance(lsz, (list, tuple)) else [lsz]; l = (sz * len(lsz))(*lsz)
    e = cl.clEnqueueNDRangeKernel(q, k, u32(len(gsz)), None, g, l, u32(0), None, None)
    if finish: cl.clFinish(q)
    return e

def finish(): return cl.clFinish(q)
def release(m): cl.clReleaseMemObject(m)
