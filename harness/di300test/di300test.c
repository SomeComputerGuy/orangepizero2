// SPDX-License-Identifier: MIT
/*
 * di300test: test client for the sun50i-di300 V4L2 mem2mem deinterlacer
 * (Allwinner H616 DI300).
 *
 * Reads raw frames (tightly packed, stride = width, as ffmpeg -f rawvideo
 * writes them), runs them through the deinterlacer and writes the output
 * frames, tightly packed, in dequeue order. Optional checks:
 *
 *   -c weave  every output must equal its input frame (exact field
 *             reconstruction, weave mode, no lag)
 *   -c keep   for every output, find the input frame and field whose
 *             lines appear unchanged in it (search over a few frames
 *             and both parities) and report the match: this shows the
 *             mode's lag, which input slot is output, and the field order
 *
 * -r N repeats the input N times without file output, for throughput.
 * -v prints the FMD statistics after each job (field-rate mode with -z).
 *
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

/* driver-private controls (sun50i-di300.c) */
#define CID_FMD_STATS		(V4L2_CID_USER_BASE + 0x1100)
#define CID_FMD_ENABLE		(V4L2_CID_USER_BASE + 0x1101)
#define CID_FMD_WEAVE		(V4L2_CID_USER_BASE + 0x1102)
#define CID_TNR_MODE		(V4L2_CID_USER_BASE + 0x1103)
#define CID_TNR_STRENGTH	(V4L2_CID_USER_BASE + 0x1104)
#define CID_TNR_LEVEL		(V4L2_CID_USER_BASE + 0x1105)

#define NOUT	4
#define NCAP	8

struct fmtinfo {
	const char *name;
	uint32_t fourcc;
	int c_div_w, c_div_h;	/* chroma subsampling */
	int planes;		/* 2: interleaved chroma, 3: planar */
	bool vu;		/* Cr first (NV21/NV61 order, YV12 plane order) */
};

static const struct fmtinfo fmts[] = {
	{ "nv12", V4L2_PIX_FMT_NV12, 2, 2, 2, false },
	{ "nv21", V4L2_PIX_FMT_NV21, 2, 2, 2, true },
	{ "i420", V4L2_PIX_FMT_YUV420, 2, 2, 3, false },
	{ "yv12", V4L2_PIX_FMT_YVU420, 2, 2, 3, true },
	{ "nv16", V4L2_PIX_FMT_NV16, 2, 1, 2, false },
	{ "nv61", V4L2_PIX_FMT_NV61, 2, 1, 2, true },
	{ "422p", V4L2_PIX_FMT_YUV422P, 2, 1, 3, false },
};

static const char *modes[] = { "field", "frame", "bob", "weave", "tnr" };
static const char *tnrmodes[] = { "off", "fixed", "adaptive" };

struct buf {
	void *p;
	size_t len;
};

static int fd = -1;
static struct buf obufs[NOUT], cbufs[NCAP];
static const struct fmtinfo *ifmt, *ofmt;
static unsigned int W, H, obpl, cbpl;
static bool verbose;

static void die(const char *what)
{
	fprintf(stderr, "%s: %s\n", what, strerror(errno));
	exit(1);
}

static const struct fmtinfo *find_fmt(const char *n)
{
	for (size_t i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++)
		if (!strcmp(fmts[i].name, n))
			return &fmts[i];
	fprintf(stderr, "unknown format %s\n", n);
	exit(1);
}

static int find_idx(const char *const *list, int n, const char *v)
{
	for (int i = 0; i < n; i++)
		if (!strcmp(list[i], v))
			return i;
	fprintf(stderr, "unknown value %s\n", v);
	exit(1);
}

/* packed frame size (stride = width) */
static size_t packed_size(const struct fmtinfo *f)
{
	size_t y = (size_t)W * H;

	return y + 2 * (y / (f->c_div_w * f->c_div_h));
}

/*
 * Copy between a packed frame and a V4L2 buffer with luma stride bpl
 * (planar chroma stride bpl / 2), in either direction.
 */
static void copy_frame(const struct fmtinfo *f, uint8_t *packed, uint8_t *v4l,
		       unsigned int bpl, bool to_v4l)
{
	unsigned int ch = H / f->c_div_h, cw = W / f->c_div_w;
	uint8_t *pp = packed, *vp = v4l;

#define CP(dst, src, n) memcpy(to_v4l ? (dst) : (src), to_v4l ? (src) : (dst), n)
	for (unsigned int y = 0; y < H; y++)
		CP(vp + (size_t)y * bpl, pp + (size_t)y * W, W);
	pp += (size_t)W * H;
	vp += (size_t)bpl * H;
	if (f->planes == 2) {
		for (unsigned int y = 0; y < ch; y++)
			CP(vp + (size_t)y * bpl, pp + (size_t)y * 2 * cw, 2 * cw);
	} else {
		for (unsigned int pl = 0; pl < 2; pl++) {
			for (unsigned int y = 0; y < ch; y++)
				CP(vp + (size_t)y * (bpl / 2), pp + (size_t)y * cw, cw);
			pp += (size_t)cw * ch;
			vp += (size_t)(bpl / 2) * ch;
		}
	}
#undef CP
}

