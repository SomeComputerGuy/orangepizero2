// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Allwinner H616 G2D mixer, V4L2 mem2mem colour conversion and scaling
 *
 * Copyright (C) 2026 Arun Iyengar <aiyengar1990@gmail.com>
 *
 * The H616 user manual (v1.0, 4.3) lists the block and its clocks, reset
 * and IOMMU master only; the register offsets and the programming
 * sequence follow the Allwinner BSP driver (drivers/char/sunxi_g2d,
 * GPL-2.0), which served as a reference.
 */

#include <linux/clk.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/math64.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/reset.h>

#include <media/v4l2-device.h>
#include <media/v4l2-event.h>
#include <media/v4l2-ioctl.h>
#include <media/v4l2-mem2mem.h>
#include <media/videobuf2-dma-contig.h>

#include "sun50i-g2d.h"

/*
 * The hardware names its RGB formats by the 32-bit little-endian word,
 * so its ARGB8888 is B, G, R, A in memory, which V4L2 calls ABGR32.
 */
static const struct g2d_fmt g2d_formats[] = {
	{ V4L2_PIX_FMT_XBGR32, G2D_FMT_XRGB8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_ABGR32, G2D_FMT_ARGB8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_XRGB32, G2D_FMT_BGRX8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_ARGB32, G2D_FMT_BGRA8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_RGBX32, G2D_FMT_XBGR8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_RGBA32, G2D_FMT_ABGR8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_BGRX32, G2D_FMT_RGBX8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_BGRA32, G2D_FMT_RGBA8888, 1, 4, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_BGR24,  G2D_FMT_RGB888,   1, 3, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_RGB24,  G2D_FMT_BGR888,   1, 3, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_RGB565, G2D_FMT_RGB565,   1, 2, 0, 1, 1, false, false },
	{ V4L2_PIX_FMT_NV12,   G2D_FMT_YUV420_SP_UV, 2, 1, 2, 2, 2, true, false },
	{ V4L2_PIX_FMT_NV21,   G2D_FMT_YUV420_SP_VU, 2, 1, 2, 2, 2, true, false },
	{ V4L2_PIX_FMT_YUV420, G2D_FMT_YUV420_P,     3, 1, 1, 2, 2, true, false },
	{ V4L2_PIX_FMT_YVU420, G2D_FMT_YUV420_P,     3, 1, 1, 2, 2, true, true },
	{ V4L2_PIX_FMT_NV16,   G2D_FMT_YUV422_SP_UV, 2, 1, 2, 2, 1, true, false },
	{ V4L2_PIX_FMT_NV61,   G2D_FMT_YUV422_SP_VU, 2, 1, 2, 2, 1, true, false },
	{ V4L2_PIX_FMT_YUV422P, G2D_FMT_YUV422_P,    3, 1, 1, 2, 1, true, false },
};

#define G2D_DEFAULT_FMT		V4L2_PIX_FMT_XBGR32

static inline u32 g2d_read(struct g2d_dev *dev, u32 reg)
{
	return readl(dev->base + reg);
}

static inline void g2d_write(struct g2d_dev *dev, u32 reg, u32 val)
{
	writel(val, dev->base + reg);
}

static const struct g2d_fmt *g2d_find_format(u32 fourcc)
{
	unsigned int i;

	for (i = 0; i < ARRAY_SIZE(g2d_formats); i++)
		if (g2d_formats[i].fourcc == fourcc)
			return &g2d_formats[i];

	return NULL;
}

/* Chroma plane pitch and height for the plane 0 pitch and frame height */
static u32 g2d_chroma_pitch(const struct g2d_fmt *fmt, u32 bpl)
{
	return bpl * fmt->cbpp / fmt->hsub;
}

static u32 g2d_chroma_height(const struct g2d_fmt *fmt, u32 height)
{
	return height / fmt->vsub;
}

/*
 * Plane addresses of a frame in one contiguous buffer, in the order the
 * hardware wants them: luma, U (Cb), V (Cr).
 */
static void g2d_plane_addrs(const struct g2d_fmt *fmt,
			    const struct v4l2_pix_format *pix,
			    dma_addr_t base, dma_addr_t addr[3], u32 pitch[3])
{
	u32 cpitch = g2d_chroma_pitch(fmt, pix->bytesperline);
	u32 cheight = g2d_chroma_height(fmt, pix->height);
	dma_addr_t plane1, plane2;

	pitch[0] = pix->bytesperline;
	pitch[1] = fmt->planes > 1 ? cpitch : 0;
	pitch[2] = fmt->planes > 2 ? cpitch : 0;

	addr[0] = base;
	plane1 = base + (dma_addr_t)pix->bytesperline * pix->height;
	plane2 = plane1 + (dma_addr_t)cpitch * cheight;
	if (fmt->planes < 2) {
		addr[1] = 0;
		addr[2] = 0;
	} else if (fmt->planes < 3) {
		addr[1] = plane1;
		addr[2] = 0;
	} else if (fmt->swap_uv) {
		addr[1] = plane2;
		addr[2] = plane1;
	} else {
		addr[1] = plane1;
		addr[2] = plane2;
	}
}

/*
 * Catmull-Rom cubic weight at distance t (Q12), returned in Q12.
 * The scaler takes 4 taps with 8-bit signed weights summing to 64.
 */
static s32 g2d_cubic_weight(u32 t)
{
	s64 t2 = ((s64)t * t) >> 12;
	s64 t3 = (t2 * t) >> 12;

	if (t < 4096)
		return (3 * t3 - 5 * t2) / 2 + 4096;
	if (t < 8192)
		return (5 * t2 - t3) / 2 - 4 * (s64)t + 8192;
	return 0;
}

/*
 * One 4-tap filter phase for the given sampling step (Q20): when
 * downscaling the kernel is stretched by the ratio so that it averages
 * the input samples instead of picking one.
 */
static u32 g2d_vsu_coef4(u32 step, unsigned int phase)
{
	s32 w[4], c[4];
	s32 sum = 0, csum = 0, largest = 0;
	int i;

	for (i = 0; i < 4; i++) {
		s32 d = (i - 1) * 4096 - (s32)(phase << 7); /* taps -1..2, Q12 */
		u64 t = abs(d);

		if (step > BIT(G2D_VSU_FRAC_BITS))
			t = div_u64(t << G2D_VSU_FRAC_BITS, step);
		w[i] = g2d_cubic_weight(min_t(u64, t, 8192));
		sum += w[i];
	}

	for (i = 0; i < 4; i++) {
		c[i] = DIV_ROUND_CLOSEST(64 * w[i], sum);
		csum += c[i];
		if (c[i] > c[largest])
			largest = i;
	}
	c[largest] += 64 - csum;

	return (c[0] & 0xff) | (c[1] & 0xff) << 8 |
	       (c[2] & 0xff) << 16 | (c[3] & 0xff) << 24;
}

/* Two-tap linear interpolation phase (taps 0 and 1 only) */
static u32 g2d_vsu_coef2(unsigned int phase)
{
	u32 c1 = 2 * phase;

	return (64 - c1) << 8 | c1 << 16;
}

