// SPDX-License-Identifier: MIT
/*
 * avs2dec: minimal AVS2 (GB/T 33475.2, IEEE 1857.4) elementary stream
 * decoder for the V4L2 stateless AVS2 uAPI (V4L2_PIX_FMT_AVS2_FRAME) of the
 * cedrus driver, written as a test tool for the Allwinner H616.
 *
 * Usage:
 *   avs2dec [-d /dev/videoN] [-m /dev/mediaN] [-o out.yuv] [-f] [-n bufs]
 *           [-c frames] [-v] stream.avs2
 *   avs2dec -p [-v] stream.avs2          parse only, no V4L2 (host test)
 *   curl -s URL | avs2dec ... -          stream from a pipe (read to EOF)
 *
 * The output is planar 4:2:0 (I420) cropped to the display size: 8 bits
 * per sample for 8-bit streams, 16-bit little endian samples for 10-bit
 * streams, in output (picture order count) order. The MD5 of the whole
 * output is printed at the end; -f prints one MD5 per frame as well.
 *
 * Clean-room: written from the AVS2 syntax as described in
 * harness/research/avs2/syntax.md, which was put together from several open
 * parsers (Rockchip MPP, davs2, Amlogic, the Moore Threads FFmpeg patch).
 * No code was copied from them; the structure (header parsing in software,
 * reference list from the reference configuration set, DOI unwrap, POC
 * derivation, picture marking and output bumping) follows the description
 * there. The weighting quantization tables in avs2_wq_tables.h are copied
 * from Rockchip MPP (Apache-2.0, see that file). MD5 is implemented from
 * RFC 1321.
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

#include "avs2_wq_tables.h"

#define SZ_PADDING	(64 * 1024)
#define MAX_RCS		32
#define MAX_REFS	7
#define MAX_BUFS	32
#define NUM_OUT_BUFS	4	/* >= the request queue depth (AVS2_DEPTH) */

static int verbose;

static void die(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	fprintf(stderr, "avs2dec: ");
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
	uint8_t *buf;		/* cleaned copy */
	size_t nbits;
	size_t pos;
	bool overrun;
};

/*
 * AVS2 encoders insert the two bits '10' wherever a start code prefix
 * would otherwise be emulated, so the byte after two zero bytes reads
 * 0x02. Remove those two bits: the following data moves up by two bits.
 */
static void bits_init(struct bits *b, const uint8_t *p, size_t len)
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
/* Headers                                                            */

struct rcs {
	bool refered_by_others;
	unsigned int num_ref;
	unsigned int ref_delta[MAX_REFS];
	unsigned int num_removed;
	unsigned int removed_delta[MAX_REFS];
};

struct seq {
	bool valid;
	unsigned int profile, level;
	bool progressive, field_coded;
	unsigned int width, height;
	unsigned int chroma_format, sample_precision, encoding_precision;
	bool low_delay, temporal_id_enable;
	unsigned int lcu_size;
	bool wq_enable;
	uint8_t wqm[2][64];
	bool background_enable;
	bool mhp_skip, dhp, wsm, amp, nsqt, nsip, secondary_transform, sao, alf;
	bool pmvr, cross_slice_lf, bcbr;
	unsigned int num_rcs;
	struct rcs rcs[MAX_RCS];
	unsigned int reorder_delay;
};

struct alf {
	bool enable[3];
	unsigned int num_luma;
	int16_t luma[16][9];
	int16_t chroma[2][9];
	uint8_t region[16];
};

struct pic {
	bool intra;
	unsigned int coding_type;	/* V4L2_AVS2_PICTURE_TYPE_* */
	bool background_picture, background_output;
	bool background_pred, background_reference;
	unsigned int doi, temporal_id, output_delay;
	bool output_delay_present;
	struct rcs rcs;
	bool progressive_frame;
	unsigned int picture_structure;
	bool top_field_first, repeat_first_field, is_top_field;
	bool fixed_qp;
	unsigned int qp;
	bool random_access_decodable;
	bool lf_disable;
	int alpha, beta, cb_delta, cr_delta;
	bool wq_enable;
	uint8_t wqm[2][64];	/* resolved matrices */
	struct alf alf;
};

static void parse_rcs(struct bits *b, struct rcs *r)
{
	unsigned int i;

	r->refered_by_others = u(b, 1);
	r->num_ref = u(b, 3);
	for (i = 0; i < r->num_ref; i++)
		r->ref_delta[i] = u(b, 6);
	r->num_removed = u(b, 3);
	for (i = 0; i < r->num_removed; i++)
		r->removed_delta[i] = u(b, 6);
	u(b, 1);	/* marker_bit */
}

static void parse_wq_matrix(struct bits *b, uint8_t m[2][64])
{
	unsigned int i;

	for (i = 0; i < 16; i++)
		m[0][i] = ue(b);
	for (i = 0; i < 64; i++)
		m[1][i] = ue(b);
}

static int parse_sequence_header(struct bits *b, struct seq *s)
{
	unsigned int i;

	memset(s, 0, sizeof(*s));
	s->profile = u(b, 8);
	s->level = u(b, 8);
	s->progressive = u(b, 1);
	s->field_coded = u(b, 1);
	s->width = u(b, 14);
	s->height = u(b, 14);
	s->chroma_format = u(b, 2);
	s->sample_precision = u(b, 3);
	s->encoding_precision = s->profile == 0x22 ? u(b, 3) : 1;
	u(b, 4);		/* aspect_ratio_information */
	u(b, 4);		/* frame_rate_code */
	u(b, 18);		/* bit_rate_lower */
	u(b, 1);		/* marker_bit */
	u(b, 12);		/* bit_rate_upper */
	s->low_delay = u(b, 1);
	u(b, 1);		/* marker_bit */
	s->temporal_id_enable = u(b, 1);
	u(b, 18);		/* bbv_buffer_size */
	s->lcu_size = u(b, 3);
	s->wq_enable = u(b, 1);
	if (s->wq_enable) {
		if (u(b, 1)) {	/* load_seq_weight_quant_data_flag */
			parse_wq_matrix(b, s->wqm);
		} else {
			memcpy(s->wqm[0], avs2_wq_default_4x4, 16);
			memcpy(s->wqm[1], avs2_wq_default_8x8, 64);
		}
	}
	s->background_enable = !u(b, 1);
	s->mhp_skip = u(b, 1);
	s->dhp = u(b, 1);
	s->wsm = u(b, 1);
	s->amp = u(b, 1);
	s->nsqt = u(b, 1);
	s->nsip = u(b, 1);
	s->secondary_transform = u(b, 1);
	s->sao = u(b, 1);
	s->alf = u(b, 1);
	s->pmvr = u(b, 1);
	u(b, 1);		/* marker_bit */
	s->num_rcs = u(b, 6);
	if (s->num_rcs > MAX_RCS)
		return -1;
	for (i = 0; i < s->num_rcs; i++)
		parse_rcs(b, &s->rcs[i]);
	s->reorder_delay = s->low_delay ? 0 : u(b, 5);
	s->cross_slice_lf = u(b, 1);
	/*
	 * Read by the vendor library for profiles 0x21 and 0x23 only
	 * (not Main or Main10).
	 */
	if ((s->profile | 2) == 0x23 && s->background_enable)
		s->bcbr = u(b, 1);

	if (b->overrun || s->lcu_size < 4 || s->lcu_size > 6 ||
	    !s->sample_precision || s->sample_precision > 2 ||
	    !s->encoding_precision || s->encoding_precision > 2 ||
	    s->width < 16 || s->height < 16)
		return -1;

	s->valid = true;
	return 0;
}

