// SPDX-License-Identifier: MIT
/*
 * afbc-gpu-check: decode the H616 VE's native AFBC captures with the Mali-G31
 * (Mesa panfrost) and md5 the result per frame against a linear reference.
 *
 * Route (b) of the AFBC bit-exactness check: the AFBC capture buffer is put in
 * a panfrost BO, imported as an EGLImage (DRM_FORMAT_YUV420_10BIT/_8BIT with
 * the AFBC 16x16|SPARSE|SPLIT modifier, strict panfrost import rules) and
 * bound to a plain GL_TEXTURE_2D (not samplerExternalOES, so no YUV->RGB
 * conversion is lowered into the shader: the texture unit returns raw Y, U, V
 * in R, G, B). A fragment shader texelFetches 4 pixels per output texel into a
 * GL_RGBA32UI target; the CPU unpacks that into the reference layout (p010le,
 * yuv420p10le, nv12 or i420) and md5s each frame.
 *
 * Input: the dump stream written by the test-only FFmpeg diff
 * (ffmpeg-drmprime-dump.diff, env V4L2REQUEST_DUMP=path) or by avs2dec
 * (AVS2_CAP=AFBC -o path): per frame a 32-byte header
 *   char magic[8] = "AFBCDMP1"; u32 size; u32 width; u32 height;
 *   u32 drm_format; u64 modifier; u32 index;
 * followed by `size` raw bytes of the capture buffer. A FIFO works.
 *
 * Usage: afbc-gpu-check [-r ref.framemd5] [-l p010le|yuv420p10le|nv12|i420]
 *                       [-m max_frames] [-D dumpdir] [-d N] [-H] [-e] [-v]
 *                       [-p pitch] [-M modifier_hex] dump-file-or-fifo
 *   -r   reference: ffmpeg -f framemd5 output, or "frame N [poc P] md5 X" lines
 *        (avs2dec -f / davs2 yuvtool) in output order
 *   -l   output layout to md5 (default: p010le for 10-bit, nv12 for 8-bit)
 *   -D   write the linear frame of the first mismatch (and of -d N) here
 *   -H   print AFBC header statistics of each frame (solid/uncompressed/
 *        compressed superblocks, body offset range)
 *   -e   bind as GL_TEXTURE_EXTERNAL_OES instead (diagnostic only: Mesa then
 *        applies a YUV->RGB matrix, the md5s cannot match)
 *   -p   force the EGL plane pitch (default: tiles * uncompressed tile bytes / 16
 *        = w*15/8 for 10-bit, w*3/2 for 8-bit; the other candidates are tried
 *        on failure)
 * Cross-build (host):
 *   aarch64-linux-gnu-gcc -O2 -std=gnu11 -I<mesa>/include -I<kernel-uapi> \
 *       -o afbc-gpu-check afbc-gpu-check.c -ldl
 * Exit status 0 when every compared frame matched, 1 otherwise.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/panfrost_drm.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif

static int verbose;

static void die(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	fprintf(stderr, "afbc-gpu-check: ");
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
	exit(2);
}

static double now(void)
{
	struct timeval tv;

	gettimeofday(&tv, NULL);
	return tv.tv_sec + tv.tv_usec / 1e6;
}

/* ------------------------------------------------------------------ */
/* MD5 (RFC 1321)                                                     */

struct md5 {
	uint32_t s[4];
	uint64_t len;
	uint8_t buf[64];
	unsigned int n;
};

static const uint32_t md5_k[64] = {
	0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
	0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
	0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
	0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
	0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
	0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
	0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
	0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
	0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
	0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
	0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
};

static const uint8_t md5_r[64] = {
	7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
	5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
	4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
	6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
};

static void md5_init(struct md5 *m)
{
	m->s[0] = 0x67452301;
	m->s[1] = 0xefcdab89;
	m->s[2] = 0x98badcfe;
	m->s[3] = 0x10325476;
	m->len = 0;
	m->n = 0;
}