static void g2d_vsu_write_coefs(struct g2d_dev *dev, u32 reg, u32 step,
				bool cubic)
{
	unsigned int i;

	for (i = 0; i < G2D_VSU_PHASES; i++)
		g2d_write(dev, reg + 4 * i,
			  cubic ? g2d_vsu_coef4(step, i) : g2d_vsu_coef2(i));
}

/* Sampling step of an in -> out resize in Q20 */
static u32 g2d_vsu_step(u32 in, u32 out)
{
	return (u32)div_u64((u64)in << G2D_VSU_FRAC_BITS, out);
}

/*
 * Colour space conversion matrix: three rows of (coef0, coef1, coef2,
 * const) in Q10, applied as out = coef . in + const on 8-bit channels,
 * with the channels ordered R, G, B and Y, Cb, Cr.
 */
struct g2d_csc {
	s32 m[12];
};

/* Luma coefficients in 1/10000 */
static void g2d_ycbcr_coefs(u8 ycbcr_enc, u32 *kr, u32 *kb)
{
	switch (ycbcr_enc) {
	case V4L2_YCBCR_ENC_709:
	case V4L2_YCBCR_ENC_XV709:
		*kr = 2126;
		*kb = 722;
		break;
	case V4L2_YCBCR_ENC_BT2020:
	case V4L2_YCBCR_ENC_BT2020_CONST_LUM:
		*kr = 2627;
		*kb = 593;
		break;
	case V4L2_YCBCR_ENC_SMPTE240M:
		*kr = 2120;
		*kb = 870;
		break;
	default: /* 601, XV601, SYCC */
		*kr = 2990;
		*kb = 1140;
		break;
	}
}

/* round(num / den * 2^10) for signed num */
static s32 g2d_q10(s64 num, s64 den)
{
	s64 v = num << 10;
	bool neg = (v < 0) != (den < 0);

	v = div64_s64(2 * abs(v) + abs(den), 2 * abs(den));
	return neg ? -(s32)v : (s32)v;
}

static void g2d_csc_matrix(struct g2d_csc *csc, bool to_yuv, u8 ycbcr_enc,
			   bool full_range)
{
	/* scale factors of the limited (studio) range, 1 for full range */
	const s64 ys_num = full_range ? 255 : 219, cs_num = full_range ? 255 : 224;
	const s64 yoff = full_range ? 0 : 16;
	const s64 D = 10000;
	u32 kr32, kb32;
	s64 kr, kb, kg;
	s32 *m = csc->m;
	int row;

	g2d_ycbcr_coefs(ycbcr_enc, &kr32, &kb32);
	kr = kr32;
	kb = kb32;
	kg = D - kr - kb;

	if (to_yuv) {
		/* Y */
		m[0] = g2d_q10(ys_num * kr, 255 * D);
		m[1] = g2d_q10(ys_num * kg, 255 * D);
		m[2] = g2d_q10(ys_num * kb, 255 * D);
		m[3] = (s32)(yoff << 10);
		/* Cb = cs * (B - Y') / (2 (1 - Kb)) */
		m[4] = g2d_q10(-cs_num * kr, 255 * 2 * (D - kb));
		m[5] = g2d_q10(-cs_num * kg, 255 * 2 * (D - kb));
		m[6] = g2d_q10(cs_num, 255 * 2);
		m[7] = 128 << 10;
		/* Cr = cs * (R - Y') / (2 (1 - Kr)) */
		m[8] = g2d_q10(cs_num, 255 * 2);
		m[9] = g2d_q10(-cs_num * kg, 255 * 2 * (D - kr));
		m[10] = g2d_q10(-cs_num * kb, 255 * 2 * (D - kr));
		m[11] = 128 << 10;
	} else {
		s32 y = g2d_q10(255, ys_num);

		m[0] = y;
		m[1] = 0;
		m[2] = g2d_q10(255 * 2 * (D - kr), cs_num * D);
		m[4] = y;
		m[5] = g2d_q10(-255 * 2 * kb * (D - kb), cs_num * D * kg);
		m[6] = g2d_q10(-255 * 2 * kr * (D - kr), cs_num * D * kg);
		m[8] = y;
		m[9] = g2d_q10(255 * 2 * (D - kb), cs_num * D);
		m[10] = 0;
		for (row = 0; row < 3; row++)
			m[4 * row + 3] = -(m[4 * row] * (s32)yoff +
					   m[4 * row + 1] * 128 +
					   m[4 * row + 2] * 128);
	}

	/* round half up on the way back to 8 bits */
	for (row = 0; row < 3; row++)
		m[4 * row + 3] += 1 << 9;
}

static void g2d_write_csc(struct g2d_dev *dev, unsigned int unit,
			  const struct g2d_csc *csc)
{
	unsigned int i;

	for (i = 0; i < 12; i++)
		g2d_write(dev, G2D_BLD_CSC_COEF(unit, i), (u32)csc->m[i]);
	g2d_write(dev, G2D_BLD_CSC_CTL, G2D_BLD_CSC_CTL_EN(unit));
}

/* The YCbCr encoding and range the job converts to or from */
static void g2d_pix_colorimetry(const struct v4l2_pix_format *pix,
				u8 *ycbcr_enc, bool *full_range)
{
	u8 enc = pix->ycbcr_enc;
	u8 quant = pix->quantization;

	if (enc == V4L2_YCBCR_ENC_DEFAULT)
		enc = V4L2_MAP_YCBCR_ENC_DEFAULT(pix->colorspace);
	if (quant == V4L2_QUANTIZATION_DEFAULT)
		quant = V4L2_MAP_QUANTIZATION_DEFAULT(false, pix->colorspace,
						      enc);
	*ycbcr_enc = enc;
	*full_range = quant == V4L2_QUANTIZATION_FULL_RANGE;
}

/* Reset pulse of both engines, as the BSP gives before every blit */
static void g2d_engines_reset(struct g2d_dev *dev)
{
	g2d_write(dev, G2D_TOP_AHB_RESET, 0);
	g2d_write(dev, G2D_TOP_AHB_RESET, G2D_TOP_MIXER | G2D_TOP_ROT);
}

static void g2d_setup_overlay(struct g2d_dev *dev, const struct g2d_fmt *fmt,
			      const struct v4l2_pix_format *pix,
			      dma_addr_t base)
{
	dma_addr_t addr[3];
	u32 pitch[3], size;
	int i;

	g2d_plane_addrs(fmt, pix, base, addr, pitch);

	g2d_write(dev, G2D_V0_ATTCTL, G2D_V0_ATTCTL_ALPHA(0xff) |
		  G2D_V0_ATTCTL_FMT(fmt->hw) | G2D_V0_ATTCTL_PIXEL_ALPHA |
		  G2D_V0_ATTCTL_EN);
	size = G2D_SIZE(pix->width, pix->height);
	g2d_write(dev, G2D_V0_MBSIZE, size);
	g2d_write(dev, G2D_V0_SIZE, size);
	g2d_write(dev, G2D_V0_COOR, 0);
	for (i = 0; i < 3; i++) {
		g2d_write(dev, G2D_V0_PITCH(i), pitch[i]);
		g2d_write(dev, G2D_V0_LADD(i), lower_32_bits(addr[i]));
	}
	g2d_write(dev, G2D_V0_HADD, (upper_32_bits(addr[0]) & 0xff) |
		  (upper_32_bits(addr[1]) & 0xff) << 8 |
		  (upper_32_bits(addr[2]) & 0xff) << 16);
}