static void parse_alf(struct bits *b, struct alf *a)
{
	unsigned int f, i, pre = 0;
	bool pattern[16] = { false };

	memset(a, 0, sizeof(*a));
	for (i = 0; i < 3; i++)
		a->enable[i] = u(b, 1);

	if (a->enable[0]) {
		a->num_luma = ue(b) + 1;
		if (a->num_luma > 16) {
			b->overrun = true;
			return;
		}
		for (f = 0; f < a->num_luma; f++) {
			if (f > 0) {
				unsigned int dist = a->num_luma == 16 ? 1 : ue(b);

				pre += dist;
				if (pre < 16)
					pattern[pre] = true;
				else
					b->overrun = true;
			}
			for (i = 0; i < 9; i++)
				a->luma[f][i] = se(b);
		}
		for (i = 1; i < 16; i++)
			a->region[i] = a->region[i - 1] +
				       (a->num_luma > 1 && pattern[i]);
	}

	for (f = 0; f < 2; f++)
		if (a->enable[1 + f])
			for (i = 0; i < 9; i++)
				a->chroma[f][i] = se(b);
}

static void resolve_wq(const struct seq *s, struct pic *p, unsigned int data_index,
		       unsigned int param_index, unsigned int model,
		       const int delta[6], const uint8_t pic_m[2][64])
{
	unsigned int i;
	int param[6];

	if (!s->wq_enable || !p->wq_enable) {
		memset(p->wqm, 64, sizeof(p->wqm));
		return;
	}

	switch (data_index) {
	case 0:
		memcpy(p->wqm, s->wqm, sizeof(p->wqm));
		break;
	case 1:
		for (i = 0; i < 6; i++) {
			if (param_index == 0)
				param[i] = avs2_wq_param_default[AVS2_WQ_DETAILED][i];
			else if (param_index == 1)
				param[i] = delta[i] + avs2_wq_param_default[AVS2_WQ_UNDETAILED][i];
			else
				param[i] = delta[i] + avs2_wq_param_default[AVS2_WQ_DETAILED][i];
		}
		for (i = 0; i < 64; i++)
			p->wqm[1][i] = param[avs2_wq_model_8x8[model][i]];
		for (i = 0; i < 16; i++)
			p->wqm[0][i] = param[avs2_wq_model_4x4[model][i]];
		break;
	default:
		memcpy(p->wqm, pic_m, sizeof(p->wqm));
		break;
	}
}

/* Common tail of the intra and inter picture headers. */
static void parse_picture_tail(struct bits *b, const struct seq *s, struct pic *p)
{
	unsigned int data_index = 0, param_index = 0, model = 0, i;
	int delta[6] = { 0 };
	uint8_t pic_m[2][64];

	p->lf_disable = u(b, 1);
	if (!p->lf_disable && u(b, 1)) {	/* loop_filter_parameter_flag */
		p->alpha = se(b);
		p->beta = se(b);
	}
	if (!u(b, 1)) {				/* chroma_quant_param_disable */
		p->cb_delta = se(b);
		p->cr_delta = se(b);
	}

	if (s->wq_enable) {
		p->wq_enable = u(b, 1);
		if (p->wq_enable) {
			data_index = u(b, 2);
			if (data_index == 1) {
				u(b, 1);	/* reserved */
				param_index = u(b, 2);
				model = u(b, 2);
				if (param_index == 1 || param_index == 2)
					for (i = 0; i < 6; i++)
						delta[i] = se(b);
			} else if (data_index == 2) {
				parse_wq_matrix(b, pic_m);
			}
		}
	}
	resolve_wq(s, p, data_index, param_index, model, delta, pic_m);

	if (s->alf)
		parse_alf(b, &p->alf);
}

static int parse_picture_rcs(struct bits *b, const struct seq *s, struct pic *p)
{
	if (u(b, 1)) {		/* reference_configuration_set_flag */
		unsigned int idx = u(b, 5);

		if (idx >= s->num_rcs)
			return -1;
		p->rcs = s->rcs[idx];
	} else {
		parse_rcs(b, &p->rcs);
	}
	return 0;
}

static void parse_picture_structure(struct bits *b, const struct seq *s,
				    struct pic *p)
{
	p->progressive_frame = u(b, 1);
	p->picture_structure = p->progressive_frame ? 1 : u(b, 1);
	p->top_field_first = u(b, 1);
	p->repeat_first_field = u(b, 1);
	if (s->field_coded) {
		p->is_top_field = u(b, 1);
		u(b, 1);	/* reserved */
	}
	p->fixed_qp = u(b, 1);
	p->qp = u(b, 7);
}

static int parse_intra_header(struct bits *b, const struct seq *s, struct pic *p)
{
	memset(p, 0, sizeof(*p));
	p->intra = true;
	p->coding_type = V4L2_AVS2_PICTURE_TYPE_I;

	u(b, 32);		/* bbv_delay */
	if (u(b, 1))		/* time_code_flag */
		u(b, 24);
	if (s->background_enable) {
		p->background_picture = u(b, 1);
		if (p->background_picture)
			p->background_output = u(b, 1);
	}
	p->doi = u(b, 8);
	if (s->temporal_id_enable)
		p->temporal_id = u(b, 3);
	/* Not coded for a background picture which is not output (GB). */
	if (!s->low_delay && !(p->background_picture && !p->background_output)) {
		p->output_delay = ue(b);
		p->output_delay_present = true;
	}
	if (parse_picture_rcs(b, s, p))
		return -1;
	if (s->low_delay)
		ue(b);		/* bbv_check_times */
	parse_picture_structure(b, s, p);
	parse_picture_tail(b, s, p);

	return b->overrun ? -1 : 0;
}

