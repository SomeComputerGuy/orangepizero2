// SPDX-License-Identifier: MIT
/*
 * jpegtest: test client for the cedrus V4L2 JPEG decoder (Allwinner VE,
 * MPEG-engine JPEG path).
 *
 *   jpegtest [-d /dev/videoN] [-f nv12|nv21|yu12|yv12|tiled] [-n N]
 *            [-o out.yuv] in.jpg
 *
 * Takes the picture size from the file's SOF segment, sets the OUTPUT
 * format to JPEG at that size and the CAPTURE format as given, decodes
 * the file N times (default 1) and writes the last output, cropped to
 * the picture size and tightly packed, to out.yuv:
 *
 *   nv12/nv21  Y plane then interleaved chroma (ffmpeg -pix_fmt nv12/nv21)
 *   yu12/yv12  Y, then U and V (yu12) or V and U (yv12) planes
 *   tiled      the raw capture buffer (32x32 tiled NV12), uncropped
 *
 * Prints the time per decode and the throughput in megapixels per second
 * (MPPS, picture pixels / wall time, including the ioctl round trip).
 * Exit status 0 when every decode finished without the error flag.
 *
 * No requests are used: the driver parses the JPEG headers itself.
 * Build: make (aarch64) in this directory.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <linux/videodev2.h>

#define NOUT	2
#define NCAP	2

struct buf {
	void *p;
	size_t len;
};

struct fmtinfo {
	const char *name;
	uint32_t fourcc;
	int layout;		/* 2: interleaved chroma, 3: planar, 0: raw */
};

static const struct fmtinfo fmts[] = {
	{ "nv12", V4L2_PIX_FMT_NV12, 2 },
	{ "nv21", V4L2_PIX_FMT_NV21, 2 },
	{ "yu12", V4L2_PIX_FMT_YUV420, 3 },
	{ "yv12", V4L2_PIX_FMT_YVU420, 3 },
	{ "tiled", V4L2_PIX_FMT_NV12_32L32, 0 },
};

static int fd = -1;
static struct buf obufs[NOUT], cbufs[NCAP];

static void die(const char *what)
{
	perror(what);
	exit(1);
}

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

/* Size from the first SOF0..SOF15 marker (not DHT/JPG/DAC). */
static int jpeg_size(const uint8_t *p, size_t n, unsigned int *w, unsigned int *h)
{
	size_t i = 2;

	if (n < 4 || p[0] != 0xff || p[1] != 0xd8)
		return -1;
	while (i + 4 <= n) {
		unsigned int m, len;

		if (p[i] != 0xff) {
			i++;
			continue;
		}
		m = p[i + 1];
		if (m == 0xff) {
			i++;
			continue;
		}
		if (m == 0xd8 || m == 0x01 || (m >= 0xd0 && m <= 0xd7)) {
			i += 2;
			continue;
		}
		len = p[i + 2] << 8 | p[i + 3];
		if (m >= 0xc0 && m <= 0xcf && m != 0xc4 && m != 0xc8 &&
		    m != 0xcc) {
			if (i + 9 > n)
				return -1;
			*h = p[i + 5] << 8 | p[i + 6];
			*w = p[i + 7] << 8 | p[i + 8];
			return 0;
		}
		if (m == 0xda)
			return -1;
		i += 2 + len;
	}
	return -1;
}