static void md5_block(struct md5 *m, const uint8_t *p)
{
	uint32_t w[16], a = m->s[0], b = m->s[1], c = m->s[2], d = m->s[3];
	int i;

	for (i = 0; i < 16; i++)
		w[i] = p[4 * i] | p[4 * i + 1] << 8 | p[4 * i + 2] << 16 |
		       (uint32_t)p[4 * i + 3] << 24;
	for (i = 0; i < 64; i++) {
		uint32_t f;
		int g;

		if (i < 16) {
			f = (b & c) | (~b & d);
			g = i;
		} else if (i < 32) {
			f = (d & b) | (~d & c);
			g = (5 * i + 1) & 15;
		} else if (i < 48) {
			f = b ^ c ^ d;
			g = (3 * i + 5) & 15;
		} else {
			f = c ^ (b | ~d);
			g = (7 * i) & 15;
		}
		f += a + md5_k[i] + w[g];
		a = d;
		d = c;
		c = b;
		b += (f << md5_r[i]) | (f >> (32 - md5_r[i]));
	}
	m->s[0] += a;
	m->s[1] += b;
	m->s[2] += c;
	m->s[3] += d;
}

static void md5_update(struct md5 *m, const void *data, size_t len)
{
	const uint8_t *p = data;

	m->len += len;
	while (len) {
		size_t n = 64 - m->n;

		if (n > len)
			n = len;
		memcpy(m->buf + m->n, p, n);
		m->n += n;
		p += n;
		len -= n;
		if (m->n == 64) {
			md5_block(m, m->buf);
			m->n = 0;
		}
	}
}

static void md5_final(struct md5 *m, char out[33])
{
	uint64_t bits = m->len * 8;
	uint8_t pad = 0x80, len[8];
	int i;

	md5_update(m, &pad, 1);
	pad = 0;
	while (m->n != 56)
		md5_update(m, &pad, 1);
	for (i = 0; i < 8; i++)
		len[i] = bits >> (8 * i);
	md5_update(m, len, 8);
	for (i = 0; i < 16; i++)
		sprintf(out + 2 * i, "%02x", (m->s[i / 4] >> (8 * (i % 4))) & 0xff);
	out[32] = 0;
}

/* ------------------------------------------------------------------ */
/* EGL / GLES loading                                                  */

static void *egl_lib, *gles_lib;

static void *gpa(const char *name)
{
	static PFNEGLGETPROCADDRESSPROC egl_gpa;
	void *p = NULL;

	if (gles_lib)
		p = dlsym(gles_lib, name);
	if (!p)
		p = dlsym(egl_lib, name);
	if (!p) {
		if (!egl_gpa)
			egl_gpa = (PFNEGLGETPROCADDRESSPROC)dlsym(egl_lib, "eglGetProcAddress");
		if (egl_gpa)
			p = (void *)egl_gpa(name);
	}
	if (!p)
		die("symbol %s not found", name);
	return p;
}

#define E(ret, name, args) static ret (*p_##name) args;
#define GLFN(X) \
	X(EGLDisplay, eglGetDisplay, (EGLNativeDisplayType)) \
	X(EGLBoolean, eglInitialize, (EGLDisplay, EGLint *, EGLint *)) \
	X(EGLBoolean, eglBindAPI, (EGLenum)) \
	X(EGLContext, eglCreateContext, (EGLDisplay, EGLConfig, EGLContext, const EGLint *)) \
	X(EGLBoolean, eglMakeCurrent, (EGLDisplay, EGLSurface, EGLSurface, EGLContext)) \
	X(EGLint, eglGetError, (void)) \
	X(const char *, eglQueryString, (EGLDisplay, EGLint)) \
	X(EGLImageKHR, eglCreateImageKHR, (EGLDisplay, EGLContext, EGLenum, EGLClientBuffer, const EGLint *)) \
	X(EGLBoolean, eglDestroyImageKHR, (EGLDisplay, EGLImageKHR)) \
	X(EGLBoolean, eglChooseConfig, (EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *)) \
	X(const GLubyte *, glGetString, (GLenum)) \
	X(GLenum, glGetError, (void)) \
	X(void, glGetIntegerv, (GLenum, GLint *)) \
	X(GLuint, glCreateShader, (GLenum)) \
	X(void, glShaderSource, (GLuint, GLsizei, const GLchar *const *, const GLint *)) \
	X(void, glCompileShader, (GLuint)) \
	X(void, glGetShaderiv, (GLuint, GLenum, GLint *)) \
	X(void, glGetShaderInfoLog, (GLuint, GLsizei, GLsizei *, GLchar *)) \
	X(GLuint, glCreateProgram, (void)) \
	X(void, glAttachShader, (GLuint, GLuint)) \
	X(void, glLinkProgram, (GLuint)) \
	X(void, glGetProgramiv, (GLuint, GLenum, GLint *)) \
	X(void, glGetProgramInfoLog, (GLuint, GLsizei, GLsizei *, GLchar *)) \
	X(void, glUseProgram, (GLuint)) \
	X(GLint, glGetUniformLocation, (GLuint, const GLchar *)) \
	X(void, glUniform1i, (GLint, GLint)) \
	X(void, glUniform1f, (GLint, GLfloat)) \
	X(void, glGenTextures, (GLsizei, GLuint *)) \
	X(void, glDeleteTextures, (GLsizei, const GLuint *)) \
	X(void, glBindTexture, (GLenum, GLuint)) \
	X(void, glActiveTexture, (GLenum)) \
	X(void, glTexParameteri, (GLenum, GLenum, GLint)) \
	X(void, glTexStorage2D, (GLenum, GLsizei, GLenum, GLsizei, GLsizei)) \
	X(void, glGenFramebuffers, (GLsizei, GLuint *)) \
	X(void, glBindFramebuffer, (GLenum, GLuint)) \
	X(void, glFramebufferTexture2D, (GLenum, GLenum, GLenum, GLuint, GLint)) \
	X(GLenum, glCheckFramebufferStatus, (GLenum)) \
	X(void, glViewport, (GLint, GLint, GLsizei, GLsizei)) \
	X(void, glDrawArrays, (GLenum, GLint, GLsizei)) \
	X(void, glReadPixels, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *)) \
	X(void, glPixelStorei, (GLenum, GLint)) \
	X(void, glFinish, (void)) \
	X(void, glEGLImageTargetTexture2DOES, (GLenum, GLeglImageOES))