static int parse_inter_header(struct bits *b, const struct seq *s, struct pic *p)
{
	unsigned int pct;

	memset(p, 0, sizeof(*p));

	u(b, 32);		/* bbv_delay */
	pct = u(b, 2);
	if (!pct)
		return -1;
	p->coding_type = pct;	/* 1 P, 2 B, 3 F as in the uAPI */
	if (s->background_enable) {
		if (pct == 1)
			p->background_pred = u(b, 1);
		if (pct != 2 && !p->background_pred)
			p->background_reference = u(b, 1);
	}
	p->doi = u(b, 8);
	if (s->temporal_id_enable)
		p->temporal_id = u(b, 3);
	if (!s->low_delay) {
		p->output_delay = ue(b);
		p->output_delay_present = true;
	}
	if (parse_picture_rcs(b, s, p))
		return -1;
	if (s->low_delay)
		ue(b);		/* bbv_check_times */
	parse_picture_structure(b, s, p);
	if (pct != 2 || p->picture_structure == 0)
		u(b, 1);	/* reserved */
	p->random_access_decodable = u(b, 1);
	parse_picture_tail(b, s, p);

	return b->overrun ? -1 : 0;
}

/* ------------------------------------------------------------------ */
/* Decoded picture buffer                                             */

struct frame {
	bool used;		/* holds a decoded picture */
	bool referenced;	/* used for reference by later pictures */
	bool scene;		/* the background (scene) reference */
	bool needs_output;
	int64_t doi;
	int32_t poc;
	uint8_t type;
	unsigned int num_refs;
	int32_t ref_poc[MAX_REFS];
	uint64_t ts;
	unsigned int out_index;	/* frame number in output order */
	bool inflight;		/* its decode request has not completed yet */
	bool out_pending;	/* chosen for output, readback not done yet */
};

struct v4l2_ctx;

struct decoder {
	struct seq seq;
	struct frame frames[MAX_BUFS];
	unsigned int num_bufs;
	int64_t doi_wrap;
	int prev_doi;
	unsigned int prev_output_delay;
	int scene;		/* index of the scene frame, -1 if none */
	int64_t last_output_poc;
	bool output_started;
	unsigned int pic_count;
	unsigned int out_count;
	unsigned int max_frames;
	bool frame_md5;
	FILE *out;
	struct md5 md5;
	struct md5 frame_md5_ctx;
	struct v4l2_ctx *v4l2;
	uint8_t *rowbuf;
	/* Output order FIFO of pictures whose readback waits for their decode. */
	int outq[MAX_BUFS];
	unsigned int outq_head, outq_len;
};

static void output_frame(struct decoder *d, int idx);
static void flush_outputs(struct decoder *d, bool wait);

static int find_ref(struct decoder *d, int64_t doi)
{
	unsigned int i;

	for (i = 0; i < d->num_bufs; i++)
		if (d->frames[i].used && d->frames[i].referenced &&
		    d->frames[i].doi == doi)
			return i;
	return -1;
}

static int pending_count(struct decoder *d)
{
	unsigned int i;
	int n = 0;

	for (i = 0; i < d->num_bufs; i++)
		n += d->frames[i].used && d->frames[i].needs_output;
	return n;
}

static int smallest_pending(struct decoder *d)
{
	unsigned int i;
	int best = -1;

	for (i = 0; i < d->num_bufs; i++)
		if (d->frames[i].used && d->frames[i].needs_output &&
		    (best < 0 || d->frames[i].poc < d->frames[best].poc))
			best = i;
	return best;
}

static void release_unused(struct decoder *d)
{
	unsigned int i;

	for (i = 0; i < d->num_bufs; i++) {
		struct frame *f = &d->frames[i];

		if (f->used && !f->referenced && !f->scene && !f->needs_output &&
		    !f->inflight && !f->out_pending)
			f->used = false;
	}
}

/* Output pictures in POC order once nothing earlier can still arrive. */
static void bump(struct decoder *d, bool flush)
{
	for (;;) {
		int idx = smallest_pending(d);

		if (idx < 0)
			break;
		if (!flush &&
		    !(d->output_started &&
		      d->frames[idx].poc <= d->last_output_poc + 1) &&
		    pending_count(d) <= (int)d->seq.reorder_delay + 1)
			break;
		output_frame(d, idx);
		d->frames[idx].needs_output = false;
		d->last_output_poc = d->frames[idx].poc;
		d->output_started = true;
	}
	release_unused(d);
}

static int get_free_frame(struct decoder *d)
{
	unsigned int i;

	for (;;) {
		release_unused(d);
		for (i = 0; i < d->num_bufs; i++)
			if (!d->frames[i].used)
				return i;
		/* Pictures waiting for readback free their buffers first. */
		if (d->outq_len) {
			flush_outputs(d, true);
			continue;
		}
		/* No free buffer: output the earliest picture early. */
		if (smallest_pending(d) < 0)
			return -1;
		i = smallest_pending(d);
		output_frame(d, i);
		d->frames[i].needs_output = false;
		d->last_output_poc = d->frames[i].poc;
		d->output_started = true;
	}
}

/* ------------------------------------------------------------------ */
/* V4L2 stateless decoding                                            */

static bool afbc_out;			/* -o given with AVS2_CAP=AFBC */
static unsigned int afbc_written;	/* AFBC frames written to -o */

struct v4l2_ctx {
	int video_fd, media_fd;
	int req_fd[NUM_OUT_BUFS];
	void *out_map[NUM_OUT_BUFS];
	size_t out_size[NUM_OUT_BUFS];
	void *cap_map[MAX_BUFS];
	size_t cap_len[MAX_BUFS];
	struct v4l2_pix_format cap_fmt;
	unsigned int num_cap;
	unsigned int next_out;
	bool p010;
	bool afbc;		/* AFBC capture: -o gets the raw buffers */
	/*
	 * Requests in flight, oldest first (AVS2_DEPTH, default 2): the next
	 * picture is queued while the VE still decodes the previous one, so
	 * the m2m core starts it straight from the completion interrupt.
	 */
	unsigned int depth;
	unsigned int fifo_out[NUM_OUT_BUFS], fifo_cap[NUM_OUT_BUFS];
	unsigned int fifo_head, fifo_len;
};

static void xioctl(int fd, unsigned long req, void *arg, const char *name)
{
	if (ioctl(fd, req, arg) < 0)
		die("%s: %s", name, strerror(errno));
}

/*
 * Board experiment (env AVS2_ALF_MODE): alternative luma region map
 * layouts, to find the one the engine uses. 0 = as derived (coding
 * order regions).
 */
