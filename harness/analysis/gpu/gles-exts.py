#!/usr/bin/env python3
"""Create a surfaceless EGL GLES3 context (no display) and dump version + extensions + key limits."""
import ctypes as C, sys
egl = C.CDLL("libEGL.so.1"); gl = C.CDLL("libGLESv2.so.2")
egl.eglGetProcAddress.restype = C.c_void_p
egl.eglGetPlatformDisplay.restype = C.c_void_p
egl.eglGetPlatformDisplay.argtypes = [C.c_uint, C.c_void_p, C.c_void_p]
EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
dpy = egl.eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, None, None)
ma, mi = C.c_int(), C.c_int(); assert egl.eglInitialize(C.c_void_p(dpy), C.byref(ma), C.byref(mi))
egl.eglBindAPI(0x30A0)  # EGL_OPENGL_ES_API
want = int(sys.argv[1]) if len(sys.argv) > 1 else 3
attrs = (C.c_int * 5)(0x3098, want, 0x30FB, int(sys.argv[2]) if len(sys.argv) > 2 else 0, 0x3038)  # MAJOR, MINOR
egl.eglCreateContext.restype = C.c_void_p
ctx = egl.eglCreateContext(C.c_void_p(dpy), None, None, attrs)
print("context ES %s.%s:" % (want, sys.argv[2] if len(sys.argv) > 2 else 0), "OK" if ctx else "FAILED err 0x%x" % egl.eglGetError())
if not ctx: sys.exit(1)
assert egl.eglMakeCurrent(C.c_void_p(dpy), None, None, C.c_void_p(ctx))
gl.glGetString.restype = C.c_char_p; gl.glGetStringi.restype = C.c_char_p
for n, e in [("VENDOR",0x1F00),("RENDERER",0x1F01),("VERSION",0x1F02),("GLSL",0x8B8C)]:
    print(n, gl.glGetString(e).decode())
n = C.c_int(); gl.glGetIntegerv(0x821D, C.byref(n))
exts = sorted(gl.glGetStringi(0x1F03, i).decode() for i in range(n.value))
print("NUM_EXTENSIONS", n.value)
for x in exts: print(" ", x)