/*
 * Coarse decimation in the overlay for large downscale ratios, then the
 * scaler proper. Returns the frame size the scaler sees.
 */
static void g2d_setup_coarse(struct g2d_dev *dev, const struct g2d_fmt *fmt,
			     u32 in_w, u32 in_h, u32 out_w, u32 out_h,
			     u32 *mid_w, u32 *mid_h)
{
	*mid_w = in_w;
	*mid_h = in_h;

	if (in_w >= out_w * G2D_COARSE_H_RATIO) {
		*mid_w = out_w * G2D_COARSE_H_RATIO;
		g2d_write(dev, G2D_V0_HDS_CTL0, *mid_w << 16 | in_w);
		g2d_write(dev, G2D_V0_HDS_CTL1, (*mid_w / fmt->hsub) << 16 |
			  DIV_ROUND_UP(in_w, fmt->hsub));
	}
	if (in_h >= out_h * G2D_COARSE_V_RATIO) {
		*mid_h = out_h * G2D_COARSE_V_RATIO;
		g2d_write(dev, G2D_V0_VDS_CTL0, *mid_h << 16 | in_h);
		g2d_write(dev, G2D_V0_VDS_CTL1, (*mid_h / fmt->vsub) << 16 |
			  DIV_ROUND_UP(in_h, fmt->vsub));
	}
}

static void g2d_setup_scaler(struct g2d_dev *dev, const struct g2d_fmt *fmt,
			     u32 in_w, u32 in_h, u32 out_w, u32 out_h)
{
	u32 ctrl = G2D_VSU_CTRL_EN | (fmt->yuv ? G2D_VSU_CTRL_YUV : 0);
	u32 ystep_h = g2d_vsu_step(in_w, out_w);
	u32 ystep_v = g2d_vsu_step(in_h, out_h);
	u32 cstep_h = ystep_h / fmt->hsub;
	u32 cstep_v = ystep_v / fmt->vsub;
	bool is_420 = fmt->vsub == 2;

	g2d_write(dev, G2D_VSU_CTRL, ctrl | G2D_VSU_CTRL_COEF_ACCESS);
	g2d_write(dev, G2D_VSU_OUT_SIZE, G2D_SIZE(out_w, out_h));
	g2d_write(dev, G2D_VSU_GLB_ALPHA, 0xff);

	g2d_write(dev, G2D_VSU_Y_SIZE, G2D_SIZE(in_w, in_h));
	g2d_write(dev, G2D_VSU_Y_HSTEP, ystep_h);
	g2d_write(dev, G2D_VSU_Y_VSTEP, ystep_v);
	g2d_write(dev, G2D_VSU_Y_HPHASE, 0);
	g2d_write(dev, G2D_VSU_Y_VPHASE0, 0);

	g2d_write(dev, G2D_VSU_C_SIZE, G2D_SIZE(DIV_ROUND_UP(in_w, fmt->hsub),
						DIV_ROUND_UP(in_h, fmt->vsub)));
	g2d_write(dev, G2D_VSU_C_HSTEP, cstep_h);
	g2d_write(dev, G2D_VSU_C_VSTEP, cstep_v);
	g2d_write(dev, G2D_VSU_C_HPHASE, is_420 ? G2D_VSU_PHASE_420 : 0);
	g2d_write(dev, G2D_VSU_C_VPHASE0, is_420 ? G2D_VSU_PHASE_420 : 0);

	g2d_vsu_write_coefs(dev, G2D_VSU_Y_HCOEF(0), ystep_h, true);
	g2d_vsu_write_coefs(dev, G2D_VSU_C_HCOEF(0), cstep_h, true);
	/* RGB sources get a linear vertical luma filter, YUV the cubic one */
	g2d_vsu_write_coefs(dev, G2D_VSU_Y_VCOEF(0), ystep_v, fmt->yuv);

	g2d_write(dev, G2D_VSU_CTRL, ctrl);
}

static void g2d_setup_blender(struct g2d_dev *dev,
			      const struct v4l2_pix_format *src_pix,
			      const struct v4l2_pix_format *dst_pix,
			      const struct g2d_fmt *src, const struct g2d_fmt *dst)
{
	u32 size = G2D_SIZE(dst_pix->width, dst_pix->height);

	g2d_write(dev, G2D_ROP_CTL, G2D_ROP_CTL_PASS);
	g2d_write(dev, G2D_BLD_EN_CTL, G2D_BLD_EN_CTL_PIPE(0));
	g2d_write(dev, G2D_BLD_CH_ISIZE(0), size);
	g2d_write(dev, G2D_BLD_CH_OFFSET(0), 0);
	g2d_write(dev, G2D_BLD_PREMUL_CTL, 0);
	g2d_write(dev, G2D_BLD_CTL, G2D_BLD_CTL_COPY);
	g2d_write(dev, G2D_BLD_SIZE, size);
	/* the blender works in the colour space of the source */
	g2d_write(dev, G2D_BLD_OUT_COLOR, src->yuv ? G2D_BLD_OUT_COLOR_YUV : 0);

	if (src->yuv != dst->yuv) {
		struct g2d_csc csc;
		bool full_range;
		u8 enc;

		g2d_pix_colorimetry(src_pix, &enc, &full_range);
		g2d_csc_matrix(&csc, dst->yuv, enc, full_range);
		g2d_write_csc(dev, G2D_CSC_WB, &csc);
	}
}

static void g2d_setup_writeback(struct g2d_dev *dev, const struct g2d_fmt *fmt,
				const struct v4l2_pix_format *pix,
				dma_addr_t base)
{
	dma_addr_t addr[3];
	u32 pitch[3];
	int i;

	g2d_plane_addrs(fmt, pix, base, addr, pitch);

	g2d_write(dev, G2D_WB_ATT, fmt->hw);
	g2d_write(dev, G2D_WB_SIZE, G2D_SIZE(pix->width, pix->height));
	for (i = 0; i < 3; i++) {
		g2d_write(dev, G2D_WB_PITCH(i), pitch[i]);
		g2d_write(dev, G2D_WB_LADD(i), lower_32_bits(addr[i]));
		g2d_write(dev, G2D_WB_HADD(i), upper_32_bits(addr[i]) & 0xff);
	}
}