static void open_dev(const char *path)
{
	struct v4l2_capability cap;
	char p[32];

	if (path) {
		fd = open(path, O_RDWR | O_NONBLOCK);
		if (fd < 0)
			die(path);
		return;
	}
	for (int i = 0; i < 64; i++) {
		snprintf(p, sizeof(p), "/dev/video%d", i);
		fd = open(p, O_RDWR | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (!ioctl(fd, VIDIOC_QUERYCAP, &cap) &&
		    !strcmp((char *)cap.driver, "cedrus")) {
			fprintf(stderr, "using %s\n", p);
			return;
		}
		close(fd);
	}
	fprintf(stderr, "no cedrus device\n");
	exit(1);
}

static void setup_queue(enum v4l2_buf_type type, struct buf *bufs, unsigned int n)
{
	struct v4l2_requestbuffers rb = { .count = n, .type = type, .memory = V4L2_MEMORY_MMAP };

	if (ioctl(fd, VIDIOC_REQBUFS, &rb) || rb.count < n)
		die("VIDIOC_REQBUFS");
	for (unsigned int i = 0; i < n; i++) {
		struct v4l2_buffer b = { .index = i, .type = type, .memory = V4L2_MEMORY_MMAP };

		if (ioctl(fd, VIDIOC_QUERYBUF, &b))
			die("VIDIOC_QUERYBUF");
		bufs[i].len = b.length;
		bufs[i].p = mmap(NULL, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, b.m.offset);
		if (bufs[i].p == MAP_FAILED)
			die("mmap");
	}
}

static void qbuf(enum v4l2_buf_type type, unsigned int i, unsigned int bytesused)
{
	struct v4l2_buffer b = { .index = i, .type = type, .memory = V4L2_MEMORY_MMAP };

	b.bytesused = bytesused;
	if (ioctl(fd, VIDIOC_QBUF, &b))
		die("VIDIOC_QBUF");
}

static int dqbuf(enum v4l2_buf_type type, struct v4l2_buffer *out)
{
	struct v4l2_buffer b = { .type = type, .memory = V4L2_MEMORY_MMAP };

	for (;;) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN | POLLOUT };

		if (!ioctl(fd, VIDIOC_DQBUF, &b))
			break;
		if (errno != EAGAIN)
			die("VIDIOC_DQBUF");
		if (poll(&pfd, 1, 2000) <= 0) {
			fprintf(stderr, "timeout waiting for %s buffer\n",
				type == V4L2_BUF_TYPE_VIDEO_OUTPUT ? "OUTPUT" : "CAPTURE");
			exit(1);
		}
	}
	if (out)
		*out = b;
	return b.index;
}

static void write_out(const char *path, const struct fmtinfo *f, const uint8_t *p,
		      const struct v4l2_pix_format *pix, unsigned int w, unsigned int h)
{
	FILE *o = fopen(path, "wb");
	unsigned int bpl = pix->bytesperline;
	unsigned int ah = (pix->height + 15) & ~15u;	/* cedrus: 16-aligned planes */
	const uint8_t *c = p + (size_t)bpl * ah;
	unsigned int cw = (w + 1) / 2, ch = (h + 1) / 2;

	if (!o)
		die(path);
	if (!f->layout) {
		fwrite(p, 1, pix->sizeimage, o);
		fclose(o);
		return;
	}
	for (unsigned int y = 0; y < h; y++)
		fwrite(p + (size_t)y * bpl, 1, w, o);
	if (f->layout == 2) {
		for (unsigned int y = 0; y < ch; y++)
			fwrite(c + (size_t)y * bpl, 1, 2 * cw, o);
	} else {
		for (int pl = 0; pl < 2; pl++) {
			const uint8_t *q = c + (size_t)pl * (bpl / 2) * (ah / 2);

			for (unsigned int y = 0; y < ch; y++)
				fwrite(q + (size_t)y * (bpl / 2), 1, cw, o);
		}
	}
	fclose(o);
}

static void usage(void)
{
	fprintf(stderr, "usage: jpegtest [-d dev] [-f nv12|nv21|yu12|yv12|tiled] [-n N] [-o out.yuv]\n"
		"                [-r raw.bin] [-F fillbyte] in.jpg\n");
	exit(2);
}

