# H616 VE AVS / AVS+ (AVS1-P2 JiZhun, AVS1-P16 Guangdian) decoder: register map and programming sequence

Clean-room description written 2026-11-03 from the vendor `libawavs.so`. Only register offsets, bit positions, buffer
sizes and the write order are recorded. No vendor code was copied. **Nothing here has run on hardware.** Items that
cannot be settled statically are marked **[board]** and collected in §12.

## 0. Sources

| build | path (under `harness/research/ve-encoder/dl/`) | notes |
|---|---|---|
| **A** (primary) | `libcedarc-aodzip/library/toolchain-sunxi-aarch64-glibc/libawavs.so` (189216 B) | GCC 6.4.1 `-g -O2`, full DWARF, normal `R_AARCH64_GLOB_DAT` relocations, so the GOT slots resolve to the named register shadow globals |
| **B** (cross-check) | `libcedarc-CalvinXu17-a133/library/androidq_64/libawavs.so` (183640 B) | clang 9, DWARF, Android packed relocations (GOT not resolvable without an APS2 decoder). Same struct layouts, same constants where compared (CTRL = 0x10000007, ISR, error case) |
| C (not used) | `orangepi-build/x/sun60iw2_.../libawavs.so` | DWARF, but pahole gives no output (DWARF 5); left for a later diff |
| D (not used) | every other `libawavs.so` in the tree | stripped, 25-42 KiB |

Generated dumps (`kernel-check/dl-vdec/re/`):
- `libawavs.aodzip.dis` (objdump -d -l of A), `libawavs.aodzip.annot.dis` (same, GOT loads annotated with the symbol,
  made by `/tmp/avs1-scripts/annot.py`), `libawavs.aodzip.pahole.txt`;
- `libawavs.a133.dis`, `libawavs.a133.pahole.txt` (B); `libawavs.sun60iw2.dis` (C).

Line references below are **A-annot line / vendor source line** (the DWARF line table names `avs_hal.c`, `avs_dec.c`,
`avs.c` under `cedarc/vdecoder/videoengine/avs/`). Function start lines:

| function | A-annot | B (`.cfi` body) | avs_hal.c lines |
|---|---|---|---|
| AvsDecoderDecode | 773 | 680 | (avs.c 368-737) |
| AvsInitDecode | 2191 | 2369 | |
| AvsRequestFrameMemory | 3096 | 3150 | (avs_dec.c 408-650) |
| AvsConfigureTriggerRegister | 6886 | 7022 | 64-105 |
| AvsConfigureDecodeExtraDataBuffer | 7004 | 7123 | 113-161 |
| AvsHwGetBits / UeVal / SeVal | 7127 / 7182 / 7239 | 7233 / 7277 / 7325 | 167-273 |
| **AvsConfigureFrameInfoRegister** | 7296 | 7372 | 278-~775 |
| **AvsConfigureDecodePicRegister** | 8388 | 8385 | 779-915 |
| AVS_Get_Cur_MB_num / AvsCheckRDmaFree / AvsCheckVeIdle | 8736 / 8747 / 8765 | 8683 / 8698 / 8715 | 917-950 |
| AvsCheckErrorCase | 8783 | 8732 | 955-983 |
| **AvsConfigureConstRegister** | 8897 | 8826 | 989-1023 |
| AvsGetStartcodeBitOffet | 8998 | 8935 | 1029-1034 (never called) |
| AvsVeIsr | 9016 | 8950 | 1051-1078 |

The library keeps one 32-bit **shadow global per register**, named after its offset (`avsFuncCtrl_reg20`,
`avsPps_reg04`, ... `avsBackCAddr_regD8`, `avsStcdHwOffset_F0`), builds the value in the shadow with bitfield stores
and then copies it to `uAvsRegisterBaseAddr + offset`. The names agree with the store offsets in every function
checked, which makes the offset map below direct, not inferred. The bitfield layouts come from the DWARF struct types
`REG_*` (pahole, lines 824-1110 of `libawavs.a133.pahole.txt`).

## 1. Engine selection

