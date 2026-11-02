# AVS2 (GB/T 33475.2 / IEEE 1857.4 / GY/T 299.1) Main and Main10 header syntax for a stateless decoder

Status: written 2026-11-02 from **static reading** of open implementations. The normative spec text was
**not** available (see "Spec availability"). Everything below is taken from at least two independent
parsers unless it is marked otherwise. Where they disagree, the disagreement is written out.

## Sources (pinned)

| tag | source | commit / version | licence |
|---|---|---|---|
| MPP | https://github.com/rockchip-linux/mpp, `mpp/codec/dec/avs2/*`, `mpp/hal/rkdec/avs2d/*`, `mpp/common/avs2d_syntax.h`, `mpp/base/mpp_bitread.c` | `7916c3cc000fefc0bdf96636b7d54fe174724f44` (2026-10-28) | each file is either "Apache-2.0" or "SPDX: Apache-2.0 OR MIT" (I checked every file header) |
| DAVS2 | https://github.com/pkuvcl/davs2, `source/common/{header,alf,quant,bitstream}.cc` | `b41cf117452e2d73d827f02d3e30aa20f1c721ac` (2022-09-03, latest) | GPL-2.0-or-later (a commercial licence is also offered) |
| AML | https://github.com/CoreELEC/media_modules-aml, `drivers/frame_provider/decoder/avs2/{vavs2.c,avs2_bufmgr.c,avs2_global.h}` | `c15aebb1ac93028d0aceadf8f35dda2204d33424` (branch 5.15.196_20260225) | GPL-2.0-or-later (file headers); `MODULE_LICENSE("GPL")` |
| MT | Moore Threads FFmpeg patch "[PATCH v1 2/2] vaapi: add vaapi_avs2 support" (adds avs2dec.c, avs2dec_headers.c, vaapi_avs2.c), https://patchwork.ffmpeg.org/project/ffmpeg/patch/20240119155300.445106-1-jianfeng.zheng@mthreads.com/ (local mbox md5 a5e96fbc1b76f120bc847e62c060cad4) | posted 2024-01-19, **not merged** | LGPL-2.1+ (FFmpeg headers) |
| VA | libva PR #738 `va/va_dec_avs2.h`, https://github.com/intel/libva/pull/738 | head `564420c92726e12975a8327e24f680283cd8075c` (gitgjogh/libva), **open, not merged** | MIT |
| FF | FFmpeg `libavcodec/avs2.[ch]`, `avs2_parser.c` | `f675c507e20ac78cd55f238ede52da470e6f6ec7` (2026-11-02) | LGPL-2.1+ |
| AW | Allwinner `libawavs2.so` (binary; data tables only, read with my own scripts) | see prior-art.md | proprietary |

Local copies are under `kernel-check/dl-avs2/{mpp,davs2,amlogic-coreelec,ffmpeg,ffmpeg-mthreads-avs2-patch,libva-pr738}/`.
I also wrote a header dump script, `/tmp/avs2-research-scripts/avs2hdr.py` (my own code, run with `python3 -I`).
It parsed every sequence and picture header of the 12 PKU conformance streams without errors (see test-streams.md).
That supports the syntax below for the field paths those streams use. It does **not** check WQ, background/scene,
field coding or temporal_id, because none of the streams I found use them.

## Spec availability (not verified to exist freely)

* IEEE 1857.4-2018 (199 pages) is paywalled: https://standards.ieee.org/ieee/1857.4/5817/
* GB/T 33475.2-2016 has been replaced by **GB/T 33475.2-2024** (published 2024-05-28, in force 2024-12-01). It is listed on
  openstd.samr.gov.cn, but the listing gives no viewable link (`javascript:void`) and I found no free PDF:
  https://openstd.samr.gov.cn/bzgk/gb/std_list?p.p2=33475.2
* GY/T 299.1-2016 (the SARFT broadcast edition, which MT cites as "Annex B.2 of GY/T 299.1-2016") is sold only, for example at
  https://www.chinesestandard.net/AMP/English.amp.aspx/GYT299.1-2016
