/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * Allwinner H616 G2D mixer, V4L2 mem2mem driver
 *
 * Copyright (C) 2026 Arun Iyengar <aiyengar1990@gmail.com>
 */

#ifndef _SUN50I_G2D_H_
#define _SUN50I_G2D_H_

#include <linux/bits.h>
#include <linux/atomic.h>
#include <linux/clk.h>
#include <linux/completion.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/reset.h>
#include <linux/spinlock.h>
#include <linux/types.h>
#include <linux/workqueue.h>

#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-mem2mem.h>
#include <media/videobuf2-v4l2.h>

#define G2D_NAME		"sun50i-g2d"

/*
 * The block is a small display-engine style mixer: one video overlay
 * (V0) with a coarse decimator, a video scaler (VSU) that also upsamples
 * chroma to 4:4:4, three UI overlays, a blender (BLD) with three colour
 * space converters, a write-back unit (WB), and a separate rotation
 * engine (ROT). This driver uses V0 -> VSU -> BLD pipe 0 -> CSC2 -> WB.
 */

/* Top level: sub-block clock gates and resets, bit 0 = mixer, bit 1 = rotate */
#define G2D_TOP_SCLK_GATE		0x0000
#define G2D_TOP_HCLK_GATE		0x0004
#define G2D_TOP_AHB_RESET		0x0008
#define G2D_TOP_SCLK_DIV		0x000c
#define G2D_TOP_IP_VERSION		0x0010
/* capability fields of IP_VERSION as the BSP's RCQ-generation header names them */
#define G2D_TOP_IP_GSU(v)		((v) & 0x3)
#define G2D_TOP_IP_VSU(v)		(((v) >> 2) & 0x3)
#define G2D_TOP_IP_RTMX(v)		(((v) >> 4) & 0x1)
#define G2D_TOP_IP_ROT(v)		(((v) >> 8) & 0x1)
#define G2D_TOP_MIXER			BIT(0)
#define G2D_TOP_ROT			BIT(1)

/* Mixer global */
#define G2D_MIXER_CTL			0x0100
#define G2D_MIXER_CTL_START		BIT(31)
#define G2D_MIXER_INT			0x0104
#define G2D_MIXER_INT_FINISH		BIT(0)
#define G2D_MIXER_INT_FINISH_EN		BIT(4)

/* Blender */
#define G2D_BLD_EN_CTL			0x0400
#define G2D_BLD_EN_CTL_PIPE(n)		BIT(8 + (n))
#define G2D_BLD_CH_ISIZE(n)		(0x0420 + 4 * (n))
#define G2D_BLD_CH_OFFSET(n)		(0x0430 + 4 * (n))
#define G2D_BLD_PREMUL_CTL		0x0440
#define G2D_BLD_BK_COLOR		0x0444
#define G2D_BLD_SIZE			0x0448
#define G2D_BLD_CTL			0x044c
/* Porter-Duff factors: source * 1 + destination * 0 */
#define G2D_BLD_CTL_COPY		0x00010001
#define G2D_BLD_OUT_COLOR		0x0460
#define G2D_BLD_OUT_COLOR_PREMUL	BIT(0)
#define G2D_BLD_OUT_COLOR_YUV		BIT(1)
#define G2D_ROP_CTL			0x0480
/* ROP3 code 0xf0 (PATCOPY): the pipe 0 pixels pass through unchanged */
#define G2D_ROP_CTL_PASS		0xf0
#define G2D_BLD_CSC_CTL			0x0500
#define G2D_BLD_CSC_CTL_EN(n)		BIT(n)
/* 3 rows of (coef0, coef1, coef2, const), Q10 fixed point */
#define G2D_BLD_CSC_COEF(n, i)		(0x0510 + 0x30 * (n) + 4 * (i))
#define G2D_CSC_WB			2

/* Video overlay 0 */
#define G2D_V0_ATTCTL			0x0800
#define G2D_V0_ATTCTL_EN		BIT(0)
#define G2D_V0_ATTCTL_PIXEL_ALPHA	(0 << 1)
#define G2D_V0_ATTCTL_GLOBAL_ALPHA	(1 << 1)
#define G2D_V0_ATTCTL_FMT(f)		((f) << 8)
#define G2D_V0_ATTCTL_ALPHA(a)		((a) << 24)
#define G2D_V0_MBSIZE			0x0804
#define G2D_V0_COOR			0x0808
#define G2D_V0_PITCH(p)			(0x080c + 4 * (p))
#define G2D_V0_LADD(p)			(0x0818 + 4 * (p))
#define G2D_V0_HADD			0x0828
#define G2D_V0_SIZE			0x082c
#define G2D_V0_HDS_CTL0			0x0830
#define G2D_V0_HDS_CTL1			0x0834
#define G2D_V0_VDS_CTL0			0x0838
#define G2D_V0_VDS_CTL1			0x083c

/* Write-back */
#define G2D_WB_ATT			0x3000
#define G2D_WB_SIZE			0x3004
#define G2D_WB_PITCH(p)			(0x3008 + 4 * (p))
#define G2D_WB_LADD(p)			(0x3014 + 8 * (p))
#define G2D_WB_HADD(p)			(0x3018 + 8 * (p))