- **Codec id.** DWARF enum: `VIDEO_CODEC_FORMAT_AVS` = 0x117 (279), `_H264` = 0x115, `_AVS2` = 0x118.
- **VE_MODE (VE+0x00).** libVE `enableDecoder` (`libVE.a133.dis` from 2450, jump table at libVE file offset 0x3822,
  24 entries for codec ids 0x101..0x118, decoded with a helper script): 0x112, 0x115 (H.264) and **0x117 (AVS) all go
  to the target at 0x8ca8, which writes mode 1** (`VE_MODE_DEC_H264`). 0x113/0x116/0x118 → 4, 0x114 (RV) → 3,
  0x110 (WMV3) → 2, 0x101 (MJPEG) → 0x20 bit, the rest → 0. The AFBC block that follows only fires for codec ids
  0x113..0x118 with the mask 0x2d (0x113, 0x115, 0x116, 0x118), so **AVS never gets AFBC**, and no RAMPD/bit-30 extra.
  So VE_MODE for AVS = the plain cedrus H.264 value (DDR mode, REC_WR mode, `VE_MODE_DEC_H264`, width class bits).
- **Engine slot.** `AvsInitDecode` (A-annot 2191, avs_dec.c ~400) calls `veOps->getGroupRegAddr(self, 2)`
  and stores the result in `uAvsRegisterBaseAddr`. libVE `VeGetGroupRegAddr` reads a 7-entry table at libVE 0x4810
  (32-byte entries, offset at +24): group 0 "VE Top Level" 0x000, 1 "DEC/Mpeg1/2/4" 0x100, **2 "DEC/H264" 0x200**,
  3 "DEC/VC-1" 0x300, 4 "DEC/RV" 0x400, 5 "DEC/H265" 0x500, 6 "DEC/JPEG" 0xE00.
  **AVS runs in the H.264 register bank, VE+0x200**, like VP8 in cedrus.
- **AVS select bit.** CTRL (+0x20) bit 28 `isAvs` (cedrus already has bit 29 = `VE_H264_CTRL_VP8`). Written as part of
  0x10000007 by ConstRegister and kept set by every later read-modify-write of the CTRL shadow.
- The register layout differs from H.264 in 0x00-0x18 and 0x50-0xD8 (AVS-specific meaning), and is identical to H.264
  for the control/trigger/status/VLD block 0x20-0x3C, 0x60, 0xB8, 0xDC (cedrus `VE_H264_*` defines).
- No SRAM writes (no use of the H.264 SRAM port 0xE0/0xE4), no table buffer in DRAM: the weighting-quant matrices are
  derived by the engine from the coded parameters (§6).

## 2. Register map (offsets from VE+0x200)