* The AVS WG says drafts are on a members-only FTP: https://avs.org.cn/en/index/list?catid=22
* Reference software: the PKU stream README says the streams decode with "AVS2 reference software RD19.2"
  (https://gitee.com/hwren/avs2_samples). **I found no public RD19.x source.** "RD19.5" is unverified.
  davs2 is the de-facto open reference (PKU-VCL; its code is clearly RD-derived).

Section and page numbers of the spec therefore **cannot be cited**. The MPP comments quote "avs2 9.12.2" for ALF,
which is the spec clause number they used.

---

## 1. Start codes and NAL framing

A start code is `00 00 01 xx` (byte-aligned):

| xx | meaning | notes |
|---|---|---|
| 0x00..0x8F | slice_start_code; `xx` = slice_vertical_position (low 8 bits) | MPP `AVS2_SLICE_MAX_START_CODE = 0x18F`; MT `AVS2_STC_SLICE_MAX = 0x18F`. **FF `avs2.h` uses 0x1AF.** 0x90..0xAF is presumably reserved (unverified) |
| 0xB0 | video_sequence_start_code (sequence_header) | |
| 0xB1 | video_sequence_end_code | |
| 0xB2 | user_data_start_code | |
| 0xB3 | intra_picture_start_code (I, G, GB) | |
| 0xB4 | reserved | FF comment |
| 0xB5 | extension_start_code; the first 4 bits are extension_id | |
| 0xB6 | inter_picture_start_code (P, F, B, S) | |
| 0xB7 | video_edit_code | |
| 0xB8..0xFF | system start codes | DAVS2 `bitstream.cc` |

Extension ids (4 bits after 0xB5), per MPP `avs2d_global.h`, DAVS2 `header.cc` and MT:
2 = sequence_display, 3 = temporal_scalable, 4 = copyright, 5 = HDR dynamic metadata (MPP), 7 = picture_display,
0xA = mastering_display_and_content_metadata, 0xB = camera_parameters, 0xC = ROI params (MT), 0xF = location data (DAVS2).

**Pseudo start code prevention (important).** AVS2 does not use H.26x `00 00 03` emulation prevention. Instead the encoder
inserts **two bits** `10` so that `00 00 02` appears. The decoder must delete the 2 LSBs of any `0x02` byte that follows two
zero bytes, which keeps the 6 MSBs (always zero). This is a *bit-level* removal, so the following bytes shift by 2 bits.
* MPP `mpp_bitread.c:update_curbyte_avs2()` does this for **all** header NALs. It is enabled in `avs2d_parse.c:639`.
* DAVS2 `bitstream.cc:bs_dispose_pseudo_code()` (line 130) applies it to every unit **except** sequence_header (B0),
  user_data (B2) and extension (B5). Note: at commit b41cf11 I found **no caller** of this function in davs2 (grep).
* MT `ff_avs2_remove_pseudo_code()` applies it to picture headers and the first 5 bytes of the slice header.
* For a stateless uAPI: userspace must undo it when it parses picture headers. Whether the H616 VE undoes it inside slice data
  must be learned from the vendor flow. Rockchip feeds raw slice NALs to its HW (below), so RK HW does it itself.

**What the hardware gets (Rockchip model).** MPP `avs2d_parse.c:store_nalu()` (line 121) sends all non-slice headers to a
software header buffer. Only slice NALs, *with their 4-byte start codes*, are concatenated into the HW stream buffer
(`p_stream`). User data is dropped. The RK HW parses the slice headers itself. VA (Moore Threads) is the same:
"When send AVS2 slice data, start code and slice header should be included". VA additionally passes per-slice
`lcu_start_x/y`, `fixed_slice_qp`, `slice_qp`, the 3 slice SAO flags and `vlc_byte_offset`.

---

## 2. sequence_header() (after 00 00 01 B0)

Field order and widths agree across MPP `avs2d_ps.c:278-398`, DAVS2 `header.cc:127-291` and FF `avs2_parser.c` (first
fields). The script also confirmed them on 23 real streams.

| # | field | bits | condition / semantics |
|---|---|---|---|
| 1 | profile_id | u(8) | 0x12 Main-Picture (intra), **0x20 Main (JiZhun/base)**, **0x22 Main10** |
| 2 | level_id | u(8) | 0x10/12/14 = 2.0.{15,30,60}; 0x20/22 = 4.0.{30,60}; 0x40..0x4A = 6.{0,2}.{30,60,120}; 0x50..0x5A = 8.x (4096x2304); 0x60..0x6A = 10.x (8192x4608) (MT enum and limits table). MPP rejects > 0x6A |
| 3 | progressive_sequence | u(1) | |
| 4 | field_coded_sequence | u(1) | |
| 5 | horizontal_size | u(14) | must be >= 16 |
| 6 | vertical_size | u(14) | must be >= 16. HW/FF/MPP align the coded size to 8 (`MINI_SIZE 8`) |
| 7 | chroma_format | u(2) | 1 = 4:2:0 (the only one MPP accepts); 0 = 4:0:0 (DAVS2 warns "unsupported") |
| 8 | sample_precision | u(3) | 1 = 8-bit, 2 = 10-bit. Output bit depth = 6 + 2*sample_precision |
| 9 | encoding_precision | u(3) | **present only if profile_id == 0x22**; otherwise 1. Internal bit depth = 6 + 2*encoding_precision |
| 10 | aspect_ratio_information | u(4) | 1 = SAR 1:1, 2 = 4:3 DAR, 3 = 16:9 DAR, 4 = 2.21:1 DAR (MT) |
| 11 | frame_rate_code | u(4) | 1..13 = 23.976, 24, 25, 29.97, 30, 50, 59.94, 60, 100, 120, 200, 240, 300 |
| 12 | bit_rate_lower | u(18) | |
| 13 | marker_bit | f(1) | =1 |
| 14 | bit_rate_upper | u(12) | bit_rate = ((upper<<18)+lower)*400 bit/s (DAVS2). MPP computes `lower<<12 + upper`, which looks like an MPP bug, harmless |
| 15 | low_delay | u(1) | |
| 16 | marker_bit | f(1) | |
| 17 | temporal_id_enable_flag | u(1) | |
| 18 | bbv_buffer_size | u(18) | |
| 19 | lcu_size (log2) | u(3) | valid 4..6 (16, 32, 64) |
| 20 | weight_quant_enable_flag | u(1) | |
| 20a | if (20): load_seq_weight_quant_data_flag | u(1) | |
| 20b | if (20a): weight_quant_matrix(): 4x4 (16 x ue(v)), then 8x8 (64 x ue(v)), each in **row-major order j*size+i** | ue(v) | if 20a == 0, use the default matrices (section 7) |
| 21 | background_picture_disable | u(1) | enable_background_picture = !this |
| 22 | mhpskip_enable (multi-hypothesis skip) | u(1) | |
| 23 | dhp_enable (dual-hypothesis prediction) | u(1) | |
| 24 | wsm_enable (weighted skip mode) | u(1) | |
| 25 | amp_enable (asymmetric motion partitions) | u(1) | |
| 26 | nsqt_enable (non-square quadtree transform) | u(1) | |
| 27 | nsip_enable (non-square intra prediction, "SDIP") | u(1) | |
| 28 | secondary_transform_enable | u(1) | |
| 29 | sample_adaptive_offset_enable | u(1) | |
| 30 | adaptive_loop_filter_enable | u(1) | |
| 31 | pmvr_enable | u(1) | |
| 32 | marker_bit | f(1) | |
| 33 | num_of_rcs | u(6) | 0..32 (DAVS2 rejects > AVS2_GOP_NUM; MPP array size 32) |
| 34 | for i < num_of_rcs: reference_configuration_set(i) | | see below |
| 35 | if (!low_delay): output_reorder_delay ("picture_reorder_delay") | u(5) | else 0 |
| 36 | cross_slice_loopfilter_enable | u(1) | |
| 37 | reserved_bits | r(2) | '00' |
| | then byte align (DAVS2 `bs_align`) | | |

**reference_configuration_set()** (MPP `parse_one_rps`, avs2d_ps.c:241; DAVS2 header.cc:236-256):

| field | bits |
|---|---|
| refered_by_others_flag | u(1) |
| num_of_reference_picture | u(3) (max 7 = AVS2_MAX_REFS; MPP rejects > 7) |
| delta_doi_of_reference_picture[j], j < num_of_reference_picture | u(6) each |
| num_of_removed_picture | u(3) |
| delta_doi_of_removed_picture[j] | u(6) each |
| marker_bit | f(1) |

Real-stream example (xavs2 RA GOP8, BasketballPass_ra): 8 RCS =
`1:[8,3,7,16]/-[16,17]`, `1:[1,9]/-[4]`, `1:[1,10]/-[9]`, `0:[1,11]`, `0:[3,2]`, `1:[5,4]`, `0:[1,5]/-[4]`, `0:[7,2]`
(format: refered_by_others:[ref deltas]/-[remove deltas]).

---

## 3. intra_picture_header() (after 00 00 01 B3); pseudo-start-code removal applies

MPP `avs2d_ps.c:584-696` + `parse_picture_header_comm` 490-582; DAVS2 `header.cc:315-494`. They agree field for field.

| field | bits | condition |
|---|---|---|
| bbv_delay | u(32) | (real streams: 0x0000FFFF) |
| time_code_flag | u(1) | |
| time_code | u(24) | if time_code_flag |
| background_picture_flag | u(1) | if enable_background_picture |
| background_picture_output_flag | u(1) | if background_picture_flag. 1 -> **G** picture (output and kept as the scene ref); 0 -> **GB** (not output, scene ref only) |
| decode_order_index (doi, "coding_order", COI) | u(8) | |
| temporal_id | u(3) | if temporal_id_enable_flag |
| picture_output_delay | ue(v) | if low_delay == 0 **and not GB** (MPP: `!(bg_flag && !bg_output_flag)`; for GB, MPP reuses the previous value). DAVS2 reads it whenever low_delay == 0 (it does not test for GB, an apparent DAVS2 gap). Must be < 64 |
| reference_configuration_set_flag ("predict"/"use RCS in SPS") | u(1) | |
| reference_configuration_set_index | u(5) | if flag; DAVS2 rejects index >= num_of_rcs |
| reference_configuration_set() inline | | if !flag (same syntax as in the sequence header, incl. marker) |
| bbv_check_times | ue(v) | if low_delay |
| progressive_frame | u(1) | |
| picture_structure | u(1) | if !progressive_frame; else 1 (frame). Meaning of 0 (field vs interleaved) is UNVERIFIED; DAVS2 rejects != FRAME |
| top_field_first | u(1) | |
| repeat_first_field | u(1) | |
| is_top_field + reserved | u(1) + r(1) | if field_coded_sequence |
| fixed_picture_qp | u(1) | |
| picture_qp | u(7) | valid 0..63+8*(bitdepth-8) |
| -- the common tail follows (section 5) -- | | |

## 4. inter_picture_header() (after 00 00 01 B6); pseudo-start-code removal applies

MPP 698-796, DAVS2 500-695.

| field | bits | condition |
|---|---|---|
| bbv_delay | u(32) | |
| picture_coding_type | u(2) | 1 = P (or S), 2 = B, 3 = F; 0 is invalid |
| background_pred_flag | u(1) | if enable_background_picture && pct == 1. 1 -> **S** picture |
| background_reference_flag ("background_reference_enable") | u(1) | if enable_background_picture && pct != 2 && !background_pred_flag (so for P and F) |
| doi | u(8) | |
| temporal_id | u(3) | if temporal_id_enable_flag |
| picture_output_delay | ue(v) | if low_delay == 0 (< 64) |
| RCS flag / index u(5) / inline RCS | | as for intra |
| bbv_check_times | ue(v) | if low_delay |
| progressive_frame | u(1) | |
| picture_structure | u(1) | if !progressive_frame, else 1 |
| top_field_first, repeat_first_field | u(1), u(1) | |
| is_top_field + reserved | u(1)+r(1) | if field_coded_sequence |
| fixed_picture_qp | u(1) | |
| picture_qp | u(7) | |
| reserved_bit | r(1) | **if (picture_coding_type != 2 \|\| picture_structure == 0)** (MPP). DAVS2 writes it as `!(pct==2 && structure==FRAME)`, which is equivalent |
| random_access_decodable_flag | u(1) | |
| -- the common tail follows (section 5) -- | | |

Picture types used by the implementations: MPP `I=0, P=1, B=2, F=3, G=4, GB=5, S=6`; VA `I=0, P=1, B=2, F=3, S=4, G=5, GB=6`
(**the enum orders differ**, so a uAPI must define its own). FF `avs2_parser.c` derives pict_type from `buf[8] & 3`.
picture_coding_type is really the **top** 2 bits of byte 8 (bbv_delay takes bytes 4..7). I checked this on
BasketballPass_ra: the bytes `000001b60000ffffc0` give `>>6 = 3` (F), while `&3 = 0`. So the FF parser's frame-type
reporting is buggy (it is metadata only). FF also labels type 3 as "S", which is wrong; 3 is F.

## 5. Common picture-header tail (both I and PB)

MPP `parse_picture_header_comm` (avs2d_ps.c:490); DAVS2 header.cc:399-483 / 597-683.

| field | bits | condition |
|---|---|---|
| loop_filter_disable_flag | u(1) | |
| loop_filter_parameter_flag | u(1) | if !disable |
| alpha_c_offset | se(v) | if parameter_flag; range -8..8 (else 0) |
| beta_offset | se(v) | if parameter_flag; range -8..8 |
| chroma_quant_param_disable_flag | u(1) | |
| chroma_quant_param_delta_cb | se(v) | if !disable; -16..16 |
| chroma_quant_param_delta_cr | se(v) | if !disable; -16..16 |
| pic_weight_quant_enable_flag | u(1) | **if weight_quant_enable_flag (sequence)** |
| pic_weight_quant_data_index | u(2) | if pic_wq_enable. 0 = use the sequence matrix, 1 = parametric, 2 = explicit matrix |
| reserved_bits (DAVS2 comment: "mb_adapt_wq_disable") | r(1) | if data_index == 1 |
| weighting_quant_param_index | u(2) | if data_index == 1. 0 = default DETAILED params, 1 = UNDETAILED+delta, 2 = DETAILED+delta |
| weighting_quant_model | u(2) | if data_index == 1 (0..3) |
| weighting_quant_param_delta1[6] | se(v) x6 | if data_index == 1 && param_index == 1 |
| weighting_quant_param_delta2[6] | se(v) x6 | if data_index == 1 && param_index == 2 |
| weight_quant_matrix(): 16 + 64 ue(v) | | if data_index == 2 |
| alf_parameter_set() | | if adaptive_loop_filter_enable (section 8) |
| then byte align (DAVS2) | | |

**DAVS2 bug (apparent, unverified at runtime):** DAVS2 `header.cc:437` / `636` sets `h->seq_info.enable_weighted_quant = 0;`
**immediately before** `if (h->seq_info.enable_weighted_quant)`. So davs2 never reads pic_weight_quant_enable. For any
stream with sequence weight_quant_enable = 1, the ALF params would then be misparsed. MPP parses it correctly. Keep this in
mind if davs2 is used to make reference md5s. None of the streams I found have WQ enabled (test-streams.md).

## 6. DOI / POC derivation, reference lists, DPB

**DOI unwrap.** doi is 8 bits (cycle 256). MPP `compute_frame_order_index` (avs2d_dpb.c:203) and DAVS2 header.cc:720-735 do the same:
`if (doi < prev_doi) wrap_cnt++; prev_doi = doi; DOI = doi + 256*wrap_cnt`.
(MPP also renormalises when DOI is close to INT_MAX, `recompute_cycle_order_index`.)

**POC ("POI", "tr"):**
```
if (low_delay == 0)  POC = DOI + picture_output_delay - output_reorder_delay;
else                 POC = DOI;
```
MPP avs2d_dpb.c:232-236, DAVS2 header.cc:739-743 and AML avs2_bufmgr.c:686-691 all use this.
For a GB picture (no output delay coded), MPP keeps the previous delay.
Example from BasketballPass_ra (reorder_delay 3): I doi0 delay3 gives POC 0; F doi1 delay10 gives 8; B doi2 delay5 gives 4;
B doi3 delay2 gives 2; B doi4 delay0 gives 1; ... This is a hierarchical GOP-8.
AML also keeps `pic_distance = POC % 256`, which it writes to the HW as the current "POC" for MV scaling
(`HEVC_MPRED_CUR_POC`) (avs2_bufmgr.c:694-697, vavs2.c config_mpred_hw).

**Reference picture lookup.** For i < num_of_reference_picture: `ref_DOI[i] = DOI_cur - delta_doi_of_reference_picture[i]`.
Then find the DPB picture with that DOI that is still marked "referenced" (MPP `dpb_set_frame_refs` avs2d_dpb.c:676;
DAVS2 `task_get_references` header.cc:1293-1330). **The list order is the RCS order.** No sorting is done.

* **P**: refs[0..n-1] in RCS order (single hypothesis).
* **F**: refs[0..n-1] in RCS order. AML fills **both** HW L0 and L1 canvas tables with the same list (vavs2.c config_mc_buffer,
  F_IMG branch), because F supports DHP/WSM.
* **B**: exactly 2 refs. **refs[0] must be the backward (future, POC > cur) picture and refs[1] the forward (past, POC < cur)
  picture.** MPP checks `refs[0]->poi > cur && refs[1]->poi < cur` (avs2d_dpb.c:715-720) and DAVS2 does the same check
  (header.cc:1332-1337). AML programs HW L0 = fref[1] (past) and L1 = fref[0] (future).
  Example: B doi2 has RCS refs [1,2] -> doi1 (F, POC 8, future) and doi0 (I, POC 0, past).
* **S** (P with background_pred_flag): single reference = the scene (G/GB) picture. MPP sets `scene_ref_replace_pos = 0`.
* **P/F with background_reference_flag**: the **last** ref slot (index num_of_ref-1) is replaced by the scene picture
  (MPP `scene_ref_replace_pos = num_of_ref - 1`, then the HAL overwrites `ref_base[replace_pos]` and `ref_poc[replace_pos]`,
  hal_avs2d_rkv.c:371-386). AML instead programs the background picture into separate canvas slots: index 15 in L0 and
  31 in L1 (vavs2.c config_mc_buffer). DAVS2 has this path **commented out** (cu.cc:1023), so it is not usable as a reference.

**Marking and removal.** After decoding the current picture, for each `delta_doi_of_removed_picture[j]` the picture with
`DOI_cur - delta` is unmarked (`refered_by_others = 0`) (MPP `dpb_update_refs` avs2d_dpb.c:638; DAVS2 defers the same
list to the next picture). The current picture is a reference iff its RCS `refered_by_others_flag` is set
(GB pictures are never "refered_by_others"; they are only the scene ref). Pictures with |POC - POC_cur| >= 128
(`AVS2_MAX_POC_DISTANCE`) are force-unmarked. On a DOI discontinuity (doi != prev+1 mod 256), MPP unmarks everything that
is more than 1 away (avs2d_dpb.c:213-226).

**Scene (background) pictures.** I/G/GB are intra. A new G or GB replaces the single scene reference. An old GB is freed
immediately; an old G stays until it is output (MPP `dpb_remove_scene_frame`). GB is `invisible` (never output).

**Output (bumping).** MPP `dpb_output_next_frame`: output the smallest-POC non-output picture when
`poc - last_output_poc <= 1` or `doi + out_delay < cur_doi`. DPB size by level (MPP `dpb_get_size`): level <= 0x22 -> 15;
otherwise `min(LevelMaxPicBuf/pic_size, 16) - 1` with LevelMaxPicBuf 13369344 (6.x), 56623104 (8.x), 213909504 (10.x),
and at least num_of_rcs + 1. MPP allocates 15 always.

**Co-located MV (temporal MV prediction).** The col picture is **refs[0]** (AML `col_pic = fref[0]`, vavs2.c config_mpred_hw).
The HW needs:
* the col picture's MV buffer,
* the current POC,
* the col picture's POC (`HEVC_MPRED_COL_POC = imgtr_next_P`: for a B picture this is fref[0]'s POC, otherwise the current POC),
* for each of the 7 refs, its POC (L0_REFxx_POC),
* **the ref-POC list that the col picture itself used** (L1_REFxx_POC = `fref[0]->ref_poc[i]`).

