# AVS2 hardware-decode prior art (open code survey)

Written 2026-11-02 from static reading only. Local copies are under `kernel-check/dl-avs2/`. Commit hashes are pinned.

## Summary table

| vendor / project | header parsing done by | open? | uAPI | licence |
|---|---|---|---|---|
| Amlogic (media_modules vavs2) | **firmware ucode** (AMRISC) parses seq/pic headers; the kernel gets an "RPM" parameter dump and does DPB, ref lists, ALF/MC/MPRED/SAO/DBLK register config | kernel driver GPL source; **ucode is a binary blob** | legacy amports + out-of-tree stateful V4L2 M2M (`aml_vcodec`) with private `V4L2_PIX_FMT_AVS2 'AVS2'` | GPL-2.0+ |
| Rockchip (rkvdec2 vdpu34x/382/383/384b) | **userspace (MPP)** parses all headers and runs the DPB; HW gets a packed "global cfg" header buffer, a scaling-list buffer, registers, and raw slice NALs | MPP userspace source open; kernel = register pass-through `mpp_service` | none (MPP ioctl) | MPP: Apache-2.0 / "Apache-2.0 OR MIT"; kernel mpp: GPL-2.0+ OR MIT |
| Moore Threads (GPU) | userspace (FFmpeg patch) parses headers + DPB | patch only, not merged | VA-API proposal (libva PR #738, open) | LGPL / MIT |
| Allwinner (CedarX / libcedarc) | userspace binary `libawavs2.so` | **no source**; only `sbmFrameAvs2.c` (NAL framing) is source | CedarX `/dev/cedar_dev` register access | proprietary |
| HiSilicon / MStar / others | - | **no open AVS2 code found** | - | - |
| FFmpeg | no native AVS2 decoder; parser + libdavs2/libxavs2 wrappers | yes | - | LGPL |
| Linux mainline | - | **no AVS2 pixfmt or controls** | - | - |

---

## 1. Amlogic media_modules (CoreELEC fork)

Repo: https://github.com/CoreELEC/media_modules-aml @ `c15aebb1ac93028d0aceadf8f35dda2204d33424` (default branch
`5.15.196_20260225`). Files: `drivers/frame_provider/decoder/avs2/{vavs2.c (9243 lines), avs2_bufmgr.c (1999), avs2_global.h (1700)}`.
(`khadas/media_modules` and `LibreELEC/media_modules-aml` return 404 on the GitHub API.)
Licence: GPL-2.0-or-later headers ("Copyright (C) 2017 Amlogic"), `MODULE_LICENSE("GPL")`. The firmware is loaded with
`get_firmware_data(VIDEO_DEC_AVS2_MMU, ...)` / `amhevc_loadmc_ex(VFORMAT_AVS2, ...)` (vavs2.c:7297-7317) and is a closed binary.

* **Who parses headers:** the ucode. The ISR gets `dec_status` = `AVS2_HEAD_SEQ_READY 0x21`, `AVS2_HEAD_PIC_I_READY 0x22`,
  `AVS2_HEAD_PIC_PB_READY 0x23`, ... (vavs2.c:106-126). It then reads `union param_u` 16 bits at a time via
  `RPM_CMD_REG` (`get_rpm_param`, vavs2.c:5550). `param_u` (avs2_global.h:1542-1635) holds the seq fields
  (profile..lcu size, `avs2_seq_flags` bitmask of the 12 tool flags, num_of_RPS, picture_reorder_delay), the pic fields
  (time_code, background flags, coding_order, cur_layer, displaydelay, predict, RPS_idx, **the resolved current RCS**:
  referred_by_others_cur, num_of_ref_cur, ref_pic_cur[8], num_to_remove_cur, remove_pic_cur[8]),
  progressive/structure/tff/rff/is_top_field, picture_coding_type, background_pred/ref flags, random_access_decodable,
  alpha/beta, chroma qp deltas, loop_filter_disable, HDR SEI fields, plus an **ALF block** (enables, filters_num_m_1,
  region_distance[16], cb/cr/y coeffmulti). **No WQ fields** reach the kernel. The kernel only writes the *default*
  4x4/8x8 WQ matrices to `HEVC_IQIT_SCALELUT_DATA` (vavs2.c:4289-4304). Picture-level WQ is presumably handled in
  ucode (**unverified**).
* **DPB / RPS / ref lists:** `avs2_bufmgr.c` is an RD-derived buffer manager (`avs2_process_header` :1711,
  `prepare_RefInfo` style). POC = coding_order + displaydelay - picture_reorder_delay; `pic_distance = tr % 256`
  (:686-697). Each frame stores `ref_poc[]` (the POCs of its refs; [past, future] for B; own POC for intra) for later col-MV use
  (:1144-1178).