| off | vendor name / DWARF type | bits (from DWARF) |
|---|---|---|
| 0x04 | `avsPps_reg04` / REG_PIC_SET_PARAM | [7:0] profile_id, [15:8] level_id, [17:16] chroma_format, [20:18] sample_precision, 21 res, **22 no_forward_reference_flag, 23 pb_field_enhanced_flag, 24 aec_enable** (DWARF: `ace_enable`), **25 weighting_quant_flag, 26 chroma_quant_param_disable**, [31:27] res |
| 0x0C | `avsWeightQuant1_reg0c` / REG_WEIGHT_QUANT1 | [7:0] wq delta[1], [15:8] wq delta[0], [17:16] weighting_quant_model, [19:18] weighting_quant_param_index, [25:20] chroma_quant_param_delta_cr (6-bit), [31:26] chroma_quant_param_delta_cb (6-bit) |
| 0x10 | `avsWeightQuant2_reg10` / REG_WEIGHT_QUANT2 | [7:0] delta[5], [15:8] delta[4], [23:16] delta[3], [31:24] delta[2] |
| 0x14 | `avspicParamSyntax_reg14` / REG_PIC_PARAM | [4:0] alpha_c_offset, 5 fwd_pic_structure, 6 fwd_top_field_first, 7 fwd_is_I_pic, [12:8] beta_offset, 13 bwd_prev_fwd_pic_structure, 14 bwd_prev_fwd_top_field_first, 15 bwd_prev_fwd_is_I_pic, [21:16] picture_qp, 22 loop_filter_disable, 23 fixed_picture_qp, 24 skip_mode_flag, 25 advanced_pred_mode_disable, 26 picture_reference_flag, 27 top_field_first, 28 progressive_frame, 29 picture_structure, [31:30] picture_coding_type (I 0, P 1, B 2) |
| 0x18 | `avspicDist_reg18` / REG_PIC_DIST | [7:0] cur_pic_distance, [15:8] forward_pic_distance, [23:16] backward_pic_distance, [31:24] prev_forward_pic_distance |
| 0x20 | `avsFuncCtrl_reg20` / REG_FUNC_CTRL | 0 slice-finish IRQ en, 1 error IRQ en, 2 VLD-data-request IRQ en, 3 overtime IRQ, 8 not_write_recons_pic, 9 write_scale_rotated_pic, 10 mcri_cache_enable, 13 histogram_output_enable, 24 eptb_detection_by_pass, 25 startcode_detect_enable, **26 avs_demulate_enable**, **28 isAvs** |
| 0x24 | `avsTrigType_reg24` / REG_TRIGGER_TYPE | [3:0] trigger type, [5:4] stcd_type, [13:8] n_bits |
| 0x28 | `avsFuncStatus_reg28` / REG_FUNC_STATUS | 0 slice/picture finished, 1 error, 2 VLD data request, 3 overtime (W1C, §8); 8 vld_busy, 9 is_busy, 10 mvp_busy, 11 iq_it_busy, 12 mcri_busy, 13 intra_pred_busy, 14 irec_busy, 15 dblk_busy, 16 mode_data_flag, 20 bs_dma_busy, 21 wb_busy, 22 avs_busy, 23 avs_idct_busy, 25 sdct_busy, [28:26] start_code_type, 29 start_code_detected |
| 0x2C | `avsCrtmbnum_reg2c` / REG_CRT_MB_NUM | [15:0] current MB number (read; written 0 before a picture) |
| 0x30 | `avsVldBitAddr_reg30` / REG_VLD_BIT_STAAR | [27:0] = (addr & 0x0ffffff0) \| (addr >> 28), 28 valid, 29 last, 30 first (same as `VE_H264_VLD_ADDR_VAL`) |
| 0x34 | `avsVldOffset_reg34` | [28:0] start bit offset from the buffer base |
| 0x38 | `avsVldBitLen_reg38` | [27:0] length in bits |
| 0x3C | `avsVldEndAddr_reg3c` | end address of the bitstream buffer, full physical address (not >> 8) |
| 0x40 | `avsRoteScal_reg40` / REG_ROTE_SCALE | [2:0] rotate angle, [11:8] scale (h ratio \| v ratio << 2), 12 field_scale_mode, 13 bottom_field_sel |
| 0x44 / 0x48 | `avsRotScaleYAddr_reg44` / `avsRotScaleCAddr_reg48` | rotate/scale output Y / C address |
| 0x50 | `avsMvCtrolAddr_reg50` / REG_MV_COL_ADDR | co-located MV buffer address (§7) |
| 0x54 | `avsMbInfoAddr_reg54` / REG_MBINFO_ADDR | MB neighbour-info buffer address (§7) |
| 0x58 | `avsPicMbSize_reg58` / REG_PIC_MB_SIZE | [7:0] pic_height_in_mbs, [15:8] pic_width_in_mbs |
| 0x5C | `avsPicSize_reg5c` / REG_PIC_SIZE | [11:0] boundary height, [27:16] boundary width (both rounded up to 16) |
| 0x60 | `avsMbAddr_reg60` / REG_MB_ADDR | [6:0] mb_y, [14:8] mb_x (start MB; written 0) |
| 0xAC / 0xD0 | `avsReconYAddr_regAc` / `avsReconCAddr_regD0` | reconstruction luma / chroma |
| 0xB0 / 0xD4 | `avsForeRefYAddr_regB0` / `avsForeCAddr_regD4` | forward reference luma / chroma |
| 0xB4 / 0xD8 | `avsBackYAddr_regB4` / `avsBackCAddr_regD8` | "backward" reference luma / chroma: the future reference for B, **the second (older) forward reference for P** (§4.5) |
| 0xB8 | `avsErrorCase_regB8` / REG_ERROR_CASE | 0 no_more_data, 1 mb_header, 2 ref_idx, 3 block error (written 0 before a picture) |
| 0xDC | `avsBitsReturnData_regDC` | result of the get-bits/ue/se triggers |
| 0xF0 | `avsStcdHwOffset_F0` / REG_STCD_OFFSET | [28:0] hardware start-code offset (read only; the reader function exists but is never called) |

