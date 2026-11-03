# AVS1 / AVS+ prior art (2026-11-03)

**Summary.** There is no V4L2 *stateless* AVS1/AVS+ uAPI anywhere (mainline or downstream), no cedrus or other
sunxi AVS work, and no open Allwinner AVS register documentation. Downstream kernels only have *stateful* AVS
fourccs. The useful models for a stateless uAPI are Rockchip MPP's AVS "syntax" (userspace owns the DPB, the hardware
gets one picture parameter struct) and the open libva PR #738 picture/slice parameter buffers. FFmpeg's software
decoder gained AVS+ (AEC, field coding, annex A) on 2026-11-02, which gives a reference for all our test streams.

## 1. Kernel / V4L2

| item | what | where |
|---|---|---|
| mainline | nothing: no `V4L2_PIX_FMT_*AVS*`, no AVS controls (checked `include/uapi/linux/videodev2.h` and `v4l2-controls.h` of our 7.3.1 tree; the only AVS entry is our own downstream `V4L2_PIX_FMT_AVS2_FRAME` 'AVS2') | `kernel-check/work-video-patch/linux-7.3.1/include/uapi/linux/` |
| NXP i.MX Hantro (stateful) | `V4L2_PIX_FMT_AVS` = **'AVS0'** | https://github.com/nxp-imx/linux-imx `lf-6.18.y`, `include/uapi/linux/imx_vpu.h` l. 110; `drivers/mxc/hantro_v4l2/vsi-v4l2-config.c` |
| Arm Mali VPU "mvx" (CIX, Kendryte K230; stateful) | `V4L2_PIX_FMT_AVS` = **'AVS1'**, `V4L2_PIX_FMT_AVS2` = 'AVS2' | https://github.com/deepin-community/kernel `linux-6.6.y`, `drivers/soc/cix/vpu/driver/linux/mvx-v4l2-controls.h` l. 75-76; kendryte/k230_sdk `.../canaan-vpu/mvx-v4l2-controls.h` |
| Amlogic (stateful, firmware parses) | 'AVS0' in the v4l2 test player; kernel decoder `avs_multi` with AVS+ WQ registers (`AVSP_IQ_WQ_PARAM_01/23/45`) and an "avsp long cabac" software assist for AEC | https://github.com/CoreELEC/media_modules-aml @ `c15aebb1ac93`, `tools/v4lplayer/v4l2_dec.h`, `drivers/frame_provider/decoder/avs_multi/avs_multi.c` (GPL-2.0-or-later) |
| MediaTek (vendor tree) | AVS mentioned in `mtk-vcodec/vdec_drv_if.c` (stateful vendor firmware path) | TCLOpenSource/mt9653 |
| linux-media / lore | no AVS stateless series found. lore.kernel.org search is behind a bot wall (HTTP 403 from curl), as noted for AVS2; a web search for "V4L2 stateless AVS cavs linux-media" returned only generic stateless material (patchwork 59500, LWN 794544/1043534, Amlogic H.264 RFC v4 2026-02 whose TODO has no AVS) | — |
| cedrus / sunxi | none. GitHub code search for `isAvs` / `VE_DEC_AVS` / cedrus+avs: 0 hits; the vendor libVE/`cedar_ve` kernel driver has no AVS registers (the library drives them through mmap) | — |

**Consequence for the fourcc:** 'AVS0' and 'AVS1' are both taken downstream (for *stateful* compressed streams).
A stateless format must not reuse them; see uapi-proposal.md ('AVSF').

## 2. Userspace models

### 2.1 Rockchip MPP (Apache-2.0), `kernel-check/dl-avs2/mpp/repo` @ `7916c3cc000f`

