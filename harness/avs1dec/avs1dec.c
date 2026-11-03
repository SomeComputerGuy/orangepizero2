// SPDX-License-Identifier: MIT
/*
 * avs1dec: AVS1 (GB/T 20090.2 JiZhun) and AVS+ (GY/T 257.1 Guangdian) test
 * decoder for the V4L2 stateless AVS uAPI (V4L2_PIX_FMT_AVS_FRAME) of the
 * cedrus driver on the Allwinner H616.
 *
 * Usage:
 *   avs1dec [options] stream          decode through /dev/videoN
 *   avs1dec --dry-run [-v] stream     parse only, no device (host test)
 *
 * Options:
 *   -d DEV       video device (default /dev/video0)
 *   -m DEV       media device (default /dev/media0)
 *   -t es|ts|ps  input container (default: detected)
 *   -o FILE      write the pictures as I420, cropped, in display order
 *   -c FILE      FFmpeg framecrc compatible adler32 lines ("-" = stdout)
 *   -5 FILE      FFmpeg framemd5 compatible md5 lines ("-" = stdout)
 *   -n N         number of capture buffers (default 6)
 *   -l N         stop after N pictures (decode order)
 *   -T           tiled NV12_32L32 capture (de-tiled for the checksums)
 *   -H           start the VLD 4 bytes after the picture start code, as
 *                the vendor library does, instead of at the first slice
 *   -v           verbose
 *   --dry-run    no device: print the controls of every picture, the
 *                display order and a summary
 *
 * The total md5 of the I420 output is printed at the end.
 *
 * Clean-room: written from the syntax summary in
 * harness/research/avs1/syntax.md and the uAPI in
 * include/uapi/linux/v4l2-controls.h. No code was copied from FFmpeg,
 * Rockchip MPP or the vendor library. MD5 follows RFC 1321, adler32
 * RFC 1950. The MD5, bit reader and V4L2 request code are our own, from
 * harness/avs2dec.
 */

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <poll.h>
#include <time.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <linux/media.h>
#include <linux/videodev2.h>

#define MAX_BUFS	32
#define NUM_OUT_BUFS	2

static int verbose;

static void die(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	fprintf(stderr, "avs1dec: ");
	vfprintf(stderr, fmt, ap);
	fprintf(stderr, "\n");
	va_end(ap);
	exit(1);
}

/* ------------------------------------------------------------------ */
/* MD5 (RFC 1321)                                                     */

struct md5 {
	uint32_t h[4];
	uint64_t len;
	uint8_t buf[64];
	unsigned int fill;
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
	m->h[0] = 0x67452301;
	m->h[1] = 0xefcdab89;
	m->h[2] = 0x98badcfe;
	m->h[3] = 0x10325476;
	m->len = 0;
	m->fill = 0;
}

static void md5_block(struct md5 *m, const uint8_t *p)
{
	uint32_t w[16], a = m->h[0], b = m->h[1], c = m->h[2], d = m->h[3];
	unsigned int i;

	for (i = 0; i < 16; i++)
		w[i] = p[4 * i] | p[4 * i + 1] << 8 | p[4 * i + 2] << 16 |
		       (uint32_t)p[4 * i + 3] << 24;

	for (i = 0; i < 64; i++) {
		uint32_t f, t;
		unsigned int g;

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
		t = d;
		d = c;
		c = b;
		f += a + md5_k[i] + w[g];
		b += (f << md5_r[i]) | (f >> (32 - md5_r[i]));
		a = t;
	}

	m->h[0] += a;
	m->h[1] += b;
	m->h[2] += c;
	m->h[3] += d;
}

static void md5_update(struct md5 *m, const void *data, size_t len)
{
	const uint8_t *p = data;

	m->len += len;
	while (len) {
		size_t n = 64 - m->fill;

		if (n > len)
			n = len;
		memcpy(m->buf + m->fill, p, n);
		m->fill += n;
		p += n;
		len -= n;
		if (m->fill == 64) {
			md5_block(m, m->buf);
			m->fill = 0;
		}
	}
}

static void md5_final(struct md5 *m, char out[33])
{
	uint64_t bits = m->len * 8;
	uint8_t pad = 0x80, len[8];
	unsigned int i;

	md5_update(m, &pad, 1);
	pad = 0;
	while (m->fill != 56)
		md5_update(m, &pad, 1);
	for (i = 0; i < 8; i++)
		len[i] = bits >> (8 * i);
	md5_update(m, len, 8);

	for (i = 0; i < 16; i++)
		sprintf(out + 2 * i, "%02x", (m->h[i / 4] >> (8 * (i % 4))) & 0xff);
}

/* ------------------------------------------------------------------ */
/* Bit reader over a header unit, with pseudo start code removal       */


struct bits {
	uint8_t *buf;		/* copy without the pseudo start code bits */
	size_t nbits;
	size_t pos;
	bool overrun;
};

/*
 * Annex A: wherever the encoder would emulate a start code prefix, the
 * byte after two zero bytes reads 0x02, whose two least significant bits
 * are stuffing. Drop them from this copy only; the OUTPUT buffer keeps
 * the raw bytes (the engine removes them from the slice data).
 */
static void bits_init(struct bits *b, const uint8_t *p, size_t len,
		      unsigned int *removed)
{
	size_t i, out = 0;
	unsigned int zeros = 0;

	b->buf = calloc(len + 8, 1);
	if (!b->buf)
		die("out of memory");

	for (i = 0; i < len; i++) {
		unsigned int n = 8, v = p[i];

		if (zeros >= 2 && v == 0x02) {
			n = 6;
			v >>= 2;
			zeros = 0;
			if (removed)
				(*removed)++;
		} else {
			zeros = v ? 0 : zeros + 1;
		}

		while (n--) {
			if (v & (1u << n))
				b->buf[out >> 3] |= 0x80 >> (out & 7);
			out++;
		}
	}

	b->nbits = out;
	b->pos = 0;
	b->overrun = false;
}

static void bits_free(struct bits *b)
{
	free(b->buf);
	b->buf = NULL;
}

static uint32_t u(struct bits *b, unsigned int n)
{
	uint32_t v = 0;

	while (n--) {
		if (b->pos >= b->nbits) {
			b->overrun = true;
			v <<= 1;
			continue;
		}
		v = v << 1 | ((b->buf[b->pos >> 3] >> (7 - (b->pos & 7))) & 1);
		b->pos++;
	}

	return v;
}

static uint32_t peek(struct bits *b, unsigned int n)
{
	size_t pos = b->pos;
	bool overrun = b->overrun;
	uint32_t v = u(b, n);

	b->pos = pos;
	b->overrun = overrun;
	return v;
}