No register at 0x00, 0x08, 0x1C, 0x4C, 0x64-0xA8, 0xBC-0xCC, 0xE0-0xEC is touched by the AVS code. Addresses are
written **as full physical addresses** (no >> 8), like the cedrus H.264/VP8 engine.

**Trigger types** used (cedrus H.264 names in brackets): 2 get n bits, 4 get se(v), 5 get ue(v) (the vendor parses
headers through the engine's bit reader; not needed with userspace parsing), 7 [INIT_SWDEC], **9 = AVS picture
decode** (no cedrus name; H.264 slice decode is 8), 0x0C (written by ConstRegister's sibling TriggerRegister when its
argument is 12; no caller passes 12 in A). `stcd_type` = 1 in every trigger the decoder writes.

## 3. Per-picture write sequence (vendor order)

The vendor decode loop (AvsDecoderDecode, avs.c 389-565) runs, for each picture: software start-code search →
`AvsParsePictureHeader` (read pointer advanced 4 bytes past `00 00 01 B3/B6`, header read through the engine's bit
reader) → `AvsGetEmptyFrameBuf` (only when `bIsFstField`) → **ConstRegister → FrameInfoRegister → DecodePicRegister**
(trigger) → `veOps->waitInterrupt` → `AvsVeIsr` → `AvsCheckErrorCase` / `AvsProcessPictureFinish`.

Total for one picture without rotate/scale: **31 register writes** (CTRL three times; PIC_DIST, VLD_ADDR, VLD_END,
MB_ADDR and TRIGGER twice each), plus 0-3 top-level writes. They touch **24 distinct registers**; a driver that drops
the transient and duplicate writes needs 26 writes per picture.

| # | function (A-annot line, source line) | reg | value |
|---|---|---|---|
| 1 | ConstRegister (8897, hal 997-1005) | 0x20 | 0x10000007: isAvs \| IRQ enables 0..2 |
| 2 | ConstRegister (hal 1010-1017) | 0x30 | VLD_ADDR_VAL(base of the bitstream buffer) \| valid (bit 28) |
| 3 | ConstRegister (hal 1020-1022) | 0x3C | physical end of the bitstream buffer |
| 4 | FrameInfoRegister (7296+, A 0x6d74) | 0x58 | (h+15)/16 \| ((w+15)/16) << 8 |
| 5 | (A 0x6dc0) | 0x5C | ((h+15) & 0xff0) \| ((w+15) & 0xff0) << 16 |
| 6 | (A 0x6de8-0x6e28) | 0x18 | transient value (overwritten in step 10) |
| 7 | (A 0x6e2c-0x6e94) | 0x04 | §4.1 |
| 8 | (A 0x6e98-0x6ef0) | 0x0C | §6 |
| 9 | (A 0x6ef4-0x6f10, 0x74c8, 0x7600) | 0x10 | §6 |
| 10 | (A 0x6f14-0x6f68, 0x7504, 0x7180) | 0x18 | §4.3, after the reference-history rotation for I/P |
| 11 | (A 0x6f6c-0x7068) | 0x14 | §4.2 |
| 12 | (A 0x706c-0x7098) | 0x20 | \|= bit 10 (mcri cache); with rotate/scale also bit 9, and bit 8 for B (§9) |
| 13 | (only with rotate/scale, A 0x73a8) | 0x40, 0x44, 0x48 | §9 |
| 14 | (A 0x70b4-0x70d8) | 0x50 | physical address of the (single) col-MV buffer |
| 15 | (A 0x70dc-0x70e8) | 0x54 | physical address of the 48 KiB MB-info buffer |
| 16 | (A 0x70ec-0x70f0) | 0x60 | 0 |
| 17 | (A 0x7140-0x71e8) | 0xAC, 0xD0 | current frame Y, C |
| 18 | (A 0x71ec-0x722c) | 0xB0, 0xD4 | forward reference Y, C (current frame when none) |
| 19 | (A 0x7230-0x7284) | 0xB4, 0xD8 | P: second forward reference; B: backward reference; I: current frame (§4.5) |
| 20 | (A 0x72a0-0x7314, top group 0) | top 0xEC [6:4], 0xC4, 0xC8 | only for YV12 (3) / NV21 (5) reference output: format, chroma length, Y \| C stride << 16; tiled default writes nothing (cedrus `cedrus_dst_format_set()` covers this) |
| 21 | DecodePicRegister (8388+, hal 829-830) | 0x20 | \|= bit 26 (`avs_demulate_enable`) |
| 22 | (hal 833-835) | 0x34 | (read pointer − buffer base) × 8 |
| 23 | (hal 838-840) | 0x38 | bytes of the current picture × 8 (`n_Cur_frame_SbmDataSize`) |
| 24 | (hal 843-864) | 0x30 | VLD_ADDR_VAL(base) \| 0x70000000 (valid, last, first) |
| 25 | (hal 868-882) | 0x3C | buffer end (again) |
| 26 | (hal 888-899) | 0x60, 0xB8, 0x2C | 0, 0, 0 |
| 27 | (hal 903-906) | 0x24 | 0x17 (INIT_SWDEC, stcd_type 1) |
| 28 | (hal 910-913) | 0x24 | **0x19 = trigger: AVS picture decode, stcd_type 1** |

Steps 26-28 run only when `bFstSetVbvFlag` (decoder+60) is 1, which the decode loop sets before calling (avs.c 449).
The buffer base/end/length variants in DecodePicRegister for the vendor's two bounce buffers (`temp_sbmInfo` for a
picture that wraps the ring buffer, `add_0x80_sbmInfo` for a copy with 0x80 bytes of padding) are ring-buffer
artefacts; a V4L2 OUTPUT buffer is linear, so the plain case applies.

