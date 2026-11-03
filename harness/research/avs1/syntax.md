# AVS1 (GB/T 20090.2 JiZhun) and AVS+ (AVS1-P16 / GY/T 257.1 Guangdian) syntax: what software parses, what the engine parses

Written 2026-11-03. The standards texts are not freely available; this is our own summary, cross-checked between the
open decoders below. No code was copied from any of them.

| source | path / URL | revision | licence |
|---|---|---|---|
| FFmpeg cavs decoder (the main open software decoder; **AVS+ AEC, field coding and annex A de-emulation landed 2026-11-02**) | `libavcodec/cavsdec.c`, `cavs.c`, `cavs.h`, `cavs_aec.c`, `cavs_parser.c`; https://github.com/FFmpeg/FFmpeg | `375e3df8fe5b` (master, 2026-11-02 22:18 UTC; series `5734b4cd4060`..`375e3df8fe5b`, author "Rainbaby"). Older local copy: `kernel-check/ffmpeg-afbc/src/ffmpeg` (`a56a208b0722`, 8.1, 2026-10-09, before the series) | LGPL-2.1-or-later |
| Rockchip MPP AVS/AVS+ parser + Hantro HAL | `mpp/codec/dec/avs/avsd_parse.c`, `avsd_parse.h`, `mpp/common/avsd_syntax.h`, `mpp/hal/rkdec/avsd/hal_avsd_plus.c` (AVS+ registers), `hal_avsd_vdpu1/2.c`; local `kernel-check/dl-avs2/mpp/repo` | `7916c3cc000f` (2026-10-28) | Apache-2.0 (file headers) |
| Amlogic avs_multi (stateful, firmware parses headers) | `drivers/frame_provider/decoder/avs_multi/avs_multi.c` of https://github.com/CoreELEC/media_modules-aml | `c15aebb1ac93` | GPL-2.0-or-later |
| Allwinner `libawavs.so` (headers parsed in software through the VE bit reader) | regmap.md §0 | A133/aodzip builds | proprietary, interop facts only |

Read-only copies of the FFmpeg files at the series commit were fetched to `/tmp/avs1-ffsrc/` for reading (not built,
not kept in the tree).

## 1. Start codes (00 00 01 xx)

| xx | meaning |
|---|---|
| 0x00-0xAF | slice; xx = slice_vertical_position (MB row, low 8 bits) |
| 0xB0 / 0xB1 | video_sequence_start / video_sequence_end |
| 0xB2 | user_data |
| 0xB3 | i_picture_start |
| 0xB5 | extension (4-bit extension_id follows: sequence display, copyright, camera parameters, ...) |
| 0xB6 | pb_picture_start |
| 0xB7 | video_edit |
| 0xB8-0xFF | reserved / system |

**Pseudo start codes (annex A in AVS1-P16, annex C in GB/T 20090.2-2006).** In picture headers and slice data, a byte
that forms `00 00 02` with the two bytes before it carries two stuffing bits that a decoder must drop (bit-level, not
byte-level de-emulation; FFmpeg d85b4d25627d, MPP removes them in its bit reader). Normative for JiZhun too.
Software removes them from its header copy; the VE removes them in slice data when CTRL bit 26 is set (regmap §5).

## 2. Sequence header (B0) — software parses, driver needs most of it