static void alf_experiment(struct v4l2_ctrl_avs2_alf *a)
{
	static const uint8_t tab[16] = { 0, 1, 4, 5, 15, 2, 3, 6,
					 14, 11, 10, 7, 13, 12, 9, 8 };
	const char *e = getenv("AVS2_ALF_MODE");
	int mode = e ? atoi(e) : 0;
	uint8_t idx[16], m[16];
	int16_t c[16][9];
	unsigned int i;

	if (!mode)
		return;
	memcpy(idx, a->luma_region_filter, 16);
	memcpy(c, a->luma_coeff, sizeof(c));
	for (i = 0; i < 16; i++) {
		switch (mode) {
		case 1: m[i] = idx[tab[i]]; break;	/* raster -> region */
		case 2: m[tab[i]] = idx[i]; break;	/* inverse */
		case 3: m[i] = idx[i ^ 1]; break;	/* nibble swap */
		default: m[i] = idx[i]; break;
		}
	}
	if (mode == 11) {
		/* every slot filter 0, slot AVS2_ALF_SLOT the identity filter */
		const char *se = getenv("AVS2_ALF_SLOT");
		int slot = se ? atoi(se) : -1;

		for (i = 0; i < 16; i++) {
			memcpy(a->luma_coeff[i], c[0], sizeof(c[0]));
			if ((int)i == slot)
				memset(a->luma_coeff[i], 0, sizeof(c[0]));
			m[i] = i;
		}
		a->num_luma_filters = 16;
		memcpy(a->luma_region_filter, m, 16);
		return;
	}
	if (mode >= 10) {
		/* slot r gets the filter of spec region perm[r], identity map */
		const char *pe = getenv("AVS2_ALF_PERM");
		unsigned int perm[16];

		for (i = 0; i < 16; i++)
			perm[i] = i;
		for (i = 0; pe && i < 16; i++)
			perm[i] = strtoul(pe, (char **)&pe, 10) & 15;
		for (i = 0; i < 16; i++) {
			memcpy(a->luma_coeff[i], c[idx[perm[i]]], sizeof(c[0]));
			m[i] = i;
		}
		a->num_luma_filters = 16;
		memcpy(a->luma_region_filter, m, 16);
		return;
	}
	if (mode == 4 || mode == 5 || mode == 6) {
		/* one filter per region, identity map */
		for (i = 0; i < 16; i++) {
			unsigned int r = mode == 5 ? tab[i] : i;
			unsigned int src = idx[r];

			if (mode == 6) {
				r = i;
				src = idx[tab[i]];
			}
			memcpy(a->luma_coeff[i], c[src], sizeof(c[0]));
			m[i] = i;
		}
		if (mode == 5) {
			/* filter i = region tab[i]'s filter, map region r -> position */
			for (i = 0; i < 16; i++)
				m[tab[i]] = i;
		}
		a->num_luma_filters = 16;
	}
	memcpy(a->luma_region_filter, m, 16);
}