static uint32_t ue(struct bits *b)
{
	unsigned int lz = 0;

	while (!u(b, 1)) {
		if (b->overrun || ++lz > 31) {
			b->overrun = true;
			return 0;
		}
	}

	return (1u << lz) - 1 + u(b, lz);
}

static int32_t se(struct bits *b)
{
	uint32_t v = ue(b);

	return v & 1 ? (int32_t)((v + 1) / 2) : -(int32_t)(v / 2);
}

/* ------------------------------------------------------------------ */
/* adler32 (RFC 1950), as FFmpeg's framecrc prints it                  */

struct adler {
	uint32_t a, b;
};

static void adler_init(struct adler *s)
{
	/* FFmpeg's framecrc seeds av_adler32_update() with 0, not RFC 1950's 1 */
	s->a = 0;
	s->b = 0;
}

static void adler_update(struct adler *s, const uint8_t *p, size_t n)
{
	while (n) {
		size_t k = n < 5552 ? n : 5552;

		n -= k;
		while (k--) {
			s->a += *p++;
			s->b += s->a;
		}
		s->a %= 65521;
		s->b %= 65521;
	}
}

static uint32_t adler_final(struct adler *s)
{
	return s->b << 16 | s->a;
}

/* ------------------------------------------------------------------ */
/* Containers                                                          */

struct buf {
	uint8_t *p;
	size_t len, cap;
};

static void buf_put(struct buf *b, const uint8_t *p, size_t n)
{
	if (b->len + n > b->cap) {
		b->cap = (b->len + n) * 2 + 4096;
		b->p = realloc(b->p, b->cap);
		if (!b->p)
			die("out of memory");
	}
	memcpy(b->p + b->len, p, n);
	b->len += n;
}

/* Payload of a PES packet starting at p (00 00 01 sid), or NULL. */
static const uint8_t *pes_payload(const uint8_t *p, size_t n, size_t *len)
{
	size_t o;

	if (n < 9)
		return NULL;
	if ((p[6] & 0xc0) == 0x80) {
		/* MPEG-2 PES header */
		o = 9 + p[8];
	} else {
		/* MPEG-1: stuffing, STD buffer, PTS/DTS */
		o = 6;
		while (o < n && p[o] == 0xff)
			o++;
		if (o < n && (p[o] & 0xc0) == 0x40)
			o += 2;
		if (o < n && (p[o] & 0xf0) == 0x20)
			o += 5;
		else if (o < n && (p[o] & 0xf0) == 0x30)
			o += 10;
		else
			o++;
	}
	if (o > n)
		return NULL;
	*len = n - o;
	return p + o;
}

/* The first video PID's PES payloads (MPEG-TS, 188 byte packets). */
static void ts_to_es(const uint8_t *d, size_t n, struct buf *es)
{
	int pid = -1;
	bool in_pes = false;
	size_t i;

	for (i = 0; i + 188 <= n; i += 188) {
		const uint8_t *p = d + i;
		unsigned int pp, afc;
		size_t o = 4, len;
		const uint8_t *pl;

		if (p[0] != 0x47)
			die("lost TS sync at %zu", i);
		pp = (p[1] & 0x1f) << 8 | p[2];
		afc = (p[3] >> 4) & 3;
		if (afc & 2)
			o += 1 + p[4];
		if (!(afc & 1) || o >= 188)
			continue;
		pl = p + o;
		len = 188 - o;

		if ((p[1] & 0x40) && len >= 4 && !pl[0] && !pl[1] &&
		    pl[2] == 1 && pl[3] >= 0xe0 && pl[3] <= 0xef) {
			if (pid < 0)
				pid = pp;
			if ((int)pp != pid)
				continue;
			pl = pes_payload(pl, len, &len);
			in_pes = pl != NULL;
			if (!pl)
				continue;
		} else if ((int)pp != pid || !in_pes) {
			continue;
		}
		buf_put(es, pl, len);
	}
}

/* Video PES payloads of an MPEG program stream. */
static void ps_to_es(const uint8_t *d, size_t n, struct buf *es)
{
	size_t i = 0;

	while (i + 4 <= n) {
		unsigned int c;
		size_t len;

		if (d[i] || d[i + 1] || d[i + 2] != 1) {
			i++;
			continue;
		}
		c = d[i + 3];
		if (c == 0xba) {
			if (i + 14 > n)
				break;
			if ((d[i + 4] & 0xc0) == 0x40)
				i += 14 + (d[i + 13] & 7);	/* MPEG-2 */
			else
				i += 12;			/* MPEG-1 */
			continue;
		}
		if (c == 0xb9)
			break;
		if (c < 0xbb) {
			i++;
			continue;
		}
		if (i + 6 > n)
			break;
		len = (size_t)d[i + 4] << 8 | d[i + 5];
		if (i + 6 + len > n)
			len = n - i - 6;
		if (c >= 0xe0 && c <= 0xef) {
			size_t plen;
			const uint8_t *pl = pes_payload(d + i, 6 + len, &plen);

			if (pl)
				buf_put(es, pl, plen);
		}
		i += 6 + len;
	}
}

/* ------------------------------------------------------------------ */
/* Headers (harness/research/avs1/syntax.md)                           */

#define SC_SLICE_MAX	0xaf
#define SC_SEQ_START	0xb0
#define SC_SEQ_END	0xb1
#define SC_USER_DATA	0xb2
#define SC_I_PICTURE	0xb3
#define SC_EXTENSION	0xb5
#define SC_PB_PICTURE	0xb6
#define SC_VIDEO_EDIT	0xb7

struct seq {
	bool valid;
	unsigned int profile, level;
	bool progressive;
	unsigned int width, height;
	unsigned int chroma_format, sample_precision;
	unsigned int aspect_ratio, frame_rate_code;
	bool low_delay;
};

struct pic {
	unsigned int type;		/* V4L2_AVS_PICTURE_TYPE_ */
	unsigned int distance;
	bool progressive_frame, structure, top_field_first, repeat_first_field;
	bool fixed_qp, ref_flag, skip_mode, adv_pred_disable;
	bool no_forward_ref, pb_field_enhanced;
	unsigned int qp;
	bool lf_disable;
	int alpha, beta;
	bool wq, chroma_qp_disable, aec;
	int cb, cr;
	unsigned int wq_index, wq_model;
	int delta1[6], delta2[6];
	/* stream facts, for the dry run */
	unsigned int slices, weighted_slices, pseudo;
	bool no_slice_start_code;
};

static bool guangdian(const struct seq *s)
{
	return s->profile == V4L2_AVS_PROFILE_GUANGDIAN;
}