| field | bits | to hardware |
|---|---|---|
| profile_id | 8 | 0x04 [7:0]. 0x20 = JiZhun, 0x48 = Guangdian / Broadcasting (AVS+). (MPP accepts only these two; FFmpeg names them `AV_PROFILE_CAVS_JIZHUN/BROADCASTING`, 5f21d2b9e787) |
| level_id | 8 | 0x04 [15:8]. MPP rejects > 0x42 (6.2) |
| progressive_sequence | 1 | — (a field picture in a progressive sequence is invalid, FFmpeg 7.2.3 check) |
| horizontal_size, vertical_size | 14 + 14 | 0x58, 0x5C (rounded up to MBs) |
| chroma_format | 2 | 0x04 [17:16]; 1 = 4:2:0 (only value the H616 path supports) |
| sample_precision | 3 | 0x04 [20:18]; 1 = 8-bit |
| aspect_ratio, frame_rate_code | 4 + 4 | — (display) |
| bit_rate_lower (18), marker, bit_rate_upper (12) | 31 | — |
| low_delay | 1 | — but changes the picture header (bbv_check_times) and output order (no B) |
| marker, bbv_buffer_size (18), reserved (3) | 22 | — |

Sequence display extension (B5, id 2): video_format 3, sample_range 1, colour_description 1 (+3 × 8),
display_horizontal_size 14, marker, display_vertical_size 14 → crop/colorimetry only.

## 3. I picture header (B3)

In order (FFmpeg `decode_pic`, MPP `get_i_picture_header`):
1. bbv_delay 16; **AVS+ only:** marker 1 + bbv_delay_extension 7.
2. time_code_flag 1, time_code 24 if set.
3. marker 1 — present in the final standard; very old JiZhun clips omit it (FFmpeg and MPP guess with the
   "stream_revision/version" heuristic on low_delay and the next bits; AVS+ always has it).
4. picture_distance 8 → 0x18 [7:0]. FFmpeg: DistanceIndex = 2 × picture_distance (fields add 1 for the second field).
5. bbv_check_times ue(v) if low_delay.
6. progressive_frame 1 → 0x14 bit 28; picture_structure 1 only if !progressive_frame (else inferred 1) → 0x14 bit 29.
7. top_field_first 1 → bit 27; repeat_first_field 1 (display only).
8. fixed_picture_qp 1 → bit 23; picture_qp 6 → [21:16].
9. skip_mode_flag 1 **only for a field-coded I picture** (its second field is coded with the P macroblock layer;
   FFmpeg 500683e42bcc) → bit 24.
10. reserved 4.
11. loop_filter_disable 1 → bit 22; if 0: loop_filter_parameter_flag 1, and if set alpha_c_offset se(v), beta_offset
    se(v) (range −8..8 per FFmpeg's check, which allows ±64) → [4:0], [12:8].
12. **AVS+ only** (tables 21/22): weighting_quant_flag 1; if set: chroma_quant_param_disable 1, then if 0
    chroma_quant_param_delta_cb se(v), _cr se(v); weighting_quant_param_index 2; weighting_quant_model 2; index 1 →
    weighting_quant_param_delta1[6] se(v); index 2 → delta2[6] se(v). Then aec_enable 1.
    → 0x04 bits 24-26, 0x0C, 0x10 (regmap §6). FFmpeg refuses WQ streams (AVERROR_PATCHWELCOME); MPP derives
    wqP[6] = base + delta and programs the derived values; the VE takes the raw syntax.

## 4. P/B picture header (B6)

1. bbv_delay 16; AVS+: marker + bbv_delay_extension 7.
2. picture_coding_type 2: 1 = P, 2 = B (0, 3 illegal) → 0x14 [31:30] (I 0, P 1, B 2).
3. picture_distance 8; bbv_check_times ue(v) if low_delay.
4. progressive_frame 1; if 0: picture_structure 1, and if picture_structure == 0: advanced_pred_mode_disable 1 (→ bit 25).
5. top_field_first, repeat_first_field, fixed_picture_qp, picture_qp 6.
6. picture_reference_flag 1, **except** for a frame-coded B picture (picture_structure 1), where it is not coded and is
   1 (FFmpeg) → bit 26. When set, reference indices are not coded in the MB layer (index 0).
7. no_forward_reference_flag 1, pb_field_enhanced_flag 1 (AVS+ only; reserved bits in JiZhun, MPP zeroes them for 0x20),
   reserved 2 → 0x04 bits 22, 23.
8. skip_mode_flag 1 → bit 24.
9. loop filter fields as for I; AVS+ WQ fields and aec_enable as for I.

## 5. Slice header — parsed by the engine, not by software

The vendor never parses slice headers (its `AVS_SLICE_INFO` struct is unused by the HAL); the engine is started once per
picture and walks the slices:
- start code 00 00 01 xx, xx = slice_vertical_position (≤ 0xAF);
- slice_vertical_position_extension 3, only when vertical_size > 2800 (FFmpeg 463cff5b9641; no level reaches it);
- fixed_slice_qp 1 + slice_qp 6 if !fixed_picture_qp;
- slice_weighting_flag 1 for non-I pictures and for the second field of a field-coded I picture; if set, per reference
  luma_scale 8, luma_shift 8, marker, chroma_scale 8, chroma_shift 8, marker, then mb_weighting_flag 1. FFmpeg and
  MPP-Hantro do not support it (FFmpeg: "Weighted prediction" sample request). The VE has no register for it, so it is
  parsed in the engine **[board]**;
- AEC slices (AVS+) end with a stuffing bit rather than at a start code (FFmpeg `check_for_slice`).

For a field-coded picture the two fields follow each other inside the one picture (one picture header): the second
field's first slice has MbRow ≥ MbHeight/2 (FFmpeg 500683e42bcc, clause 7.2.3; MPP's Hantro HAL triggers once per
field and offsets the output by one line; the Allwinner engine has only frame-sized MB/size registers, regmap B8).