static void g2d_device_run(void *priv)
{
	struct g2d_ctx *ctx = priv;
	struct g2d_dev *dev = ctx->dev;
	struct vb2_v4l2_buffer *src, *dst;
	const struct g2d_fmt *sfmt, *dfmt;
	u32 mid_w, mid_h;

	src = v4l2_m2m_next_src_buf(ctx->fh.m2m_ctx);
	dst = v4l2_m2m_next_dst_buf(ctx->fh.m2m_ctx);
	v4l2_m2m_buf_copy_metadata(src, dst);

	sfmt = g2d_find_format(ctx->src_fmt.pixelformat);
	dfmt = g2d_find_format(ctx->dst_fmt.pixelformat);

	/* every job starts from the reset state of the engines */
	g2d_engines_reset(dev);

	g2d_setup_overlay(dev, sfmt, &ctx->src_fmt,
			  vb2_dma_contig_plane_dma_addr(&src->vb2_buf, 0));

	/* YUV sources always pass the scaler, which upsamples the chroma */
	if (sfmt->yuv || ctx->src_fmt.width != ctx->dst_fmt.width ||
	    ctx->src_fmt.height != ctx->dst_fmt.height) {
		g2d_setup_coarse(dev, sfmt, ctx->src_fmt.width,
				 ctx->src_fmt.height, ctx->dst_fmt.width,
				 ctx->dst_fmt.height, &mid_w, &mid_h);
		g2d_setup_scaler(dev, sfmt, mid_w, mid_h, ctx->dst_fmt.width,
				 ctx->dst_fmt.height);
	}

	g2d_setup_blender(dev, &ctx->src_fmt, &ctx->dst_fmt, sfmt, dfmt);
	g2d_setup_writeback(dev, dfmt, &ctx->dst_fmt,
			    vb2_dma_contig_plane_dma_addr(&dst->vb2_buf, 0));

	spin_lock(&dev->job_lock);
	dev->job_active = true;
	spin_unlock(&dev->job_lock);
	schedule_delayed_work(&dev->watchdog_work,
			      msecs_to_jiffies(G2D_JOB_TIMEOUT_MS));

	g2d_write(dev, G2D_MIXER_INT, G2D_MIXER_INT_FINISH_EN);
	g2d_write(dev, G2D_MIXER_CTL,
		  g2d_read(dev, G2D_MIXER_CTL) | G2D_MIXER_CTL_START);
}

/* Claim the running job; false when the irq or the watchdog took it */
static bool g2d_take_job(struct g2d_dev *dev)
{
	bool active;

	spin_lock(&dev->job_lock);
	active = dev->job_active;
	dev->job_active = false;
	spin_unlock(&dev->job_lock);

	return active;
}

static void g2d_finish_job(struct g2d_dev *dev, enum vb2_buffer_state state)
{
	struct vb2_v4l2_buffer *buf;
	struct g2d_ctx *ctx;

	ctx = v4l2_m2m_get_curr_priv(dev->m2m_dev);
	if (!ctx) {
		v4l2_err(&dev->v4l2_dev,
			 "Instance released before the end of transaction\n");
		return;
	}

	buf = v4l2_m2m_src_buf_remove(ctx->fh.m2m_ctx);
	v4l2_m2m_buf_done(buf, state);
	buf = v4l2_m2m_dst_buf_remove(ctx->fh.m2m_ctx);
	v4l2_m2m_buf_done(buf, state);
	v4l2_m2m_job_finish(dev->m2m_dev, ctx->fh.m2m_ctx);
}

static irqreturn_t g2d_irq(int irq, void *data)
{
	struct g2d_dev *dev = data;
	u32 status = g2d_read(dev, G2D_MIXER_INT);
	u32 rot = g2d_read(dev, G2D_ROT_INT);

	if (!(status & G2D_MIXER_INT_FINISH) && !(rot & G2D_ROT_INT_FINISH))
		return IRQ_NONE;

	atomic_inc(&dev->irq_count);

	/* only the probe self-test uses the rotation engine so far */
	if (rot & G2D_ROT_INT_FINISH) {
		g2d_write(dev, G2D_ROT_INT, G2D_ROT_INT_FINISH);
		complete(&dev->selftest_done);
	}
	if (!(status & G2D_MIXER_INT_FINISH))
		return IRQ_HANDLED;

	/* clears the flag and leaves the interrupt disabled */
	g2d_write(dev, G2D_MIXER_INT, G2D_MIXER_INT_FINISH);

	if (!g2d_take_job(dev)) {
		complete(&dev->selftest_done);
		return IRQ_HANDLED;
	}

	cancel_delayed_work(&dev->watchdog_work);
	g2d_finish_job(dev, VB2_BUF_STATE_DONE);

	return IRQ_HANDLED;
}

static void g2d_watchdog(struct work_struct *work)
{
	struct g2d_dev *dev = container_of(work, struct g2d_dev,
					   watchdog_work.work);

	if (!g2d_take_job(dev))
		return;

	v4l2_err(&dev->v4l2_dev,
		 "job timed out, mixer status %08x ctl %08x top %x/%x/%x v0 %08x bld %08x wb %08x irqs %d\n",
		 g2d_read(dev, G2D_MIXER_INT), g2d_read(dev, G2D_MIXER_CTL),
		 g2d_read(dev, G2D_TOP_SCLK_GATE),
		 g2d_read(dev, G2D_TOP_HCLK_GATE),
		 g2d_read(dev, G2D_TOP_AHB_RESET),
		 g2d_read(dev, G2D_V0_ATTCTL), g2d_read(dev, G2D_BLD_EN_CTL),
		 g2d_read(dev, G2D_WB_ATT), atomic_read(&dev->irq_count));
	g2d_write(dev, G2D_MIXER_INT, 0);
	g2d_engines_reset(dev);
	g2d_finish_job(dev, VB2_BUF_STATE_ERROR);
}

static inline struct g2d_ctx *g2d_file2ctx(struct file *file)
{
	return container_of(file_to_v4l2_fh(file), struct g2d_ctx, fh);
}

/*
 * Clamp a format to what the hardware takes and fill in the layout: one
 * contiguous buffer, plane 0 pitch a multiple of 16 bytes (a caller may
 * ask for a larger one), chroma planes following at pitch / hsub * cbpp.
 */
static void g2d_prepare_format(struct v4l2_pix_format *pix)
{
	const struct g2d_fmt *fmt;
	u32 bpl, min_bpl;

	fmt = g2d_find_format(pix->pixelformat);
	if (!fmt) {
		pix->pixelformat = G2D_DEFAULT_FMT;
		fmt = g2d_find_format(pix->pixelformat);
	}

	pix->width = clamp_t(u32, ALIGN(pix->width, fmt->hsub), G2D_MIN_WIDTH,
			     G2D_MAX_WIDTH);
	pix->height = clamp_t(u32, ALIGN(pix->height, fmt->vsub),
			      G2D_MIN_HEIGHT, G2D_MAX_HEIGHT);
	pix->field = V4L2_FIELD_NONE;

	min_bpl = pix->width * fmt->bpp;
	bpl = max(pix->bytesperline, min_bpl);
	/* keep user strides sane: no more than twice the minimum */
	bpl = min(bpl, 2 * ALIGN(min_bpl, G2D_PITCH_ALIGN));
	pix->bytesperline = ALIGN(bpl, G2D_PITCH_ALIGN);

	pix->sizeimage = pix->bytesperline * pix->height;
	if (fmt->planes > 1)
		pix->sizeimage += (fmt->planes - 1) *
			g2d_chroma_pitch(fmt, pix->bytesperline) *
			g2d_chroma_height(fmt, pix->height);
}

static int g2d_querycap(struct file *file, void *priv,
			struct v4l2_capability *cap)
{
	strscpy(cap->driver, G2D_NAME, sizeof(cap->driver));
	strscpy(cap->card, "Allwinner G2D", sizeof(cap->card));