* **MC refs:** `config_mc_buffer` (vavs2.c:2879) writes canvas ids into `HEVCD_MPP_ANC_CANVAS_*`. P: L0 = refs.
  F: L0 = L1 = refs. B: L0 = fref[1] (past), L1 = fref[0] (future). Background picture: L0 slot 15, L1 slot 31.
* **Col-MV:** `config_mpred_hw` (vavs2.c:3089). col = fref[0]. It writes MV wr/rd start/end addresses, `HEVC_MPRED_CTRL9`
  (bk_img_is_top_field, background_picture_enable, num_of_ref, pmvr, is_top_field, is_field_sequence, typeb,
  background_reference_enable), `HEVC_MPRED_CUR_POC = pic_distance`, `HEVC_MPRED_COL_POC = imgtr_next_P`,
  `L0_REFxx_POC` = each ref's POC, `L1_REFxx_POC` = **col picture's ref_poc[xx]** (7 pairs, written in strict L0, L1 order).
  MV memory unit per LCU: 0x200 (64), 0x80 (32), 0x20 (16) bytes.
* **ALF:** the kernel reconstructs coefficients (`reconstructCoefInfo`, vavs2.c:3621) and writes Cr, Cb, then the 16-entry
  var/region index table (2 words) and then per filter 2 words (7-bit coeffs, c4 split 4+3 bits, bit31 = last) to
  `HEVC_DBLK_CFGD` (`config_alf_hw`, 3640-3816).
* **Deblock/SAO:** `config_dblk_hw` (3237) and `config_sao_hw` (3300) use the RPM values.
* **10-bit / buffers:** bit depth from sample_precision/encoding_precision (avs2_bufmgr.c:225-240). Output is the Amlogic
  lossless-compressed frame (MMU, "compress header") with optional double-write (8-bit or 10-bit downscaled) (vavs2.c
  `double_write_mode` comment :256-280). An `AVS2_10B_DISCARD_NAL` status exists.
* **uAPI:** legacy amports (`/dev/amstream_*`) plus `drivers/amvdec_ports` (a stateful V4L2 M2M driver derived from the MediaTek
  vcodec) which defines a private `V4L2_PIX_FMT_AVS2 v4l2_fourcc('A','V','S','2')` (aml_vcodec_drv.h:1236). Stateful, not
  stateless.

## 2. Rockchip

### MPP userspace (the best structural model)
Repo: https://github.com/rockchip-linux/mpp @ `7916c3cc000fefc0bdf96636b7d54fe174724f44`. Parser: `mpp/codec/dec/avs2/`.
HALs: `mpp/hal/rkdec/avs2d/hal_avs2d_{rkv (vdpu34x/RK356x), vdpu382, vdpu383 (RK3576), vdpu384b}.c` + `hal_avs2d_com.c`.
Interface struct: `mpp/common/avs2d_syntax.h`, which is DXVA-style:
* `PicParams_Avs2d`: chroma_format_idc:2, pic_width/height_in_luma_samples:16 (aligned to 8), bit_depth_luma/chroma_minus8:3,
  lcu_size:3, progressive_sequence, field_coded_sequence, 11 tool flags (mhp_skip, dhp, wsm, amp, nsqt, nsip, 2nd_transform, sao,
  alf, pmvr, cross_slice_lf), picture_type:3 (I0 P1 B2 F3 G4 GB5 S6), scene_reference_enable_flag, bottom_field_picture_flag,
  fixed_picture_qp, picture_qp:7, loop_filter_disable_flag, alpha_c_offset, beta_offset, cur_poc.
* `RefParams_Avs2d`: ref_pic_num, ref_poc_list[32], scene_ref_slot_idx, scene_ref_enable, scene_ref_replace_pos.
* `AlfParams_Avs2d`: 3 enables, alf_filter_num_minus1, alf_coeff_idx_tab[16], alf_coeff_y[16][9], cb[9], cr[9].
* `WqmParams_Avs2d`: pic_weight_quant_enable_flag, chroma_quant_param_delta_cb/cr, wq_matrix[2][64] (final matrices).