static int parse_sequence_header(struct bits *b, struct seq *s)
{
	struct seq n = { .valid = true };

	n.profile = u(b, 8);
	n.level = u(b, 8);
	n.progressive = u(b, 1);
	n.width = u(b, 14);
	n.height = u(b, 14);
	n.chroma_format = u(b, 2);
	n.sample_precision = u(b, 3);
	n.aspect_ratio = u(b, 4);
	n.frame_rate_code = u(b, 4);
	u(b, 18);		/* bit_rate_lower */
	u(b, 1);		/* marker */
	u(b, 12);		/* bit_rate_upper */
	n.low_delay = u(b, 1);
	if (b->overrun)
		return -1;
	*s = n;
	return 0;
}

/*
 * Streams of the pre-final revision have no marker bit after time_code.
 * Once a stream is seen with it, it stays: those old clips are all
 * progressive, without low_delay and with top_field_first and
 * repeat_first_field 0, which tells the two apart.
 */
static bool final_revision;

static void parse_tools(struct bits *b, const struct seq *s, struct pic *p)
{
	unsigned int i;

	p->lf_disable = u(b, 1);
	if (!p->lf_disable && u(b, 1)) {	/* loop_filter_parameter_flag */
		p->alpha = se(b);
		p->beta = se(b);
	}

	if (!guangdian(s))
		return;

	p->wq = u(b, 1);
	if (p->wq) {
		p->chroma_qp_disable = u(b, 1);
		if (!p->chroma_qp_disable) {
			p->cb = se(b);
			p->cr = se(b);
		}
		p->wq_index = u(b, 2);
		p->wq_model = u(b, 2);
		if (p->wq_index == 1)
			for (i = 0; i < 6; i++)
				p->delta1[i] = se(b);
		else if (p->wq_index == 2)
			for (i = 0; i < 6; i++)
				p->delta2[i] = se(b);
	}
	p->aec = u(b, 1);
}

static int parse_picture_header(struct bits *b, const struct seq *s,
				unsigned int code, struct pic *p)
{
	memset(p, 0, sizeof(*p));

	u(b, 16);			/* bbv_delay */
	if (guangdian(s))
		u(b, 8);		/* marker, bbv_delay_extension */

	if (code == SC_PB_PICTURE) {
		p->type = u(b, 2);
		if (p->type != V4L2_AVS_PICTURE_TYPE_P &&
		    p->type != V4L2_AVS_PICTURE_TYPE_B)
			return -1;
	} else {
		p->type = V4L2_AVS_PICTURE_TYPE_I;
		if (u(b, 1))	/* time_code_flag */
			u(b, 24);
		if (guangdian(s) || s->low_delay || !(peek(b, 9) & 1) ||
		    (peek(b, 11) & 3))
			final_revision = true;
		if (final_revision)
			u(b, 1);	/* marker */
	}

	p->distance = u(b, 8);
	if (s->low_delay)
		ue(b);			/* bbv_check_times */
	p->progressive_frame = u(b, 1);
	p->structure = true;
	if (!p->progressive_frame) {
		p->structure = u(b, 1);
		if (!p->structure && code == SC_PB_PICTURE)
			p->adv_pred_disable = u(b, 1);
	}
	p->top_field_first = u(b, 1);
	p->repeat_first_field = u(b, 1);
	p->fixed_qp = u(b, 1);
	p->qp = u(b, 6);

	if (code == SC_I_PICTURE) {
		if (!p->structure)
			p->skip_mode = u(b, 1);
		u(b, 4);		/* reserved */
	} else {
		/* not coded for frame B pictures, where it is 1 */
		p->ref_flag = true;
		if (!(p->type == V4L2_AVS_PICTURE_TYPE_B && p->structure))
			p->ref_flag = u(b, 1);
		p->no_forward_ref = u(b, 1);
		p->pb_field_enhanced = u(b, 1);
		if (!guangdian(s)) {
			/* reserved bits in JiZhun */
			p->no_forward_ref = false;
			p->pb_field_enhanced = false;
		}
		u(b, 2);		/* reserved */
		p->skip_mode = u(b, 1);
	}

	parse_tools(b, s, p);

	return b->overrun ? -1 : 0;
}

/* MB rows of the frame, for the field of a slice */
static unsigned int mb_height(const struct seq *s)
{
	return s->progressive ? (s->height + 15) / 16 :
	       (s->height + 31) / 32 * 2;
}

/* Slice header fields that matter for the dry run (slice weighting). */
static void parse_slice_header(const struct seq *s, const struct pic *p,
			       unsigned int code, const uint8_t *data,
			       size_t len, struct pic *stats, int index)
{
	struct bits b;
	unsigned int row = code;
	bool second_field;

	bits_init(&b, data, len > 64 ? 64 : len, NULL);
	if (s->height > 2800)
		row += u(&b, 3) << 7;
	if (!p->fixed_qp) {
		u(&b, 1);		/* fixed_slice_qp */
		u(&b, 6);		/* slice_qp */
	}
	second_field = !p->structure && row >= mb_height(s) / 2;
	if (p->type != V4L2_AVS_PICTURE_TYPE_I || second_field) {
		if (u(&b, 1)) {
			unsigned int ls, cs;
			int lo, co;

			stats->weighted_slices++;
			/* the parameters of the first reference */
			ls = u(&b, 8);
			lo = (int8_t)u(&b, 8);
			u(&b, 1);	/* marker */
			cs = u(&b, 8);
			co = (int8_t)u(&b, 8);
			printf("  picture %d slice row %u: slice_weighting_flag 1 (ref 0: luma scale %u shift %d, chroma scale %u shift %d)\n",
			       index, row, ls, lo, cs, co);
		}
	}
	bits_free(&b);
}

/* ------------------------------------------------------------------ */
/* V4L2                                                                */

struct v4l2_ctx {
	int video_fd, media_fd;
	int req_fd[NUM_OUT_BUFS];
	void *out_map[NUM_OUT_BUFS];
	size_t out_size[NUM_OUT_BUFS];
	void *cap_map[MAX_BUFS];
	size_t cap_len[MAX_BUFS];
	struct v4l2_pix_format cap_fmt;
	unsigned int next_out;
	bool tiled;
};

static void xioctl(int fd, unsigned long req, void *arg, const char *name)
{
	if (ioctl(fd, req, arg) < 0)
		die("%s: %s", name, strerror(errno));
}