	return 0;
}

static int g2d_enum_fmt(struct file *file, void *priv, struct v4l2_fmtdesc *f)
{
	if (f->index >= ARRAY_SIZE(g2d_formats))
		return -EINVAL;

	f->pixelformat = g2d_formats[f->index].fourcc;

	return 0;
}

static int g2d_enum_framesizes(struct file *file, void *priv,
			       struct v4l2_frmsizeenum *fsize)
{
	const struct g2d_fmt *fmt;

	if (fsize->index != 0)
		return -EINVAL;

	fmt = g2d_find_format(fsize->pixel_format);
	if (!fmt)
		return -EINVAL;

	fsize->type = V4L2_FRMSIZE_TYPE_STEPWISE;
	fsize->stepwise.min_width = G2D_MIN_WIDTH;
	fsize->stepwise.min_height = G2D_MIN_HEIGHT;
	fsize->stepwise.max_width = G2D_MAX_WIDTH;
	fsize->stepwise.max_height = G2D_MAX_HEIGHT;
	fsize->stepwise.step_width = fmt->hsub;
	fsize->stepwise.step_height = fmt->vsub;

	return 0;
}

static int g2d_g_fmt_vid_cap(struct file *file, void *priv,
			     struct v4l2_format *f)
{
	struct g2d_ctx *ctx = g2d_file2ctx(file);

	f->fmt.pix = ctx->dst_fmt;

	return 0;
}

static int g2d_g_fmt_vid_out(struct file *file, void *priv,
			     struct v4l2_format *f)
{
	struct g2d_ctx *ctx = g2d_file2ctx(file);

	f->fmt.pix = ctx->src_fmt;

	return 0;
}

/* The capture side carries the colorimetry of the output side */
static void g2d_copy_colorimetry(const struct v4l2_pix_format *from,
				 struct v4l2_pix_format *to)
{
	to->colorspace = from->colorspace;
	to->xfer_func = from->xfer_func;
	to->ycbcr_enc = from->ycbcr_enc;
	to->quantization = from->quantization;
}

static int g2d_try_fmt_vid_cap(struct file *file, void *priv,
			       struct v4l2_format *f)
{
	struct g2d_ctx *ctx = g2d_file2ctx(file);

	g2d_prepare_format(&f->fmt.pix);
	g2d_copy_colorimetry(&ctx->src_fmt, &f->fmt.pix);

	return 0;
}

static int g2d_try_fmt_vid_out(struct file *file, void *priv,
			       struct v4l2_format *f)
{
	g2d_prepare_format(&f->fmt.pix);

	return 0;
}

static int g2d_s_fmt_vid_cap(struct file *file, void *priv,
			     struct v4l2_format *f)
{
	struct g2d_ctx *ctx = g2d_file2ctx(file);
	struct vb2_queue *vq;

	vq = v4l2_m2m_get_vq(ctx->fh.m2m_ctx, f->type);
	if (vb2_is_busy(vq))
		return -EBUSY;

	g2d_try_fmt_vid_cap(file, priv, f);
	ctx->dst_fmt = f->fmt.pix;

	return 0;
}

static int g2d_s_fmt_vid_out(struct file *file, void *priv,
			     struct v4l2_format *f)
{
	struct g2d_ctx *ctx = g2d_file2ctx(file);
	struct vb2_queue *vq;

	vq = v4l2_m2m_get_vq(ctx->fh.m2m_ctx, f->type);
	if (vb2_is_busy(vq))
		return -EBUSY;

	g2d_try_fmt_vid_out(file, priv, f);
	ctx->src_fmt = f->fmt.pix;
	g2d_copy_colorimetry(&ctx->src_fmt, &ctx->dst_fmt);

	return 0;
}

static const struct v4l2_ioctl_ops g2d_ioctl_ops = {
	.vidioc_querycap		= g2d_querycap,
	.vidioc_enum_framesizes		= g2d_enum_framesizes,

	.vidioc_enum_fmt_vid_cap	= g2d_enum_fmt,
	.vidioc_g_fmt_vid_cap		= g2d_g_fmt_vid_cap,
	.vidioc_try_fmt_vid_cap		= g2d_try_fmt_vid_cap,
	.vidioc_s_fmt_vid_cap		= g2d_s_fmt_vid_cap,

	.vidioc_enum_fmt_vid_out	= g2d_enum_fmt,
	.vidioc_g_fmt_vid_out		= g2d_g_fmt_vid_out,
	.vidioc_try_fmt_vid_out		= g2d_try_fmt_vid_out,
	.vidioc_s_fmt_vid_out		= g2d_s_fmt_vid_out,

	.vidioc_reqbufs			= v4l2_m2m_ioctl_reqbufs,
	.vidioc_querybuf		= v4l2_m2m_ioctl_querybuf,
	.vidioc_qbuf			= v4l2_m2m_ioctl_qbuf,
	.vidioc_dqbuf			= v4l2_m2m_ioctl_dqbuf,
	.vidioc_prepare_buf		= v4l2_m2m_ioctl_prepare_buf,
	.vidioc_create_bufs		= v4l2_m2m_ioctl_create_bufs,
	.vidioc_expbuf			= v4l2_m2m_ioctl_expbuf,

	.vidioc_streamon		= v4l2_m2m_ioctl_streamon,
	.vidioc_streamoff		= v4l2_m2m_ioctl_streamoff,

	.vidioc_log_status		= v4l2_ctrl_log_status,
	.vidioc_subscribe_event		= v4l2_ctrl_subscribe_event,
	.vidioc_unsubscribe_event	= v4l2_event_unsubscribe,
};

static int g2d_queue_setup(struct vb2_queue *vq, unsigned int *nbuffers,
			   unsigned int *nplanes, unsigned int sizes[],
			   struct device *alloc_devs[])
{
	struct g2d_ctx *ctx = vb2_get_drv_priv(vq);
	struct v4l2_pix_format *pix;

	pix = V4L2_TYPE_IS_OUTPUT(vq->type) ? &ctx->src_fmt : &ctx->dst_fmt;

	if (*nplanes) {
		if (sizes[0] < pix->sizeimage)
			return -EINVAL;
	} else {
		sizes[0] = pix->sizeimage;
		*nplanes = 1;
	}

	return 0;
}

static int g2d_buf_prepare(struct vb2_buffer *vb)
{
	struct vb2_queue *vq = vb->vb2_queue;
	struct g2d_ctx *ctx = vb2_get_drv_priv(vq);
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct v4l2_pix_format *pix;

	pix = V4L2_TYPE_IS_OUTPUT(vq->type) ? &ctx->src_fmt : &ctx->dst_fmt;

	if (vb2_plane_size(vb, 0) < pix->sizeimage)
		return -EINVAL;

	if (V4L2_TYPE_IS_OUTPUT(vq->type)) {
		if (vbuf->field == V4L2_FIELD_ANY)
			vbuf->field = V4L2_FIELD_NONE;
		if (vbuf->field != V4L2_FIELD_NONE)
			return -EINVAL;
	}

	vb2_set_plane_payload(vb, 0, pix->sizeimage);

	return 0;
}