Filled in `avs2d_fill_parameters` (avs2d_parse.c:359). The HAL packs it into a bit-serialised **"global cfg" (SHPH) buffer**
(`hal_avs2d_vdpu38x_prepare_header`, hal_avs2d_com.c:95; older `prepare_header` hal_avs2d_rkv.c:54) in this field order:
seq bits, pic bits, `chroma qp deltas:6 x2`, wq enable, ALF (coeffs 7 bits each), the 6 tool flags, `cur_poc:32`, 8 x `ref_poc:32`,
8 x field flags, 8 x bottom flags, 8 x valid bits, 64-bit aligned. Scaling list: `prepare_scalist` (4x4 then 8x8, transposed
by 4x4 block). Registers (hal_avs2d_rkv.c fill_registers 256-400): `dec_mode = 3 (AVS2)`; `cur_pic_is_idr` for I/G/GB;
cur POC `reg65`; up to 16 ref bases `reg164_179` + ref colmv bases `reg181_196` + ref POCs `reg67_98`; the scene ref
overwrites the `replace_pos` slot; colmv cur base `reg131`; stream `reg128` = packet with **concatenated raw slice NALs incl.
start codes** (headers stripped by `store_nalu`); `str_len` = align16(len)+64. So: the userspace parses everything except the
slices, and the HW parses slice headers plus pseudo-start-code removal internally. This is a stateless design, and it maps
1:1 onto a V4L2 stateless control set.
Output formats: NV12 8-bit or `YUV420SP_10BIT` (packed 10-bit), optional FBC/AFBC and tile.

### Rockchip kernel
* Downstream `rockchip-linux/kernel` `develop-6.1` @ `77168c8d5ab82399f65a80e9f807b50ba37cf483`:
  `drivers/video/rockchip/mpp/mpp_rkvdec2.c` only has AVS2 **fd-translation tables** (`trans_tbl_avs2d`,
  `trans_vdpu383_tbl_avs2d`, `RKVDEC_FMT_AVS2`) for the register pass-through `mpp_service`. There is no V4L2 AVS2.
  Licence GPL-2.0+ OR MIT.
