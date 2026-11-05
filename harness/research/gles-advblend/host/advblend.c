/* advblend: minimal repro of KHR-GLES31.core.blend_equation_advanced.test_coherency.{mixedSequence,multiplySequence}
 * (EGL surfaceless + GLES 3.1, FBO RGBA8). Draws the CTS blend sequence with one fullscreen quad per step,
 * reads the result back and reports: first pixel, distinct values, a per-16x16-tile map of bad tiles.
 * Host: run under the panfrost drm-shim (no execution, descriptor/shader trace). Board: real result.
 *   advblend [--seq mixed|multiply] [--repeat N] [--size W] [--barrier] [--nocoherent] [--dump file] [--quiet]
 * Exit 0 = all pixels equal the reference (CTS pass criterion: first pixel within threshold, all pixels equal),
 * 1 = mismatch, 2 = setup error. */
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl32.h>
#include <GLES2/gl2ext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifndef GL_BLEND_ADVANCED_COHERENT_KHR
#define GL_BLEND_ADVANCED_COHERENT_KHR 0x9285
#endif
#ifndef GL_MULTIPLY_KHR
#define GL_MULTIPLY_KHR 0x9294
#define GL_SCREEN_KHR 0x9295
#define GL_OVERLAY_KHR 0x9296
#define GL_DARKEN_KHR 0x9297
#define GL_LIGHTEN_KHR 0x9298
#define GL_COLORDODGE_KHR 0x9299
#define GL_COLORBURN_KHR 0x929A
#define GL_HARDLIGHT_KHR 0x929B
#define GL_SOFTLIGHT_KHR 0x929C
#define GL_DIFFERENCE_KHR 0x929E
#define GL_EXCLUSION_KHR 0x92A0
#endif

struct step { GLenum mode; float src[4]; };
static const struct step s_mixed[] = {
   {GL_LIGHTEN_KHR, {0.250f, 0.375f, 1.000f, 1.000f}}, {GL_OVERLAY_KHR, {1.000f, 1.000f, 1.000f, 1.000f}},
   {GL_HARDLIGHT_KHR, {0.750f, 0.750f, 0.250f, 1.000f}}, {GL_DARKEN_KHR, {0.250f, 0.250f, 0.250f, 1.000f}},
   {GL_COLORDODGE_KHR, {0.750f, 0.875f, 1.000f, 1.000f}}, {GL_MULTIPLY_KHR, {0.500f, 0.500f, 0.500f, 1.000f}},
   {GL_SCREEN_KHR, {0.500f, 0.500f, 0.500f, 1.000f}}, {GL_DARKEN_KHR, {0.250f, 0.500f, 0.500f, 1.000f}},
   {GL_DIFFERENCE_KHR, {0.000f, 0.875f, 0.125f, 1.000f}}, {GL_EXCLUSION_KHR, {1.000f, 0.500f, 0.750f, 1.000f}},
   {GL_DARKEN_KHR, {0.125f, 0.125f, 0.125f, 1.000f}},
};
static const struct step s_multiply[] = {
   {GL_LIGHTEN_KHR, {1, 1, 1, 1}}, {GL_MULTIPLY_KHR, {.5f, .5f, .5f, 1}}, {GL_MULTIPLY_KHR, {.5f, .5f, .5f, 1}},
   {GL_MULTIPLY_KHR, {.5f, .5f, .5f, 1}}, {GL_MULTIPLY_KHR, {.5f, .5f, .5f, 1}}, {GL_MULTIPLY_KHR, {.5f, .5f, .5f, 1}},
   {GL_MULTIPLY_KHR, {.5f, .5f, .5f, 1}},
};

/* reference blend, same formulas as the CTS (glcBlendEquationAdvancedTests.cpp), straight alpha = 1 everywhere */
static float f_mult(float s, float d) { return s * d; }
static float f_screen(float s, float d) { return s + d - s * d; }
static float f_hardlight(float s, float d) { return s <= 0.5f ? f_mult(d, 2 * s) : f_screen(d, 2 * s - 1); }
static float f_overlay(float s, float d) { return f_hardlight(d, s); }
static float f_darken(float s, float d) { return s < d ? s : d; }
static float f_lighten(float s, float d) { return s > d ? s : d; }
static float f_dodge(float s, float d) { if (d <= 0) return 0; if (s >= 1) return 1; float r = d / (1 - s); return r > 1 ? 1 : r; }
static float f_diff(float s, float d) { return fabsf(s - d); }
static float f_excl(float s, float d) { return s + d - 2 * s * d; }
static void ref_blend(GLenum mode, const float *s, float *d)
{
   float (*f)(float, float) = NULL;
   switch (mode) {
   case GL_MULTIPLY_KHR: f = f_mult; break; case GL_SCREEN_KHR: f = f_screen; break;
   case GL_OVERLAY_KHR: f = f_overlay; break; case GL_DARKEN_KHR: f = f_darken; break;
   case GL_LIGHTEN_KHR: f = f_lighten; break; case GL_COLORDODGE_KHR: f = f_dodge; break;
   case GL_HARDLIGHT_KHR: f = f_hardlight; break; case GL_DIFFERENCE_KHR: f = f_diff; break;
   case GL_EXCLUSION_KHR: f = f_excl; break; default: abort();
   }
   /* alpha of src and dst is 1 after the first step: result = f(s,d); first step on dst alpha 0: result = src */
   float sa = s[3], da = d[3];
   for (int c = 0; c < 3; c++) {
      float r = (1 - sa) * da * d[c] + (1 - da) * sa * s[c] + sa * da * f(s[c], d[c]);
      float ra = sa + da - sa * da;
      d[c] = ra > 0 ? r / ra : 0;
   }
   d[3] = sa + da - sa * da;
}