AML stores `ref_poc[]` per decoded frame (avs2_bufmgr.c:1144-1178). For B frames it stores [past, future]. For intra frames
all entries are the picture's own POC. RK passes `cur_poc` plus `ref_poc_list[8]` and per-ref field flags in its HW header
buffer (`hal_avs2d_vdpu38x_prepare_header`, hal_avs2d_com.c:95). The per-ref "ref POC" lists presumably live in the RK
colmv buffer (unverified). **uAPI implication:** each DPB entry must carry its POC, and either the kernel driver keeps
per-buffer ref-POC lists or the uAPI passes them (like the HEVC DPB entries).

## 7. Weighted quantisation (WQ) tables and derivation

Tables (MPP avs2d_ps.c:31-128 and DAVS2 quant.cc:39-140 are identical):

```
wq_param_default[2][6]:          // index 0 = UNDETAILED, 1 = DETAILED (MPP/DAVS2 #define UNDETAILED 0, DETAILED 1)
  { 67, 71, 71, 80, 80, 106 },   // [UNDETAILED]
  { 64, 49, 53, 58, 58,  64 }    // [DETAILED]
g_WqMDefault4x4[16] = { 64,64,64,68, 64,64,68,72, 64,68,76,80, 72,76,84,96 }
g_WqMDefault8x8[64] = {
  64, 64, 64, 64, 68, 68, 72, 76,
  64, 64, 64, 68, 72, 76, 84, 92,
  64, 64, 68, 72, 76, 80, 88,100,
  64, 68, 72, 80, 84, 92,100, X ,   <-- X disputed, see below
  68, 72, 80, 84, 92,104,112,128,
  76, 80, 84, 92,104,116,132,152,
  96,100,104,116,124,140,164,188,
 104,108,116,128,152,172,192,216 }
WeightQuantModel[4][64] and WeightQuantModel4x4[4][16]: per-position index 0..5 into the 6-entry param array
  (copied verbatim in MPP avs2d_ps.c:54-128 / DAVS2 quant.cc:68-140; reproduce from there)
```

