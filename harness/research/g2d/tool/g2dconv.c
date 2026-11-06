// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * g2dconv: test client for the sun50i-g2d V4L2 mem2mem converter.
 *
 *   g2dconv gen  FOURCC WxH out.raw [-c 601|709|2020|jpeg]
 *       write the analytic test pattern tightly packed in that format
 *       (YUV with the matrix of the given colour space, 601 limited by default)
 *   g2dconv conv [-d /dev/videoN] [-n count] [-c 601|709|2020|jpeg]
 *                -i in.raw FOURCC WxH -o out.raw FOURCC WxH
 *       convert a tightly packed frame through the device, write the result
 *       tightly packed; prints FMT/TIME/RESULT lines
 *
 * Files are tightly packed: plane 0 stride = width * bytes per pixel, chroma
 * planes follow with stride = width / hsub * bytes per chroma sample.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <linux/videodev2.h>

struct fmt {
	const char *name;
	uint32_t fourcc;
	int bpp, planes, cbpp, hsub, vsub, yuv, swap_uv;
	/* byte offsets of R, G, B, A/X in a 32/24-bit pixel (-1 = none) */
	int r, g, b, a;
};

static const struct fmt fmts[] = {
	{ "XR24", V4L2_PIX_FMT_XBGR32, 4, 1, 0, 1, 1, 0, 0, 2, 1, 0, 3 },
	{ "AR24", V4L2_PIX_FMT_ABGR32, 4, 1, 0, 1, 1, 0, 0, 2, 1, 0, 3 },
	{ "BX24", V4L2_PIX_FMT_XRGB32, 4, 1, 0, 1, 1, 0, 0, 1, 2, 3, 0 },
	{ "BA24", V4L2_PIX_FMT_ARGB32, 4, 1, 0, 1, 1, 0, 0, 1, 2, 3, 0 },
	{ "XB24", V4L2_PIX_FMT_RGBX32, 4, 1, 0, 1, 1, 0, 0, 0, 1, 2, 3 },
	{ "AB24", V4L2_PIX_FMT_RGBA32, 4, 1, 0, 1, 1, 0, 0, 0, 1, 2, 3 },
	{ "RX24", V4L2_PIX_FMT_BGRX32, 4, 1, 0, 1, 1, 0, 0, 3, 2, 1, 0 },
	{ "RA24", V4L2_PIX_FMT_BGRA32, 4, 1, 0, 1, 1, 0, 0, 3, 2, 1, 0 },
	{ "BGR3", V4L2_PIX_FMT_BGR24,  3, 1, 0, 1, 1, 0, 0, 2, 1, 0, -1 },
	{ "RGB3", V4L2_PIX_FMT_RGB24,  3, 1, 0, 1, 1, 0, 0, 0, 1, 2, -1 },
	{ "RGBP", V4L2_PIX_FMT_RGB565, 2, 1, 0, 1, 1, 0, 0, -1, -1, -1, -1 },
	{ "NV12", V4L2_PIX_FMT_NV12,   1, 2, 2, 2, 2, 1, 0 },
	{ "NV21", V4L2_PIX_FMT_NV21,   1, 2, 2, 2, 2, 1, 1 },
	{ "YU12", V4L2_PIX_FMT_YUV420, 1, 3, 1, 2, 2, 1, 0 },
	{ "YV12", V4L2_PIX_FMT_YVU420, 1, 3, 1, 2, 2, 1, 1 },
	{ "NV16", V4L2_PIX_FMT_NV16,   1, 2, 2, 2, 1, 1, 0 },
	{ "NV61", V4L2_PIX_FMT_NV61,   1, 2, 2, 2, 1, 1, 1 },
	{ "422P", V4L2_PIX_FMT_YUV422P, 1, 3, 1, 2, 1, 1, 0 },
};