static const char *vs_src =
   "#version 310 es\nin vec2 aPos;\nvoid main(){ gl_Position = vec4(aPos, 0.0, 1.0); }\n";
static const char *fs_src =
   "#version 310 es\n#extension GL_KHR_blend_equation_advanced : require\n\nprecision highp float;\n\n"
   "layout (blend_support_all_equations) out;\nlayout (location = 0) out vec4 oCol;\n\nuniform vec4 uSrcCol;\n\n"
   "void main (void) {\n   oCol = uSrcCol;\n}\n";

static GLuint compile(GLenum type, const char *src)
{
   GLuint s = glCreateShader(type); glShaderSource(s, 1, &src, NULL); glCompileShader(s);
   GLint ok = 0; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
   if (!ok) { char log[4096]; glGetShaderInfoLog(s, sizeof log, NULL, log); fprintf(stderr, "shader: %s\n", log); exit(2); }
   return s;
}

int main(int argc, char **argv)
{
   const struct step *steps = s_mixed; int nsteps = 11, repeat = 4, dim = 1024, barrier = 0, nocoherent = 0, quiet = 0;
   const char *dump = NULL;
   for (int i = 1; i < argc; i++) {
      if (!strcmp(argv[i], "--seq") && i + 1 < argc) { i++; if (!strcmp(argv[i], "multiply")) { steps = s_multiply; nsteps = 7; repeat = 1; } }
      else if (!strcmp(argv[i], "--repeat") && i + 1 < argc) repeat = atoi(argv[++i]);
      else if (!strcmp(argv[i], "--size") && i + 1 < argc) dim = atoi(argv[++i]);
      else if (!strcmp(argv[i], "--barrier")) barrier = 1;
      else if (!strcmp(argv[i], "--nocoherent")) nocoherent = 1;
      else if (!strcmp(argv[i], "--dump") && i + 1 < argc) dump = argv[++i];
      else if (!strcmp(argv[i], "--quiet")) quiet = 1;
      else { fprintf(stderr, "usage: see source\n"); return 2; }
   }

   EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
   if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL)) { fprintf(stderr, "no EGL display (EGL_PLATFORM=surfaceless?)\n"); return 2; }
   eglBindAPI(EGL_OPENGL_ES_API);
   EGLint cattr[] = { EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_NONE };
   EGLConfig cfg; EGLint n = 0;
   if (!eglChooseConfig(dpy, cattr, &cfg, 1, &n) || n < 1) { fprintf(stderr, "no EGL config\n"); return 2; }
   EGLint xattr[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 1, EGL_NONE };
   EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, xattr);
   if (ctx == EGL_NO_CONTEXT) { fprintf(stderr, "no GLES 3.1 context\n"); return 2; }
   EGLint pattr[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
   EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, pattr);
   if (!eglMakeCurrent(dpy, surf, surf, ctx)) { fprintf(stderr, "makecurrent failed\n"); return 2; }

   const char *exts = (const char *)glGetString(GL_EXTENSIONS);
   int has_coh = exts && strstr(exts, "GL_KHR_blend_equation_advanced_coherent") != NULL;
   if (!exts || !strstr(exts, "GL_KHR_blend_equation_advanced")) { fprintf(stderr, "no GL_KHR_blend_equation_advanced\n"); return 2; }
   printf("renderer: %s | version: %s | coherent ext: %d | seq %s x%d, %dx%d, barrier=%d\n", glGetString(GL_RENDERER),
          glGetString(GL_VERSION), has_coh, steps == s_mixed ? "mixed" : "multiply", repeat, dim, dim, barrier);
   if (has_coh && nocoherent) glDisable(GL_BLEND_ADVANCED_COHERENT_KHR);

   GLuint fbo, rb; glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
   glGenRenderbuffers(1, &rb); glBindRenderbuffer(GL_RENDERBUFFER, rb);
   glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, dim, dim);
   glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
   if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { fprintf(stderr, "fbo incomplete\n"); return 2; }
   glViewport(0, 0, dim, dim);

   GLuint prog = glCreateProgram();
   glAttachShader(prog, compile(GL_VERTEX_SHADER, vs_src)); glAttachShader(prog, compile(GL_FRAGMENT_SHADER, fs_src));
   glLinkProgram(prog); GLint ok = 0; glGetProgramiv(prog, GL_LINK_STATUS, &ok);
   if (!ok) { char log[4096]; glGetProgramInfoLog(prog, sizeof log, NULL, log); fprintf(stderr, "link: %s\n", log); return 2; }
   glUseProgram(prog);
   GLint uloc = glGetUniformLocation(prog, "uSrcCol");

   static const float pos[] = { -1, -1, 1, -1, 1, 1, -1, 1 };
   static const GLushort idx[] = { 0, 1, 2, 2, 3, 0 };  /* two triangles like the CTS (s_indices) */
   GLuint vao, vbo, ibo; glGenVertexArrays(1, &vao); glBindVertexArray(vao);
   glGenBuffers(1, &vbo); glBindBuffer(GL_ARRAY_BUFFER, vbo); glBufferData(GL_ARRAY_BUFFER, sizeof pos, pos, GL_STATIC_DRAW);
   GLint aloc = glGetAttribLocation(prog, "aPos"); glEnableVertexAttribArray(aloc); glVertexAttribPointer(aloc, 2, GL_FLOAT, GL_FALSE, 0, 0);
   glGenBuffers(1, &ibo); glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo); glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof idx, idx, GL_STATIC_DRAW);

   glDisable(GL_DITHER); glEnable(GL_BLEND);
   float dst[4] = { 0, 0, 0, 0 };
   glClearColor(0, 0, 0, 0); glClear(GL_COLOR_BUFFER_BIT);
   if (barrier) glBlendBarrier();
   for (int r = 0; r < repeat; r++)
      for (int j = 0; j < nsteps; j++) {
         ref_blend(steps[j].mode, steps[j].src, dst);
         glBlendEquation(steps[j].mode);
         glUniform4fv(uloc, 1, steps[j].src);
         glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_SHORT, 0);
         if (barrier) glBlendBarrier();
      }
   GLenum err = glGetError(); if (err) { fprintf(stderr, "GL error 0x%x\n", err); return 2; }

   unsigned char *res = malloc((size_t)dim * dim * 4);
   glReadPixels(0, 0, dim, dim, GL_RGBA, GL_UNSIGNED_BYTE, res);
   glFinish();
   if (dump) { FILE *f = fopen(dump, "wb"); if (f) { fwrite(res, 4, (size_t)dim * dim, f); fclose(f); } }

   unsigned char ref[4]; for (int c = 0; c < 4; c++) { float v = dst[c] * 255.0f + 0.5f; ref[c] = v < 0 ? 0 : v > 255 ? 255 : (unsigned char)v; }
   int first_ok = 1; for (int c = 0; c < 4; c++) if (abs((int)res[c] - (int)ref[c]) > 2) first_ok = 0;
   /* distinct values + bad tiles (16x16, like the Mali tile size at RGBA8) */
   int ntiles = (dim + 15) / 16; int *bad = calloc((size_t)ntiles * ntiles, sizeof *bad); long nbad = 0;
   unsigned int vals[64]; long cnt[64]; int nv = 0; long ex[64][2];
   for (long i = 0; i < (long)dim * dim; i++) {
      unsigned int v; memcpy(&v, res + i * 4, 4);
      int k; for (k = 0; k < nv; k++) if (vals[k] == v) break;
      if (k == nv) { if (nv < 64) { vals[nv] = v; cnt[nv] = 0; ex[nv][0] = i % dim; ex[nv][1] = i / dim; nv++; } else continue; }
      cnt[k]++;
      if (memcmp(res + i * 4, res, 4)) { nbad++; bad[(i / dim / 16) * ntiles + (i % dim) / 16]++; }
   }
   printf("first pixel: %u,%u,%u,%u ref %u,%u,%u,%u %s; distinct values: %d%s; pixels != first: %ld of %ld\n",
          res[0], res[1], res[2], res[3], ref[0], ref[1], ref[2], ref[3], first_ok ? "OK" : "WRONG", nv, nv >= 64 ? "+" : "", nbad, (long)dim * dim);
   for (int k = 0; k < nv && k < 16; k++)
      printf("  value %3u,%3u,%3u,%3u x%ld (e.g. %ld,%ld)\n", vals[k] & 255, (vals[k] >> 8) & 255, (vals[k] >> 16) & 255, vals[k] >> 24, cnt[k], ex[k][0], ex[k][1]);
   if (nbad && !quiet) {
      long nbt = 0; for (int t = 0; t < ntiles * ntiles; t++) if (bad[t]) nbt++;
      printf("bad tiles: %ld of %d (16x16); map (row 0 = y 0..15, '.' ok, '#' all 256 wrong, '+' partly):\n", nbt, ntiles * ntiles);
      for (int ty = 0; ty < ntiles && ty < 64; ty++) { printf("  ");
         for (int tx = 0; tx < ntiles && tx < 128; tx++) putchar(bad[ty * ntiles + tx] == 0 ? '.' : bad[ty * ntiles + tx] >= 256 ? '#' : '+');
         putchar('\n'); }
   }
   int pass = first_ok && nbad == 0;
   printf("RESULT %s\n", pass ? "PASS" : "FAIL");
   return pass ? 0 : 1;
}