**Disputed default 8x8 entry [3][7]:** it is **28** in DAVS2, MPP **and in every Allwinner libawavs2.so I scanned** (8 builds; int32
table at e.g. offset 0x90b8 in the sunxi-aarch64-glibc build; script `/tmp/avs2-research-scripts/findtab.py`). It is **112** in the
Amlogic kernel driver (vavs2.c:203-212) and in the Moore Threads patch. 112 fits the monotone row, so 28 is likely an
RD typo that RD-derived decoders inherited. For **bit-exactness with the vendor H616 flow, use 28** (it matches libawavs2).
This only matters when weight_quant_enable = 1 and load_seq_weight_quant_data_flag = 0. Mark as **unresolved against the spec**.

**Derivation** (MPP `wq_init_frame_quant_param` / `wq_update_frame_matrix`, avs2d_ps.c:135-209):
1. Sequence matrix: `seq_wqm[sizeId]` = coded (load flag = 1) or default (load flag = 0). sizeId 0 = 4x4, 1 = 8x8.
2. If the picture enables WQ:
   * data_index 0 -> use seq_wqm.
   * data_index 1 -> `param[k]` = param_index 0: `wq_param_default[DETAILED][k]`; 1: `delta1[k] + wq_param_default[UNDETAILED][k]`;
     2: `delta2[k] + wq_param_default[DETAILED][k]`. Then
     `pic_wqm[1][j*8+i] = param[WeightQuantModel[wq_model][j*8+i]]`,
     `pic_wqm[0][j*4+i] = param[WeightQuantModel4x4[wq_model][j*4+i]]`.
   * data_index 2 -> explicit pic matrix (16 + 64 ue(v)).