GLFN(E)
#undef E

static void load_gl(void)
{
	if (!getenv("EGL_PLATFORM"))
		setenv("EGL_PLATFORM", "surfaceless", 1);
	egl_lib = dlopen("libEGL.so.1", RTLD_NOW | RTLD_GLOBAL);
	if (!egl_lib)
		egl_lib = dlopen("libEGL_mesa.so.0", RTLD_NOW | RTLD_GLOBAL);
	if (!egl_lib)
		die("dlopen libEGL: %s", dlerror());
	gles_lib = dlopen("libGLESv2.so.2", RTLD_NOW | RTLD_GLOBAL);
#define L(ret, name, args) p_##name = (ret (*) args)gpa(#name);
	GLFN(L)
#undef L
}

static void gl_check(const char *what)
{
	GLenum e = p_glGetError();

	if (e != GL_NO_ERROR)
		die("%s: GL error 0x%x", what, e);
}

static GLuint shader(GLenum type, const char *src)
{
	GLuint s = p_glCreateShader(type);
	GLint ok = 0;

	p_glShaderSource(s, 1, &src, NULL);
	p_glCompileShader(s);
	p_glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		char log[4096];

		p_glGetShaderInfoLog(s, sizeof(log), NULL, log);
		die("shader compile failed:\n%s", log);
	}
	return s;
}

static const char *vs_src =
	"#version 300 es\n"
	"void main() {\n"
	"  vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);\n"
	"  gl_Position = vec4(p, 0.0, 1.0);\n"
	"}\n";

/*
 * One output texel per 4 horizontally adjacent pixels:
 *   r = y0 | y1 << 10 | y2 << 20
 *   g = y3 | u01 << 10 | v01 << 20      (chroma of the pixel pair 0-1)
 *   b = u23 | v23 << 10 | flag << 20    (flag: the chroma returned for pixel
 *                                        1 (3) differs from pixel 0 (2))
 * Raw sample values: the texture is bound as a plain sampler2D, so the texture
 * unit's Y, U, V land in r, g, b with no colour conversion.
 */
static const char *fs_fmt =
	"#version 300 es\n"
	"%s\n"
	"precision highp float;\n"
	"precision highp int;\n"
	"precision highp %s;\n"
	"uniform %s tex;\n"
	"uniform float scale;\n"
	"uniform float texh;\n"
	"out uvec4 o;\n"
	"uint q(float v) { return uint(v * scale + 0.5); }\n"
	"vec4 F(int x, int y) {\n"
	"%s"
	"}\n"
	"void main() {\n"
	"  int X = int(gl_FragCoord.x) * 4, Y = int(gl_FragCoord.y);\n"
	"  vec4 p0 = F(X, Y), p1 = F(X + 1, Y), p2 = F(X + 2, Y), p3 = F(X + 3, Y);\n"
	"  uint f = (abs(p1.g - p0.g) > 1e-4 || abs(p1.b - p0.b) > 1e-4 ||\n"
	"            abs(p3.g - p2.g) > 1e-4 || abs(p3.b - p2.b) > 1e-4) ? 1u : 0u;\n"
	"  o = uvec4(q(p0.r) | q(p1.r) << 10 | q(p2.r) << 20,\n"
	"            q(p3.r) | q(p0.g) << 10 | q(p0.b) << 20,\n"
	"            q(p2.g) | q(p2.b) << 10 | f << 20, 0u);\n"
	"}\n";