static void fill_sequence_ctrl(const struct seq *s,
			       struct v4l2_ctrl_avs_sequence *c)
{
	memset(c, 0, sizeof(*c));
	if (s->progressive)
		c->flags |= V4L2_AVS_SEQUENCE_FLAG_PROGRESSIVE_SEQUENCE;
	if (s->low_delay)
		c->flags |= V4L2_AVS_SEQUENCE_FLAG_LOW_DELAY;
	c->horizontal_size = s->width;
	c->vertical_size = s->height;
	c->profile_id = s->profile;
	c->level_id = s->level;
	/*
	 * Streams of the pre-final revision (FATE cavs.mpg) code 0 here;
	 * they are 8-bit 4:2:0.
	 */
	c->chroma_format = s->chroma_format ? s->chroma_format : 1;
	c->sample_precision = s->sample_precision ? s->sample_precision : 1;
	c->aspect_ratio = s->aspect_ratio;
	c->frame_rate_code = s->frame_rate_code;
}

static void set_ctrls(int fd, int req_fd, struct v4l2_ext_control *c,
		      unsigned int n)
{
	struct v4l2_ext_controls ctrls = {
		.which = req_fd >= 0 ? V4L2_CTRL_WHICH_REQUEST_VAL : 0,
		.request_fd = req_fd,
		.count = n,
		.controls = c,
	};

	xioctl(fd, VIDIOC_S_EXT_CTRLS, &ctrls, "VIDIOC_S_EXT_CTRLS");
}

static struct v4l2_ctx *v4l2_open(const char *video, const char *media,
				  const struct seq *s, size_t max_pic,
				  unsigned int num_cap, bool tiled)
{
	struct v4l2_ctx *v = calloc(1, sizeof(*v));
	struct v4l2_ctrl_avs_sequence sc;
	struct v4l2_ext_control c = {
		.id = V4L2_CID_STATELESS_AVS_SEQUENCE,
		.size = sizeof(sc),
		.ptr = &sc,
	};
	uint32_t cap_pixfmt = tiled ? V4L2_PIX_FMT_NV12_32L32 :
				       V4L2_PIX_FMT_NV12;
	struct v4l2_format fmt = { 0 };
	struct v4l2_requestbuffers rb = { 0 };
	enum v4l2_buf_type type;
	unsigned int i;

	if (!v)
		die("out of memory");
	v->tiled = tiled;
	v->video_fd = open(video, O_RDWR);
	if (v->video_fd < 0)
		die("%s: %s", video, strerror(errno));
	v->media_fd = open(media, O_RDWR);
	if (v->media_fd < 0)
		die("%s: %s", media, strerror(errno));

	fmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_AVS_FRAME;
	fmt.fmt.pix.width = s->width;
	fmt.fmt.pix.height = s->height;
	fmt.fmt.pix.sizeimage = (max_pic + 64 * 1024 + 4095) & ~4095u;
	xioctl(v->video_fd, VIDIOC_S_FMT, &fmt, "VIDIOC_S_FMT(OUTPUT)");
	if (fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_AVS_FRAME)
		die("the driver has no AVS_FRAME output format");

	fill_sequence_ctrl(s, &sc);
	set_ctrls(v->video_fd, -1, &c, 1);

	memset(&fmt, 0, sizeof(fmt));
	fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	fmt.fmt.pix.pixelformat = cap_pixfmt;
	fmt.fmt.pix.width = s->width;
	fmt.fmt.pix.height = s->height;
	xioctl(v->video_fd, VIDIOC_S_FMT, &fmt, "VIDIOC_S_FMT(CAPTURE)");
	if (fmt.fmt.pix.pixelformat != cap_pixfmt)
		die("capture format %s not available", tiled ? "NV12_32L32" : "NV12");
	v->cap_fmt = fmt.fmt.pix;
	if (verbose)
		fprintf(stderr, "capture %ux%u bytesperline %u sizeimage %u\n",
			v->cap_fmt.width, v->cap_fmt.height,
			v->cap_fmt.bytesperline, v->cap_fmt.sizeimage);

	rb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	rb.memory = V4L2_MEMORY_MMAP;
	rb.count = NUM_OUT_BUFS;
	xioctl(v->video_fd, VIDIOC_REQBUFS, &rb, "VIDIOC_REQBUFS(OUTPUT)");
	if (rb.count < NUM_OUT_BUFS)
		die("too few output buffers");
	for (i = 0; i < NUM_OUT_BUFS; i++) {
		struct v4l2_buffer buf = {
			.type = V4L2_BUF_TYPE_VIDEO_OUTPUT,
			.memory = V4L2_MEMORY_MMAP,
			.index = i,
		};

		xioctl(v->video_fd, VIDIOC_QUERYBUF, &buf, "VIDIOC_QUERYBUF");
		v->out_size[i] = buf.length;
		v->out_map[i] = mmap(NULL, buf.length, PROT_READ | PROT_WRITE,
				     MAP_SHARED, v->video_fd, buf.m.offset);
		if (v->out_map[i] == MAP_FAILED)
			die("mmap: %s", strerror(errno));
		xioctl(v->media_fd, MEDIA_IOC_REQUEST_ALLOC, &v->req_fd[i],
		       "MEDIA_IOC_REQUEST_ALLOC");
	}

	memset(&rb, 0, sizeof(rb));
	rb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	rb.memory = V4L2_MEMORY_MMAP;
	rb.count = num_cap;
	xioctl(v->video_fd, VIDIOC_REQBUFS, &rb, "VIDIOC_REQBUFS(CAPTURE)");
	if (rb.count < num_cap)
		die("only %u capture buffers", rb.count);
	for (i = 0; i < num_cap; i++) {
		struct v4l2_buffer buf = {
			.type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
			.memory = V4L2_MEMORY_MMAP,
			.index = i,
		};

		xioctl(v->video_fd, VIDIOC_QUERYBUF, &buf, "VIDIOC_QUERYBUF");
		v->cap_len[i] = buf.length;
		v->cap_map[i] = mmap(NULL, buf.length, PROT_READ, MAP_SHARED,
				     v->video_fd, buf.m.offset);
		if (v->cap_map[i] == MAP_FAILED)
			die("mmap: %s", strerror(errno));
	}

	type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	xioctl(v->video_fd, VIDIOC_STREAMON, &type, "VIDIOC_STREAMON(OUTPUT)");
	type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	xioctl(v->video_fd, VIDIOC_STREAMON, &type, "VIDIOC_STREAMON(CAPTURE)");

	return v;
}

/* One request per picture; waits for it. Returns -1 on a decode error. */
/* request queue -> completion, summed over all jobs (hardware time) */
static long long hw_ns;
static unsigned int hw_jobs;

static int v4l2_decode(struct v4l2_ctx *v, const uint8_t *data, size_t len,
		       uint64_t ts, unsigned int cap_index,
		       struct v4l2_ext_control *ctrls, unsigned int nctrls)
{
	unsigned int out = v->next_out;
	int req = v->req_fd[out];
	struct v4l2_buffer buf = { 0 };
	struct pollfd pfd = { .fd = req, .events = POLLPRI };
	struct timespec t0, t1;
	int ret, error = 0;