static void set_ctrl(uint32_t id, int32_t v)
{
	struct v4l2_control c = { .id = id, .value = v };

	if (ioctl(fd, VIDIOC_S_CTRL, &c))
		die("VIDIOC_S_CTRL");
}

static void set_weave(uint32_t a, uint32_t b)
{
	uint32_t v[2] = { a, b };
	struct v4l2_ext_control c = { .id = CID_FMD_WEAVE, .size = sizeof(v), .p_u32 = v };
	struct v4l2_ext_controls cs = { .which = V4L2_CTRL_WHICH_CUR_VAL, .count = 1, .controls = &c };

	if (ioctl(fd, VIDIOC_S_EXT_CTRLS, &cs))
		die("FMD_WEAVE");
}

static void print_fmd(unsigned int job)
{
	uint32_t v[10];
	struct v4l2_ext_control c = { .id = CID_FMD_STATS, .size = sizeof(v), .p_u32 = v };
	struct v4l2_ext_controls cs = { .which = V4L2_CTRL_WHICH_CUR_VAL, .count = 1, .controls = &c };

	if (ioctl(fd, VIDIOC_G_EXT_CTRLS, &cs))
		return;
	printf("fmd %u: fid12 %u fid23 %u fod30 %u fod32 %u fod10 %u fod12 %u frd02 %u frd13 %u hist0 %08x hist1 %08x\n",
	       job, v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9]);
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
		    !strcmp((char *)cap.driver, "sun50i-di300")) {
			fprintf(stderr, "using %s\n", p);
			return;
		}
		close(fd);
	}
	fprintf(stderr, "no sun50i-di300 device\n");
	exit(1);
}

