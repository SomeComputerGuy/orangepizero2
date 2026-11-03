# Proposed downstream stateless uAPI: AVS1 (JiZhun) / AVS+ (Guangdian) decoding

Draft 2026-11-03, for the cedrus H616 backend (regmap.md). Modelled on our AVS2 uAPI (scratch tree
`kernel-check/scratch-avs2/linux`, branch `avs2-v4`, `include/uapi/linux/v4l2-controls.h`, controls at
`V4L2_CID_CODEC_STATELESS_BASE + 900..903`, types 0x02c0..0x02c3), MPP's `PicParams_Avsd` and libva PR #738
(prior-art.md). Downstream only, like AVS2: upstream would want a second user.

## Headline

- Pixel format **`V4L2_PIX_FMT_AVS_FRAME` = v4l2_fourcc('A', 'V', 'S', 'F')**: one OUTPUT buffer = one coded picture
  (picture header + all slices of both fields, raw, with start codes and pseudo start codes intact); sequence header,
  extensions and user data may precede it. ('AVS0' and 'AVS1' are taken by stateful downstream drivers.)
- Three controls at **`V4L2_CID_CODEC_STATELESS_BASE + 1000..1002`**, types **0x02d0..0x02d2**:
  `V4L2_CID_STATELESS_AVS_SEQUENCE` (16 B), `V4L2_CID_STATELESS_AVS_PICTURE` (64 B, with 3 resolved reference
  descriptors), `V4L2_CID_STATELESS_AVS_WEIGHT_QUANT` (24 B, AVS+ only).
