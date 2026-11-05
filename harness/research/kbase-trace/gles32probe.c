// SPDX-License-Identifier: MIT
/* GLES 3.2 GS/tessellation probe for the Arm libmali blob (GBM platform, surfaceless context).
 * Usage: gles32probe <outdir> [test-name ...]   (no test names = all tests)
 * Writes <outdir>/info.txt, <outdir>/<test>.rgba (64x64 RGBA8 readback), <outdir>/<test>.progbin
 * (glGetProgramBinary). Calls kbtrace_marker() around each test when kbtrace.so is preloaded. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl32.h>
#include <gbm.h>

#define W 64
#define H 64
static const char *od;
static FILE *info;
static void (*marker)(const char *);
static void mark(const char *s) { if (marker) marker(s); }

static GLuint sh(GLenum t, const char *src)
{
	GLuint s = glCreateShader(t);
	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) { char l[4096]; glGetShaderInfoLog(s, sizeof l, NULL, l); fprintf(stderr, "compile 0x%x: %s\n", t, l); }
	return s;
}

static GLuint prog(const char *vs, const char *tcs, const char *tes, const char *gs, const char *fs,
		   const char **xfb, int nxfb)
{
	GLuint p = glCreateProgram();
	glProgramParameteri(p, GL_PROGRAM_BINARY_RETRIEVABLE_HINT, GL_TRUE);
	glAttachShader(p, sh(GL_VERTEX_SHADER, vs));
	if (tcs) glAttachShader(p, sh(GL_TESS_CONTROL_SHADER, tcs));
	if (tes) glAttachShader(p, sh(GL_TESS_EVALUATION_SHADER, tes));
	if (gs) glAttachShader(p, sh(GL_GEOMETRY_SHADER, gs));
	if (fs) glAttachShader(p, sh(GL_FRAGMENT_SHADER, fs));
	if (nxfb) glTransformFeedbackVaryings(p, nxfb, xfb, GL_INTERLEAVED_ATTRIBS);
	glLinkProgram(p);
	GLint ok; glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok) { char l[4096]; glGetProgramInfoLog(p, sizeof l, NULL, l); fprintf(stderr, "link: %s\n", l); return 0; }
	return p;
}

static void save_bin(const char *name, GLuint p)
{
	GLint len = 0; glGetProgramiv(p, GL_PROGRAM_BINARY_LENGTH, &len);
	if (len <= 0) return;
	void *b = malloc(len); GLenum fmt; GLsizei got;
	glGetProgramBinary(p, len, &got, &fmt, b);
	char fn[512]; snprintf(fn, sizeof fn, "%s/%s.progbin", od, name);
	FILE *f = fopen(fn, "wb"); fwrite(b, 1, got, f); fclose(f);
	fprintf(info, "%s: program binary %d bytes, format 0x%x\n", name, got, fmt);
	free(b);
}

static void readback(const char *name)
{
	static unsigned char px[W * H * 4];
	glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
	unsigned sum = 0, lit = 0;
	for (int i = 0; i < W * H; i++) { sum = sum * 31 + px[4*i] + (px[4*i+1] << 8) + (px[4*i+2] << 16); lit += px[4*i] | px[4*i+1] | px[4*i+2] ? 1 : 0; }
	char fn[512]; snprintf(fn, sizeof fn, "%s/%s.rgba", od, name);
	FILE *f = fopen(fn, "wb"); fwrite(px, 1, sizeof px, f); fclose(f);
	fprintf(info, "%s: lit pixels %u/%u, hash %08x, px(16,16)=%02x%02x%02x px(48,40)=%02x%02x%02x, glError 0x%x\n",
		name, lit, W * H, sum, px[4*(16*W+16)], px[4*(16*W+16)+1], px[4*(16*W+16)+2],
		px[4*(40*W+48)], px[4*(40*W+48)+1], px[4*(40*W+48)+2], glGetError());
	fflush(info);
}

#define V "#version 320 es\n"
static const char *vs_tri = V "precision highp float;\nconst vec2 p[3] = vec2[](vec2(-0.8,-0.8), vec2(0.8,-0.8), vec2(0.0,0.8));\n"
	"out vec3 vcol;\nvoid main() { gl_Position = vec4(p[gl_VertexID % 3], 0.0, 1.0); vcol = vec3(gl_VertexID == 0, gl_VertexID == 1, gl_VertexID == 2); }\n";
static const char *fs_col = V "precision mediump float;\nin vec3 fcol;\nout vec4 o;\nvoid main() { o = vec4(fcol, 1.0); }\n";
static const char *fs_vcol = V "precision mediump float;\nin vec3 vcol;\nout vec4 o;\nvoid main() { o = vec4(vcol, 1.0); }\n";
static const char *gs_pass = V "layout(triangles) in;\nlayout(triangle_strip, max_vertices = 3) out;\nin vec3 vcol[];\nout vec3 fcol;\n"
	"void main() { for (int i = 0; i < 3; i++) { gl_Position = gl_in[i].gl_Position * vec4(0.9, 0.9, 1.0, 1.0); fcol = vcol[i].zxy; EmitVertex(); } EndPrimitive(); }\n";
static const char *vs_pts = V "precision highp float;\nout vec3 vcol;\nvoid main() { float x = -0.6 + 0.4 * float(gl_VertexID); gl_Position = vec4(x, x * 0.5, 0.0, 1.0); vcol = vec3(1.0, 0.5, 0.25); }\n";
static const char *gs_amp = V "layout(points) in;\nlayout(triangle_strip, max_vertices = 4) out;\nin vec3 vcol[];\nout vec3 fcol;\n"
	"void main() { vec4 c = gl_in[0].gl_Position; float s = 0.15;\n"
	" for (int i = 0; i < 4; i++) { gl_Position = c + vec4((i & 1) == 0 ? -s : s, (i & 2) == 0 ? -s : s, 0.0, 0.0);\n"
	"  fcol = vcol[0] * float(gl_PrimitiveIDIn + 1) / 4.0; EmitVertex(); }\n EndPrimitive(); }\n";
static const char *gs_inv = V "layout(triangles, invocations = 4) in;\nlayout(triangle_strip, max_vertices = 3) out;\nin vec3 vcol[];\nout vec3 fcol;\n"
	"void main() { vec2 off = vec2(float(gl_InvocationID & 1) - 0.5, float(gl_InvocationID >> 1) - 0.5);\n"
	" for (int i = 0; i < 3; i++) { gl_Position = vec4(gl_in[i].gl_Position.xy * 0.4 + off, 0.0, 1.0); fcol = vcol[i] * (0.25 + 0.25 * float(gl_InvocationID)); EmitVertex(); }\n"
	" EndPrimitive(); }\n";
static const char *vs_patch = V "precision highp float;\nconst vec2 p[4] = vec2[](vec2(-0.8,-0.8), vec2(0.8,-0.8), vec2(0.0,0.8), vec2(0.8,0.8));\n"
	"out vec3 vcol;\nvoid main() { gl_Position = vec4(p[gl_VertexID % 4], 0.0, 1.0); vcol = vec3(gl_VertexID == 0, gl_VertexID == 1, gl_VertexID >= 2); }\n";
static const char *tcs_tri = V "layout(vertices = 3) out;\nin vec3 vcol[];\nout vec3 tcol[];\npatch out float pscale;\n"
	"void main() { gl_out[gl_InvocationID].gl_Position = gl_in[gl_InvocationID].gl_Position; tcol[gl_InvocationID] = vcol[gl_InvocationID];\n"
	" if (gl_InvocationID == 0) { gl_TessLevelOuter[0] = 4.0; gl_TessLevelOuter[1] = 4.0; gl_TessLevelOuter[2] = 4.0; gl_TessLevelInner[0] = 4.0; pscale = 0.95; } }\n";
static const char *tes_tri = V "layout(triangles, equal_spacing, ccw) in;\nin vec3 tcol[];\npatch in float pscale;\nout vec3 fcol;\n"
	"void main() { vec3 b = gl_TessCoord; gl_Position = (b.x * gl_in[0].gl_Position + b.y * gl_in[1].gl_Position + b.z * gl_in[2].gl_Position) * vec4(pscale, pscale, 1.0, 1.0);\n"
	" fcol = b.x * tcol[0] + b.y * tcol[1] + b.z * tcol[2]; }\n";
static const char *tcs_quad = V "layout(vertices = 4) out;\nin vec3 vcol[];\nout vec3 tcol[];\n"
	"void main() { gl_out[gl_InvocationID].gl_Position = gl_in[gl_InvocationID].gl_Position; tcol[gl_InvocationID] = vcol[gl_InvocationID];\n"
	" gl_TessLevelOuter[0] = 2.0; gl_TessLevelOuter[1] = 3.0; gl_TessLevelOuter[2] = 4.0; gl_TessLevelOuter[3] = 5.0; gl_TessLevelInner[0] = 3.0; gl_TessLevelInner[1] = 2.0; }\n";
static const char *tes_quad = V "layout(quads, fractional_odd_spacing, cw) in;\nin vec3 tcol[];\nout vec3 fcol;\n"
	"void main() { vec2 u = gl_TessCoord.xy; vec4 a = mix(gl_in[0].gl_Position, gl_in[1].gl_Position, u.x), b = mix(gl_in[2].gl_Position, gl_in[3].gl_Position, u.x);\n"
	" gl_Position = mix(a, b, u.y); fcol = mix(mix(tcol[0], tcol[1], u.x), mix(tcol[2], tcol[3], u.x), u.y) * (0.5 + 0.5 * float(gl_PrimitiveID + 1)); }\n";
static const char *tes_tri_v = V "layout(triangles, equal_spacing, ccw) in;\nin vec3 tcol[];\npatch in float pscale;\nout vec3 vcol;\n"
	"void main() { vec3 b = gl_TessCoord; gl_Position = b.x * gl_in[0].gl_Position + b.y * gl_in[1].gl_Position + b.z * gl_in[2].gl_Position; vcol = b.x * tcol[0] + b.y * tcol[1] + b.z * tcol[2]; }\n";
static const char *gs_shrink = V "layout(triangles) in;\nlayout(triangle_strip, max_vertices = 3) out;\nin vec3 vcol[];\nout vec3 fcol;\n"
	"void main() { vec4 c = (gl_in[0].gl_Position + gl_in[1].gl_Position + gl_in[2].gl_Position) / 3.0;\n"
	" for (int i = 0; i < 3; i++) { gl_Position = mix(c, gl_in[i].gl_Position, 0.8); fcol = vcol[i]; EmitVertex(); } EndPrimitive(); }\n";
static const char *gs_xfb = V "layout(triangles) in;\nlayout(triangle_strip, max_vertices = 6) out;\nin vec3 vcol[];\nout vec3 fcol;\nout vec4 xpos;\n"
	"void main() { for (int k = 0; k < 2; k++) { for (int i = 0; i < 3; i++) { gl_Position = gl_in[i].gl_Position * vec4(0.5, 0.5, 1.0, 1.0) + vec4(float(k) * 0.4 - 0.2, 0.0, 0.0, 0.0);\n"
	"  xpos = gl_Position; fcol = vcol[i]; EmitVertex(); } EndPrimitive(); } }\n";
static const char *gs_layer = V "layout(triangles) in;\nlayout(triangle_strip, max_vertices = 6) out;\nin vec3 vcol[];\nout vec3 fcol;\n"
	"void main() { for (int l = 0; l < 2; l++) { gl_Layer = l; for (int i = 0; i < 3; i++) { gl_Position = gl_in[i].gl_Position; fcol = l == 0 ? vcol[i] : vcol[i].bgr; EmitVertex(); } EndPrimitive(); } }\n";

static GLuint fbo_2d(void)
{
	GLuint t, f;
	glGenTextures(1, &t); glBindTexture(GL_TEXTURE_2D, t); glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, W, H);
	glGenFramebuffers(1, &f); glBindFramebuffer(GL_FRAMEBUFFER, f);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t, 0);
	glViewport(0, 0, W, H); glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
	return f;
}

static int want(int argc, char **argv, const char *n)
{
	if (argc <= 2) return 1;
	for (int i = 2; i < argc; i++) if (!strcmp(argv[i], n)) return 1;
	return 0;
}

static void run(const char *name, GLuint p, GLenum mode, int count)
{
	if (!p) { fprintf(info, "%s: LINK FAILED\n", name); return; }
	char m[128];
	fbo_2d(); glUseProgram(p);
	glFinish();
	snprintf(m, sizeof m, "begin %s", name); mark(m);
	glDrawArrays(mode, 0, count);
	glFinish();
	snprintf(m, sizeof m, "end %s", name); mark(m);
	readback(name); save_bin(name, p);
}

int main(int argc, char **argv)
{
	od = argc > 1 ? argv[1] : ".";
	char fn[512]; snprintf(fn, sizeof fn, "%s/info.txt", od);
	info = fopen(fn, "w");
	marker = (void (*)(const char *))dlsym(RTLD_DEFAULT, "kbtrace_marker");
	const char *devs[] = { "/dev/dri/card0", "/dev/dri/card1", "/dev/dri/renderD128" };
	int fd = -1;
	for (int i = 0; i < 3 && fd < 0; i++) fd = open(devs[i], O_RDWR | O_CLOEXEC);
	struct gbm_device *gbm = gbm_create_device(fd);
	PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay dpy = gpd ? gpd(EGL_PLATFORM_GBM_KHR, gbm, NULL) : eglGetDisplay((EGLNativeDisplayType)gbm);
	EGLint maj, min;
	if (!eglInitialize(dpy, &maj, &min)) { fprintf(stderr, "eglInitialize failed 0x%x\n", eglGetError()); return 1; }
	fprintf(info, "EGL_VENDOR: %s\nEGL_VERSION: %s\nEGL_CLIENT_APIS: %s\nEGL_EXTENSIONS: %s\n",
		eglQueryString(dpy, EGL_VENDOR), eglQueryString(dpy, EGL_VERSION), eglQueryString(dpy, EGL_CLIENT_APIS),
		eglQueryString(dpy, EGL_EXTENSIONS));
	{
		EGLint nc = 0; eglGetConfigs(dpy, NULL, 0, &nc);
		EGLConfig *cf = calloc(nc, sizeof *cf); eglGetConfigs(dpy, cf, nc, &nc);
		fprintf(info, "EGL configs: %d\n", nc);
		for (int i = 0; i < nc; i++) {
			EGLint id, r, g, b, a, d, s, st, rt, ms, vis;
			eglGetConfigAttrib(dpy, cf[i], EGL_CONFIG_ID, &id); eglGetConfigAttrib(dpy, cf[i], EGL_RED_SIZE, &r);
			eglGetConfigAttrib(dpy, cf[i], EGL_GREEN_SIZE, &g); eglGetConfigAttrib(dpy, cf[i], EGL_BLUE_SIZE, &b);
			eglGetConfigAttrib(dpy, cf[i], EGL_ALPHA_SIZE, &a); eglGetConfigAttrib(dpy, cf[i], EGL_DEPTH_SIZE, &d);
			eglGetConfigAttrib(dpy, cf[i], EGL_STENCIL_SIZE, &s); eglGetConfigAttrib(dpy, cf[i], EGL_SURFACE_TYPE, &st);
			eglGetConfigAttrib(dpy, cf[i], EGL_RENDERABLE_TYPE, &rt); eglGetConfigAttrib(dpy, cf[i], EGL_SAMPLES, &ms);
			eglGetConfigAttrib(dpy, cf[i], EGL_NATIVE_VISUAL_ID, &vis);
			fprintf(info, "  cfg %d: rgba %d%d%d%d d%d s%d ms%d surface 0x%x renderable 0x%x visual 0x%x\n", id, r, g, b, a, d, s, ms, st, rt, vis);
		}
		free(cf);
	}
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint ca[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 2, EGL_NONE };
	EGLContext ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ca);
	if (ctx == EGL_NO_CONTEXT) {
		EGLint cfa[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE }, n; EGLConfig cfg;
		eglChooseConfig(dpy, cfa, &cfg, 1, &n);
		ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ca);
	}
	if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
		fprintf(stderr, "context failed 0x%x\n", eglGetError()); return 1;
	}
	fprintf(info, "GL_VENDOR: %s\nGL_RENDERER: %s\nGL_VERSION: %s\nGL_SHADING_LANGUAGE_VERSION: %s\n",
		glGetString(GL_VENDOR), glGetString(GL_RENDERER), glGetString(GL_VERSION), glGetString(GL_SHADING_LANGUAGE_VERSION));
	GLint n = 0; glGetIntegerv(GL_NUM_EXTENSIONS, &n);
	fprintf(info, "GL_NUM_EXTENSIONS: %d\nGL_EXTENSIONS:", n);
	for (int i = 0; i < n; i++) fprintf(info, " %s", glGetStringi(GL_EXTENSIONS, i));
	fprintf(info, "\n");
	struct { GLenum e; const char *n; } lim[] = {
		{ GL_MAX_GEOMETRY_OUTPUT_VERTICES, "MAX_GEOMETRY_OUTPUT_VERTICES" },
		{ GL_MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS, "MAX_GEOMETRY_TOTAL_OUTPUT_COMPONENTS" },
		{ GL_MAX_GEOMETRY_SHADER_INVOCATIONS, "MAX_GEOMETRY_SHADER_INVOCATIONS" },
		{ GL_MAX_GEOMETRY_INPUT_COMPONENTS, "MAX_GEOMETRY_INPUT_COMPONENTS" },
		{ GL_MAX_GEOMETRY_OUTPUT_COMPONENTS, "MAX_GEOMETRY_OUTPUT_COMPONENTS" },
		{ GL_MAX_GEOMETRY_UNIFORM_BLOCKS, "MAX_GEOMETRY_UNIFORM_BLOCKS" },
		{ GL_MAX_GEOMETRY_SHADER_STORAGE_BLOCKS, "MAX_GEOMETRY_SHADER_STORAGE_BLOCKS" },
		{ GL_MAX_GEOMETRY_ATOMIC_COUNTERS, "MAX_GEOMETRY_ATOMIC_COUNTERS" },
		{ GL_MAX_GEOMETRY_IMAGE_UNIFORMS, "MAX_GEOMETRY_IMAGE_UNIFORMS" },
		{ GL_MAX_GEOMETRY_TEXTURE_IMAGE_UNITS, "MAX_GEOMETRY_TEXTURE_IMAGE_UNITS" },
		{ GL_MAX_FRAMEBUFFER_LAYERS, "MAX_FRAMEBUFFER_LAYERS" },
		{ GL_MAX_PATCH_VERTICES, "MAX_PATCH_VERTICES" },
		{ GL_MAX_TESS_GEN_LEVEL, "MAX_TESS_GEN_LEVEL" },
		{ GL_MAX_TESS_CONTROL_INPUT_COMPONENTS, "MAX_TESS_CONTROL_INPUT_COMPONENTS" },
		{ GL_MAX_TESS_CONTROL_OUTPUT_COMPONENTS, "MAX_TESS_CONTROL_OUTPUT_COMPONENTS" },
		{ GL_MAX_TESS_PATCH_COMPONENTS, "MAX_TESS_PATCH_COMPONENTS" },
		{ GL_MAX_TESS_CONTROL_TOTAL_OUTPUT_COMPONENTS, "MAX_TESS_CONTROL_TOTAL_OUTPUT_COMPONENTS" },
		{ GL_MAX_TESS_EVALUATION_INPUT_COMPONENTS, "MAX_TESS_EVALUATION_INPUT_COMPONENTS" },
		{ GL_MAX_TESS_EVALUATION_OUTPUT_COMPONENTS, "MAX_TESS_EVALUATION_OUTPUT_COMPONENTS" },
		{ GL_MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS, "MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS" },
		{ GL_MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS, "MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS" },
		{ GL_MAX_TESS_CONTROL_UNIFORM_BLOCKS, "MAX_TESS_CONTROL_UNIFORM_BLOCKS" },
		{ GL_MAX_TESS_CONTROL_ATOMIC_COUNTERS, "MAX_TESS_CONTROL_ATOMIC_COUNTERS" },
		{ GL_MAX_TESS_CONTROL_IMAGE_UNIFORMS, "MAX_TESS_CONTROL_IMAGE_UNIFORMS" },
		{ GL_MAX_VERTEX_SHADER_STORAGE_BLOCKS, "MAX_VERTEX_SHADER_STORAGE_BLOCKS" },
		{ GL_MAX_VERTEX_ATOMIC_COUNTERS, "MAX_VERTEX_ATOMIC_COUNTERS" },
		{ GL_MAX_VERTEX_IMAGE_UNIFORMS, "MAX_VERTEX_IMAGE_UNIFORMS" },
		{ GL_MAX_COMPUTE_SHARED_MEMORY_SIZE, "MAX_COMPUTE_SHARED_MEMORY_SIZE" },
		{ GL_MAX_TEXTURE_SIZE, "MAX_TEXTURE_SIZE" },
		{ GL_MAX_SAMPLES, "MAX_SAMPLES" },
	};
	while (glGetError()) ;
	for (unsigned i = 0; i < sizeof lim / sizeof lim[0]; i++) {
		GLint v = -1; glGetIntegerv(lim[i].e, &v);
		fprintf(info, "%s = %d%s\n", lim[i].n, v, glGetError() ? " (error)" : "");
	}
	GLint layer_prov = 0; glGetIntegerv(GL_LAYER_PROVOKING_VERTEX, &layer_prov);
	fprintf(info, "LAYER_PROVOKING_VERTEX = 0x%x\n", layer_prov);
	fflush(info);

	GLuint vao; glGenVertexArrays(1, &vao); glBindVertexArray(vao);
	if (want(argc, argv, "basic")) run("basic", prog(vs_tri, NULL, NULL, NULL, fs_vcol, NULL, 0), GL_TRIANGLES, 3);
	if (want(argc, argv, "gs_pass")) run("gs_pass", prog(vs_tri, NULL, NULL, gs_pass, fs_col, NULL, 0), GL_TRIANGLES, 3);
	if (want(argc, argv, "gs_amp")) run("gs_amp", prog(vs_pts, NULL, NULL, gs_amp, fs_col, NULL, 0), GL_POINTS, 4);
	if (want(argc, argv, "gs_inv")) run("gs_inv", prog(vs_tri, NULL, NULL, gs_inv, fs_col, NULL, 0), GL_TRIANGLES, 3);
	glPatchParameteri(GL_PATCH_VERTICES, 3);
	if (want(argc, argv, "tess_tri")) run("tess_tri", prog(vs_patch, tcs_tri, tes_tri, NULL, fs_col, NULL, 0), GL_PATCHES, 3);
	if (want(argc, argv, "tess_gs")) run("tess_gs", prog(vs_patch, tcs_tri, tes_tri_v, gs_shrink, fs_col, NULL, 0), GL_PATCHES, 3);
	glPatchParameteri(GL_PATCH_VERTICES, 4);
	if (want(argc, argv, "tess_quad")) run("tess_quad", prog(vs_patch, tcs_quad, tes_quad, NULL, fs_col, NULL, 0), GL_PATCHES, 4);

	if (want(argc, argv, "gs_xfb")) {
		const char *vv[] = { "xpos" };
		GLuint p = prog(vs_tri, NULL, NULL, gs_xfb, fs_col, vv, 1);
		GLuint b, q, tf; glGenBuffers(1, &b); glGenQueries(1, &q);
		glGenTransformFeedbacks(1, &tf); glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, tf);
		glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER, b);
		glBufferData(GL_TRANSFORM_FEEDBACK_BUFFER, 6 * 16 * 2, NULL, GL_STATIC_READ);
		glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, b);
		fbo_2d(); glUseProgram(p); glFinish();
		mark("begin gs_xfb");
		glBeginQuery(GL_PRIMITIVES_GENERATED, q);
		glBeginTransformFeedback(GL_TRIANGLES);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		glEndTransformFeedback();
		glEndQuery(GL_PRIMITIVES_GENERATED);
		glFinish();
		mark("end gs_xfb");
		GLuint prims = 0; glGetQueryObjectuiv(q, GL_QUERY_RESULT, &prims);
		float *x = glMapBufferRange(GL_TRANSFORM_FEEDBACK_BUFFER, 0, 6 * 16, GL_MAP_READ_BIT);
		fprintf(info, "gs_xfb: PRIMITIVES_GENERATED=%u xfb[0]=(%.3f %.3f %.3f %.3f) xfb[3]=(%.3f %.3f)\n", prims,
			x ? x[0] : -9, x ? x[1] : -9, x ? x[2] : -9, x ? x[3] : -9, x ? x[12] : -9, x ? x[13] : -9);
		glUnmapBuffer(GL_TRANSFORM_FEEDBACK_BUFFER);
		glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, 0);
		readback("gs_xfb"); save_bin("gs_xfb", p);
	}
	if (want(argc, argv, "gs_layer")) {
		GLuint p = prog(vs_tri, NULL, NULL, gs_layer, fs_col, NULL, 0), t, f;
		glGenTextures(1, &t); glBindTexture(GL_TEXTURE_2D_ARRAY, t); glTexStorage3D(GL_TEXTURE_2D_ARRAY, 1, GL_RGBA8, W, H, 2);
		glGenFramebuffers(1, &f); glBindFramebuffer(GL_FRAMEBUFFER, f);
		glFramebufferTexture(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, t, 0);
		fprintf(info, "gs_layer: fb status 0x%x\n", glCheckFramebufferStatus(GL_FRAMEBUFFER));
		glViewport(0, 0, W, H); glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
		glUseProgram(p); glFinish();
		mark("begin gs_layer");
		glDrawArrays(GL_TRIANGLES, 0, 3);
		glFinish();
		mark("end gs_layer");
		GLuint rf; glGenFramebuffers(1, &rf);
		for (int l = 0; l < 2; l++) {
			glBindFramebuffer(GL_FRAMEBUFFER, rf);
			glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, t, 0, l);
			char nm[32]; snprintf(nm, sizeof nm, "gs_layer%d", l); readback(nm);
		}
		save_bin("gs_layer", p);
	}
	fprintf(info, "done\n");
	fclose(info);
	return 0;
}