3. If WQ is disabled for the picture (or the sequence), the matrix is all 64 (flat).
4. RK HW wants the matrices transposed in 4x4 blocks ("dump by block4x4, vertical direction",
   hal_avs2d_com.c:188-226). The H616 layout is for the RE side to determine.
   (DAVS2 additionally derives larger-TU matrices internally; not needed for the uAPI.)

## 8. ALF picture parameters (alf_parameter_set)

Syntax (MPP `parse_pic_alf_params` avs2d_ps.c:427-488; DAVS2 `alf_read_param` / `vlc_read_alf_coeff`, alf.cc:357-419):

```
picture_alf_enable_flag[Y]  u(1)
picture_alf_enable_flag[Cb] u(1)
picture_alf_enable_flag[Cr] u(1)
if (alf_Y) {
    alf_filter_num_minus1                    ue(v)   // filters_per_group = +1, max 16
    for (f = 0; f < filters_per_group; f++) {
        if (f > 0)
            alf_region_distance[f]           ue(v)   // NOT coded when filters_per_group == 16 (then = 1)
        alf_coeff_luma[f][0..8]              se(v) x9
    }
}
if (alf_Cb) alf_coeff_chroma[0][0..8]        se(v) x9
if (alf_Cr) alf_coeff_chroma[1][0..8]        se(v) x9
```
Ranges (MPP): coeff[0..7] in [-64, 63]; coeff[8] in [-1088, 1071]; sum of region distances <= 15.