int main(int argc, char **argv)
{
	const struct fmtinfo *f = &fmts[0];
	const char *dev = NULL, *outp = NULL;
	struct v4l2_format of = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT };
	struct v4l2_format cf = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE };
	enum v4l2_buf_type t;
	unsigned int n = 1, w, h, errors = 0, last = 0;
	uint8_t *jpg;
	size_t jlen;
	const char *rawp = NULL;
	int fill = -1;
	double t0, dt;
	FILE *in;
	int c;

	while ((c = getopt(argc, argv, "d:f:n:o:r:F:")) != -1) {
		switch (c) {
		case 'r': rawp = optarg; break;
		case 'F': fill = strtol(optarg, NULL, 0); break;
		case 'd': dev = optarg; break;
		case 'n': n = strtoul(optarg, NULL, 0); break;
		case 'o': outp = optarg; break;
		case 'f':
			f = NULL;
			for (unsigned int i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++)
				if (!strcmp(fmts[i].name, optarg))
					f = &fmts[i];
			if (!f)
				usage();
			break;
		default: usage();
		}
	}
	if (optind + 1 != argc || !n)
		usage();

	in = fopen(argv[optind], "rb");
	if (!in)
		die(argv[optind]);
	fseek(in, 0, SEEK_END);
	jlen = ftell(in);
	rewind(in);
	jpg = malloc(jlen);
	if (!jpg || fread(jpg, 1, jlen, in) != jlen)
		die("read");
	fclose(in);
	if (jpeg_size(jpg, jlen, &w, &h)) {
		fprintf(stderr, "no SOF segment\n");
		return 1;
	}

	open_dev(dev);

	of.fmt.pix.pixelformat = V4L2_PIX_FMT_JPEG;
	of.fmt.pix.width = w;
	of.fmt.pix.height = h;
	of.fmt.pix.sizeimage = jlen + 4096;
	if (ioctl(fd, VIDIOC_S_FMT, &of))
		die("S_FMT OUTPUT (JPEG)");
	if (of.fmt.pix.pixelformat != V4L2_PIX_FMT_JPEG) {
		fprintf(stderr, "driver has no JPEG OUTPUT format\n");
		return 1;
	}
	cf.fmt.pix.pixelformat = f->fourcc;
	cf.fmt.pix.width = w;
	cf.fmt.pix.height = h;
	if (ioctl(fd, VIDIOC_S_FMT, &cf))
		die("S_FMT CAPTURE");
	if (cf.fmt.pix.pixelformat != f->fourcc) {
		fprintf(stderr, "CAPTURE format %s not supported\n", f->name);
		return 1;
	}
	fprintf(stderr, "%ux%u, %zu bytes; capture %s %ux%u bpl %u size %u\n",
		w, h, jlen, f->name, cf.fmt.pix.width, cf.fmt.pix.height,
		cf.fmt.pix.bytesperline, cf.fmt.pix.sizeimage);

	setup_queue(V4L2_BUF_TYPE_VIDEO_OUTPUT, obufs, NOUT);
	setup_queue(V4L2_BUF_TYPE_VIDEO_CAPTURE, cbufs, NCAP);
	/* -F: pre-fill the capture buffers to see which bytes the engine writes */
	if (fill >= 0)
		for (unsigned int i = 0; i < NCAP; i++)
			memset(cbufs[i].p, fill, cbufs[i].len);
	for (unsigned int i = 0; i < NOUT; i++) {
		if (obufs[i].len < jlen) {
			fprintf(stderr, "OUTPUT buffer too small (%zu)\n", obufs[i].len);
			return 1;
		}
		memcpy(obufs[i].p, jpg, jlen);
	}

	t = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	if (ioctl(fd, VIDIOC_STREAMON, &t))
		die("STREAMON OUTPUT");
	t = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	if (ioctl(fd, VIDIOC_STREAMON, &t))
		die("STREAMON CAPTURE");

	/* Keep two jobs in flight. */
	t0 = now();
	unsigned int queued = 0, done = 0;

	for (; queued < n && queued < NOUT; queued++) {
		qbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, queued, 0);
		qbuf(V4L2_BUF_TYPE_VIDEO_OUTPUT, queued, jlen);
	}
	while (done < n) {
		struct v4l2_buffer cb, ob;

		dqbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, &cb);
		dqbuf(V4L2_BUF_TYPE_VIDEO_OUTPUT, &ob);
		if (cb.flags & V4L2_BUF_FLAG_ERROR)
			errors++;
		last = cb.index;
		done++;
		if (queued < n) {
			qbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, cb.index, 0);
			qbuf(V4L2_BUF_TYPE_VIDEO_OUTPUT, ob.index, jlen);
			queued++;
		}
	}
	dt = now() - t0;

	printf("%u decodes, %u errors, %.3f ms each, %.1f MPPS\n", n, errors,
	       dt * 1e3 / n, (double)w * h * n / dt / 1e6);

	if (outp)
		write_out(outp, f, cbufs[last].p, &cf.fmt.pix, w, h);
	if (rawp) {
		/* -r: the whole capture buffer, as the engine left it */
		FILE *r = fopen(rawp, "wb");

		if (!r)
			die(rawp);
		fwrite(cbufs[last].p, 1, cbufs[last].len, r);
		fclose(r);
	}

	return errors ? 1 : 0;
}