	v->next_out = (out + 1) % NUM_OUT_BUFS;

	if (len > v->out_size[out])
		die("picture of %zu bytes does not fit the %zu byte buffer",
		    len, v->out_size[out]);
	memcpy(v->out_map[out], data, len);

	set_ctrls(v->video_fd, req, ctrls, nctrls);

	buf.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	buf.memory = V4L2_MEMORY_MMAP;
	buf.index = out;
	buf.bytesused = len;
	buf.flags = V4L2_BUF_FLAG_REQUEST_FD;
	buf.request_fd = req;
	buf.timestamp.tv_sec = ts / 1000000000;
	buf.timestamp.tv_usec = (ts % 1000000000) / 1000;
	xioctl(v->video_fd, VIDIOC_QBUF, &buf, "VIDIOC_QBUF(OUTPUT)");

	memset(&buf, 0, sizeof(buf));
	buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	buf.memory = V4L2_MEMORY_MMAP;
	buf.index = cap_index;
	xioctl(v->video_fd, VIDIOC_QBUF, &buf, "VIDIOC_QBUF(CAPTURE)");

	clock_gettime(CLOCK_MONOTONIC, &t0);
	xioctl(req, MEDIA_REQUEST_IOC_QUEUE, NULL, "MEDIA_REQUEST_IOC_QUEUE");

	ret = poll(&pfd, 1, 5000);
	if (ret <= 0)
		die("request timed out");
	clock_gettime(CLOCK_MONOTONIC, &t1);
	hw_ns += (t1.tv_sec - t0.tv_sec) * 1000000000LL +
		 (t1.tv_nsec - t0.tv_nsec);
	hw_jobs++;

	memset(&buf, 0, sizeof(buf));
	buf.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	buf.memory = V4L2_MEMORY_MMAP;
	xioctl(v->video_fd, VIDIOC_DQBUF, &buf, "VIDIOC_DQBUF(OUTPUT)");

	memset(&buf, 0, sizeof(buf));
	buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	buf.memory = V4L2_MEMORY_MMAP;
	xioctl(v->video_fd, VIDIOC_DQBUF, &buf, "VIDIOC_DQBUF(CAPTURE)");
	if (buf.index != cap_index)
		die("dequeued capture buffer %u, expected %u", buf.index,
		    cap_index);
	if (buf.flags & V4L2_BUF_FLAG_ERROR)
		error = -1;

	xioctl(req, MEDIA_REQUEST_IOC_REINIT, NULL, "MEDIA_REQUEST_IOC_REINIT");

	return error;
}

/* ------------------------------------------------------------------ */
/* Decoder: reference history, output order                            */

struct frame {
	bool ref;		/* R0 or R1 */
	bool pending;		/* waiting to be output */
	uint64_t ts;
	int dec_index;
	unsigned int type, distance;
};

struct ref {
	bool valid;
	int slot;
	uint64_t ts;
	unsigned int distance;
	unsigned int flags;	/* V4L2_AVS_REF_FLAG_ */
};

struct decoder {
	struct seq seq;
	struct frame frames[MAX_BUFS];
	unsigned int num_frames;
	struct ref r[3];	/* R0 newest .. R2 */
	int held;		/* I/P picture waiting for the next I/P */
	struct v4l2_ctx *v4l2;
	bool dry_run, vld_at_header;
	FILE *yuv, *crc, *md5f;
	struct md5 md5;
	unsigned int out_count, dec_count, errors, skipped;
	unsigned int count[3], field_pics, weighted_pics, pseudo, aec_pics,
		     enhanced_b, wq_pics, no_slice_sc;
	uint8_t *row;
	char order[4096];
	size_t order_len;
};

static const char type_char[] = "IPB";

static void tb_of(unsigned int frc, unsigned int *num, unsigned int *den)
{
	static const unsigned int rate[9][2] = {
		{ 25, 1 }, { 24000, 1001 }, { 24, 1 }, { 25, 1 },
		{ 30000, 1001 }, { 30, 1 }, { 50, 1 }, { 60000, 1001 },
		{ 60, 1 },
	};

	if (frc > 8)
		frc = 0;
	*num = rate[frc][1];
	*den = rate[frc][0];
}

static void print_headers(struct decoder *d)
{
	unsigned int num, den;

	tb_of(d->seq.frame_rate_code, &num, &den);
	if (d->md5f)
		fprintf(d->md5f, "#format: frame checksums\n#version: 2\n#hash: MD5\n");
	if (d->crc)
		fprintf(d->crc, "#tb 0: %u/%u\n#media_type 0: video\n#codec_id 0: rawvideo\n#dimensions 0: %ux%u\n#sar 0: 0/1\n",
			num, den, d->seq.width, d->seq.height);
	if (d->md5f)
		fprintf(d->md5f, "#tb 0: %u/%u\n#media_type 0: video\n#codec_id 0: rawvideo\n#dimensions 0: %ux%u\n#sar 0: 0/1\n#stream#, dts,        pts, duration,     size, hash\n",
			num, den, d->seq.width, d->seq.height);
}

static const uint8_t *cap_pixel_row(struct v4l2_ctx *v, const uint8_t *plane,
				    unsigned int y, unsigned int width,
				    uint8_t *tmp)
{
	unsigned int bpl = v->cap_fmt.bytesperline, x;

	if (!v->tiled) {
		memcpy(tmp, plane + (size_t)y * bpl, width);
		return tmp;
	}

	/* NV12_32L32: 32x32 byte tiles, in rows of bpl / 32 tiles */
	for (x = 0; x < width; x += 32) {
		size_t off = ((size_t)(y / 32) * (bpl / 32) + x / 32) * 1024 +
			     (y % 32) * 32;
		unsigned int n = width - x < 32 ? width - x : 32;

		memcpy(tmp + x, plane + off, n);
	}
	return tmp;
}