Semantics:
* **Region pattern / merge table:** `pre = 0; for f >= 1: pattern[pre + dist[f]] = 1; pre += dist[f]`. Then
  `coeff_idx_tab[0] = 0; coeff_idx_tab[i] = pattern[i] ? coeff_idx_tab[i-1] + 1 : coeff_idx_tab[i-1]` for i = 1..15.
  The result is a 16-entry map from region to filter index, e.g. `0000111222223333` (MPP comment cites "avs2 9.12.2").
* **Coefficient reconstruction:** `c[8] = coded[8] + 64 - 2*sum(coded[0..7])` (ALF_NUM_BIT_SHIFT = 6; DAVS2
  `alf_recon_coefficients`, alf.cc:52; MPP read_pic_alf_coeff). The filter is symmetric: 8 coded tap-pairs plus the centre.
  DAVS2 alf_filter_block1 (alf.cc:~110-150) gives the geometry: c0 = (0,+-3) vertical, c1 = (0,+-2), c2 = (+1,+1)/(-1,-1)
  diagonal, c3 = (0,+-1), c4 = (+1,-1)/(-1,+1), c5 = (+-3,0) horizontal, c6 = (+-2,0), c7 = (+-1,0), c8 = centre.
  So it is a 7x7 cross plus a 3x3 square, output `(sum + 32) >> 6`, clipped.
  At LCU row boundaries ALF works on a 4-line-shifted window (`startPos = y-4` if top available) and clips vertically (virtual boundary).