static const struct fmt *find_fmt(const char *name)
{
	for (unsigned i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++)
		if (!strcmp(fmts[i].name, name))
			return &fmts[i];
	fprintf(stderr, "unknown format %s\n", name);
	exit(1);
}

static size_t tight_size(const struct fmt *f, int w, int h)
{
	size_t s = (size_t)w * f->bpp * h;

	if (f->planes > 1)
		s += (size_t)(f->planes - 1) * (w / f->hsub * f->cbpp) * (h / f->vsub);
	return s;
}

/* copy plane by plane and line by line between a tight frame and a strided one */
static void repack(const struct fmt *f, int w, int h, uint8_t *dst, size_t dst_bpl,
		   const uint8_t *src, size_t src_bpl)
{
	size_t sp = 0, dp = 0;

	for (int p = 0; p < f->planes; p++) {
		int lines = p ? h / f->vsub : h;
		size_t sbpl = p ? src_bpl / f->hsub * f->cbpp : src_bpl;
		size_t dbpl = p ? dst_bpl / f->hsub * f->cbpp : dst_bpl;
		size_t len = p ? (size_t)w / f->hsub * f->cbpp : (size_t)w * f->bpp;

		for (int y = 0; y < lines; y++)
			memcpy(dst + dp + y * dbpl, src + sp + y * sbpl, len);
		sp += sbpl * lines;
		dp += dbpl * lines;
	}
}

/* ---- the analytic pattern: smooth gradients plus a sine, in [0, 1] ---- */

static void pattern(double u, double v, double *r, double *g, double *b)
{
	*r = u;
	*g = v;
	*b = 0.5 + 0.5 * sin(2 * M_PI * (u + v));
}

struct csc { double kr, kb, ys, yo, cs; };

static struct csc csc_of(const char *name)
{
	struct csc c = { 0.299, 0.114, 219.0 / 255, 16, 224.0 / 255 };

	if (!name || !strcmp(name, "601"))
		return c;
	if (!strcmp(name, "709")) {
		c.kr = 0.2126; c.kb = 0.0722;
	} else if (!strcmp(name, "2020")) {
		c.kr = 0.2627; c.kb = 0.0593;
	} else if (!strcmp(name, "jpeg")) {
		c.ys = 1; c.yo = 0; c.cs = 1;
	} else {
		fprintf(stderr, "unknown colour space %s (601, 709, 2020, jpeg)\n", name);
		exit(1);
	}
	return c;
}

static uint32_t v4l2_colorspace(const char *name)
{
	if (!name || !strcmp(name, "601"))
		return V4L2_COLORSPACE_SMPTE170M;
	if (!strcmp(name, "709"))
		return V4L2_COLORSPACE_REC709;
	if (!strcmp(name, "2020"))
		return V4L2_COLORSPACE_BT2020;
	return V4L2_COLORSPACE_JPEG;
}

static int clamp8(double v)
{
	long x = lround(v);

	return x < 0 ? 0 : x > 255 ? 255 : x;
}