/* ------------------------------------------------------------------ */
/* panfrost BO                                                         */

static int drm_fd = -1;

struct bo {
	uint32_t handle;
	size_t size;
	void *map;
	int fd;
};

static void bo_create(struct bo *b, size_t size)
{
	struct drm_panfrost_create_bo cb = { .size = size, .flags = PANFROST_BO_NOEXEC };
	struct drm_panfrost_mmap_bo mb = { 0 };
	struct drm_prime_handle ph = { 0 };

	if (ioctl(drm_fd, DRM_IOCTL_PANFROST_CREATE_BO, &cb) < 0)
		die("PANFROST_CREATE_BO(%zu): %s", size, strerror(errno));
	b->handle = cb.handle;
	b->size = size;
	mb.handle = cb.handle;
	if (ioctl(drm_fd, DRM_IOCTL_PANFROST_MMAP_BO, &mb) < 0)
		die("PANFROST_MMAP_BO: %s", strerror(errno));
	b->map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, drm_fd, mb.offset);
	if (b->map == MAP_FAILED)
		die("mmap bo: %s", strerror(errno));
	ph.handle = cb.handle;
	ph.flags = DRM_CLOEXEC | DRM_RDWR;
	if (ioctl(drm_fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, &ph) < 0)
		die("PRIME_HANDLE_TO_FD: %s", strerror(errno));
	b->fd = ph.fd;
}

static void bo_destroy(struct bo *b)
{
	struct drm_gem_close gc = { .handle = b->handle };

	munmap(b->map, b->size);
	close(b->fd);
	ioctl(drm_fd, DRM_IOCTL_GEM_CLOSE, &gc);
}

/* ------------------------------------------------------------------ */
/* AFBC header statistics (format per Linux Documentation/gpu/afbc.rst  */
/* and Mesa pan_afbc.h: 16 bytes per 16x16 superblock, u32 body offset */
/* from the buffer start, then 16 x 6-bit subblock sizes; first size 0  */
/* = solid colour, size 1 = uncompressed subblock).                     */

static void header_stats(const uint8_t *buf, size_t size, unsigned int w,
			 unsigned int h, unsigned int depth, unsigned int frame)
{
	unsigned int tw = (w + 15) / 16, th = (h + 15) / 16, i, j;
	unsigned int solid = 0, uncomp = 0, comp = 0, bad = 0, pay = depth > 8 ? 480 : 384;
	uint32_t omin = UINT32_MAX, omax = 0, endmax = 0;
	unsigned int sub_uncomp = depth > 8 ? 30 : 24; /* 4x4 subblock bytes */

	for (i = 0; i < tw * th; i++) {
		const uint8_t *hd = buf + 16 * i;
		uint32_t off = hd[0] | hd[1] << 8 | hd[2] << 16 | (uint32_t)hd[3] << 24;
		unsigned int sum = 0, first = 0;

		for (j = 0; j < 16; j++) {
			unsigned int bit = 32 + 6 * j, sz;

			sz = ((hd[bit / 8] | hd[bit / 8 + 1] << 8) >> (bit % 8)) & 0x3f;
			if (j == 0)
				first = sz;
			sum += sz == 1 ? sub_uncomp : sz;
		}
		if (first == 0) {
			solid++;
			continue;
		}
		if (sum >= pay)
			uncomp++;
		else
			comp++;
		if (off < omin)
			omin = off;
		if (off > omax)
			omax = off;
		if ((uint64_t)off + sum > endmax)
			endmax = off + sum;
		if ((uint64_t)off + sum > size)
			bad++;
	}
	printf("hdr frame %u: %ux%u superblocks, solid %u, uncompressed %u, compressed %u, "
	       "body offsets 0x%x..0x%x, end 0x%x, buffer 0x%zx, out-of-range %u\n",
	       frame, tw, th, solid, uncomp, comp, omin, omax, endmax, size, bad);
}

/* ------------------------------------------------------------------ */
/* Reference md5 list                                                  */

static char (*refs)[33];
static unsigned int nrefs;