static void fill_sequence_ctrl(const struct seq *s, struct v4l2_ctrl_avs2_sequence *c)
{
	memset(c, 0, sizeof(*c));
#define SF(cond, flag) do { if (cond) c->flags |= V4L2_AVS2_SEQUENCE_FLAG_##flag; } while (0)
	SF(s->progressive, PROGRESSIVE_SEQUENCE);
	SF(s->field_coded, FIELD_CODED_SEQUENCE);
	SF(s->low_delay, LOW_DELAY);
	SF(s->temporal_id_enable, TEMPORAL_ID_ENABLE);
	SF(s->wq_enable, WEIGHT_QUANT_ENABLE);
	SF(s->background_enable, BACKGROUND_PICTURE_ENABLE);
	SF(s->mhp_skip, MHP_SKIP_ENABLE);
	SF(s->dhp, DHP_ENABLE);
	SF(s->wsm, WSM_ENABLE);
	SF(s->amp, AMP_ENABLE);
	SF(s->nsqt, NSQT_ENABLE);
	SF(s->nsip, NSIP_ENABLE);
	SF(s->secondary_transform, SECONDARY_TRANSFORM_ENABLE);
	SF(s->sao, SAO_ENABLE);
	SF(s->alf, ALF_ENABLE);
	SF(s->pmvr, PMVR_ENABLE);
	SF(s->cross_slice_lf, CROSS_SLICE_LOOPFILTER_ENABLE);
	SF(s->bcbr, BCBR_ENABLE);
#undef SF
	c->horizontal_size = s->width;
	c->vertical_size = s->height;
	c->profile_id = s->profile;
	c->level_id = s->level;
	c->chroma_format = s->chroma_format;
	c->sample_precision = s->sample_precision;
	c->encoding_precision = s->encoding_precision;
	c->lcu_size = s->lcu_size;
	c->picture_reorder_delay = s->reorder_delay;
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
				  const struct seq *s, unsigned int num_cap)
{
	struct v4l2_ctx *v = calloc(1, sizeof(*v));
	struct v4l2_ctrl_avs2_sequence sc;
	struct v4l2_ext_control c = {
		.id = V4L2_CID_STATELESS_AVS2_SEQUENCE,
		.size = sizeof(sc),
		.ptr = &sc,
	};
	struct v4l2_format fmt = { 0 };
	struct v4l2_requestbuffers rb = { 0 };
	enum v4l2_buf_type type;
	unsigned int i;

	if (!v)
		die("out of memory");
	v->video_fd = open(video, O_RDWR);
	if (v->video_fd < 0)
		die("%s: %s", video, strerror(errno));
	v->media_fd = open(media, O_RDWR);
	if (v->media_fd < 0)
		die("%s: %s", media, strerror(errno));

	fmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_AVS2_FRAME;
	fmt.fmt.pix.width = s->width;
	fmt.fmt.pix.height = s->height;
	fmt.fmt.pix.sizeimage = s->width * s->height + SZ_PADDING;
	xioctl(v->video_fd, VIDIOC_S_FMT, &fmt, "VIDIOC_S_FMT(OUTPUT)");
	if (fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_AVS2_FRAME)
		die("the driver has no AVS2_FRAME output format");

	/* The sequence sets the bit depth and with it the capture formats. */
	fill_sequence_ctrl(s, &sc);
	set_ctrls(v->video_fd, -1, &c, 1);

	/*
	 * 10-bit pictures go to P010 unless AVS2_CAP=NV12, which selects the
	 * 8-bit planes of the NV12 + 2-bit layout (a separate linear
	 * reconstruction path, for cross-checking the P010 output).
	 */
	v->p010 = s->sample_precision > 1 &&
		  !(getenv("AVS2_CAP") && !strcmp(getenv("AVS2_CAP"), "NV12"));
	memset(&fmt, 0, sizeof(fmt));
	fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	fmt.fmt.pix.pixelformat = v->p010 ? V4L2_PIX_FMT_P010 : V4L2_PIX_FMT_NV12;
	/* AVS2_CAP=ST12: tiled NV12_32L32, throughput runs only (AVS2_NOOUT=1). */
	if (getenv("AVS2_CAP") && !strcmp(getenv("AVS2_CAP"), "ST12")) {
		if (!getenv("AVS2_NOOUT"))
			die("AVS2_CAP=ST12 needs AVS2_NOOUT=1");
		v->p010 = false;
		fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_NV12_32L32;
	}
	/*
	 * AVS2_CAP=AFBC: 10-bit AFBC capture. No linear readback or md5:
	 * either AVS2_NOOUT=1 (throughput runs) or -o file, which then gets
	 * the raw AFBC capture buffers in output order (see readback_frame()).
	 */
	if (getenv("AVS2_CAP") && !strcmp(getenv("AVS2_CAP"), "AFBC")) {
		if (!getenv("AVS2_NOOUT") && !afbc_out)
			die("AVS2_CAP=AFBC needs AVS2_NOOUT=1 or -o file");
		v->p010 = false;
		v->afbc = true;
		fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_YUV420_10_AFBC_16X16_SPLIT;
	}
	fmt.fmt.pix.width = s->width;
	fmt.fmt.pix.height = s->height;
	xioctl(v->video_fd, VIDIOC_S_FMT, &fmt, "VIDIOC_S_FMT(CAPTURE)");
	{
		const char *cap = getenv("AVS2_CAP") ? getenv("AVS2_CAP") : "";
		uint32_t want = v->p010 ? V4L2_PIX_FMT_P010 :
				!strcmp(cap, "ST12") ? V4L2_PIX_FMT_NV12_32L32 :
				!strcmp(cap, "AFBC") ?
				V4L2_PIX_FMT_YUV420_10_AFBC_16X16_SPLIT :
				V4L2_PIX_FMT_NV12;

		if (fmt.fmt.pix.pixelformat != want)
			die("capture format %.4s not available", (char *)&want);
	}
	v->cap_fmt = fmt.fmt.pix;

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
	v->num_cap = num_cap;
	v->depth = getenv("AVS2_DEPTH") ? atoi(getenv("AVS2_DEPTH")) : 2;
	if (v->depth < 1 || v->depth > NUM_OUT_BUFS - 1)
		die("AVS2_DEPTH must be 1..%d", NUM_OUT_BUFS - 1);
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

/* Wait for the oldest request; returns its capture index, *error on failure. */
static unsigned int v4l2_complete_oldest(struct v4l2_ctx *v, int *error)
{
	unsigned int out = v->fifo_out[v->fifo_head];
	unsigned int cap = v->fifo_cap[v->fifo_head];
	int req = v->req_fd[out];
	struct v4l2_buffer buf = { 0 };
	struct pollfd pfd = { .fd = req, .events = POLLPRI };
	int ret;

	ret = poll(&pfd, 1, 5000);
	if (ret <= 0)
		die("request timed out");

	/* Completion is in queue order, so the oldest buffers come back. */
	buf.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	buf.memory = V4L2_MEMORY_MMAP;
	xioctl(v->video_fd, VIDIOC_DQBUF, &buf, "VIDIOC_DQBUF(OUTPUT)");
	if (buf.index != out)
		die("dequeued output buffer %u, expected %u", buf.index, out);

	memset(&buf, 0, sizeof(buf));
	buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	buf.memory = V4L2_MEMORY_MMAP;
	xioctl(v->video_fd, VIDIOC_DQBUF, &buf, "VIDIOC_DQBUF(CAPTURE)");
	if (buf.index != cap)
		die("dequeued capture buffer %u, expected %u", buf.index, cap);
	*error = (buf.flags & V4L2_BUF_FLAG_ERROR) ? -1 : 0;

	xioctl(req, MEDIA_REQUEST_IOC_REINIT, NULL, "MEDIA_REQUEST_IOC_REINIT");

	v->fifo_head = (v->fifo_head + 1) % NUM_OUT_BUFS;
	v->fifo_len--;
	return cap;
}

static void complete_oldest(struct decoder *d)
{
	int error;
	unsigned int cap = v4l2_complete_oldest(d->v4l2, &error);
	struct frame *f = &d->frames[cap];

	f->inflight = false;
	if (error)
		fprintf(stderr, "picture doi %" PRId64 " poc %d: decode error\n",
			f->doi, f->poc);
}

/* Queue one picture; at most v->depth requests stay in flight. */
static void v4l2_submit(struct decoder *d, const uint8_t *data, size_t len,
			uint64_t ts, unsigned int cap_index,
			struct v4l2_ext_control *ctrls, unsigned int nctrls)
{
	struct v4l2_ctx *v = d->v4l2;
	unsigned int out = v->next_out;
	int req = v->req_fd[out];
	struct v4l2_buffer buf = { 0 };

	while (v->fifo_len >= v->depth)
		complete_oldest(d);

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

	xioctl(req, MEDIA_REQUEST_IOC_QUEUE, NULL, "MEDIA_REQUEST_IOC_QUEUE");

	v->fifo_out[(v->fifo_head + v->fifo_len) % NUM_OUT_BUFS] = out;
	v->fifo_cap[(v->fifo_head + v->fifo_len) % NUM_OUT_BUFS] = cap_index;
	v->fifo_len++;
	d->frames[cap_index].inflight = true;
}

/* ------------------------------------------------------------------ */
/* Output                                                             */

/*
 * Board test options (environment):
 * AVS2_OUT8=1   write 10-bit P010 pictures as their upper 8 bits (I420),
 *               to compare with the 8-bit planes of NV12 capture;
 * AVS2_DUMP=a,b only write output frames a, b, ... to the -o file (the
 *               md5s still cover every frame);
 * AVS2_NOOUT=1  skip reading the pictures back (no md5): throughput runs.
 * AVS2_CAP=AFBC with -o file: the raw 10-bit AFBC capture buffers go to the
 *               file in output order (32-byte header per frame, see
 *               readback_frame()) for vdec-perf/afbc/afbc-gpu-check.
 */
static bool out8;
static bool dump_this = true;

static bool dump_wanted(unsigned int n)
{
	const char *e = getenv("AVS2_DUMP");
	char *end;

	if (!e)
		return true;
	while (*e) {
		if (strtoul(e, &end, 10) == n && end != e)
			return true;
		if (end == e)
			break;
		e = *end ? end + 1 : end;
	}
	return false;
}

static void put(struct decoder *d, const void *p, size_t n)
{
	md5_update(&d->md5, p, n);
	if (d->frame_md5)
		md5_update(&d->frame_md5_ctx, p, n);
	if (d->out && dump_this && fwrite(p, 1, n, d->out) != n)
		die("write: %s", strerror(errno));
}

static void readback_frame(struct decoder *d, int idx);

/*
 * Output in POC order is decided here; the readback (md5, file) of a
 * picture still being decoded is deferred until its request completes,
 * in the same order.
 */
static void output_frame(struct decoder *d, int idx)
{
	d->frames[idx].out_pending = true;
	d->outq[(d->outq_head + d->outq_len) % MAX_BUFS] = idx;
	d->outq_len++;
	flush_outputs(d, false);
}

static void flush_outputs(struct decoder *d, bool wait)
{
	while (d->outq_len) {
		int idx = d->outq[d->outq_head];

		if (d->frames[idx].inflight) {
			if (!wait)
				return;
			while (d->frames[idx].inflight)
				complete_oldest(d);
		}
		d->outq_head = (d->outq_head + 1) % MAX_BUFS;
		d->outq_len--;
		d->frames[idx].out_pending = false;
		readback_frame(d, idx);
	}
}

static void readback_frame(struct decoder *d, int idx)
{
	struct frame *f = &d->frames[idx];
	struct v4l2_ctx *v = d->v4l2;
	unsigned int w = d->seq.width, h = d->seq.height, x, y, c;
	char sum[33];

	f->out_index = d->out_count++;
	dump_this = dump_wanted(f->out_index);

	if (verbose)
		fprintf(stderr, "output poc %d (doi %" PRId64 ")\n", f->poc,
			f->doi);
	/* AVS2_NOOUT=1: no readback or md5 (throughput runs). */
	if (!v || (getenv("AVS2_NOOUT") && atoi(getenv("AVS2_NOOUT"))))
		return;

	/*
	 * AFBC capture: write the raw capture buffer to the -o file behind a
	 * 32-byte header (the afbc-gpu-check dump format: magic, size, width,
	 * height, DRM fourcc YUV420_10BIT, AFBC 16x16|SPARSE|SPLIT modifier,
	 * output index). The md5 of an AFBC surface means nothing, so none.
	 */
	if (v->afbc) {
		struct {
			char magic[8];
			uint32_t size, width, height, drm_format;
			uint64_t modifier;
			uint32_t index;
		} __attribute__((packed)) hdr = {
			{ 'A', 'F', 'B', 'C', 'D', 'M', 'P', '1' },
			v->cap_len[idx], w, h,
			0x30315559,		/* DRM_FORMAT_YUV420_10BIT */
			(8ULL << 56) | 0x1 | 0x40 | 0x400,
			f->out_index,
		};

		if (!d->out)
			die("AFBC capture needs -o");
		if (fwrite(&hdr, sizeof(hdr), 1, d->out) != 1 ||
		    fwrite(v->cap_map[idx], 1, hdr.size, d->out) != hdr.size)
			die("write: %s", strerror(errno));
		fflush(d->out);
		afbc_written++;
		return;
	}

	if (d->frame_md5)
		md5_init(&d->frame_md5_ctx);

	{
		const uint8_t *base = v->cap_map[idx];
		unsigned int bpl = v->cap_fmt.bytesperline;
		const uint8_t *chroma = base + (size_t)bpl * v->cap_fmt.height;
		unsigned int bps = v->p010 ? 2 : 1;
		uint8_t *row = d->rowbuf;

		/*
		 * The capture mapping is not cached: copy each row into a
		 * cached buffer with wide loads before touching single bytes.
		 */
		static uint8_t *cached;
		static size_t cached_len;

		if (cached_len < bpl) {
			free(cached);
			cached = malloc(bpl);
			if (!cached)
				die("out of memory");
			cached_len = bpl;
		}

		for (y = 0; y < h; y++) {
			const uint8_t *src = cached;

			memcpy(cached, base + (size_t)y * bpl, bpl);

			if (v->p010) {
				for (x = 0; x < w; x++) {
					unsigned int s = src[2 * x] | src[2 * x + 1] << 8;

					s >>= 6;
					if (out8) {
						row[x] = s >> 2;
						continue;
					}
					row[2 * x] = s & 0xff;
					row[2 * x + 1] = s >> 8;
				}
				put(d, row, out8 ? w : 2 * w);
			} else {
				put(d, src, w);
			}
		}

		for (c = 0; c < 2; c++) {
			for (y = 0; y < (h + 1) / 2; y++) {
				const uint8_t *src = cached;

				memcpy(cached, chroma + (size_t)y * bpl, bpl);

				for (x = 0; x < (w + 1) / 2; x++) {
					if (v->p010) {
						const uint8_t *s = src + 4 * x + 2 * c;
						unsigned int val = (s[0] | s[1] << 8) >> 6;

						if (out8) {
							row[x] = val >> 2;
							continue;
						}
						row[2 * x] = val & 0xff;
						row[2 * x + 1] = val >> 8;
					} else {
						row[x] = src[2 * x + c];
					}
				}
				put(d, row, (out8 ? 1 : bps) * ((w + 1) / 2));
			}
		}
	}

	if (d->frame_md5) {
		md5_final(&d->frame_md5_ctx, sum);
		printf("frame %u poc %d md5 %s\n", f->out_index, f->poc, sum);
	}
}

/* ------------------------------------------------------------------ */
/* Picture decoding                                                    */

static void decode_picture(struct decoder *d, const uint8_t *data, size_t len,
			   size_t hdr_len, size_t data_offset, bool intra)
{
	const struct seq *s = &d->seq;
	struct v4l2_ctrl_avs2_picture pc;
	struct v4l2_ctrl_avs2_weight_quant wq;
	struct v4l2_ctrl_avs2_alf alf;
	struct v4l2_ext_control ctrls[4];
	int refs[MAX_REFS];
	unsigned int nrefs = 0, i, j;
	struct frame *cur;
	struct bits b;
	struct pic p;
	int64_t doi;
	int32_t poc;
	int idx, ret;

	if (!s->valid) {
		fprintf(stderr, "picture before any sequence header, skipped\n");
		return;
	}

	/* Header unit, without its 4-byte start code. */
	bits_init(&b, data + 4, hdr_len - 4);
	ret = intra ? parse_intra_header(&b, s, &p) : parse_inter_header(&b, s, &p);
	bits_free(&b);
	if (ret) {
		fprintf(stderr, "picture %u: bad picture header, skipped\n",
			d->pic_count);
		return;
	}

	/* Decode order index without its 8-bit wrap around. */
	if (d->prev_doi >= 0 && (int)p.doi < d->prev_doi)
		d->doi_wrap += 256;
	d->prev_doi = p.doi;
	doi = p.doi + d->doi_wrap;

	if (!p.output_delay_present)
		p.output_delay = d->prev_output_delay;
	d->prev_output_delay = p.output_delay;
	poc = s->low_delay ? doi : doi + p.output_delay - s->reorder_delay;

	/* Reference pictures, in the order of the configuration set. */
	if (!p.intra) {
		for (i = 0; i < p.rcs.num_ref; i++) {
			refs[i] = find_ref(d, doi - p.rcs.ref_delta[i]);
			if (refs[i] < 0)
				fprintf(stderr, "picture doi %" PRId64 ": reference doi %" PRId64 " missing\n",
					doi, doi - p.rcs.ref_delta[i]);
		}
		nrefs = p.rcs.num_ref;
		if (p.background_pred) {
			refs[0] = d->scene;
			nrefs = nrefs ? nrefs : 1;
		} else if (p.background_reference && nrefs) {
			refs[nrefs - 1] = d->scene;
		}
	}

	idx = get_free_frame(d);
	if (idx < 0)
		die("no free capture buffer");
	cur = &d->frames[idx];
	memset(cur, 0, sizeof(*cur));
	cur->doi = doi;
	cur->poc = poc;
	cur->type = p.coding_type;
	cur->ts = (uint64_t)(d->pic_count + 1) * 1000;
	cur->num_refs = p.background_pred ? 1 : nrefs;
	for (i = 0; i < nrefs; i++)
		cur->ref_poc[i] = refs[i] >= 0 ? d->frames[refs[i]].poc : 0;

	memset(&pc, 0, sizeof(pc));
	for (i = 0; i < nrefs; i++) {
		struct v4l2_avs2_ref_pic *r = &pc.ref_pics[i];
		struct frame *f;

		if (refs[i] < 0)
			continue;
		f = &d->frames[refs[i]];
		r->timestamp = f->ts;
		r->poc = f->poc;
		r->picture_type = f->type;
		r->num_ref_pics = f->num_refs;
		for (j = 0; j < f->num_refs; j++)
			r->ref_poc[j] = f->ref_poc[j];
		if (f->scene && refs[i] == d->scene)
			r->flags = V4L2_AVS2_REF_PIC_FLAG_BACKGROUND;
	}
	pc.data_offset = data_offset;
	pc.poc = poc;
	pc.picture_type = p.coding_type;
	pc.num_ref_pics = nrefs;
	pc.decode_order_index = p.doi;
	pc.temporal_id = p.temporal_id;
	pc.picture_output_delay = p.output_delay;
	pc.picture_qp = p.qp;
	pc.alpha_c_offset = p.alpha;
	pc.beta_offset = p.beta;
	pc.chroma_quant_param_delta_cb = p.cb_delta;
	pc.chroma_quant_param_delta_cr = p.cr_delta;
#define PF(cond, flag) do { if (cond) pc.flags |= V4L2_AVS2_PICTURE_FLAG_##flag; } while (0)
	PF(p.progressive_frame, PROGRESSIVE_FRAME);
	PF(p.picture_structure, PICTURE_STRUCTURE);
	PF(p.top_field_first, TOP_FIELD_FIRST);
	PF(p.repeat_first_field, REPEAT_FIRST_FIELD);
	PF(p.is_top_field, IS_TOP_FIELD);
	PF(p.fixed_qp, FIXED_PICTURE_QP);
	PF(p.lf_disable, LOOP_FILTER_DISABLE);
	PF(p.rcs.refered_by_others, REFERED_BY_OTHERS);
	PF(p.background_picture, BACKGROUND_PICTURE);
	PF(p.background_output, BACKGROUND_PICTURE_OUTPUT);
	PF(p.background_pred, BACKGROUND_PRED);
	PF(p.background_reference, BACKGROUND_REFERENCE);
	PF(p.random_access_decodable, RANDOM_ACCESS_DECODABLE);
	PF(p.wq_enable, WEIGHT_QUANT_ENABLE);
#undef PF

	memcpy(wq.matrix_4x4, p.wqm[0], 16);
	memcpy(wq.matrix_8x8, p.wqm[1], 64);

	memset(&alf, 0, sizeof(alf));
	if (p.alf.enable[0])
		alf.flags |= V4L2_AVS2_ALF_FLAG_LUMA_ENABLE;
	if (p.alf.enable[1])
		alf.flags |= V4L2_AVS2_ALF_FLAG_CB_ENABLE;
	if (p.alf.enable[2])
		alf.flags |= V4L2_AVS2_ALF_FLAG_CR_ENABLE;
	alf.num_luma_filters = p.alf.num_luma;
	memcpy(alf.luma_coeff, p.alf.luma, sizeof(alf.luma_coeff));
	memcpy(alf.chroma_coeff, p.alf.chroma, sizeof(alf.chroma_coeff));
	memcpy(alf.luma_region_filter, p.alf.region, 16);
	alf_experiment(&alf);

	if (verbose) {
		static const char tn[] = "IPBF";

		fprintf(stderr, "pic %u: %c%s doi %" PRId64 " poc %d qp %u refs",
			d->pic_count, tn[p.coding_type],
			p.background_pred ? "(S)" : p.background_picture ?
			(p.background_output ? "(G)" : "(GB)") : "",
			doi, poc, p.qp);
		for (i = 0; i < nrefs; i++)
			fprintf(stderr, " %d", cur->ref_poc[i]);
		fprintf(stderr, " alf %d%d%d/%u wq %d len %zu off %zu buf %d\n",
			p.alf.enable[0], p.alf.enable[1], p.alf.enable[2],
			p.alf.num_luma, p.wq_enable, len, data_offset, idx);
	}

	if (d->v4l2) {
		struct v4l2_ctrl_avs2_sequence sc;

		fill_sequence_ctrl(s, &sc);
		ctrls[0] = (struct v4l2_ext_control){
			.id = V4L2_CID_STATELESS_AVS2_SEQUENCE,
			.size = sizeof(sc), .ptr = &sc };
		ctrls[1] = (struct v4l2_ext_control){
			.id = V4L2_CID_STATELESS_AVS2_PICTURE,
			.size = sizeof(pc), .ptr = &pc };
		ctrls[2] = (struct v4l2_ext_control){
			.id = V4L2_CID_STATELESS_AVS2_WEIGHT_QUANT,
			.size = sizeof(wq), .ptr = &wq };
		ctrls[3] = (struct v4l2_ext_control){
			.id = V4L2_CID_STATELESS_AVS2_ALF,
			.size = sizeof(alf), .ptr = &alf };
		v4l2_submit(d, data, len, cur->ts, idx, ctrls, 4);
	}

	cur->used = true;
	d->pic_count++;

	/* Marking. */
	for (i = 0; i < p.rcs.num_removed; i++) {
		int r = find_ref(d, doi - p.rcs.removed_delta[i]);

		if (r >= 0)
			d->frames[r].referenced = false;
	}
	for (i = 0; i < d->num_bufs; i++) {
		struct frame *f = &d->frames[i];

		if (f->used && f->referenced &&
		    (f->poc - poc >= 128 || poc - f->poc >= 128))
			f->referenced = false;
	}
	cur->referenced = p.rcs.refered_by_others &&
			  !(p.background_picture && !p.background_output);
	if (p.background_picture) {
		if (d->scene >= 0)
			d->frames[d->scene].scene = false;
		cur->scene = true;
		d->scene = idx;
	}
	cur->needs_output = !(p.background_picture && !p.background_output);

	bump(d, false);
}

/* ------------------------------------------------------------------ */
/* Elementary stream                                                  */

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
		"usage: avs2dec [-p] [-d video] [-m media] [-o out.yuv] [-f]\n"
		"               [-n capture_buffers] [-c max_frames] [-v] stream\n");
	exit(2);
}