* Mainline: the Collabora rkvdec2 (vdpu34x) series says the core supports "H264, HEVC, VP9 and AVS2" but the driver
  "currently only supports H264" (https://lwn.net/Articles/978909/, https://patches.linaro.org/patch/804590). **No AVS2 driver
  or uAPI has been posted that I could find.**

## 3. Linux mainline / linux-media uAPI discussion

* `include/uapi/linux/videodev2.h` and `v4l2-controls.h` at torvalds/linux `6628e7d4c6b25c8d18f1345e3a20d21829aae7e4` contain
  **no "AVS"** (grep). The stateless formats are MPEG2_SLICE, VP8_FRAME, VP9_FRAME, H264_SLICE, HEVC_SLICE, AV1_FRAME.
* The only AVS2 uAPI proposal found: "[PATCH] [media] v4l2: Add AV1, AVS and AVS2 format" by hao.shi (Amlogic per the thread),
  2022-08-26. It added `V4L2_PIX_FMT_AVS2 'AVS2'` (stateful compressed fourcc). Laurent Pinchart asked for documentation, and
  Nicolas Dufresne asked for the exact bitstream representation and noted AVS/AVS2 are "not very common outside China". It was
  not merged. https://lkml.iu.edu/hypermail/linux/kernel/2208.3/03865.html ,
  https://lore.kernel.org/lkml/YwiPMOyfXKM8lxIR@pendragon.ideasonboard.com/T/
* lore.kernel.org search could not be queried directly (Anubis bot wall). A web search for AVS2 stateless uAPI patches found
  nothing else. **"No stateless AVS2 uAPI was ever proposed" is likely but not exhaustively verified.**

## 4. Allwinner

* **No AVS2 decoder source exists publicly** that I could find. The GitHub code search for `avs2_hal`, `AVS2_PICTURE_START_CODE`
  and `avs2 path:cedar_ve.c|.h` returned 0 hits. In libcedarc, AVS2 appears as `VIDEO_CODEC_FORMAT_AVS2` → `SBM_TYPE_FRAME_AVS2`
  (vdecoder.c:668) and as the **only AVS2 source file `vdecoder/sbm/sbmFrameAvs2.c`** ("Copyright (c) 2008-2018 Allwinner ... All
  rights reserved", author xyliu, 2018-09-05). It does NAL framing only (start codes B0/B1/B2/B3/B5/B6/B7 split frames).
  Copy: `kernel-check/dl-avs2/tinyvision-libcedarc/sbmFrameAvs2.c`, from
  https://github.com/YuzukiHD/TinyVision/tree/356b94946a4887b721423f41711c7bc94fe74a18/tina/openwrt/package/allwinner/multimedia/tina_multimedia/libcedarc (md5 of sbmFrameAvs2.c: see local copy)
  The decoder itself is linked as the prebuilt `libawavs2.so` / static (Android.mk_d `LOCAL_STATIC_LIBRARIES += libawavs2`).
* **Kernel:** the Allwinner cedar_ve drivers (allwinner-zh/linux-3.4-sunxi, Allwinner-Homlet/H6-BSP4.9, sipeed LonganPi-3H-SDK
  bsp/drivers/ve, orangepi-xunlong kernels ...) have **no AVS2 register defines**. Code search "avs2" restricted to
  cedar_ve.{c,h} gave 0 hits. "AVS" hits in sunxi kernels are `sunxi_avs.c` (an A/V sync counter, not the codec).
  The VE is a register-poke device. All codec knowledge is in userspace.
* **Other libawavs2.so copies** (all **stripped**: `file` says "stripped", readelf shows no `.debug_*`/`.symtab`). All export
  ~61-70 defined dynamic functions with meaningful names (e.g. `Avs2SetTopReg`, `Avs2SetFrameSecReg`, `Avs2Set10BitReg`,
  `Avs2SetHeaderReg`, `Avs2SetBitstreamReg`, `Avs2SetDramReg`, `Avs2SetFunctionReg`, `AVS2ConfigureRegister`,
  `Avs2UpdateRefFrameToEntryPointBuf`, `Avs2UpdateAlfPraramToEntryPointBuf`, `Avs2UpdateWqmToEntryPointBuf`,
  `Avs2UpdateAlfWqmParam`, `Avs2ReconstructCoefInfo`, `Avs2InitFrameQuantParam`, `Avs2UpdateFrameWqMatrix`, `Avs2ComputeOffset`,
  `Avs2ParseSequenceInf`, `Avs2ParseIntraPicHeader`, `Avs2ParseInterPicHeader`, `Avs2AlfReadParam`, `Avs2SearchSliceStartCode`,
  `Avs2RemoveUnrefedFrame`, `Avs2AddReferedFrame` ...). The names suggest an "entry point buffer" in DRAM holding ref/ALF/WQM
  data (an RK-SHPH-like design; **inference**). No unstripped (DWARF) copy other than the ones you already have was found.

  | dir (kernel-check/dl-avs2/) | source URL @ commit | md5 | `file` |
  |---|---|---|---|
  | so-lindenis-v853-arm-none-linux-gnueabi | lindenis-org/lindenis-v853-external @ bf42476c… `libcedarc/library/arm-none-linux-gnueabi/` | fff4b4b3150cf349f37fd28d990c8603 | ELF32 ARM EABI5 so, stripped; .comment: Sourcery G++ Lite 2010.09-50 GCC 4.5.1 |
  | so-lindenis-v853-arm-linux-gnueabihf | same, `arm-linux-gnueabihf/` | 221c6db755d653661069a29f83756f67 | ELF32 ARM EABI5, BuildID ac2cd05c…, stripped; Linaro GCC 4.8.3 |
  | so-lindenis-v853-roku | same, `roku_toolchain/arm-roku-linux-gnueabi/` | 4a8587cfc3655ddda690bbdd1fdc96eb | ELF32 ARM, stripped; Roku GCC 8.2.0 |
  | so-lindenis-v853-sunxi-aarch64-glibc | same, `toolchain-sunxi-aarch64-glibc/` | 680fab68fa29eb38694dae1aea5dbdbe | ELF64 aarch64, stripped |
  | so-opi-tina-aarch64-glibc-gcc830 | OPI-LINUX/tina-package @ f23ad47d… `allwinner/tina_multimedia/libcedarc/library/toolchain-sunxi-aarch64-glibc-gcc-830/` | 96a577f94fc29c263950d95e654d6c87 | ELF64 aarch64, stripped |
  | so-opi-tina-riscv-glibc | same, `toolchain-sunxi-riscv-glibc/` | fe62d14ee0833d41b9483b797bed8169 | ELF64 RISC-V RVC, stripped (C-SKY RISCV tools) |
  | so-yajatapps-androideabi_32 | YAJATapps/android_frameworks_av @ 4069a322… `media/libcedarc/library/androideabi_32/` | 431acb4effdb4bba1dbe8030fa9ef82b | ELF32 ARM, Android 31, stripped |
  | so-calvinxu17-aore80_32 | CalvinXu17/libcedarc @ e68d4a72… `library/aore80_32/` | 37cd6488a7e790a5807b29365190f432 | ELF32 ARM, Android 29, stripped |

  Repos that list libawavs2 but where I did not fetch it: CrealityTech/sonic_pad_os, YuzukiHD/TinyVision (trees truncated),
  HandsomeMod/handsomefeed, lindenis-v536-package, sterling-teng/d1s-melis (no avs2 file in tree), and Android vendor dumps
  (lineageos-on-allwinner/*). They were not checked for unstripped builds.
  Useful data point: **all 8 builds contain the default WQ tables with 8x8[3][7] = 28** (see syntax.md section 7).
* CedarX "libcedarx" configs (`cedarx.conf`) list awavs2 as a plugin. That is not source.

## 5. HiSilicon, MStar/SigmaStar, Realtek, MediaTek, NVIDIA etc.

I found no open AVS2 decoder code or register docs from these vendors. (NVIDIA/GMAT and other "avs2.c" hits are FFmpeg copies.)
The Moore Threads VA-API proposal (below) is the only other hardware-vendor open interface.

## 6. FFmpeg and VA-API

* FFmpeg master `f675c507e20ac78cd55f238ede52da470e6f6ec7`: files `libavcodec/avs2.[ch]` (frame-rate table + start code enums),
  `avs2_parser.c`, `libdavs2.c`, `libxavs2.c`, `libavformat/avs2dec.c` (raw ES probe). **No native AVS2 decoder, no hwaccel, no FATE
  AVS2 tests** (fate-suite has no avs2/ dir; HTTP 404). MPEG-TS stream_type 0xd2 = AVS2 was accepted 2021
  (patchwork 31052). The parser derives pict_type from `buf[8] & 3`, which is a **bug** (see syntax.md section 4).
* Moore Threads (jianfeng.zheng@mthreads.com), "[PATCH v1 2/2] vaapi: add vaapi_avs2 support", 2024-01-19, 19 files
  +2450 lines: adds `avs2dec.c`, `avs2dec_headers.c` (full header parse + DPB, **HW-only, no SW path**) and `vaapi_avs2.c`.
  Review: Zhao Zhili asked for a split, and it was noted that libva must accept the interface first. Status "New", **not merged**.
  https://ffmpeg.org/pipermail/ffmpeg-devel/2024-January/319807.html , https://patchwork.ffmpeg.org/comment/82244
  Local mbox: `kernel-check/dl-avs2/ffmpeg-mthreads-avs2-patch/vaapi_avs2.mbox`.
* libva PR #738 "add va_dec_avs & va_dec_avs2" (gitgjogh / Moore Threads), opened 2023-07-25, **open**. `va_dec_avs2.h`
  (MIT) defines `VAPictureAVS2 {surface, doi, poi, num_ref, ref_doi[7], ref_poi[7]}`, which carries **per-picture ref lists**
  so that the driver can do col-MV. It also defines `VAPictureParameterBufferAVS2` (CurrPic, ref_list[7], seq/pic flags, alpha/beta,
  chroma deltas, `wq_mat[16+64]`, `alf_coeff[18][9]`, pic_alf_on_Y/U/V, scene flags, pic_type) and `VASliceParameterBufferAVS2`
  (slice data incl. start code + header; lcu_start_x/y, slice qp, slice SAO flags, vlc_byte_offset).
  Local copy: `kernel-check/dl-avs2/libva-pr738/va_dec_avs2.h`. https://github.com/intel/libva/pull/738
* No v4l2-request (stateless) AVS2 hwaccel attempt was found in FFmpeg forks (Kwiboo/jernejsk v4l2-request branches are
  H.264/HEVC/MPEG2/VP8/VP9/AV1; not exhaustively checked).

## 7. Software decoders (for reference md5s; do not build yet)

* **davs2**: https://github.com/pkuvcl/davs2 (mirror https://gitee.com/pkuvcl/davs2). Latest commit
  `b41cf117452e2d73d827f02d3e30aa20f1c721ac` (2022-09-03, "Add checking for `frame_rate_code`"). Licence **GPL-2.0**
  (or-later per headers; commercial dual licence offered). Build: handwritten autoconf-style `build/linux/configure` + `Makefile`
  (x264-style; nasm optional), VS2013 solution for Windows. **10-bit needs `./configure --bit-depth=10`**
  (sets HIGH_BIT_DEPTH; the default is 8, and 8-bit builds reject 10-bit streams: "Un-supported bit-depth 10",
  https://forum.selur.net/archive/index.php/thread-4243-5.html). Known gaps from reading the source: field coding is rejected,
  the background-reference MC path is commented out, picture-level WQ parsing is dead code (syntax.md section 5), and
  `bs_dispose_pseudo_code` has no caller.
* **xavs2** (encoder, could generate WQ/10-bit test streams): https://github.com/pkuvcl/xavs2 latest
  `eae1e8b9d12468059bdd7dee893508e470fa83d8` (2019-04-22), GPL-2.0.
* RK MPP's parser + DPB is the most complete open implementation of background/scene handling, but it needs RK HW for pixels.