## 4. Picture parameters

### 4.1 0x04 (sequence + AVS+ picture flags), A 0x6e2c-0x6e94

profile_id ← seq.profileId, level_id ← seq.levelId, chroma_format ← seq.chromaFormat, sample_precision ←
seq.samplePrecision (both as coded: 1 = 4:2:0, 1 = 8-bit), bit 22 ← no_forward_reference_flag, 23 ←
pb_field_enhanced_flag, 24 ← aec_enable, 25 ← weighting_quant_flag, 26 ← chroma_quant_param_disable. The AVS+ fields
are 0 for JiZhun (profile 0x20) streams because the parser leaves them 0.

### 4.2 0x14, A 0x6f6c-0x7068

Always: [31:30] = vendor type − 1 (I 0, P 1, B 2), 29 picture_structure, 28 progressive_frame, 27 top_field_first,
26 picture_reference_flag, 25 advanced_pred_mode_disable, 24 skip_mode_flag, 23 fixed_picture_qp,
22 = 1 − loop_filter (i.e. loop_filter_disable), [21:16] picture_qp, [12:8] beta_offset, [4:0] alpha_c_offset (5-bit
two's complement of the se(v) values; 0 when loop_filter_parameter_flag is 0).

Reference descriptor bits (values from the reference-history table, §4.4):

| picture | bits 5/6/7 ("fwd") | bits 13/14/15 ("bwd_prev_fwd") |
|---|---|---|
| I | 0 (the vendor masks the byte to alpha/beta only, A 0x75d0) | 0 |
| P | forward ref: structure / top_field_first / is_I | **second forward ref** (older): structure / tff / is_I (A 0x701c) |
| B | forward ref | **backward ref** (A 0x7498) |

"structure" is that reference's coded picture_structure (1 = frame), "is_I" whether it was an I picture.

### 4.3 0x18, picture distances (A 0x6f14-0x6f68, 0x7180, 0x7504)

| picture | [7:0] | [15:8] forward | [23:16] backward | [31:24] prev_forward |
|---|---|---|---|---|
| I, P | own picture_distance | distance of the nearest reference (forward) | 0 | distance of the second (older) reference |
| B | own picture_distance | distance of the forward (past) ref | distance of the backward (future) ref | distance of the reference before the forward ref = the backward ref's own second reference |

Values are the coded 8-bit picture_distance of each picture, not differences: the engine derives the (mod-256 / field)
distances itself. **[board]** whether field distances (2·pd, 2·pd+1) are derived by the engine as the spec's
DistanceIndex is (FFmpeg `cur.poc = 2·picture_distance`).

### 4.4 Reference history kept by the vendor (AVS_FBM_INFO, decoder+8800)

For each of three slots — `preFwd`, `fore`, `back` — the vendor stores picture_distance, picture_structure,
top_field_first and is_I. For an **I or P** picture (A 0x7504, before 0x18/0x14 are built) it shifts the history:
preFwd ← fore, fore ← back, back ← current. Frame pointers rotate the same way (A 0x710c-0x713c): pLastRefFrm ←
pForRefFrm, pForRefFrm ← pBacRefFrm, pBacRefFrm ← pCurFrm. B pictures do not shift. So, after the shift:
- for P: forward = the previous I/P picture, second forward = the one before it (AVS P pictures have two references);
- for B: forward = the older of the two latest I/P pictures, backward = the latest; prev_forward = the one before forward.
For a stateless driver this history becomes userspace's job: userspace passes three resolved reference descriptors
(uapi-proposal.md).

### 4.5 Reference addresses (A 0x7140-0x7284)

- 0xAC/0xD0 ← current frame Y/C.
- 0xB0/0xD4 ← pForRefFrm (forward), or the current frame if there is none.
- 0xB4/0xD8 ← **pLastRefFrm for P** (the second forward reference; the vendor tests type == P at A 0x7238), pBacRefFrm
  for I/B (for I that is the current frame after the shift); current frame if missing.
- Both fields of a reference are addressed through the one frame address (frame buffers hold interleaved fields).
- Only two reference frames exist: AVS1 has at most 2 reference frames = 4 reference fields per direction (FFmpeg
  commit 500683e42bcc).

## 5. Bitstream registers

- 0x30 base (+valid/first/last), 0x34 start bit offset, 0x38 bit length, 0x3C end address, exactly the cedrus H.264
  VLD block. The vendor programs a whole picture per trigger (no per-slice triggers): the engine parses the slice
  headers (slice_vertical_position[_extension], slice_qp, slice weighting) itself.
- **Start position.** The vendor's read pointer, from which 0x34 is computed, is 4 bytes past the picture start code
  (`AvsParsePictureHeader`, A 0x62c8: `AvsSbmUpdateReadPointer(dec, 4)` before `AvsParseIPictureInfo`; no further
  advance in the header parsers). So the engine is started **inside the picture header** and must find the first slice
  start code itself (stcd_type 1 in the trigger). **[board]** whether starting exactly at the first slice start code
  (the natural V4L2 `data_offset`) also works; it should, if the engine scans for `00 00 01`.
- 0x38 = the whole picture's bytes × 8 from that point (`n_Cur_frame_SbmDataSize`). The header-parse helper
  (TriggerRegister, hal 70-86) instead rounds the length down to a 4-byte aligned end; the picture path does not.
- **Pseudo start codes (annex A).** The vendor sets CTRL bit 26 `avs_demulate_enable` for the picture decode and clears
  it for its own header reads (TriggerRegister, hal 75). So **the engine removes the `00 00 02` two-bit stuffing in
  slice data itself**; the OUTPUT buffer carries the raw stream. Userspace must remove them only from its own copy of
  the headers (FFmpeg d85b4d25627d makes this normative for JiZhun too). The AVS+ test card has 15 of them (FFmpeg
  f80a436ffd92): a direct test. **[board]**
- Bit 25 `startcode_detect_enable` and bit 24 `eptb_detection_by_pass` stay 0.

## 6. Weighting quantisation (AVS+), A 0x6e98-0x6f10, 0x7578, 0x75e8, 0x74c8, 0x7600

The engine gets the **coded parameters**, not matrices:
- 0x0C [31:26] chroma_quant_param_delta_cb, [25:20] delta_cr (6-bit two's complement), [19:18]
  weighting_quant_param_index, [17:16] weighting_quant_model;
- index 1: 0x0C [15:8] = delta1[0], [7:0] = delta1[1]; 0x10 = delta1[2] << 24 | delta1[3] << 16 | delta1[4] << 8 | delta1[5];
- index 2: same with delta2[];
- index 0 (default parameters) or 3: deltas 0.
- 0x04 bit 25 weighting_quant_flag, bit 26 chroma_quant_param_disable.
So the default/base parameter sets (MPP `avsd_parse.c` lists {128,98,106,116,116,128} and {135,143,143,160,160,213})
and the 8x8 matrix derivation per weighting_quant_model are **inside the engine**. The driver only copies syntax
elements. **[board]**: no public WQ stream (FFmpeg refuses WQ; MPP parses it) — WQ stays untested until an AVS+ WQ
stream is found.

## 7. Work buffers (AvsRequestFrameMemory, A 0x4278-0x42f0)

| buffer | size | register |
|---|---|---|
| MB neighbour info (`mbInfoBuf`) | **0xC000 = 48 KiB**, fixed, one per decoder | 0x54 |
| col MV (`mvInfoBuf`) | **(((w+63)>>4) & ~3) × (((h+63)>>4) & ~3) × 32 bytes** (MB counts rounded up to a multiple of 4, 32 B per MB): 1920x1088 → 120 × 68 × 32 = 261120 B; one per decoder | 0x50 |

- The vendor also computes a 16 KiB-aligned physical address of the MB-info buffer (`mbInfo16KAlignBufPhy`) but only
  logs it; 0x54 gets the unaligned address. **[board]** alignment needs (allocate 16 KiB aligned anyway).
- **One col-MV buffer for all pictures.** Only an I/P picture can be the backward (co-located) reference of a B, and B
  pictures are never references, so the buffer written by the last I/P is what the following Bs read. That implies the
  engine **writes** 0x50 for I/P and **reads** it for B. **[board]**: does a B picture also write it (it would destroy
  the col data for the next B)? The vendor's single buffer says no. A stateless driver should keep one col buffer per
  capture buffer: I/P → 0x50 = own buffer, B → 0x50 = the backward reference's buffer, which is correct either way
  and survives seeks.
- Frame buffers: the vendor asks the FBM for the reference format (tiled 32x32 by default, YV12/NV21 on newer IPs)
  with nothing extra appended (no per-frame MV area). With cedrus the primary output goes through
  `cedrus_dst_format_set()`.

## 8. IRQ, status, error

- Enable: CTRL bits 0..2 (set to 7 by ConstRegister; vendor `REG_FUNC_CTRL` also names bit 3 overtime).
- `AvsVeIsr` (hal 1051-1078): read 0x28; build a clear mask of bits 0..2 that are set and write it back (W1C);
  return bit 0 → finished, bit 1 → error, bit 2 → VLD data request. Same as cedrus `VE_H264_STATUS_*`.
- `AvsCheckErrorCase` (hal 955-983): read 0xB8; bits 1, 2, 3, 0 = mb_header, ref_idx, block, no_more_data errors
  (logged only).
- `AvsCheckVeIdle` = 0x28 bit 8 (vld_busy), `AvsCheckRDmaFree` = 0x28 bit 22 (avs_busy), `AVS_Get_Cur_MB_num` = 0x2C.
- The vendor checks `nFrame_MbNum` against 0x2C after a VLD data request to tell a complete picture from a truncated
  one (avs.c 655-660). cedrus can treat bit 2 as an error (the whole picture is in the buffer).

## 9. Rotation / scale-down (vendor only, optional)

With rotate or scale: CTRL bit 9 (write the scaled picture), plus bit 8 (do not write the reconstruction) for B pictures;
0x40 = angle [2:0] | (h_ratio | v_ratio << 2) << 8; 0x44/0x48 = scaled frame Y/C; top 0xE8 [31:30] cleared then set by
format, 0xEC [2:0]/[6:4] formats, 0xCC strides (A 0x7330-0x73a4, 0x7628-0x76b0, 0x7738). Field scale mode
(0x40 bit 12, 13) is never set by the vendor. Not needed for a first driver.

## 10. AVS vs AVS+ (profile 0x20 JiZhun vs 0x48 Guangdian / AVS1-P16 Broadcasting)

| feature | hardware handling | evidence |
|---|---|---|
| AEC (arithmetic entropy coding, AVS1-P16 clause 8.4) | 0x04 bit 24; macroblock layer decoded by the engine | DWARF `ace_enable`, `aceEnable` in AVS_PIC_INFO |
| weighting quantisation | 0x04 bits 25-26, 0x0C, 0x10 (§6) | REG_WEIGHT_QUANT1/2 |
| no_forward_reference_flag, pb_field_enhanced_flag | 0x04 bits 22, 23 | REG_PIC_SET_PARAM |
| field coding (both profiles) | 0x14 bits 27-29 + per-reference structure/tff bits | REG_PIC_PARAM |
| slice weighted prediction (slice_weighting_flag, both profiles) | parsed by the engine from the slice header (no register) | no register exists |
| bbv_delay_extension, extra marker in AVS+ headers | parsed in software only | MPP avsd_parse.c 219/291, FFmpeg a479cb82921f |

## 11. How it slots into cedrus

- New `cedrus_avs.c` modelled on `cedrus_vp8.c` (same engine, same IRQ/VLD helpers `VE_H264_CTRL/STATUS/VLD_*`).
- `cedrus_engine_enable()`: add `V4L2_PIX_FMT_AVS_FRAME` to the `VE_MODE_DEC_H264` case.
- New capability `CEDRUS_CAPABILITY_AVS_DEC` = BIT(10) (BIT(9) is AVS2), enabled for the H616 variant in its own patch.
- VE reset on a codec switch, as already done for AVS2 (the H.264 bank is shared with H.264 and VP8).
- Size limit: MB_ADDR mb_x/mb_y are 7 bits (≤ 2048), PIC_SIZE 12 bits; UM §4.4.1 says 1080p@60. Advertise
  16..1920 × 16..1088 (frame), **[board]** 2048x2048.

## 12. [board] questions

| # | question | test |
|---|---|---|
| B1 | Engine select = VE_MODE 1 + CTRL bit 28, no other enable | first I picture of bunny decodes, IRQ bit 0 |
| B2 | Trigger 0x17 then 0x19 needed, or 0x19 alone | try both |
| B3 | VLD start: just after the picture start code (vendor) vs at the first slice start code | both on bunny |
| B4 | CTRL bit 26 removes annex A pseudo start codes in slice data | AVS+ test card (15) and AVSFileFormat.es (12 candidates) |
| B5 | 0x18 takes raw picture_distance values, engine derives distances (frame and field) | bunny B pictures (3 B between P), test card field B |
| B6 | Col-MV buffer: written by I/P only, read by B; per-capture buffers work | bunny md5 vs FATE |
| B7 | 0xB4 = second forward ref for P (two-reference P) | any P with picture_reference_flag 0 |
| B8 | Field pictures: one trigger decodes both fields of the picture (engine finds the second field's first slice at MbRow ≥ MbHeight/2), or the vendor's `bIsFstField` path re-triggers per field | AVS+ test card: 5 pictures × 2 fields, 1 slice per field |
| B9 | AEC (0x04 bit 24) | AVS+ test card |
| B10 | WQ (0x04 bit 25, 0x0C/0x10) | no stream |
| B11 | MB-info buffer alignment (16 KiB?) and that 48 KiB suffices at 1920 | 1080i test card |
| B12 | NV12 / untiled output through the cedrus top registers works with the AVS mode | compare tiled vs NV12 md5 |
| B13 | pb_field_enhanced B (0x04 bit 23) | test card has two enhanced field B pictures |
| B14 | Old pre-final JiZhun streams without slice start codes (fate `cavs.mpg`) | expect failure; informative |