static void output_frame(struct decoder *d, int slot)
{
	struct frame *f = &d->frames[slot];
	unsigned int w = d->seq.width, h = d->seq.height, cw = (w + 1) / 2;
	unsigned int size = w * h + 2 * cw * ((h + 1) / 2);
	unsigned int idx = d->out_count++;
	struct md5 fm;
	struct adler ad;
	char sum[33];
	int n;

	f->pending = false;
	n = snprintf(d->order + d->order_len, sizeof(d->order) - d->order_len,
		     "%c%u ", type_char[f->type], f->distance);
	if (n > 0 && d->order_len + n < sizeof(d->order))
		d->order_len += n;

	if (d->dry_run) {
		if (verbose)
			printf("output %u: picture %d (%c, distance %u)\n", idx,
			       f->dec_index, type_char[f->type], f->distance);
		return;
	}

	md5_init(&fm);
	adler_init(&ad);
	{
		struct v4l2_ctx *v = d->v4l2;
		const uint8_t *luma = v->cap_map[slot];
		const uint8_t *chroma = luma + (size_t)v->cap_fmt.bytesperline *
					v->cap_fmt.height;
		uint8_t *tmp = d->row, *out = d->row + v->cap_fmt.bytesperline + 64;
		unsigned int x, y, c;

		for (y = 0; y < h; y++) {
			const uint8_t *r = cap_pixel_row(v, luma, y, w, tmp);

			md5_update(&fm, r, w);
			md5_update(&d->md5, r, w);
			adler_update(&ad, r, w);
			if (d->yuv && fwrite(r, 1, w, d->yuv) != w)
				die("write: %s", strerror(errno));
		}
		for (c = 0; c < 2; c++) {
			for (y = 0; y < (h + 1) / 2; y++) {
				const uint8_t *r = cap_pixel_row(v, chroma, y,
								 2 * cw, tmp);

				for (x = 0; x < cw; x++)
					out[x] = r[2 * x + c];
				md5_update(&fm, out, cw);
				md5_update(&d->md5, out, cw);
				adler_update(&ad, out, cw);
				if (d->yuv && fwrite(out, 1, cw, d->yuv) != cw)
					die("write: %s", strerror(errno));
			}
		}
	}
	md5_final(&fm, sum);

	if (d->crc)
		fprintf(d->crc, "0, %10u, %10u, %8d, %8u, 0x%08x\n", idx, idx, 1,
			size, adler_final(&ad));
	if (d->md5f)
		fprintf(d->md5f, "0, %10u, %10u, %8d, %8u, %s\n", idx, idx, 1,
			size, sum);
	if (verbose)
		fprintf(stderr, "output %u: picture %d (%c, distance %u) md5 %s\n",
			idx, f->dec_index, type_char[f->type], f->distance, sum);
}

static int get_free_frame(struct decoder *d)
{
	unsigned int i;

	for (i = 0; i < d->num_frames; i++)
		if (!d->frames[i].ref && !d->frames[i].pending)
			return i;
	die("no free capture buffer");
	return -1;
}

static void fill_ref(struct v4l2_avs_ref_pic *c, const struct ref *r)
{
	memset(c, 0, sizeof(*c));
	if (!r->valid)
		return;
	c->timestamp = r->ts;
	c->picture_distance = r->distance;
	c->flags = r->flags;
}

static void print_ref(const char *name, const struct v4l2_avs_ref_pic *c)
{
	if (!(c->flags & V4L2_AVS_REF_FLAG_VALID)) {
		printf(" %s=-", name);
		return;
	}
	printf(" %s={ts %" PRIu64 " dist %u flags 0x%x}", name, (uint64_t)c->timestamp,
	       c->picture_distance, c->flags);
}

/*
 * One picture: data is the OUTPUT buffer content, from the picture start
 * code to the end of its last slice; first_slice is the offset of the
 * first slice start code in it (0 if there is none).
 */