/* Rotation engine (same layout as the DE2 rotate block) */
#define G2D_ROT_CTL			0x28000
#define G2D_ROT_CTL_EN			BIT(0)
#define G2D_ROT_CTL_START		BIT(31)
#define G2D_ROT_INT			0x28004
#define G2D_ROT_INT_FINISH		BIT(0)
#define G2D_ROT_INT_FINISH_EN		BIT(16)
#define G2D_ROT_IFMT			0x28020
#define G2D_ROT_ISIZE			0x28024
#define G2D_ROT_IPITCH(p)		(0x28030 + 4 * (p))
#define G2D_ROT_ILADD(p)		(0x28040 + 8 * (p))
#define G2D_ROT_IHADD(p)		(0x28044 + 8 * (p))
#define G2D_ROT_OSIZE			0x28084
#define G2D_ROT_OPITCH(p)		(0x28090 + 4 * (p))
#define G2D_ROT_OLADD(p)		(0x280a0 + 8 * (p))
#define G2D_ROT_OHADD(p)		(0x280a4 + 8 * (p))

/* Video scaler */
#define G2D_VSU_CTRL			0x8000
#define G2D_VSU_CTRL_EN			BIT(0)
/* held while the filter tables are written */
#define G2D_VSU_CTRL_COEF_ACCESS	BIT(8)
#define G2D_VSU_CTRL_YUV		BIT(16)
#define G2D_VSU_OUT_SIZE		0x8040
#define G2D_VSU_GLB_ALPHA		0x8044
#define G2D_VSU_Y_SIZE			0x8080
#define G2D_VSU_Y_HSTEP			0x8088
#define G2D_VSU_Y_VSTEP			0x808c
#define G2D_VSU_Y_HPHASE		0x8090
#define G2D_VSU_Y_VPHASE0		0x8098
#define G2D_VSU_C_SIZE			0x80c0
#define G2D_VSU_C_HSTEP			0x80c8
#define G2D_VSU_C_VSTEP			0x80cc
#define G2D_VSU_C_HPHASE		0x80d0
#define G2D_VSU_C_VPHASE0		0x80d8
#define G2D_VSU_Y_HCOEF(i)		(0x8200 + 4 * (i))
#define G2D_VSU_Y_VCOEF(i)		(0x8300 + 4 * (i))
#define G2D_VSU_C_HCOEF(i)		(0x8400 + 4 * (i))
/* steps and phases are Q20 fixed point; 32 filter phases of 4 taps */
#define G2D_VSU_FRAC_BITS		20
#define G2D_VSU_PHASES			32
/* 4:2:0 chroma sits a quarter sample ahead of luma on both axes */
#define G2D_VSU_PHASE_420		(-(1 << (G2D_VSU_FRAC_BITS - 2)))

/* sizes are coded as (height - 1) << 16 | (width - 1) */
#define G2D_SIZE(w, h)			((((h) - 1) << 16) | ((w) - 1))

/* Hardware pixel format codes (V0 and WB) */
#define G2D_FMT_ARGB8888		0x00
#define G2D_FMT_ABGR8888		0x01
#define G2D_FMT_RGBA8888		0x02
#define G2D_FMT_BGRA8888		0x03
#define G2D_FMT_XRGB8888		0x04
#define G2D_FMT_XBGR8888		0x05
#define G2D_FMT_RGBX8888		0x06
#define G2D_FMT_BGRX8888		0x07
#define G2D_FMT_RGB888			0x08
#define G2D_FMT_BGR888			0x09
#define G2D_FMT_RGB565			0x0a
#define G2D_FMT_BGR565			0x0b
#define G2D_FMT_YUV422_SP_UV		0x24
#define G2D_FMT_YUV422_SP_VU		0x25
#define G2D_FMT_YUV422_P		0x26
#define G2D_FMT_YUV420_SP_UV		0x28
#define G2D_FMT_YUV420_SP_VU		0x29
#define G2D_FMT_YUV420_P		0x2a

#define G2D_MIN_WIDTH			8
#define G2D_MIN_HEIGHT			8
#define G2D_MAX_WIDTH			2048
#define G2D_MAX_HEIGHT			2048
#define G2D_PITCH_ALIGN			16
#define G2D_CLK_RATE			300000000
#define G2D_JOB_TIMEOUT_MS		500
/* probe-time self-test: one 16x16 copy through the mixer and through ROT */
#define G2D_SELFTEST_SIZE		16
#define G2D_SELFTEST_TIMEOUT_MS		100

/* above this input/output ratio the overlay decimates before the scaler */
#define G2D_COARSE_H_RATIO		8
#define G2D_COARSE_V_RATIO		4

struct g2d_fmt {
	u32 fourcc;
	u8 hw;
	u8 planes;
	u8 bpp;		/* bytes per pixel of plane 0 */
	u8 cbpp;	/* bytes per chroma sample in the chroma plane(s) */
	u8 hsub;
	u8 vsub;
	bool yuv;
	bool swap_uv;	/* planar with the V plane before the U plane */
};

struct g2d_dev {
	struct device *dev;
	struct v4l2_device v4l2_dev;
	struct video_device vfd;
	struct v4l2_m2m_dev *m2m_dev;
	/* serialises the ioctls and the file operations */
	struct mutex dev_mutex;
	/* protects job_active between the irq and the watchdog */
	spinlock_t job_lock;
	bool job_active;
	struct delayed_work watchdog_work;
	/* completed by finish interrupts that belong to no m2m job */
	struct completion selftest_done;
	atomic_t irq_count;

	void __iomem *base;
	struct clk *bus_clk;
	struct clk *mod_clk;
	struct clk *mbus_clk;
	struct reset_control *rstc;
};

struct g2d_ctx {
	struct v4l2_fh fh;
	struct g2d_dev *dev;
	struct v4l2_ctrl_handler ctrl_handler;

	struct v4l2_pix_format src_fmt;
	struct v4l2_pix_format dst_fmt;
};

#endif /* _SUN50I_G2D_H_ */