int main(int argc, char **argv)
{
	const char *video = "/dev/video0", *media = "/dev/media0", *outname = NULL;
	struct decoder d = { .prev_doi = -1, .scene = -1, .num_bufs = 16 };
	bool parse_only = false;
	size_t len, pos, pic_start = 0, pic_hdr_end = 0, slice_off = 0;
	bool in_pic = false, pic_intra = false;
	uint8_t *data;
	struct stat st;
	char sum[33];
	int opt, fd;

	while ((opt = getopt(argc, argv, "pd:m:o:fn:c:v")) != -1) {
		switch (opt) {
		case 'p': parse_only = true; break;
		case 'd': video = optarg; break;
		case 'm': media = optarg; break;
		case 'o': outname = optarg; break;
		case 'f': d.frame_md5 = true; break;
		case 'n': d.num_bufs = atoi(optarg); break;
		case 'c': d.max_frames = atoi(optarg); break;
		case 'v': verbose++; break;
		default: usage();
		}
	}
	if (optind + 1 != argc || d.num_bufs < 2 || d.num_bufs > MAX_BUFS)
		usage();
	out8 = getenv("AVS2_OUT8") && atoi(getenv("AVS2_OUT8"));
	afbc_out = outname != NULL;

	/* "-" or any non-regular file (a pipe from curl) is read to EOF. */
	if (!strcmp(argv[optind], "-"))
		fd = STDIN_FILENO;
	else
		fd = open(argv[optind], O_RDONLY);
	if (fd < 0 || fstat(fd, &st))
		die("%s: %s", argv[optind], strerror(errno));
	if (S_ISREG(st.st_mode)) {
		len = st.st_size;
		data = malloc(len + 4);
		if (!data || read(fd, data, len) != (ssize_t)len)
			die("read %s failed", argv[optind]);
	} else {
		size_t cap = 1 << 20;
		ssize_t n;

		len = 0;
		data = malloc(cap + 4);
		while (data) {
			if (len == cap) {
				cap *= 2;
				data = realloc(data, cap + 4);
				if (!data)
					break;
			}
			n = read(fd, data + len, cap - len);
			if (n < 0 && errno == EINTR)
				continue;
			if (n < 0)
				die("read %s: %s", argv[optind], strerror(errno));
			if (!n)
				break;
			len += n;
		}
		if (!data)
			die("out of memory reading %s", argv[optind]);
	}
	if (fd != STDIN_FILENO)
		close(fd);

	if (outname) {
		d.out = fopen(outname, "wb");
		if (!d.out)
			die("%s: %s", outname, strerror(errno));
	}
	md5_init(&d.md5);

	pos = next_start_code(data, len, 0);
	while (pos < len) {
		size_t next = next_start_code(data, len, pos + 3);
		unsigned int code = data[pos + 3];
		bool is_slice = code <= 0x8f;

		/* A picture ends at the first start code that is not a slice. */
		if (in_pic && !is_slice) {
			if (slice_off)
				decode_picture(&d, data + pic_start, pos - pic_start,
					       pic_hdr_end - pic_start,
					       slice_off - pic_start, pic_intra);
			in_pic = false;
			if (d.max_frames && d.pic_count >= d.max_frames)
				break;
		}

		switch (code) {
		case 0xb0: {
			struct bits b;
			struct seq s;

			bits_init(&b, data + pos + 4, next - pos - 4);
			if (parse_sequence_header(&b, &s)) {
				fprintf(stderr, "bad sequence header at %zu\n", pos);
			} else {
				if (d.seq.valid &&
				    (s.width != d.seq.width || s.height != d.seq.height ||
				     s.sample_precision != d.seq.sample_precision))
					die("sequence parameters change mid-stream (not supported)");
				if (!d.seq.valid && verbose)
					fprintf(stderr, "sequence: profile 0x%02x level 0x%02x %ux%u %s %u-bit (enc %u) lcu %u rcs %u reorder %u%s%s%s wq %d bg %d\n",
						s.profile, s.level, s.width, s.height,
						s.progressive ? "progressive" : "interlaced",
						6 + 2 * s.sample_precision,
						6 + 2 * s.encoding_precision,
						1u << s.lcu_size, s.num_rcs, s.reorder_delay,
						s.low_delay ? " low-delay" : "",
						s.sao ? " sao" : "", s.alf ? " alf" : "",
						s.wq_enable, s.background_enable);
				d.seq = s;
				if (!parse_only && !d.v4l2) {
					d.v4l2 = v4l2_open(video, media, &d.seq,
							   d.num_bufs);
					d.rowbuf = malloc(4 * s.width + 16);
				}
			}
			bits_free(&b);
			break;
		}
		case 0xb1:	/* sequence end */
			bump(&d, true);
			break;
		case 0xb3:
		case 0xb6:
			in_pic = true;
			pic_intra = code == 0xb3;
			pic_start = pos;
			pic_hdr_end = next;
			slice_off = 0;
			break;
		default:
			if (is_slice && in_pic && !slice_off)
				slice_off = pos;
			break;
		}

		pos = next;
	}
	if (in_pic && slice_off &&
	    !(d.max_frames && d.pic_count >= d.max_frames))
		decode_picture(&d, data + pic_start, len - pic_start,
			       pic_hdr_end - pic_start, slice_off - pic_start,
			       pic_intra);
	bump(&d, true);
	if (d.v4l2) {
		while (d.v4l2->fifo_len)
			complete_oldest(&d);
		flush_outputs(&d, true);
	}

	md5_final(&d.md5, sum);
	printf("%u pictures decoded, %u output", d.pic_count, d.out_count);
	if (afbc_written)
		printf(", %u AFBC capture buffers written", afbc_written);
	else if (!parse_only)
		printf(", md5 %s", sum);
	printf("\n");

	if (d.out)
		fclose(d.out);
	free(data);
	return 0;
}