static void load_refs(const char *path)
{
	FILE *f = fopen(path, "r");
	char line[1024];

	if (!f)
		die("%s: %s", path, strerror(errno));
	while (fgets(line, sizeof(line), f)) {
		char *p, *last = NULL, *tok;

		if (line[0] == '#')
			continue;
		/* avs2dec/davs2 "frame N ... md5 X" or ffmpeg framemd5 "0, pts, dts, dur, size, X" */
		for (tok = strtok_r(line, " ,\t\r\n", &p); tok; tok = strtok_r(NULL, " ,\t\r\n", &p))
			last = tok;
		if (!last || strlen(last) != 32)
			continue;
		if (!strncmp(line, "frame", 5) || (line[0] >= '0' && line[0] <= '9')) {
			refs = realloc(refs, (nrefs + 1) * 33);
			strcpy(refs[nrefs++], last);
		}
	}
	fclose(f);
}

/* ------------------------------------------------------------------ */

struct dump_hdr {
	char magic[8];
	uint32_t size, width, height, drm_format;
	uint64_t modifier;
	uint32_t index;
} __attribute__((packed));

enum layout { L_P010, L_YUV420P10, L_NV12, L_I420 };

static const char *layout_name[] = { "p010le", "yuv420p10le", "nv12", "i420" };

static size_t pack_frame(const uint32_t *px, unsigned int w, unsigned int h,
			 enum layout l, uint8_t *out, unsigned int *flags)
{
	unsigned int x, y, tw = w / 4;
	size_t ysz = (size_t)w * h, csz = (size_t)(w / 2) * (h / 2);
	uint16_t *y16 = (uint16_t *)out, *c16;
	uint8_t *c8;
	unsigned int fl = 0;

	for (y = 0; y < h; y++) {
		const uint32_t *row = px + (size_t)y * tw * 4;
		bool chroma_row = !(y & 1);
		unsigned int cy = y / 2;

		for (x = 0; x < tw; x++) {
			uint32_t r = row[4 * x], g = row[4 * x + 1], b = row[4 * x + 2];
			unsigned int yy[4] = { r & 1023, (r >> 10) & 1023, (r >> 20) & 1023, g & 1023 };
			unsigned int u01 = (g >> 10) & 1023, v01 = (g >> 20) & 1023;
			unsigned int u23 = b & 1023, v23 = (b >> 10) & 1023;
			unsigned int px0 = 4 * x, cx = 2 * x, k;

			fl += (b >> 20) & 1;
			switch (l) {
			case L_P010:
				for (k = 0; k < 4; k++)
					y16[(size_t)y * w + px0 + k] = yy[k] << 6;
				if (chroma_row) {
					c16 = (uint16_t *)(out + ysz * 2) + (size_t)cy * w;
					c16[2 * cx] = u01 << 6;
					c16[2 * cx + 1] = v01 << 6;
					c16[2 * cx + 2] = u23 << 6;
					c16[2 * cx + 3] = v23 << 6;
				}
				break;
			case L_YUV420P10:
				for (k = 0; k < 4; k++)
					y16[(size_t)y * w + px0 + k] = yy[k];
				if (chroma_row) {
					c16 = (uint16_t *)(out + ysz * 2) + (size_t)cy * (w / 2);
					c16[cx] = u01;
					c16[cx + 1] = u23;
					c16 = (uint16_t *)(out + ysz * 2 + csz * 2) + (size_t)cy * (w / 2);
					c16[cx] = v01;
					c16[cx + 1] = v23;
				}
				break;
			case L_NV12:
				for (k = 0; k < 4; k++)
					out[(size_t)y * w + px0 + k] = yy[k];
				if (chroma_row) {
					c8 = out + ysz + (size_t)cy * w;
					c8[2 * cx] = u01;
					c8[2 * cx + 1] = v01;
					c8[2 * cx + 2] = u23;
					c8[2 * cx + 3] = v23;
				}
				break;
			case L_I420:
				for (k = 0; k < 4; k++)
					out[(size_t)y * w + px0 + k] = yy[k];
				if (chroma_row) {
					c8 = out + ysz + (size_t)cy * (w / 2);
					c8[cx] = u01;
					c8[cx + 1] = u23;
					c8 = out + ysz + csz + (size_t)cy * (w / 2);
					c8[cx] = v01;
					c8[cx + 1] = v23;
				}
				break;
			}
		}
	}
	*flags = fl;
	return (l == L_P010 || l == L_YUV420P10) ? (ysz + 2 * csz) * 2 : ysz + 2 * csz;
}