* **LCU to region mapping (16 regions, 4x4 grid):** `quad_w = (w_lcu+1)>>2; quad_h = (h_lcu+1)>>2;
  rx = quad_w ? min(x/quad_w, 3) : 3; ry likewise; region = regionTable[ry*4+rx]` with
  `regionTable = {0,1,4,5,15,2,3,6,14,11,10,7,13,12,9,8}` (DAVS2 alf.cc:328-347). Luma filter for an LCU =
  `coeff[coeff_idx_tab[region]]`. Chroma uses one filter each.
* LCU-level on/off flags are in slice data (CABAC). The HW handles them.
* What HWs want: RK packs `alf_filter_num_minus1` (4 bits), `alf_coeff_idx_tab[16]` (4 bits each), 16x9 luma and 9+9 chroma coeffs
  **at 7 bits each** (hal_avs2d_com.c:140-152; it is not clear how RK carries the wide c[8], unverified). AML writes reconstructed
  `m_filterCoeffSym` (c[0..3] 7 bits, c[4] split 4+3 bits, c[5..8] 7 bits) and the 16-entry `m_varIndTab` to `HEVC_DBLK_CFGD`
  (vavs2.c config_alf_hw 3640-3816). VA passes `int8_t alf_coeff[16+2][9]`.

## 9. Slice header (the HW parses it; shown for completeness)