static void gen(const struct fmt *f, int w, int h, const char *path, const char *cs)
{
	struct csc c = csc_of(cs);
	double kg = 1 - c.kr - c.kb;
	size_t size = tight_size(f, w, h);
	uint8_t *buf = calloc(1, size);
	FILE *fp;

	if (!f->yuv) {
		for (int y = 0; y < h; y++)
			for (int x = 0; x < w; x++) {
				double r, g, b;
				uint8_t *px = buf + ((size_t)y * w + x) * f->bpp;

				pattern((x + 0.5) / w, (y + 0.5) / h, &r, &g, &b);
				if (f->bpp == 2) {
					uint16_t v = (clamp8(r * 255) >> 3) << 11 |
						     (clamp8(g * 255) >> 2) << 5 |
						     (clamp8(b * 255) >> 3);
					px[0] = v & 0xff;
					px[1] = v >> 8;
				} else {
					px[f->r] = clamp8(r * 255);
					px[f->g] = clamp8(g * 255);
					px[f->b] = clamp8(b * 255);
					if (f->a >= 0)
						px[f->a] = 0x5a; /* X/A byte, tells if it leaks */
				}
			}
	} else {
		int cw = w / f->hsub, ch = h / f->vsub;
		uint8_t *yp = buf, *cp = buf + (size_t)w * h;

		for (int y = 0; y < h; y++)
			for (int x = 0; x < w; x++) {
				double r, g, b;

				pattern((x + 0.5) / w, (y + 0.5) / h, &r, &g, &b);
				yp[(size_t)y * w + x] = clamp8(255 * (c.ys * (c.kr * r + kg * g + c.kb * b)) + c.yo);
			}
		for (int y = 0; y < ch; y++)
			for (int x = 0; x < cw; x++) {
				double r, g, b, yy, cb, cr;
				int u8, v8;

				/* chroma sample at the centre of its hsub x vsub block */
				pattern((x + 0.5) / cw, (y + 0.5) / ch, &r, &g, &b);
				yy = c.kr * r + kg * g + c.kb * b;
				cb = c.cs * (b - yy) / (2 * (1 - c.kb));
				cr = c.cs * (r - yy) / (2 * (1 - c.kr));
				u8 = clamp8(255 * cb + 128);
				v8 = clamp8(255 * cr + 128);
				if (f->planes == 2) {
					uint8_t *p = cp + ((size_t)y * cw + x) * 2;

					p[0] = f->swap_uv ? v8 : u8;
					p[1] = f->swap_uv ? u8 : v8;
				} else {
					size_t o = (size_t)y * cw + x, psz = (size_t)cw * ch;

					cp[o + (f->swap_uv ? psz : 0)] = u8;
					cp[o + (f->swap_uv ? 0 : psz)] = v8;
				}
			}
	}
	fp = fopen(path, "wb");
	if (!fp || fwrite(buf, 1, size, fp) != size) {
		perror(path);
		exit(1);
	}
	fclose(fp);
	printf("GEN %s %dx%d %zu bytes %s\n", f->name, w, h, size, path);
}

/* ---- V4L2 ---- */

static int xioctl(int fd, unsigned long req, void *arg)
{
	int r;

	do {
		r = ioctl(fd, req, arg);
	} while (r == -1 && errno == EINTR);
	return r;
}

static int open_device(const char *path)
{
	char name[32];
	struct v4l2_capability cap;
	int fd;

	if (path) {
		fd = open(path, O_RDWR);
		if (fd < 0)
			perror(path);
		return fd;
	}
	for (int i = 0; i < 64; i++) {
		snprintf(name, sizeof(name), "/dev/video%d", i);
		fd = open(name, O_RDWR);
		if (fd < 0)
			continue;
		if (!xioctl(fd, VIDIOC_QUERYCAP, &cap) &&
		    !strcmp((char *)cap.driver, "sun50i-g2d")) {
			printf("DEVICE %s\n", name);
			return fd;
		}
		close(fd);
	}
	fprintf(stderr, "no sun50i-g2d device found\n");
	return -1;
}

static void print_fmt(const char *tag, const struct fmt *f, const struct v4l2_pix_format *p)
{
	printf("FMT %s %s %u %u bpl %u size %u cs %u enc %u quant %u\n", tag, f->name,
	       p->width, p->height, p->bytesperline, p->sizeimage, p->colorspace,
	       p->ycbcr_enc, p->quantization);
}

static int set_fmt(int fd, uint32_t type, const struct fmt *f, int w, int h, uint32_t cs,
		   struct v4l2_pix_format *out)
{
	struct v4l2_format fmt = { .type = type };