static void setup_queue(enum v4l2_buf_type type, struct buf *bufs, unsigned int n)
{
	struct v4l2_requestbuffers rb = { .count = n, .type = type, .memory = V4L2_MEMORY_MMAP };

	if (ioctl(fd, VIDIOC_REQBUFS, &rb) || rb.count != n)
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

static void qbuf(enum v4l2_buf_type type, unsigned int i, uint64_t ts_us)
{
	struct v4l2_buffer b = { .index = i, .type = type, .memory = V4L2_MEMORY_MMAP };

	b.timestamp.tv_sec = ts_us / 1000000;
	b.timestamp.tv_usec = ts_us % 1000000;
	if (type == V4L2_BUF_TYPE_VIDEO_OUTPUT)
		b.bytesused = obufs[i].len;
	if (ioctl(fd, VIDIOC_QBUF, &b))
		die("VIDIOC_QBUF");
}

/* returns index or -1 if nothing ready */
static int dqbuf(enum v4l2_buf_type type, struct v4l2_buffer *out)
{
	struct v4l2_buffer b = { .type = type, .memory = V4L2_MEMORY_MMAP };

	if (ioctl(fd, VIDIOC_DQBUF, &b)) {
		if (errno == EAGAIN)
			return -1;
		die("VIDIOC_DQBUF");
	}
	if (out)
		*out = b;
	return b.index;
}

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

/* -c keep: which input field survives unchanged in this output? */
static void check_keep(uint8_t **in, unsigned int nin, unsigned int out_idx,
		       const uint8_t *o, unsigned int center)
{
	int best_f = -1, best_par = -1;
	double best = -1;

	for (int f = (int)center - 2; f <= (int)center + 1; f++) {
		if (f < 0 || f >= (int)nin)
			continue;
		for (int par = 0; par < 2; par++) {
			unsigned long same = 0, tot = 0;

			for (unsigned int y = par; y < H; y += 2) {
				const uint8_t *a = in[f] + (size_t)y * W, *b = o + (size_t)y * W;

				for (unsigned int x = 0; x < W; x++)
					same += a[x] == b[x];
				tot += W;
			}
			if ((double)same / tot > best) {
				best = (double)same / tot;
				best_f = f;
				best_par = par;
			}
		}
	}
	printf("keep: out %u = in %d %s field (%.2f%% of its luma lines exact)\n",
	       out_idx, best_f, best_par ? "bottom" : "top", best * 100);
}

static void usage(void)
{
	fprintf(stderr,
		"usage: di300test -W w -H h -f fmt [-F capfmt] [-m field|frame|bob|weave|tnr]\n"
		"         [-t off|fixed|adaptive] [-s strength] [-l 0-2] [-b] [-z]\n"
		"         [-w p0,p1] [-c weave|keep] [-r repeat] [-n frames] [-d dev] [-v]\n"
		"         -i in.yuv [-o out.yuv]\n"
		"formats: nv12 nv21 i420 yv12 nv16 nv61 422p\n");
	exit(2);
}

int main(int argc, char **argv)
{
	const char *dev = NULL, *inpath = NULL, *outpath = NULL, *check = NULL;
	int mode = 0, tnr = -1, strength = -1, level = -1, opt;
	unsigned int repeat = 1, maxframes = 0, w0 = 3, w1 = 3;
	bool bff = false, fmd = false, weave_set = false;
	FILE *fin, *fout = NULL;
	struct v4l2_format f;
	uint8_t **frames;
	unsigned int nin = 0;
	size_t isz, osz;

	ifmt = ofmt = NULL;
	while ((opt = getopt(argc, argv, "W:H:f:F:m:t:s:l:bzw:c:r:n:d:i:o:v")) != -1) {
		switch (opt) {
		case 'W': W = atoi(optarg); break;
		case 'H': H = atoi(optarg); break;
		case 'f': ifmt = find_fmt(optarg); break;
		case 'F': ofmt = find_fmt(optarg); break;
		case 'm': mode = find_idx(modes, 5, optarg); break;
		case 't': tnr = find_idx(tnrmodes, 3, optarg); break;
		case 's': strength = atoi(optarg); break;
		case 'l': level = atoi(optarg); break;
		case 'b': bff = true; break;
		case 'z': fmd = true; break;
		case 'w': sscanf(optarg, "%u,%u", &w0, &w1); weave_set = true; break;
		case 'c': check = optarg; break;
		case 'r': repeat = atoi(optarg); break;
		case 'n': maxframes = atoi(optarg); break;
		case 'd': dev = optarg; break;
		case 'i': inpath = optarg; break;
		case 'o': outpath = optarg; break;
		case 'v': verbose = true; break;
		default: usage();
		}
	}
	if (!W || !H || !ifmt || !inpath)
		usage();
	if (!ofmt)
		ofmt = ifmt;

	/* load all input frames */
	isz = packed_size(ifmt);
	osz = packed_size(ofmt);
	fin = fopen(inpath, "rb");
	if (!fin)
		die(inpath);
	frames = NULL;
	for (;;) {
		uint8_t *p = malloc(isz);

		if (!p || fread(p, 1, isz, fin) != isz) {
			free(p);
			break;
		}
		frames = realloc(frames, (nin + 1) * sizeof(*frames));
		frames[nin++] = p;
		if (maxframes && nin == maxframes)
			break;
	}
	fclose(fin);
	if (!nin) {
		fprintf(stderr, "no input frames\n");
		return 1;
	}
	if (outpath && repeat == 1) {
		fout = fopen(outpath, "wb");
		if (!fout)
			die(outpath);
	}

	open_dev(dev);

	memset(&f, 0, sizeof(f));
	f.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	f.fmt.pix.width = W;
	f.fmt.pix.height = H;
	f.fmt.pix.pixelformat = ifmt->fourcc;
	f.fmt.pix.field = mode == 4 ? V4L2_FIELD_NONE :
			  bff ? V4L2_FIELD_INTERLACED_BT : V4L2_FIELD_INTERLACED_TB;
	if (ioctl(fd, VIDIOC_S_FMT, &f))
		die("S_FMT output");
	if (f.fmt.pix.width != W || f.fmt.pix.height != H || f.fmt.pix.pixelformat != ifmt->fourcc) {
		fprintf(stderr, "output format adjusted to %ux%u %.4s\n", f.fmt.pix.width,
			f.fmt.pix.height, (char *)&f.fmt.pix.pixelformat);
		return 1;
	}
	obpl = f.fmt.pix.bytesperline;

	memset(&f, 0, sizeof(f));
	f.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	f.fmt.pix.width = W;
	f.fmt.pix.height = H;
	f.fmt.pix.pixelformat = ofmt->fourcc;
	if (ioctl(fd, VIDIOC_S_FMT, &f))
		die("S_FMT capture");
	if (f.fmt.pix.pixelformat != ofmt->fourcc) {
		fprintf(stderr, "capture format %s not accepted\n", ofmt->name);
		return 1;
	}
	cbpl = f.fmt.pix.bytesperline;
	fprintf(stderr, "%ux%u %s -> %s, bytesperline %u/%u, mode %s\n", W, H,
		ifmt->name, ofmt->name, obpl, cbpl, modes[mode]);

	set_ctrl(V4L2_CID_DEINTERLACING_MODE, mode);
	if (tnr >= 0)
		set_ctrl(CID_TNR_MODE, tnr);
	if (strength >= 0)
		set_ctrl(CID_TNR_STRENGTH, strength);
	if (level >= 0)
		set_ctrl(CID_TNR_LEVEL, level);
	if (fmd)
		set_ctrl(CID_FMD_ENABLE, 1);
	if (weave_set)
		set_weave(w0, w1);

	setup_queue(V4L2_BUF_TYPE_VIDEO_OUTPUT, obufs, NOUT);
	setup_queue(V4L2_BUF_TYPE_VIDEO_CAPTURE, cbufs, NCAP);
	for (unsigned int i = 0; i < NCAP; i++)
		qbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, i, 0);

	enum v4l2_buf_type t = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	if (ioctl(fd, VIDIOC_STREAMON, &t))
		die("STREAMON output");
	t = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	if (ioctl(fd, VIDIOC_STREAMON, &t))
		die("STREAMON capture");

	unsigned int total = nin * repeat, sent = 0, done_in = 0, outs = 0, mism = 0;
	unsigned int expect_per = mode == 0 ? 2 : 1;
	bool ofree[NOUT];
	uint8_t *packed = malloc(osz > isz ? osz : isz);
	double t0 = now(), tlast = t0;

	for (unsigned int i = 0; i < NOUT; i++)
		ofree[i] = true;

	while (done_in < total) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN | POLLOUT };
		struct v4l2_buffer b;
		int i;

		/* feed */
		for (i = 0; i < NOUT && sent < total; i++) {
			if (!ofree[i])
				continue;
			copy_frame(ifmt, frames[sent % nin], obufs[i].p, obpl, true);
			/* 25 frames/s timestamps */
			qbuf(V4L2_BUF_TYPE_VIDEO_OUTPUT, i, (uint64_t)sent * 40000);
			ofree[i] = false;
			sent++;
		}
		if (poll(&pfd, 1, 2000) <= 0) {
			fprintf(stderr, "timeout: %u in sent, %u done, %u out\n", sent, done_in, outs);
			break;
		}
		while ((i = dqbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, &b)) >= 0) {
			if (b.flags & V4L2_BUF_FLAG_ERROR)
				fprintf(stderr, "capture buffer error\n");
			if (verbose)
				printf("out %u: ts %ld.%06ld seq %u\n", outs, (long)b.timestamp.tv_sec,
				       (long)b.timestamp.tv_usec, b.sequence);
			if (repeat == 1) {
				copy_frame(ofmt, packed, cbufs[i].p, cbpl, false);
				if (fout)
					fwrite(packed, 1, osz, fout);
				if (check && !strcmp(check, "weave")) {
					unsigned int src = outs / expect_per;

					if (ofmt != ifmt || memcmp(packed, frames[src], osz)) {
						size_t d = 0;

						for (size_t k = 0; k < osz && ofmt == ifmt; k++)
							d += packed[k] != frames[src][k];
						printf("weave: out %u != in %u (%zu bytes differ)\n", outs, src, d);
						mism++;
					}
				} else if (check && !strcmp(check, "keep")) {
					check_keep(frames, nin, outs, packed, outs / expect_per);
				}
			}
			outs++;
			tlast = now();
			qbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, i, 0);
		}
		while ((i = dqbuf(V4L2_BUF_TYPE_VIDEO_OUTPUT, &b)) >= 0) {
			ofree[i] = true;
			done_in++;
			if (verbose && fmd)
				print_fmd(done_in);
		}
		/* sources held as history only come back at stream off */
		if (sent == total && outs >= total * expect_per)
			break;
	}

	double el = tlast - t0;

	printf("frames in %u, out %u, %.3f s, %.1f out/s, %.1f Mpixel/s in\n", sent, outs, el,
	       el > 0 ? outs / el : 0, el > 0 ? (double)sent * W * H / el / 1e6 : 0);
	if (check && !strcmp(check, "weave"))
		printf("weave check: %s (%u mismatching frames)\n", mism ? "FAIL" : "PASS", mism);

	t = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	ioctl(fd, VIDIOC_STREAMOFF, &t);
	t = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	ioctl(fd, VIDIOC_STREAMOFF, &t);
	if (fout)
		fclose(fout);
	return mism ? 1 : 0;
}