static void g2d_buf_queue(struct vb2_buffer *vb)
{
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct g2d_ctx *ctx = vb2_get_drv_priv(vb->vb2_queue);

	v4l2_m2m_buf_queue(ctx->fh.m2m_ctx, vbuf);
}

static void g2d_queue_cleanup(struct vb2_queue *vq, u32 state)
{
	struct g2d_ctx *ctx = vb2_get_drv_priv(vq);
	struct vb2_v4l2_buffer *vbuf;

	do {
		if (V4L2_TYPE_IS_OUTPUT(vq->type))
			vbuf = v4l2_m2m_src_buf_remove(ctx->fh.m2m_ctx);
		else
			vbuf = v4l2_m2m_dst_buf_remove(ctx->fh.m2m_ctx);
		if (vbuf)
			v4l2_m2m_buf_done(vbuf, state);
	} while (vbuf);
}

static int g2d_start_streaming(struct vb2_queue *vq, unsigned int count)
{
	struct g2d_ctx *ctx = vb2_get_drv_priv(vq);
	int ret;

	if (!V4L2_TYPE_IS_OUTPUT(vq->type))
		return 0;

	ret = pm_runtime_resume_and_get(ctx->dev->dev);
	if (ret < 0) {
		g2d_queue_cleanup(vq, VB2_BUF_STATE_QUEUED);
		return ret;
	}

	return 0;
}

static void g2d_stop_streaming(struct vb2_queue *vq)
{
	struct g2d_ctx *ctx = vb2_get_drv_priv(vq);

	if (V4L2_TYPE_IS_OUTPUT(vq->type))
		pm_runtime_put(ctx->dev->dev);

	g2d_queue_cleanup(vq, VB2_BUF_STATE_ERROR);
}

static const struct vb2_ops g2d_qops = {
	.queue_setup		= g2d_queue_setup,
	.buf_prepare		= g2d_buf_prepare,
	.buf_queue		= g2d_buf_queue,
	.start_streaming	= g2d_start_streaming,
	.stop_streaming		= g2d_stop_streaming,
};

static int g2d_queue_init(void *priv, struct vb2_queue *src_vq,
			  struct vb2_queue *dst_vq)
{
	struct g2d_ctx *ctx = priv;
	int ret;

	src_vq->type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	src_vq->io_modes = VB2_MMAP | VB2_DMABUF;
	src_vq->drv_priv = ctx;
	src_vq->buf_struct_size = sizeof(struct v4l2_m2m_buffer);
	src_vq->min_queued_buffers = 1;
	src_vq->ops = &g2d_qops;
	src_vq->mem_ops = &vb2_dma_contig_memops;
	src_vq->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_COPY;
	src_vq->lock = &ctx->dev->dev_mutex;
	src_vq->dev = ctx->dev->dev;

	ret = vb2_queue_init(src_vq);
	if (ret)
		return ret;

	dst_vq->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	dst_vq->io_modes = VB2_MMAP | VB2_DMABUF;
	dst_vq->drv_priv = ctx;
	dst_vq->buf_struct_size = sizeof(struct v4l2_m2m_buffer);
	dst_vq->min_queued_buffers = 1;
	dst_vq->ops = &g2d_qops;
	dst_vq->mem_ops = &vb2_dma_contig_memops;
	dst_vq->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_COPY;
	dst_vq->lock = &ctx->dev->dev_mutex;
	dst_vq->dev = ctx->dev->dev;

	return vb2_queue_init(dst_vq);
}

static int g2d_open(struct file *file)
{
	struct g2d_dev *dev = video_drvdata(file);
	struct g2d_ctx *ctx;
	int ret;

	if (mutex_lock_interruptible(&dev->dev_mutex))
		return -ERESTARTSYS;

	ctx = kzalloc_obj(*ctx);
	if (!ctx) {
		ret = -ENOMEM;
		goto err_unlock;
	}

	ctx->dev = dev;

	ctx->src_fmt.pixelformat = G2D_DEFAULT_FMT;
	ctx->src_fmt.width = 640;
	ctx->src_fmt.height = 480;
	ctx->src_fmt.colorspace = V4L2_COLORSPACE_SRGB;
	g2d_prepare_format(&ctx->src_fmt);
	ctx->dst_fmt = ctx->src_fmt;

	v4l2_fh_init(&ctx->fh, video_devdata(file));

	/* no controls yet; the handler serves LOG_STATUS and the events */
	v4l2_ctrl_handler_init(&ctx->ctrl_handler, 0);
	ctx->fh.ctrl_handler = &ctx->ctrl_handler;

	ctx->fh.m2m_ctx = v4l2_m2m_ctx_init(dev->m2m_dev, ctx,
					    &g2d_queue_init);
	if (IS_ERR(ctx->fh.m2m_ctx)) {
		ret = PTR_ERR(ctx->fh.m2m_ctx);
		goto err_free;
	}

	v4l2_fh_add(&ctx->fh, file);
	mutex_unlock(&dev->dev_mutex);

	return 0;

err_free:
	v4l2_ctrl_handler_free(&ctx->ctrl_handler);
	v4l2_fh_exit(&ctx->fh);
	kfree(ctx);
err_unlock:
	mutex_unlock(&dev->dev_mutex);

	return ret;
}

static int g2d_release(struct file *file)
{
	struct g2d_dev *dev = video_drvdata(file);
	struct g2d_ctx *ctx = g2d_file2ctx(file);

	mutex_lock(&dev->dev_mutex);

	v4l2_fh_del(&ctx->fh, file);
	v4l2_fh_exit(&ctx->fh);
	v4l2_m2m_ctx_release(ctx->fh.m2m_ctx);
	v4l2_ctrl_handler_free(&ctx->ctrl_handler);
	kfree(ctx);

	mutex_unlock(&dev->dev_mutex);

	return 0;
}

static const struct v4l2_file_operations g2d_fops = {
	.owner		= THIS_MODULE,
	.open		= g2d_open,
	.release	= g2d_release,
	.poll		= v4l2_m2m_fop_poll,
	.unlocked_ioctl	= video_ioctl2,
	.mmap		= v4l2_m2m_fop_mmap,
};

static const struct video_device g2d_video_device = {
	.name		= G2D_NAME,
	.vfl_dir	= VFL_DIR_M2M,
	.fops		= &g2d_fops,
	.ioctl_ops	= &g2d_ioctl_ops,
	.minor		= -1,
	.release	= video_device_release_empty,
	.device_caps	= V4L2_CAP_VIDEO_M2M | V4L2_CAP_STREAMING,
};

/*
 * Probe-time self-test, for the kernel log only (it never fails the
 * probe): register write/read-back in the mixer and the rotation engine,
 * then one 16x16 copy through each engine, waited for on the finish
 * interrupt. "noirq" = the finish flag is set but no interrupt came.
 */
static bool g2d_reg_holds(struct g2d_dev *dev, u32 reg, u32 val, u32 *got)
{
	g2d_write(dev, reg, val);
	*got = g2d_read(dev, reg);

	return *got == val;
}