	fmt.fmt.pix.pixelformat = f->fourcc;
	fmt.fmt.pix.width = w;
	fmt.fmt.pix.height = h;
	fmt.fmt.pix.field = V4L2_FIELD_NONE;
	fmt.fmt.pix.colorspace = cs;
	if (xioctl(fd, VIDIOC_S_FMT, &fmt)) {
		perror("S_FMT");
		return -1;
	}
	*out = fmt.fmt.pix;
	print_fmt(type == V4L2_BUF_TYPE_VIDEO_OUTPUT ? "OUT" : "CAP", f, out);
	if (out->pixelformat != f->fourcc || (int)out->width != w || (int)out->height != h) {
		fprintf(stderr, "driver changed the format\n");
		return -1;
	}
	return 0;
}

static void *map_buf(int fd, uint32_t type, uint32_t *len)
{
	struct v4l2_requestbuffers req = { .count = 1, .type = type, .memory = V4L2_MEMORY_MMAP };
	struct v4l2_buffer buf = { .type = type, .memory = V4L2_MEMORY_MMAP, .index = 0 };
	void *p;

	if (xioctl(fd, VIDIOC_REQBUFS, &req) || xioctl(fd, VIDIOC_QUERYBUF, &buf)) {
		perror("REQBUFS/QUERYBUF");
		return NULL;
	}
	p = mmap(NULL, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, buf.m.offset);
	if (p == MAP_FAILED) {
		perror("mmap");
		return NULL;
	}
	*len = buf.length;
	return p;
}

static double now_us(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1e6 + ts.tv_nsec / 1e3;
}