static void usage(void)
{
	fprintf(stderr, "usage: afbc-gpu-check [-r ref] [-l layout] [-m max] [-D dir] [-d N] [-H] [-e] [-v] [-p pitch] [-M modhex] dump\n");
	exit(2);
}

int main(int argc, char **argv)
{
	const char *ref = NULL, *dumpdir = NULL, *layout_opt = NULL;
	unsigned int max_frames = 0, dump_frame = UINT32_MAX, force_pitch = 0;
	uint64_t force_mod = 0;
	bool hstats = false, external = false;
	int opt;
	FILE *in;
	EGLDisplay dpy;
	EGLContext ctx;
	GLuint prog = 0, fbo = 0, rt = 0;
	GLint loc_tex, loc_scale, loc_texh;
	unsigned int frames = 0, compared = 0, matched = 0, first_bad = UINT32_MAX;
	unsigned int cur_w = 0, cur_h = 0;
	uint8_t *raw = NULL, *lin = NULL;
	uint32_t *px = NULL;
	size_t raw_cap = 0;
	double t0 = now(), tgpu = 0, tcpu = 0;
	enum layout lay = L_P010;

	while ((opt = getopt(argc, argv, "r:l:m:D:d:Hevp:M:")) != -1) {
		switch (opt) {
		case 'r': ref = optarg; break;
		case 'l': layout_opt = optarg; break;
		case 'm': max_frames = atoi(optarg); break;
		case 'D': dumpdir = optarg; break;
		case 'd': dump_frame = atoi(optarg); break;
		case 'H': hstats = true; break;
		case 'e': external = true; break;
		case 'v': verbose++; break;
		case 'p': force_pitch = atoi(optarg); break;
		case 'M': force_mod = strtoull(optarg, NULL, 16); break;
		default: usage();
		}
	}
	if (optind + 1 != argc)
		usage();
	if (ref)
		load_refs(ref);
	in = strcmp(argv[optind], "-") ? fopen(argv[optind], "rb") : stdin;
	if (!in)
		die("%s: %s", argv[optind], strerror(errno));

	drm_fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
	if (drm_fd < 0)
		die("/dev/dri/renderD128: %s", strerror(errno));

	load_gl();
	{
		PFNEGLGETPLATFORMDISPLAYEXTPROC gpd =
			(PFNEGLGETPLATFORMDISPLAYEXTPROC)gpa("eglGetPlatformDisplayEXT");
		EGLint maj, min;
		static const EGLint cattr[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
		const char *ext;

		dpy = gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
		if (dpy == EGL_NO_DISPLAY)
			dpy = p_eglGetDisplay(EGL_DEFAULT_DISPLAY);
		if (dpy == EGL_NO_DISPLAY || !p_eglInitialize(dpy, &maj, &min))
			die("eglInitialize failed: 0x%x", p_eglGetError());
		ext = p_eglQueryString(dpy, EGL_EXTENSIONS);
		if (verbose)
			fprintf(stderr, "EGL %d.%d %s\n%s\n", maj, min,
				p_eglQueryString(dpy, EGL_VERSION), ext);
		if (!strstr(ext, "EGL_EXT_image_dma_buf_import_modifiers"))
			die("no EGL_EXT_image_dma_buf_import_modifiers");
		p_eglBindAPI(EGL_OPENGL_ES_API);
		ctx = p_eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, cattr);
		if (ctx == EGL_NO_CONTEXT)
			die("eglCreateContext failed: 0x%x", p_eglGetError());
		if (!p_eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx))
			die("eglMakeCurrent failed: 0x%x", p_eglGetError());
		fprintf(stderr, "GL_RENDERER %s, %s\n", p_glGetString(GL_RENDERER),
			p_glGetString(GL_VERSION));
	}
	{
		char *fs;
		GLuint v, f;
		GLint ok;

		if (asprintf(&fs, fs_fmt,
			     external ? "#extension GL_OES_EGL_image_external_essl3 : require" : "",
			     external ? "samplerExternalOES" : "sampler2D",
			     external ? "samplerExternalOES" : "sampler2D",
			     external ? "  return texture(tex, (vec2(x, y) + 0.5) / vec2(float(textureSize(tex, 0).x), texh));\n"
				      : "  return texelFetch(tex, ivec2(x, y), 0);\n") < 0)
			die("asprintf");
		v = shader(GL_VERTEX_SHADER, vs_src);
		f = shader(GL_FRAGMENT_SHADER, fs);
		prog = p_glCreateProgram();
		p_glAttachShader(prog, v);
		p_glAttachShader(prog, f);
		p_glLinkProgram(prog);
		p_glGetProgramiv(prog, GL_LINK_STATUS, &ok);
		if (!ok) {
			char log[4096];

			p_glGetProgramInfoLog(prog, sizeof(log), NULL, log);
			die("link failed:\n%s", log);
		}
		p_glUseProgram(prog);
		loc_tex = p_glGetUniformLocation(prog, "tex");
		loc_scale = p_glGetUniformLocation(prog, "scale");
		loc_texh = p_glGetUniformLocation(prog, "texh");
		p_glUniform1i(loc_tex, 0);
		free(fs);
	}
	p_glGenFramebuffers(1, &fbo);
	gl_check("setup");

	for (;;) {
		struct dump_hdr hd;
		unsigned int w, h, depth, pay, tw, th;
		uint32_t fmt;
		uint64_t mod;
		struct bo bo;
		EGLImageKHR img = EGL_NO_IMAGE_KHR;
		GLuint tex;
		GLenum target = external ? GL_TEXTURE_EXTERNAL_OES : GL_TEXTURE_2D;
		unsigned int pitches[6], np = 0, i, flags;
		size_t linsz;
		char sum[33];
		double ta, tb;
		const char *res;
		bool match = false;

		if (fread(&hd, sizeof(hd), 1, in) != 1)
			break;
		if (memcmp(hd.magic, "AFBCDMP1", 8))
			die("bad frame header at frame %u", frames);
		w = hd.width;
		h = hd.height;
		fmt = hd.drm_format;
		mod = force_mod ? force_mod : hd.modifier;
		if (fmt == DRM_FORMAT_YUV420_10BIT) {
			depth = 10;
			pay = 480;
		} else if (fmt == DRM_FORMAT_YUV420_8BIT) {
			depth = 8;
			pay = 384;
		} else {
			die("unexpected drm format 0x%08x", fmt);
		}
		if (frames == 0) {
			if (layout_opt) {
				for (i = 0; i < 4; i++)
					if (!strcmp(layout_opt, layout_name[i]))
						break;
				if (i == 4)
					die("unknown layout %s", layout_opt);
				lay = i;
			} else {
				lay = depth > 8 ? L_P010 : L_NV12;
			}
			printf("input: %ux%u %c%c%c%c modifier 0x%016" PRIx64 " size %u, %u-bit, layout %s, %u reference md5s\n",
			       w, h, fmt & 0xff, (fmt >> 8) & 0xff, (fmt >> 16) & 0xff, fmt >> 24,
			       mod, hd.size, depth, layout_name[lay], nrefs);
			fflush(stdout);
		}
		if (hd.size > raw_cap) {
			free(raw);
			raw = malloc(hd.size);
			if (!raw)
				die("out of memory");
			raw_cap = hd.size;
		}
		if (fread(raw, 1, hd.size, in) != hd.size)
			die("short frame %u", frames);
		if (w != cur_w || h != cur_h) {
			if (rt)
				p_glDeleteTextures(1, &rt);
			p_glGenTextures(1, &rt);
			p_glBindTexture(GL_TEXTURE_2D, rt);
			p_glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA32UI, w / 4, h);
			p_glBindFramebuffer(GL_FRAMEBUFFER, fbo);
			p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, rt, 0);
			if (p_glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
				die("FBO incomplete");
			p_glViewport(0, 0, w / 4, h);
			free(px);
			free(lin);
			px = malloc((size_t)(w / 4) * h * 16);
			lin = malloc((size_t)w * h * 3);
			if (!px || !lin)
				die("out of memory");
			cur_w = w;
			cur_h = h;
			gl_check("render target");
		}
		if (hstats || verbose > 1)
			header_stats(raw, hd.size, w, h, depth, frames);

		ta = now();
		tw = (w + 15) / 16;
		th = (h + 15) / 16;
		/* BO large enough for the VE's layout and Mesa's strict one. */
		bo_create(&bo, hd.size > (size_t)tw * th * (pay + 16) + 4096 ?
			       hd.size : (size_t)tw * th * (pay + 16) + 4096);
		memcpy(bo.map, raw, hd.size);

		/* Pitch candidates: Mesa's strict AFBC(YUV) import wants
		 * pitch * 16 to be a multiple of the uncompressed 16x16 tile
		 * payload (480 B for 10-bit, 384 B for 8-bit). */
		if (force_pitch)
			pitches[np++] = force_pitch;
		pitches[np++] = tw * pay / 16;
		pitches[np++] = w * 2;
		pitches[np++] = w * 3 / 2;
		pitches[np++] = w;
		pitches[np++] = w * 4;
		for (i = 0; i < np && img == EGL_NO_IMAGE_KHR; i++) {
			EGLint attr[] = {
				EGL_WIDTH, w, EGL_HEIGHT, h,
				EGL_LINUX_DRM_FOURCC_EXT, fmt,
				EGL_DMA_BUF_PLANE0_FD_EXT, bo.fd,
				EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0,
				EGL_DMA_BUF_PLANE0_PITCH_EXT, pitches[i],
				EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, (EGLint)(mod & 0xffffffff),
				EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, (EGLint)(mod >> 32),
				EGL_NONE
			};

			img = p_eglCreateImageKHR(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attr);
			if (img == EGL_NO_IMAGE_KHR) {
				if (verbose || frames == 0)
					fprintf(stderr, "import with pitch %u failed: EGL 0x%x\n",
						pitches[i], p_eglGetError());
			} else if (frames == 0) {
				printf("import ok: pitch %u\n", pitches[i]);
			}
		}
		if (img == EGL_NO_IMAGE_KHR)
			die("dma-buf import failed for every pitch");

		p_glGenTextures(1, &tex);
		p_glActiveTexture(GL_TEXTURE0);
		p_glBindTexture(target, tex);
		p_glEGLImageTargetTexture2DOES(target, img);
		gl_check("glEGLImageTargetTexture2DOES");
		p_glTexParameteri(target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		p_glTexParameteri(target, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		p_glTexParameteri(target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		p_glTexParameteri(target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		p_glUseProgram(prog);
		p_glUniform1f(loc_scale, depth > 8 ? 1023.0f : 255.0f);
		p_glUniform1f(loc_texh, (float)h);
		p_glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		p_glDrawArrays(GL_TRIANGLES, 0, 3);
		p_glPixelStorei(GL_PACK_ALIGNMENT, 4);
		p_glReadPixels(0, 0, w / 4, h, GL_RGBA_INTEGER, GL_UNSIGNED_INT, px);
		p_glFinish();
		gl_check("draw/readback");
		p_glDeleteTextures(1, &tex);
		p_eglDestroyImageKHR(dpy, img);
		bo_destroy(&bo);
		tb = now();
		tgpu += tb - ta;

		linsz = pack_frame(px, w, h, lay, lin, &flags);
		{
			struct md5 m;

			md5_init(&m);
			md5_update(&m, lin, linsz);
			md5_final(&m, sum);
		}
		tcpu += now() - tb;

		if (frames < nrefs) {
			compared++;
			match = !strcmp(sum, refs[frames]);
			if (match)
				matched++;
			else if (first_bad == UINT32_MAX)
				first_bad = frames;
			res = match ? "PASS" : "FAIL";
		} else {
			res = "noref";
		}
		printf("frame %u md5 %s %s chroma-pair-diff %u\n", frames, sum, res, flags);
		if (!match && frames < nrefs && verbose)
			printf("  ref %s\n", refs[frames]);
		fflush(stdout);

		if (dumpdir && ((frames < nrefs && !match && first_bad == frames) || frames == dump_frame)) {
			char path[512];
			FILE *o;

			snprintf(path, sizeof(path), "%s/frame-%u.%s", dumpdir, frames, layout_name[lay]);
			o = fopen(path, "wb");
			if (o) {
				fwrite(lin, 1, linsz, o);
				fclose(o);
				printf("  wrote %s\n", path);
			}
			snprintf(path, sizeof(path), "%s/frame-%u.afbc", dumpdir, frames);
			o = fopen(path, "wb");
			if (o) {
				fwrite(&hd, sizeof(hd), 1, o);
				fwrite(raw, 1, hd.size, o);
				fclose(o);
				printf("  wrote %s\n", path);
			}
			if (!hstats)
				header_stats(raw, hd.size, w, h, depth, frames);
		}
		frames++;
		if (max_frames && frames >= max_frames)
			break;
	}
	{
		char fb[32] = "none";

		if (first_bad != UINT32_MAX)
			snprintf(fb, sizeof(fb), "frame %u", first_bad);
		printf("done: %u frames, %u compared, %u matched, first mismatch %s, %.1f s (gpu %.2f s, cpu %.2f s)\n",
		       frames, compared, matched, fb, now() - t0, tgpu, tcpu);
	}
	return (compared && matched == compared) ? 0 : 1;
}