static const char *g2d_selftest_wait(struct g2d_dev *dev, u32 int_reg,
				     u32 flag, const u32 *in, const u32 *out,
				     unsigned int n, u32 mask)
{
	unsigned int i;

	if (!wait_for_completion_timeout(&dev->selftest_done,
			msecs_to_jiffies(G2D_SELFTEST_TIMEOUT_MS)))
		return (g2d_read(dev, int_reg) & flag) ? "noirq" : "timeout";

	for (i = 0; i < n; i++)
		if ((in[i] ^ out[i]) & mask)
			return "baddata";

	return "ok";
}

static void g2d_selftest(struct g2d_dev *dev)
{
	const unsigned int n = G2D_SELFTEST_SIZE * G2D_SELFTEST_SIZE;
	const u32 size = G2D_SIZE(G2D_SELFTEST_SIZE, G2D_SELFTEST_SIZE);
	const struct g2d_fmt *fmt = g2d_find_format(V4L2_PIX_FMT_XBGR32);
	struct v4l2_pix_format pix = {
		.width = G2D_SELFTEST_SIZE,
		.height = G2D_SELFTEST_SIZE,
		.pixelformat = V4L2_PIX_FMT_XBGR32,
		.bytesperline = G2D_SELFTEST_SIZE * 4,
		.colorspace = V4L2_COLORSPACE_SRGB,
	};
	u32 v_int, v_v0, v_wb, v_bld, v_rot, ver, m_ctl, m_int, r_ctl, r_int;
	bool mixer_regs, rot_regs;
	const char *mres, *rres;
	dma_addr_t dma, dma_out;
	u32 *in, *out, m_out0;
	unsigned int i;

	ver = g2d_read(dev, G2D_TOP_IP_VERSION);
	g2d_engines_reset(dev);
	mixer_regs = g2d_reg_holds(dev, G2D_MIXER_INT, G2D_MIXER_INT_FINISH_EN,
				   &v_int);
	mixer_regs &= g2d_reg_holds(dev, G2D_V0_SIZE, size, &v_v0);
	mixer_regs &= g2d_reg_holds(dev, G2D_WB_SIZE, size, &v_wb);
	mixer_regs &= g2d_reg_holds(dev, G2D_BLD_SIZE, size, &v_bld);
	rot_regs = g2d_reg_holds(dev, G2D_ROT_ISIZE, size, &v_rot);
	g2d_write(dev, G2D_MIXER_INT, 0);

	dev_info(dev->dev,
		 "selftest regs: top %x/%x/%x ip %08x (rtmx %u vsu %u gsu %u rot %u) mixer_regs %s (int %08x v0 %08x wb %08x bld %08x) rot_regs %s (%08x)\n",
		 g2d_read(dev, G2D_TOP_SCLK_GATE),
		 g2d_read(dev, G2D_TOP_HCLK_GATE),
		 g2d_read(dev, G2D_TOP_AHB_RESET), ver, G2D_TOP_IP_RTMX(ver),
		 G2D_TOP_IP_VSU(ver), G2D_TOP_IP_GSU(ver), G2D_TOP_IP_ROT(ver),
		 mixer_regs ? "ok" : "bad", v_int, v_v0, v_wb, v_bld,
		 rot_regs ? "ok" : "bad", v_rot);

	in = dma_alloc_coherent(dev->dev, 2 * n * 4, &dma, GFP_KERNEL);
	if (!in)
		return;
	out = in + n;
	dma_out = dma + n * 4;
	for (i = 0; i < n; i++)
		in[i] = (i + 1) * 0x9e3779b1;

	/* mixer: V0 -> blender pipe 0 (COPY) -> write-back, XRGB8888 */
	memset(out, 0, n * 4);
	reinit_completion(&dev->selftest_done);
	g2d_engines_reset(dev);
	g2d_setup_overlay(dev, fmt, &pix, dma);
	g2d_setup_blender(dev, &pix, &pix, fmt, fmt);
	g2d_setup_writeback(dev, fmt, &pix, dma_out);
	g2d_write(dev, G2D_MIXER_INT, G2D_MIXER_INT_FINISH_EN);
	g2d_write(dev, G2D_MIXER_CTL,
		  g2d_read(dev, G2D_MIXER_CTL) | G2D_MIXER_CTL_START);
	/* the X byte is not defined by the copy */
	mres = g2d_selftest_wait(dev, G2D_MIXER_INT, G2D_MIXER_INT_FINISH,
				 in, out, n, 0x00ffffff);
	m_ctl = g2d_read(dev, G2D_MIXER_CTL);
	m_int = g2d_read(dev, G2D_MIXER_INT);
	m_out0 = out[0];
	g2d_write(dev, G2D_MIXER_INT, 0);

	/* rotation engine: plain copy (0 degrees, no flip), ARGB8888 */
	memset(out, 0, n * 4);
	reinit_completion(&dev->selftest_done);
	g2d_engines_reset(dev);
	g2d_write(dev, G2D_ROT_CTL, G2D_ROT_CTL_EN);
	g2d_write(dev, G2D_ROT_IFMT, G2D_FMT_ARGB8888);
	g2d_write(dev, G2D_ROT_ISIZE, size);
	g2d_write(dev, G2D_ROT_IPITCH(0), pix.bytesperline);
	g2d_write(dev, G2D_ROT_ILADD(0), lower_32_bits(dma));
	g2d_write(dev, G2D_ROT_IHADD(0), upper_32_bits(dma) & 0xff);
	g2d_write(dev, G2D_ROT_OSIZE, size);
	g2d_write(dev, G2D_ROT_OPITCH(0), pix.bytesperline);
	g2d_write(dev, G2D_ROT_OLADD(0), lower_32_bits(dma_out));
	g2d_write(dev, G2D_ROT_OHADD(0), upper_32_bits(dma_out) & 0xff);
	g2d_write(dev, G2D_ROT_INT, G2D_ROT_INT_FINISH_EN);
	g2d_write(dev, G2D_ROT_CTL,
		  g2d_read(dev, G2D_ROT_CTL) | G2D_ROT_CTL_START);
	rres = g2d_selftest_wait(dev, G2D_ROT_INT, G2D_ROT_INT_FINISH,
				 in, out, n, 0xffffffff);
	r_ctl = g2d_read(dev, G2D_ROT_CTL);
	r_int = g2d_read(dev, G2D_ROT_INT);
	g2d_write(dev, G2D_ROT_INT, 0);

	dev_info(dev->dev,
		 "selftest: mixer %s (ctl %08x int %08x in0 %08x out0 %08x) rot %s (ctl %08x int %08x out0 %08x) irqs %d\n",
		 mres, m_ctl, m_int, in[0], m_out0, rres, r_ctl, r_int, out[0],
		 atomic_read(&dev->irq_count));

	g2d_engines_reset(dev);
	dma_free_coherent(dev->dev, 2 * n * 4, in, dma);
}

static const struct v4l2_m2m_ops g2d_m2m_ops = {
	.device_run	= g2d_device_run,
};