## 6. References, distances, output order

- **References:** only I and P pictures are references (B never). P pictures use the two most recent references
  (two frames, or up to four fields); B pictures use the nearest past (forward) and future (backward) reference.
  With field pictures, references are counted in fields: up to four per direction, and the second field of a P (or of
  an I coded with the P layer) can reference the first field of the same frame (MPP HAL `refer0_base = output` for
  the second field; FFmpeg 500683e42bcc).
- **What the VE needs per reference:** its coded picture_distance, its picture_structure, its top_field_first, and
  whether it was an I picture (regmap §4.2-4.4). For B: also the picture_distance of the backward reference's own
  second reference (0x18 [31:24], for direct mode with field co-located blocks; FFmpeg 5734b4cd4060 shows direct mode
  divides by the co-located block's BlockDistanceRef).
- **Distances:** DistanceIndex = 2·picture_distance (+1 for the second field), arithmetic mod 512 (FFmpeg
  `dist = (a − b) & 511`), i.e. picture_distance wraps at 256. The VE gets raw picture_distance values.
- **Co-located picture** for B direct/skip: the backward reference (always an I/P), its MVs from the col buffer.
- **Output order:** low_delay = 1 → no B, output in decode order. Otherwise the usual one-reference delay: a B is output
  at once; an I/P is output when the next I/P is decoded (or at end of stream). picture_distance gives the display
  order inside a GOP (bunny: decode I0 P4 B1 B2 B3 P8 ..., display 0 1 2 3 4 ...). Userspace owns this (stateless).
- Open GOP: a B after an I at the start of a stream has a missing forward reference → skip until two references exist
  (FFmpeg rejects a B without DPB[1]).

## 7. Software vs engine summary

| layer | software (userspace) | VE |
|---|---|---|
| start-code scan, PES/TS demux | yes | — |
| annex A pseudo start codes | remove in its own header copy | removes in slice data (CTRL bit 26) |
| sequence header, extensions | parse, pass sequence control | — |
| picture header incl. AVS+ WQ/AEC fields | parse, pass picture (+WQ) control | — |
| reference choice (2 refs, rotation), POC/output order | userspace DPB | — |
| slice headers, slice weighting, MB layer (VLC or AEC), field second-slice detection | — | yes |
| WQ matrices from index/model/deltas | — (pass syntax) | yes |
| col MVs | (driver allocates) | writes for I/P, reads for B |