- No slice control: the VE (and MPP's Hantro) parse slice headers.
- cedrus: **H.264 slot (VE+0x200), VE_MODE 1 (`VE_MODE_DEC_H264`), CTRL bit 28 (isAvs)**, new
  `CEDRUS_CAPABILITY_AVS_DEC` = **BIT(10)**, enabled for the H616 variant in a separate patch.

## 1. Pixel format

```
#define V4L2_PIX_FMT_AVS_FRAME v4l2_fourcc('A', 'V', 'S', 'F') /* AVS1/AVS+ parsed frame */
```
Documentation (pixfmt-compressed.rst): "AVS1 (GB/T 20090.2) and AVS+ (AVS1-P16, GY/T 257.1) picture. One buffer holds
the picture start code and header and all slices of the picture, as found in the elementary stream; for a field coded
picture both fields. Requires the three AVS stateless controls."

## 2. Controls

```c
#define V4L2_AVS_PROFILE_JIZHUN				0x20
#define V4L2_AVS_PROFILE_GUANGDIAN			0x48

#define V4L2_AVS_SEQUENCE_FLAG_PROGRESSIVE_SEQUENCE	0x00000001
#define V4L2_AVS_SEQUENCE_FLAG_LOW_DELAY		0x00000002

#define V4L2_CID_STATELESS_AVS_SEQUENCE	(V4L2_CID_CODEC_STATELESS_BASE + 1000)
struct v4l2_ctrl_avs_sequence {
	__u32	flags;			/* V4L2_AVS_SEQUENCE_FLAG_{} */
	__u16	horizontal_size;
	__u16	vertical_size;
	__u8	profile_id;		/* V4L2_AVS_PROFILE_{} */
	__u8	level_id;
	__u8	chroma_format;		/* 1 = 4:2:0 */
	__u8	sample_precision;	/* 1 = 8-bit */
	__u8	aspect_ratio;
	__u8	frame_rate_code;
	__u8	reserved[2];
};					/* 16 bytes, no holes */

#define V4L2_AVS_PICTURE_TYPE_I				0
#define V4L2_AVS_PICTURE_TYPE_P				1
#define V4L2_AVS_PICTURE_TYPE_B				2

#define V4L2_AVS_PICTURE_FLAG_PROGRESSIVE_FRAME		0x00000001
#define V4L2_AVS_PICTURE_FLAG_PICTURE_STRUCTURE		0x00000002 /* 1 = frame coded */
#define V4L2_AVS_PICTURE_FLAG_TOP_FIELD_FIRST		0x00000004
#define V4L2_AVS_PICTURE_FLAG_REPEAT_FIRST_FIELD	0x00000008
#define V4L2_AVS_PICTURE_FLAG_FIXED_PICTURE_QP		0x00000010
#define V4L2_AVS_PICTURE_FLAG_PICTURE_REFERENCE		0x00000020 /* picture_reference_flag */
#define V4L2_AVS_PICTURE_FLAG_SKIP_MODE			0x00000040
#define V4L2_AVS_PICTURE_FLAG_ADVANCED_PRED_MODE_DISABLE 0x00000080
#define V4L2_AVS_PICTURE_FLAG_LOOP_FILTER_DISABLE	0x00000100
#define V4L2_AVS_PICTURE_FLAG_NO_FORWARD_REFERENCE	0x00000200 /* AVS+ */
#define V4L2_AVS_PICTURE_FLAG_PB_FIELD_ENHANCED		0x00000400 /* AVS+ */
#define V4L2_AVS_PICTURE_FLAG_WEIGHTING_QUANT		0x00000800 /* AVS+, see WEIGHT_QUANT */
#define V4L2_AVS_PICTURE_FLAG_AEC			0x00001000 /* AVS+ aec_enable */

#define V4L2_AVS_REF_FORWARD				0
#define V4L2_AVS_REF_SECOND_FORWARD			1
#define V4L2_AVS_REF_BACKWARD				2
#define V4L2_AVS_NUM_REFS				3

#define V4L2_AVS_REF_FLAG_VALID				0x01
#define V4L2_AVS_REF_FLAG_INTRA				0x02 /* was an I picture */
#define V4L2_AVS_REF_FLAG_PICTURE_STRUCTURE		0x04 /* its picture_structure (1 = frame) */
#define V4L2_AVS_REF_FLAG_TOP_FIELD_FIRST		0x08

struct v4l2_avs_ref_pic {
	__u64	timestamp;		/* capture buffer of the reference */
	__u8	picture_distance;	/* as coded in its header */
	__u8	flags;			/* V4L2_AVS_REF_FLAG_{} */
	__u8	reserved[6];
};					/* 16 bytes */

#define V4L2_CID_STATELESS_AVS_PICTURE	(V4L2_CID_CODEC_STATELESS_BASE + 1001)
struct v4l2_ctrl_avs_picture {
	struct v4l2_avs_ref_pic refs[V4L2_AVS_NUM_REFS];
	__u32	data_offset;		/* bytes to the start code prefix of the first slice */
	__u32	flags;			/* V4L2_AVS_PICTURE_FLAG_{} */
	__u8	picture_type;		/* V4L2_AVS_PICTURE_TYPE_{} */
	__u8	picture_distance;
	__u8	picture_qp;
	__s8	alpha_c_offset;		/* 0 unless loop_filter_parameter_flag */
	__s8	beta_offset;
	__u8	reserved[3];
};					/* 48 + 16 = 64 bytes, 8-byte aligned, no holes */

#define V4L2_AVS_WEIGHT_QUANT_FLAG_CHROMA_QUANT_PARAM_DISABLE 0x00000001

#define V4L2_CID_STATELESS_AVS_WEIGHT_QUANT (V4L2_CID_CODEC_STATELESS_BASE + 1002)
struct v4l2_ctrl_avs_weight_quant {
	__u32	flags;
	__s8	chroma_quant_param_delta_cb;	/* 0 when disabled */
	__s8	chroma_quant_param_delta_cr;
	__u8	weighting_quant_param_index;	/* 0..2 */
	__u8	weighting_quant_model;		/* 0..3 */
	__s8	weighting_quant_param_delta1[6];/* used when index == 1 */
	__s8	weighting_quant_param_delta2[6];/* used when index == 2 */
	__u8	reserved[4];
};					/* 24 bytes */
```

Sizes worked out by hand from natural alignment (the AVS2 structs were checked with pahole on the host; do the same
when the patch is written).

### 2.1 Reference semantics (the part userspace must get right)

Userspace keeps the last three I/P pictures (newest first: R0, R1, R2) with their picture_distance, structure,
top_field_first and type.

| picture | refs[FORWARD] | refs[SECOND_FORWARD] | refs[BACKWARD] |
|---|---|---|---|
| I | — (flags 0) | — | — |
| P | R0 (nearest) | R1 | — |
| B | R1 (past) | R2: only `picture_distance` + flags are used (it is the backward reference's own second reference; no buffer access) | R0 (future, co-located) |

A field-coded P's second field also references the first field of the current frame; the engine does that itself
(the current frame is the reconstruction target) — **[board]** (regmap B8). Missing references (stream start, open
GOP) are flagged invalid; the driver then uses the current frame, as the vendor does, and the picture is expected to be
damaged.

### 2.2 Validation (try_ctrl / std_validate_compound)

- SEQUENCE: profile 0x20 or 0x48; chroma_format 1; sample_precision 1; sizes 16..1920 × 16..1088 (driver limit);
  reserved zero; unknown flags rejected.
- PICTURE: type ≤ 2; flags mask; AVS+-only flags rejected when the sequence profile is 0x20 (driver, since it needs
  the sequence); P needs FORWARD valid, B needs FORWARD and BACKWARD valid; `data_offset` < payload size.
- WEIGHT_QUANT: index ≤ 2, model ≤ 3, deltas in −32..31 for cb/cr (6-bit hardware fields, **[spec]** range to check),
  reserved zero. Read by the driver only when the picture has WEIGHTING_QUANT.

### 2.3 Docs to write (as for AVS2)

ext-ctrls-codec-stateless.rst (3 controls), pixfmt-compressed.rst ('AVSF'), vidioc-queryctrl.rst and
vidioc-g-ext-ctrls.rst type tables, videodev2.h.rst.exceptions, biblio entries GB/T 20090.2-2013 and GY/T 257.1-2012
(AVS+), v4l2-ctrls-core.c/v4l2-ctrls-defs.c (names, types, `std_validate_compound`, `std_log`, sizes in
`v4l2_ctrl_new`).

## 3. cedrus mapping

| uAPI | register (regmap.md) |
|---|---|
| sequence profile/level/chroma/precision, picture NO_FORWARD/PB_FIELD_ENHANCED/AEC/WEIGHTING_QUANT, WQ CHROMA_DISABLE | 0x04 |
| WQ cb/cr/index/model/deltas | 0x0C, 0x10 (deltas of the active index, 0 for index 0) |
| picture type, structure flags, qp, loop filter, alpha/beta, refs[FORWARD] flags, refs[SECOND_FORWARD] (P) or refs[BACKWARD] (B) flags | 0x14 |
| picture_distance; FORWARD, BACKWARD, SECOND_FORWARD distances | 0x18 [7:0], [15:8], [23:16], [31:24] |
| sizes | 0x58, 0x5C |
| OUTPUT buffer, `data_offset`, payload | 0x30, 0x34, 0x38, 0x3C |
| capture buffer of the current picture | 0xAC/0xD0 |
| refs[FORWARD] buffer | 0xB0/0xD4 |
| refs[SECOND_FORWARD] buffer for P, refs[BACKWARD] buffer for B | 0xB4/0xD8 |
| per-context 48 KiB MB-info buffer | 0x54 |
| per-capture-buffer col-MV buffer: own for I/P, refs[BACKWARD]'s for B | 0x50 |

Driver flow (`cedrus_avs.c`, like `cedrus_vp8.c`): `.setup` writes CTRL 0x10000007 | bit 10 | bit 26, the registers
above, MB_ADDR/ERROR/CUR_MB = 0, then `.trigger` writes 0x17 and 0x19 to 0x24 (regmap B2). IRQ: `VE_H264_STATUS`
bits 0..2 (W1C), error on bit 1 or 2. Capture formats: NV12_32L32 (tiled) and, with `CEDRUS_CAPABILITY_UNTILED`,
NV12/NV21/YUV420/YVU420 through the existing top-register path. 8-bit only (no P010).

## 4. Userspace

Test tool `harness/avs1dec/` (to write, MIT, own code): ES/PS/TS input, start-code scan, annex A removal for headers,
sequence/picture parsing (syntax.md), 3-slot reference history, output ordering, one request per picture, I420 output
and per-frame md5 and FFmpeg-framecrc-compatible adler32 (test-streams.md). An FFmpeg v4l2-request AVS hwaccel would
be the second step.