static int g2d_runtime_resume(struct device *device)
{
	struct g2d_dev *dev = dev_get_drvdata(device);
	int ret;

	/* the BSP releases the reset before it enables the clocks */
	ret = reset_control_deassert(dev->rstc);
	if (ret) {
		dev_err(dev->dev, "Failed to deassert reset\n");
		return ret;
	}

	ret = clk_prepare_enable(dev->bus_clk);
	if (ret) {
		dev_err(dev->dev, "Failed to enable bus clock\n");
		goto err_reset;
	}

	ret = clk_prepare_enable(dev->mod_clk);
	if (ret) {
		dev_err(dev->dev, "Failed to enable module clock\n");
		goto err_bus_clk;
	}

	ret = clk_prepare_enable(dev->mbus_clk);
	if (ret) {
		dev_err(dev->dev, "Failed to enable MBUS clock\n");
		goto err_mod_clk;
	}

	/* clock and release both engines, as the BSP's g2d_bsp_open() */
	g2d_write(dev, G2D_TOP_SCLK_GATE, G2D_TOP_MIXER | G2D_TOP_ROT);
	g2d_write(dev, G2D_TOP_HCLK_GATE, G2D_TOP_MIXER | G2D_TOP_ROT);
	g2d_write(dev, G2D_TOP_AHB_RESET, G2D_TOP_MIXER | G2D_TOP_ROT);
	g2d_write(dev, G2D_TOP_SCLK_DIV, 0);

	return 0;

err_mod_clk:
	clk_disable_unprepare(dev->mod_clk);
err_bus_clk:
	clk_disable_unprepare(dev->bus_clk);
err_reset:
	reset_control_assert(dev->rstc);

	return ret;
}

static int g2d_runtime_suspend(struct device *device)
{
	struct g2d_dev *dev = dev_get_drvdata(device);

	g2d_write(dev, G2D_TOP_AHB_RESET, 0);
	g2d_write(dev, G2D_TOP_HCLK_GATE, 0);
	g2d_write(dev, G2D_TOP_SCLK_GATE, 0);

	reset_control_assert(dev->rstc);
	clk_disable_unprepare(dev->mbus_clk);
	clk_disable_unprepare(dev->mod_clk);
	clk_disable_unprepare(dev->bus_clk);

	return 0;
}

static int g2d_probe(struct platform_device *pdev)
{
	struct g2d_dev *dev;
	struct video_device *vfd;
	int irq, ret;

	dev = devm_kzalloc(&pdev->dev, sizeof(*dev), GFP_KERNEL);
	if (!dev)
		return -ENOMEM;

	dev->dev = &pdev->dev;
	dev->vfd = g2d_video_device;
	mutex_init(&dev->dev_mutex);
	spin_lock_init(&dev->job_lock);
	INIT_DELAYED_WORK(&dev->watchdog_work, g2d_watchdog);
	init_completion(&dev->selftest_done);
	atomic_set(&dev->irq_count, 0);

	ret = dma_set_mask_and_coherent(dev->dev, DMA_BIT_MASK(32));
	if (ret)
		return ret;

	dev->base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(dev->base))
		return PTR_ERR(dev->base);

	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;

	ret = devm_request_irq(dev->dev, irq, g2d_irq, 0, dev_name(dev->dev),
			       dev);
	if (ret)
		return dev_err_probe(dev->dev, ret, "Failed to request IRQ\n");

	dev->bus_clk = devm_clk_get(dev->dev, "bus");
	if (IS_ERR(dev->bus_clk))
		return dev_err_probe(dev->dev, PTR_ERR(dev->bus_clk),
				     "Failed to get bus clock\n");

	dev->mod_clk = devm_clk_get(dev->dev, "mod");
	if (IS_ERR(dev->mod_clk))
		return dev_err_probe(dev->dev, PTR_ERR(dev->mod_clk),
				     "Failed to get module clock\n");

	dev->mbus_clk = devm_clk_get(dev->dev, "mbus");
	if (IS_ERR(dev->mbus_clk))
		return dev_err_probe(dev->dev, PTR_ERR(dev->mbus_clk),
				     "Failed to get MBUS clock\n");

	dev->rstc = devm_reset_control_get(dev->dev, NULL);
	if (IS_ERR(dev->rstc))
		return dev_err_probe(dev->dev, PTR_ERR(dev->rstc),
				     "Failed to get reset control\n");

	ret = clk_set_rate(dev->mod_clk, G2D_CLK_RATE);
	if (ret)
		dev_warn(dev->dev, "Failed to set the module clock rate\n");

	ret = v4l2_device_register(&pdev->dev, &dev->v4l2_dev);
	if (ret)
		return dev_err_probe(dev->dev, ret,
				     "Failed to register V4L2 device\n");

	dev->m2m_dev = v4l2_m2m_init(&g2d_m2m_ops);
	if (IS_ERR(dev->m2m_dev)) {
		ret = PTR_ERR(dev->m2m_dev);
		v4l2_err(&dev->v4l2_dev, "Failed to initialize M2M device\n");
		goto err_v4l2;
	}

	vfd = &dev->vfd;
	vfd->lock = &dev->dev_mutex;
	vfd->v4l2_dev = &dev->v4l2_dev;
	video_set_drvdata(vfd, dev);

	platform_set_drvdata(pdev, dev);
	pm_runtime_enable(dev->dev);

	ret = pm_runtime_resume_and_get(dev->dev);
	if (ret < 0)
		goto err_pm;
	v4l2_info(&dev->v4l2_dev, "G2D IP version %08x, module clock %lu Hz\n",
		  g2d_read(dev, G2D_TOP_IP_VERSION), clk_get_rate(dev->mod_clk));
	g2d_selftest(dev);
	pm_runtime_put(dev->dev);

	ret = video_register_device(vfd, VFL_TYPE_VIDEO, 0);
	if (ret) {
		v4l2_err(&dev->v4l2_dev, "Failed to register video device\n");
		goto err_pm;
	}

	v4l2_info(&dev->v4l2_dev, "Device registered as /dev/video%d\n",
		  vfd->num);

	return 0;

err_pm:
	pm_runtime_force_suspend(dev->dev);
	v4l2_m2m_release(dev->m2m_dev);
err_v4l2:
	v4l2_device_unregister(&dev->v4l2_dev);

	return ret;
}

static void g2d_remove(struct platform_device *pdev)
{
	struct g2d_dev *dev = platform_get_drvdata(pdev);

	video_unregister_device(&dev->vfd);
	cancel_delayed_work_sync(&dev->watchdog_work);
	v4l2_m2m_release(dev->m2m_dev);
	v4l2_device_unregister(&dev->v4l2_dev);
	pm_runtime_force_suspend(&pdev->dev);
}

static const struct of_device_id g2d_dt_match[] = {
	{ .compatible = "allwinner,sun50i-h616-g2d" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, g2d_dt_match);

static const struct dev_pm_ops g2d_pm_ops = {
	.runtime_resume		= g2d_runtime_resume,
	.runtime_suspend	= g2d_runtime_suspend,
};

static struct platform_driver g2d_driver = {
	.probe		= g2d_probe,
	.remove		= g2d_remove,
	.driver		= {
		.name		= G2D_NAME,
		.of_match_table	= g2d_dt_match,
		.pm		= &g2d_pm_ops,
	},
};
module_platform_driver(g2d_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Arun Iyengar <aiyengar1990@gmail.com>");
MODULE_DESCRIPTION("Allwinner H616 G2D colour conversion and scaling driver");