static void decode_picture(struct decoder *d, const struct pic *p,
			   const uint8_t *data, size_t len, size_t first_slice)
{
	struct v4l2_ctrl_avs_sequence sc;
	struct v4l2_ctrl_avs_picture pc = { 0 };
	struct v4l2_ctrl_avs_weight_quant wc = { 0 };
	struct v4l2_ext_control c[3] = {
		{ .id = V4L2_CID_STATELESS_AVS_SEQUENCE, .size = sizeof(sc), .ptr = &sc },
		{ .id = V4L2_CID_STATELESS_AVS_PICTURE, .size = sizeof(pc), .ptr = &pc },
		{ .id = V4L2_CID_STATELESS_AVS_WEIGHT_QUANT, .size = sizeof(wc), .ptr = &wc },
	};
	int index = d->dec_count++;
	bool is_ref = p->type != V4L2_AVS_PICTURE_TYPE_B;
	struct frame *f;
	unsigned int i;
	int slot;

	d->count[p->type]++;
	if (!p->structure)
		d->field_pics++;
	if (p->weighted_slices)
		d->weighted_pics++;
	if (p->aec)
		d->aec_pics++;
	if (p->wq)
		d->wq_pics++;
	if (p->pb_field_enhanced && !p->structure &&
	    p->type == V4L2_AVS_PICTURE_TYPE_B)
		d->enhanced_b++;
	d->pseudo += p->pseudo;
	if (p->no_slice_start_code)
		d->no_slice_sc++;

	/* Missing references (open GOP, stream start): skip the picture. */
	if ((p->type == V4L2_AVS_PICTURE_TYPE_P && !d->r[0].valid) ||
	    (p->type == V4L2_AVS_PICTURE_TYPE_B &&
	     (!d->r[0].valid || !d->r[1].valid))) {
		printf("picture %d (%c, distance %u): reference missing, skipped\n",
		       index, type_char[p->type], p->distance);
		d->skipped++;
		return;
	}

	fill_sequence_ctrl(&d->seq, &sc);

	if (p->type == V4L2_AVS_PICTURE_TYPE_B) {
		fill_ref(&pc.refs[V4L2_AVS_REF_FORWARD], &d->r[1]);
		fill_ref(&pc.refs[V4L2_AVS_REF_BACKWARD], &d->r[0]);
		fill_ref(&pc.refs[V4L2_AVS_REF_SECOND_FORWARD], &d->r[2]);
	} else {
		fill_ref(&pc.refs[V4L2_AVS_REF_FORWARD], &d->r[0]);
		fill_ref(&pc.refs[V4L2_AVS_REF_SECOND_FORWARD], &d->r[1]);
	}

	if (d->vld_at_header || !first_slice)
		pc.data_offset = 4;
	else
		pc.data_offset = first_slice;
	if (p->progressive_frame)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_PROGRESSIVE_FRAME;
	if (p->structure)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_PICTURE_STRUCTURE;
	if (p->top_field_first)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_TOP_FIELD_FIRST;
	if (p->repeat_first_field)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_REPEAT_FIRST_FIELD;
	if (p->fixed_qp)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_FIXED_PICTURE_QP;
	if (p->ref_flag)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_PICTURE_REFERENCE;
	if (p->skip_mode)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_SKIP_MODE;
	if (p->adv_pred_disable)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_ADVANCED_PRED_MODE_DISABLE;
	if (p->lf_disable)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_LOOP_FILTER_DISABLE;
	if (p->no_forward_ref)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_NO_FORWARD_REFERENCE;
	if (p->pb_field_enhanced)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_PB_FIELD_ENHANCED;
	if (p->wq)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_WEIGHTING_QUANT;
	if (p->aec)
		pc.flags |= V4L2_AVS_PICTURE_FLAG_AEC;
	pc.picture_type = p->type;
	pc.picture_distance = p->distance;
	pc.picture_qp = p->qp;
	pc.alpha_c_offset = p->alpha;
	pc.beta_offset = p->beta;

	if (p->wq) {
		if (p->chroma_qp_disable)
			wc.flags |= V4L2_AVS_WEIGHT_QUANT_FLAG_CHROMA_QUANT_PARAM_DISABLE;
		wc.chroma_quant_param_delta_cb = p->cb;
		wc.chroma_quant_param_delta_cr = p->cr;
		wc.weighting_quant_param_index = p->wq_index;
		wc.weighting_quant_model = p->wq_model;
		for (i = 0; i < 6; i++) {
			wc.weighting_quant_param_delta1[i] = p->delta1[i];
			wc.weighting_quant_param_delta2[i] = p->delta2[i];
		}
	}

	slot = get_free_frame(d);
	f = &d->frames[slot];
	f->ts = (uint64_t)(index + 1) * 1000;
	f->dec_index = index;
	f->type = p->type;
	f->distance = p->distance;

	if (d->dry_run) {
		printf("picture %d: %c dist %u size %zu data_offset %u flags 0x%04x qp %u alpha %d beta %d slices %u pseudo %u buf %d ts %" PRIu64,
		       index, type_char[p->type], p->distance, len, pc.data_offset,
		       pc.flags, pc.picture_qp, pc.alpha_c_offset, pc.beta_offset,
		       p->slices, p->pseudo, slot, f->ts);
		print_ref("fwd", &pc.refs[V4L2_AVS_REF_FORWARD]);
		print_ref("fwd2", &pc.refs[V4L2_AVS_REF_SECOND_FORWARD]);
		print_ref("bwd", &pc.refs[V4L2_AVS_REF_BACKWARD]);
		if (p->wq)
			printf(" wq{flags 0x%x cb %d cr %d index %u model %u}",
			       wc.flags, wc.chroma_quant_param_delta_cb,
			       wc.chroma_quant_param_delta_cr,
			       wc.weighting_quant_param_index,
			       wc.weighting_quant_model);
		if (p->weighted_slices)
			printf(" weighted_slices %u", p->weighted_slices);
		printf("\n");
	} else if (v4l2_decode(d->v4l2, data, len, f->ts, slot, c,
			       p->wq ? 3 : 2) < 0) {
		fprintf(stderr, "picture %d (%c, distance %u): decode error\n",
			index, type_char[p->type], p->distance);
		d->errors++;
	}

	if (!is_ref) {
		output_frame(d, slot);
		return;
	}

	/* An I/P picture is output when the next I/P picture is decoded. */
	if (d->held >= 0) {
		output_frame(d, d->held);
		d->held = -1;
	}

	if (d->r[1].valid && d->r[1].slot >= 0)
		d->frames[d->r[1].slot].ref = false;
	d->r[2] = d->r[1];
	d->r[2].slot = -1;	/* no longer read, only its distance */
	d->r[1] = d->r[0];
	d->r[0].valid = true;
	d->r[0].slot = slot;
	d->r[0].ts = f->ts;
	d->r[0].distance = p->distance;
	d->r[0].flags = V4L2_AVS_REF_FLAG_VALID;
	if (p->type == V4L2_AVS_PICTURE_TYPE_I)
		d->r[0].flags |= V4L2_AVS_REF_FLAG_INTRA;
	if (p->structure)
		d->r[0].flags |= V4L2_AVS_REF_FLAG_PICTURE_STRUCTURE;
	if (p->top_field_first)
		d->r[0].flags |= V4L2_AVS_REF_FLAG_TOP_FIELD_FIRST;
	f->ref = true;

	if (d->seq.low_delay) {
		output_frame(d, slot);
	} else {
		f->pending = true;
		d->held = slot;
	}
}

/* ------------------------------------------------------------------ */
/* Main                                                                */

static size_t next_start_code(const uint8_t *p, size_t len, size_t from)
{
	size_t i;

	for (i = from; i + 3 < len; i++)
		if (!p[i] && !p[i + 1] && p[i + 2] == 1)
			return i;
	return len;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: avs1dec [-d video] [-m media] [-t es|ts|ps] [-o out.yuv] [-c crc] [-5 md5]\n"
		"               [-n bufs] [-l pictures] [-T] [-H] [-v] [--dry-run] stream\n");
	exit(2);
}