- Parser `mpp/codec/dec/avs/avsd_parse.c`: sequence header (profiles 0x20/0x48 only, level ≤ 0x42), sequence display
  extension, I and PB picture headers incl. the AVS+ fields, WQ parameter derivation (`gen_weight_quant_param`, base
  tables {128,98,106,116,116,128} / {135,143,143,160,160,213}), DPB of 2 frames (`dpb[2]`, "2 refer frames or 4
  refer field").
- **Syntax struct** `mpp/common/avsd_syntax.h`: `PicParams_Avsd` = flat sequence + display-extension + picture header
  fields + WQ raw (cb/cr deltas, index, model, delta1[6], delta2[6]) **and** derived `weightingQuantParam[6]`, plus
  `aecEnable`, `noForwardReferenceFlag`, `pbFieldEnhancedFlag`; `AvsdSyntax_t` adds the bitstream pointer/offset/size.
  References are passed as task slots (`task->refer[0..1]`), not inside the struct.
- HAL `mpp/hal/rkdec/avsd/hal_avsd_plus.c` (AVS+ "plus" Hantro variant) and `hal_avsd_vdpu1/2.c`: per-field triggers
  (`first_field`), second-field references include the current frame (`refer0_base = output`), output offset by one
  line for the bottom field, B needs the future reference's field/frame coding.
- This is the model for "userspace owns the DPB, hardware gets resolved references", and its field set matches what
  the Allwinner engine needs, except that the VE wants raw WQ syntax (MPP's Hantro wants derived wqP).

### 2.2 libva PR #738 (MIT, open since 2023-07-25, head `564420c92726`, by Moore Threads)

https://github.com/intel/libva/pull/738, file `va/va_dec_avs.h` (read from the PR head; not kept in the tree):
- `VAPictureParameterBufferAVS`: `curr_pic`, `ref_list[2]` (surface + top/bottom field flags + poc), coded size,
  picture_type, progressive_seq/frame, picture_structure, fixed qp, qp, loop filter, skip_mode, picture_reference,
  no_forward_reference, alpha/beta, and `guangdian_fields` {guangdian, aec, weight_quant, pb_field_enhanced flags,
  chroma cb/cr deltas, **resolved `wqm_8x8[64]`**}.
- `VASliceParameterBufferAVS`: slice offsets, mb_data_bit_offset, slice_vertical_pos, slice qp, slice/mb weighting
  flags, luma/chroma scale/shift[4].
- Same author family as the AVS2 header we used for the AVS2 uAPI. Not merged.

### 2.3 FFmpeg (LGPL-2.1-or-later)

- `libavcodec/cavsdec.c` etc.: software decoder; no hwaccel for AVS1 (no VA/VDPAU/V4L2-request AVS path).
  The 2026-11-02 series (commits `5734b4cd4060` .. `375e3df8fe5b`) adds AVS1-P16 profile 0x48: AEC (`cavs_aec.c`),
  field-coded pictures, enhanced field B, annex A pseudo-start-code removal, slice_vertical_position_extension, and
  FATE tests `cavs-bunny` and `cavs-avsplus`. Still unsupported: adaptive weighted quantisation, slice weighted
  prediction, enhanced field P (PFieldSkip).
- The `v4l2request` FFmpeg forks we build (Jernej's) have no AVS hwaccel; one would have to be written (AVS1 is small:
  one picture parameter set per picture, like MPEG-2).

### 2.4 Allwinner

- `libawavs.so` (proprietary, regmap.md): headers parsed in software through the VE bit reader, one trigger per picture,
  per-picture state is a reference-history table, WQ given as raw syntax.
- No open Allwinner source for AVS (the TinyVision libcedarc copy has only the AVS2 framing source `sbmFrameAvs2.c`).

## 3. What the uAPI takes from each

| decision | from |
|---|---|
| one OUTPUT buffer = one picture with raw start codes (headers + slices), software parses headers | MPP, vendor, our AVS2 uAPI |
| flat sequence control, picture control with syntax flags | MPP `PicParams_Avsd`, libva |
| resolved references in the picture control (timestamp + per-ref metadata) | AVS2 uAPI pattern; libva `ref_list[2]` |
| per-ref picture_distance / structure / top_field_first / is-intra | Allwinner engine needs (regmap §4.2-4.4) |
| WQ as raw syntax (index, model, deltas) | Allwinner engine and MPP raw fields; drivers needing matrices derive them (MPP shows how) |
| no slice control | vendor and MPP: the hardware parses slice headers |