DAVS2 `parse_slice_header` (header.cc:769-818) and MT `ff_avs2_decode_slice_header` agree:
```
(start code 00 00 01 xx, xx = slice_vertical_position[7:0])
if (vertical_size > 144 * LCU)  slice_vertical_position_extension  u(3)   // row = (ext << 7) + pos (sic, both sources)
slice_horizontal_position                                           u(8)
if (horizontal_size > 255 * LCU) slice_horizontal_position_extension u(2)  // col = pos + (ext << 8)
if (!fixed_picture_qp) { fixed_slice_qp u(1); slice_qp u(7) }
if (sample_adaptive_offset_enable) { slice_sao_enable[Y,Cb,Cr] u(1) x3 }
aec_byte_alignment_bit(s) to the byte boundary, then AEC (CABAC) data
```
VA's slice params carry exactly these (+ `vlc_byte_offset` = header bytes up to the AEC start).

## 10. What a stateless uAPI needs (synthesis, for discussion)

From the RK "syntax" (`avs2d_syntax.h`: PicParams/RefParams/AlfParams/WqmParams, which is effectively a DXVA-style layout) and VA
`VAPictureParameterBufferAVS2`:
* Sequence: chroma_format, width/height (aligned to 8), bit_depth luma/chroma (or encoding/output precision), lcu_size,
  progressive_sequence, field_coded_sequence, the 11 tool flags (mhp_skip, dhp, wsm, amp, nsqt, nsip, 2nd-transform, sao,
  alf, pmvr), cross_slice_loopfilter, enable_background_picture.
* Picture: picture_type (I/P/B/F/S/G/GB), scene_reference_enable (= background_reference_flag), bottom_field flag,
  fixed_picture_qp, picture_qp, loop_filter_disable, alpha/beta offset, chroma_quant_param_delta_cb/cr,
  pic_weight_quant_enable + the final 4x4 and 8x8 matrices, ALF enables + idx_tab[16] + coeffs[16][9] + cb[9] + cr[9],
  cur POC (+DOI), num_ref, ref POC list[7], scene-ref buffer + replace position.
* DPB/refs: per-ref buffer ids and POCs. The col picture's own ref-POC list (or keep it per capture buffer in the driver).
* Slices: raw slice NALs including start codes. HW parses slice headers (RK, MT). Whether userspace strips pseudo start
  codes in slice data depends on the H616 VE (open question for the RE agent).
* No mainline V4L2 AVS2 controls or pixel format exist (see prior-art.md).