static int conv(int argc, char **argv)
{
	const char *dev = NULL, *in = NULL, *out = NULL, *cs = NULL;
	const struct fmt *fi = NULL, *fo = NULL;
	int wi = 0, hi = 0, wo = 0, ho = 0, n = 1, fd, ret = 1;
	struct v4l2_pix_format pi, po;
	uint8_t *tight_in, *tight_out, *bo, *bc;
	uint32_t lo, lc;
	size_t isz, osz;
	FILE *fp;
	double t0, tsum = 0, tmin = 1e12, tmax = 0;
	uint32_t type_o = V4L2_BUF_TYPE_VIDEO_OUTPUT, type_c = V4L2_BUF_TYPE_VIDEO_CAPTURE;

	for (int i = 0; i < argc; i++) {
		if (!strcmp(argv[i], "-d") && i + 1 < argc)
			dev = argv[++i];
		else if (!strcmp(argv[i], "-n") && i + 1 < argc)
			n = atoi(argv[++i]);
		else if (!strcmp(argv[i], "-c") && i + 1 < argc)
			cs = argv[++i];
		else if (!strcmp(argv[i], "-i") && i + 3 < argc) {
			in = argv[++i];
			fi = find_fmt(argv[++i]);
			sscanf(argv[++i], "%dx%d", &wi, &hi);
		} else if (!strcmp(argv[i], "-o") && i + 3 < argc) {
			out = argv[++i];
			fo = find_fmt(argv[++i]);
			sscanf(argv[++i], "%dx%d", &wo, &ho);
		} else {
			fprintf(stderr, "bad argument %s\n", argv[i]);
			return 1;
		}
	}
	if (!in || !out || !wi || !hi || !wo || !ho) {
		fprintf(stderr, "conv: -i in FOURCC WxH -o out FOURCC WxH needed\n");
		return 1;
	}
	csc_of(cs); /* validates the name */

	isz = tight_size(fi, wi, hi);
	osz = tight_size(fo, wo, ho);
	tight_in = malloc(isz);
	tight_out = calloc(1, osz);
	fp = fopen(in, "rb");
	if (!fp || fread(tight_in, 1, isz, fp) != isz) {
		fprintf(stderr, "cannot read %zu bytes from %s\n", isz, in);
		return 1;
	}
	fclose(fp);

	fd = open_device(dev);
	if (fd < 0)
		return 1;
	if (set_fmt(fd, type_o, fi, wi, hi, v4l2_colorspace(cs), &pi) ||
	    set_fmt(fd, type_c, fo, wo, ho, v4l2_colorspace(cs), &po))
		goto out;
	bo = map_buf(fd, type_o, &lo);
	bc = map_buf(fd, type_c, &lc);
	if (!bo || !bc)
		goto out;
	repack(fi, wi, hi, bo, pi.bytesperline, tight_in, (size_t)wi * fi->bpp);

	if (xioctl(fd, VIDIOC_STREAMON, &type_o) || xioctl(fd, VIDIOC_STREAMON, &type_c)) {
		perror("STREAMON");
		goto out;
	}

	for (int it = 0; it < n; it++) {
		struct v4l2_buffer qo = { .type = type_o, .memory = V4L2_MEMORY_MMAP, .index = 0,
					  .bytesused = pi.sizeimage, .field = V4L2_FIELD_NONE };
		struct v4l2_buffer qc = { .type = type_c, .memory = V4L2_MEMORY_MMAP, .index = 0 };
		struct pollfd pfd = { .fd = fd, .events = POLLIN };
		double dt;
		int pr;

		memset(bc, 0x11, lc);
		t0 = now_us();
		if (xioctl(fd, VIDIOC_QBUF, &qc) || xioctl(fd, VIDIOC_QBUF, &qo)) {
			perror("QBUF");
			goto streamoff;
		}
		pr = poll(&pfd, 1, 2000);
		if (pr <= 0) {
			printf("RESULT rc 1 reason TIMEOUT iteration %d\n", it);
			goto streamoff;
		}
		if (xioctl(fd, VIDIOC_DQBUF, &qc)) {
			perror("DQBUF capture");
			goto streamoff;
		}
		dt = now_us() - t0;
		if (xioctl(fd, VIDIOC_DQBUF, &qo)) {
			perror("DQBUF output");
			goto streamoff;
		}
		if (qc.flags & V4L2_BUF_FLAG_ERROR) {
			printf("RESULT rc 1 reason BUFERR iteration %d\n", it);
			goto streamoff;
		}
		tsum += dt;
		if (dt < tmin)
			tmin = dt;
		if (dt > tmax)
			tmax = dt;
	}
	repack(fo, wo, ho, tight_out, (size_t)wo * fo->bpp, bc, po.bytesperline);
	fp = fopen(out, "wb");
	if (!fp || fwrite(tight_out, 1, osz, fp) != osz) {
		perror(out);
		goto streamoff;
	}
	fclose(fp);
	printf("TIME n %d avg_us %.0f min_us %.0f max_us %.0f\n", n, tsum / n, tmin, tmax);
	printf("RESULT rc 0\n");
	ret = 0;
streamoff:
	xioctl(fd, VIDIOC_STREAMOFF, &type_o);
	xioctl(fd, VIDIOC_STREAMOFF, &type_c);
out:
	close(fd);
	return ret;
}

int main(int argc, char **argv)
{
	if (argc >= 5 && !strcmp(argv[1], "gen")) {
		const struct fmt *f = find_fmt(argv[2]);
		int w = 0, h = 0;
		const char *cs = NULL;

		sscanf(argv[3], "%dx%d", &w, &h);
		if (argc >= 7 && !strcmp(argv[5], "-c"))
			cs = argv[6];
		if (w <= 0 || h <= 0) {
			fprintf(stderr, "bad size %s\n", argv[3]);
			return 1;
		}
		gen(f, w, h, argv[4], cs);
		return 0;
	}
	if (argc >= 2 && !strcmp(argv[1], "conv"))
		return conv(argc - 2, argv + 2);
	fprintf(stderr, "usage: g2dconv gen FOURCC WxH out.raw [-c 601|709|2020|jpeg]\n"
			"       g2dconv conv [-d dev] [-n count] [-c cs] -i in FOURCC WxH -o out FOURCC WxH\n");
	return 1;
}