int main(int argc, char **argv)
{
	const char *video = "/dev/video0", *media = "/dev/media0";
	const char *kind = NULL, *yuv = NULL, *crc = NULL, *md5n = NULL;
	unsigned int num_cap = 6, limit = 0;
	struct decoder d = { .held = -1 };
	struct buf in = { 0 }, es = { 0 };
	const uint8_t *s;
	size_t n, i, max_pic = 0;
	bool tiled = false;
	FILE *fp;
	int opt;

	for (i = 1; i < (size_t)argc; i++)
		if (!strcmp(argv[i], "--dry-run"))
			d.dry_run = true;

	while ((opt = getopt(argc, argv, "d:m:t:o:c:5:n:l:THv-:")) != -1) {
		switch (opt) {
		case 'd': video = optarg; break;
		case 'm': media = optarg; break;
		case 't': kind = optarg; break;
		case 'o': yuv = optarg; break;
		case 'c': crc = optarg; break;
		case '5': md5n = optarg; break;
		case 'n': num_cap = atoi(optarg); break;
		case 'l': limit = atoi(optarg); break;
		case 'T': tiled = true; break;
		case 'H': d.vld_at_header = true; break;
		case 'v': verbose++; break;
		case '-':
			if (strcmp(optarg, "dry-run"))
				usage();
			break;
		default: usage();
		}
	}
	if (optind != argc - 1)
		usage();
	if (num_cap < 3 || num_cap > MAX_BUFS)
		die("-n must be 3 to %d", MAX_BUFS);

	fp = strcmp(argv[optind], "-") ? fopen(argv[optind], "rb") : stdin;
	if (!fp)
		die("%s: %s", argv[optind], strerror(errno));
	for (;;) {
		uint8_t chunk[65536];
		size_t r = fread(chunk, 1, sizeof(chunk), fp);

		if (!r)
			break;
		buf_put(&in, chunk, r);
	}
	if (fp != stdin)
		fclose(fp);

	if (!kind) {
		if (in.len >= 376 && in.p[0] == 0x47 && in.p[188] == 0x47)
			kind = "ts";
		else if (in.len >= 4 && !in.p[0] && !in.p[1] && in.p[2] == 1 &&
			 in.p[3] == 0xba)
			kind = "ps";
		else
			kind = "es";
	}
	if (!strcmp(kind, "ts"))
		ts_to_es(in.p, in.len, &es);
	else if (!strcmp(kind, "ps"))
		ps_to_es(in.p, in.len, &es);
	else if (!strcmp(kind, "es"))
		es = in;
	else
		usage();
	s = es.p;
	n = es.len;
	if (verbose)
		fprintf(stderr, "%s input, %zu elementary stream bytes\n", kind, n);

	/* First sequence header, and the largest picture. */
	for (i = next_start_code(s, n, 0); i < n;
	     i = next_start_code(s, n, i + 3)) {
		size_t end = next_start_code(s, n, i + 3);

		if (s[i + 3] == SC_SEQ_START && !d.seq.valid) {
			struct bits b;

			bits_init(&b, s + i + 4, end - i - 4, NULL);
			if (parse_sequence_header(&b, &d.seq))
				die("bad sequence header");
			bits_free(&b);
		}
		if (s[i + 3] == SC_I_PICTURE || s[i + 3] == SC_PB_PICTURE) {
			size_t j = end;

			while (j < n && s[j + 3] <= SC_SLICE_MAX)
				j = next_start_code(s, n, j + 3);
			if (j - i > max_pic)
				max_pic = j - i;
		}
	}
	if (!d.seq.valid)
		die("no sequence header");
	if (!d.seq.chroma_format || !d.seq.sample_precision)
		printf("warning: chroma_format %u sample_precision %u (pre-final revision stream?), passed as 1\n",
		       d.seq.chroma_format, d.seq.sample_precision);

	printf("sequence: profile 0x%02x level 0x%02x %ux%u %s chroma_format %u sample_precision %u frame_rate_code %u low_delay %d\n",
	       d.seq.profile, d.seq.level, d.seq.width, d.seq.height,
	       d.seq.progressive ? "progressive" : "interlaced",
	       d.seq.chroma_format, d.seq.sample_precision,
	       d.seq.frame_rate_code, d.seq.low_delay);

	if (crc)
		d.crc = strcmp(crc, "-") ? fopen(crc, "w") : stdout;
	if (md5n)
		d.md5f = strcmp(md5n, "-") ? fopen(md5n, "w") : stdout;
	if (yuv)
		d.yuv = fopen(yuv, "wb");
	if ((crc && !d.crc) || (md5n && !d.md5f) || (yuv && !d.yuv))
		die("cannot open an output file: %s", strerror(errno));
	if (d.dry_run && (yuv || crc || md5n))
		die("--dry-run writes no pictures or checksums");

	d.num_frames = num_cap;
	md5_init(&d.md5);
	if (!d.dry_run) {
		d.v4l2 = v4l2_open(video, media, &d.seq, max_pic, num_cap, tiled);
		d.row = malloc(2 * d.v4l2->cap_fmt.bytesperline + 128);
		if (!d.row)
			die("out of memory");
	}
	print_headers(&d);

	for (i = next_start_code(s, n, 0); i < n;) {
		size_t end = next_start_code(s, n, i + 3);
		unsigned int code = s[i + 3];
		size_t j, first_slice = 0, last = end;
		struct bits b;
		struct pic p;

		if (code == SC_SEQ_START) {
			struct seq ns;

			bits_init(&b, s + i + 4, end - i - 4, NULL);
			if (!parse_sequence_header(&b, &ns) &&
			    (ns.width != d.seq.width || ns.height != d.seq.height ||
			     ns.profile != d.seq.profile))
				die("sequence change at %zu is not supported", i);
			bits_free(&b);
			i = end;
			continue;
		}
		if (code != SC_I_PICTURE && code != SC_PB_PICTURE) {
			i = end;
			continue;
		}

		bits_init(&b, s + i + 4, end - i - 4, NULL);
		if (parse_picture_header(&b, &d.seq, code, &p))
			die("bad picture header at %zu", i);
		bits_free(&b);

		/*
		 * The picture runs to its last slice; extensions and user data
		 * between the header and the first slice belong to it.
		 */
		for (j = end; j < n; j = next_start_code(s, n, j + 3)) {
			unsigned int c = s[j + 3];
			size_t e = next_start_code(s, n, j + 3);
			struct bits sb;

			if (c <= SC_SLICE_MAX) {
				if (!first_slice)
					first_slice = j - i;
				p.slices++;
				bits_init(&sb, s + j + 4, e - j - 4, &p.pseudo);
				bits_free(&sb);
				parse_slice_header(&d.seq, &p, c, s + j + 4,
						   e - j - 4, &p, d.dec_count);
				last = e;
				continue;
			}
			if ((c == SC_EXTENSION || c == SC_USER_DATA) &&
			    !first_slice) {
				last = e;
				continue;
			}
			break;
		}
		if (!first_slice) {
			/* pre-final revision streams: data follows the header */
			p.no_slice_start_code = true;
			bits_init(&b, s + i + 4, end - i - 4, &p.pseudo);
			bits_free(&b);
		}

		decode_picture(&d, &p, s + i, last - i, first_slice);
		i = last;
		if (limit && d.dec_count >= limit)
			break;
	}

	if (d.held >= 0)
		output_frame(&d, d.held);

	printf("pictures %u (I %u P %u B %u), field coded %u, AEC %u, enhanced field B %u, WQ %u, with slice weighting %u, pseudo start codes %u, without slice start code %u, skipped %u, errors %u\n",
	       d.dec_count, d.count[0], d.count[1], d.count[2], d.field_pics,
	       d.aec_pics, d.enhanced_b, d.wq_pics, d.weighted_pics, d.pseudo,
	       d.no_slice_sc, d.skipped, d.errors);
	printf("output %u frames, display order: %.*s\n", d.out_count,
	       (int)d.order_len, d.order);
	if (!d.dry_run) {
		char sum[33];

		md5_final(&d.md5, sum);
		printf("md5 %s\n", sum);
		if (hw_jobs)
			printf("hardware: %u jobs, %.3f ms each (queue to completion)\n",
			       hw_jobs, hw_ns / 1e6 / hw_jobs);
	}
	if (d.crc && d.crc != stdout)
		fclose(d.crc);
	if (d.md5f && d.md5f != stdout)
		fclose(d.md5f);
	if (d.yuv)
		fclose(d.yuv);

	return d.errors ? 1 : 0;
}
