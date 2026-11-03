#!/usr/bin/env python3
"""Display-less GLES 3.1 smoke test: surfaceless EGL, compute shader -> SSBO, FBO render + readback,
plus a timed fill-rate loop (rough GPU throughput with no connector)."""
import ctypes as C, struct, time
egl = C.CDLL("libEGL.so.1"); gl = C.CDLL("libGLESv2.so.2")
egl.eglGetPlatformDisplay.restype = C.c_void_p; egl.eglGetPlatformDisplay.argtypes = [C.c_uint, C.c_void_p, C.c_void_p]
dpy = C.c_void_p(egl.eglGetPlatformDisplay(0x31DD, None, None)); assert egl.eglInitialize(dpy, None, None)
egl.eglBindAPI(0x30A0); egl.eglCreateContext.restype = C.c_void_p
ctx = C.c_void_p(egl.eglCreateContext(dpy, None, None, (C.c_int * 5)(0x3098, 3, 0x30FB, 1, 0x3038)))
assert egl.eglMakeCurrent(dpy, None, None, ctx)
gl.glGetString.restype = C.c_char_p; gl.glCreateShader.restype = C.c_uint; gl.glCreateProgram.restype = C.c_uint
gl.glMapBufferRange.restype = C.c_void_p; gl.glMapBufferRange.argtypes = [C.c_uint, C.c_long, C.c_long, C.c_uint]
print(gl.glGetString(0x1F02).decode(), "|", gl.glGetString(0x1F01).decode())
def prog(*stages):
    p = gl.glCreateProgram()
    for typ, src in stages:
        s = gl.glCreateShader(typ); b = C.c_char_p(src.encode()); gl.glShaderSource(s, 1, C.byref(b), None); gl.glCompileShader(s)
        ok = C.c_int(); gl.glGetShaderiv(s, 0x8B81, C.byref(ok))
        if not ok.value:
            log = C.create_string_buffer(4096); gl.glGetShaderInfoLog(s, 4096, None, log); raise SystemExit("compile: " + log.value.decode())
        gl.glAttachShader(p, s)
    gl.glLinkProgram(p); ok = C.c_int(); gl.glGetProgramiv(p, 0x8B82, C.byref(ok)); assert ok.value; return p
res = {}
# compute: SSBO of 65536 uints, out[i] = i*i ^ 0x5a5a5a5a, 256 invocations/group
cp = prog((0x91B9, """#version 310 es
layout(local_size_x=256) in; layout(std430, binding=0) buffer B { uint v[]; };
void main(){ uint i=gl_GlobalInvocationID.x; v[i]=i*i ^ 0x5a5a5a5au; }"""))
N = 65536; bo = C.c_uint(); gl.glGenBuffers(1, C.byref(bo)); gl.glBindBuffer(0x90D2, bo)
gl.glBufferData(0x90D2, C.c_long(4 * N), None, 0x88EA); gl.glBindBufferBase(0x90D2, 0, bo)
gl.glUseProgram(cp); gl.glDispatchCompute(N // 256, 1, 1); gl.glMemoryBarrier(0x2000); gl.glFinish()
ptr = gl.glMapBufferRange(0x90D2, 0, 4 * N, 1); data = struct.unpack("%dI" % N, C.string_at(ptr, 4 * N)); gl.glUnmapBuffer(0x90D2)
res["compute shader SSBO 64k"] = "PASS" if all(data[i] == ((i * i) & 0xffffffff) ^ 0x5a5a5a5a for i in range(N)) else "FAIL"
# render: full-screen gradient into 1920x1080 RGBA8 FBO, read back
W, H = 1920, 1080
tex = C.c_uint(); gl.glGenTextures(1, C.byref(tex)); gl.glBindTexture(0x0DE1, tex); gl.glTexStorage2D(0x0DE1, 1, 0x8058, W, H)
fb = C.c_uint(); gl.glGenFramebuffers(1, C.byref(fb)); gl.glBindFramebuffer(0x8D40, fb); gl.glFramebufferTexture2D(0x8D40, 0x8CE0, 0x0DE1, tex, 0)
res["FBO complete"] = "PASS" if gl.glCheckFramebufferStatus(0x8D40) == 0x8CD5 else "FAIL"
rp = prog((0x8B31, """#version 310 es
void main(){ vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2)); gl_Position=vec4(p*2.0-1.0,0.0,1.0);}"""),
          (0x8B30, """#version 310 es
precision highp float; uniform float t; out vec4 c;
void main(){ c=vec4(floor(gl_FragCoord.x)/1919.0, floor(gl_FragCoord.y)/1079.0, fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233))+t)*43758.5453), 1.0);}"""))
vao = C.c_uint(); gl.glGenVertexArrays(1, C.byref(vao)); gl.glBindVertexArray(vao)
gl.glUseProgram(rp); gl.glViewport(0, 0, W, H); gl.glDrawArrays(4, 0, 3); gl.glFinish()
px = C.create_string_buffer(W * H * 4); gl.glReadPixels(0, 0, W, H, 0x1908, 0x1401, px)
raw = px.raw; ok = all(abs(raw[(y * W + x) * 4] - round(x / 1919 * 255)) <= 1 and abs(raw[(y * W + x) * 4 + 1] - round(y / 1079 * 255)) <= 1
                     for y in range(0, H, 37) for x in range(0, W, 41))
res["render 1080p FBO + readback gradient"] = "PASS" if ok else "FAIL"
# throughput: separate render passes (glFlush per frame defeats forward-pixel-kill merging of overdraw)
cprog = prog((0x8B31, """#version 310 es
void main(){ vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2)); gl_Position=vec4(p*2.0-1.0,0.0,1.0);}"""),
             (0x8B30, """#version 310 es
precision mediump float; uniform vec4 col; out vec4 c; void main(){ c=col; }"""))
for name, p, u in [("noise shader", rp, b"t"), ("flat colour", cprog, b"col")]:
    gl.glUseProgram(p); loc = gl.glGetUniformLocation(p, u); gl.glFinish(); t0 = time.time()
    for f in range(200):
        if u == b"t": gl.glUniform1f(loc, C.c_float(f))
        else: gl.glUniform4f(loc, C.c_float((f & 7) / 7), C.c_float(0.5), C.c_float(0.25), C.c_float(1.0))
        gl.glDrawArrays(4, 0, 3); gl.glFlush()
    gl.glFinish(); dt = time.time() - t0
    mhz = int(open("/sys/class/devfreq/1800000.gpu/cur_freq").read()) / 1e6
    res["%s: 200 x 1080p passes %.1f fps, %.0f Mpix/s, %.2f pix/clk @%d MHz" % (name, 200 / dt, 200 * W * H / dt / 1e6, 200 * W * H / dt / (mhz * 1e6), mhz)] = "INFO"
gl.glFinish(); err = gl.glGetError(); res["glGetError"] = "PASS" if err == 0 else "0x%x" % err
for k, v in res.items(): print("%-58s %s" % (k, v))
