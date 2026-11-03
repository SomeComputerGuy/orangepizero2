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
	s->a = 1;
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

