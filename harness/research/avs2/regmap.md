# H616 VE AVS2 decoder: register map and programming sequence

Clean-room description written 2026-11-02 from the vendor `libawavs2.so`. The source copy is the
CalvinXu17 libcedarc A133 aarch64 build, which kept its DWARF:
`harness/research/ve-encoder/dl/libcedarc-CalvinXu17-a133/library/aarch64-linux-gnu/libawavs2.so`.

Inputs (all read statically):
- the disassembly `kernel-check/dl-vdec/re/libawavs2.dis`;
- the pahole dump `harness/research/vdec/libawavs2.pahole.txt`;
- the register bitfield dump `harness/research/vdec/avs2-regs-libawavs2.txt`;
- the libVE `enableDecoder` in `kernel-check/dl-vdec/re/libVE.a133.dis`, line 2450.

No vendor code was copied. Only register offsets, bit positions, table layouts and the write order are
recorded, which is what the driver needs for interoperability. The implementation is
`drivers/staging/media/sunxi/cedrus/cedrus_avs2.c`, from the patch
`media-cedrus-add-AVS2-decoding.patch`.

**Status: none of this has run on hardware yet.** The open items, marked **[board]**, are collected in
`harness/research/impl-avs2.md` §4.

## 1. Engine selection

- **Slot.** AVS2 runs in the H.265 slot: VE+0x500, base `getGroupRegAddr(self, 5)`. The top
  registers are group 0.
- **VE_MODE (VE+0x00).** libVE `enableDecoder` maps the AVS2 codec id 0x118 to mode 4 (H.265).
  - It sets the AFBC bits (0x10, bit 29, bit 12, and clears 26/27) only when AFBC output is requested.
  - It sets neither the RAMPD bit nor the VP9 reserved bit 30.
  - The driver therefore uses the plain H.265 path: DDR mode | DEC_H265 | the width class bits.
  - **[board]** Confirm that no RAMPD is needed.
- **Decoder select.** Bits 31:30 of REG04 select the decoder: 0 = H.265, 1 = AVS2, and VP9 sets
  bit 31 (`decoder_selected` in the vendor struct).

## 2. Register writes, in vendor order (`AVS2ConfigureRegister`, dis line 4135)

Offsets are from VE+0x500 unless marked "top" (VE+0x000).

| step | vendor function | register | value |
|---|---|---|---|
| 1 | Avs2SetTopReg (3970) | top 0xEC | output format bits [6:4] |
| | | top 0xC4 | reference chroma buffer length |
| | | top 0xC8 | luma stride \| chroma stride << 16 |
| 2 | Avs2SetHeaderReg (3356) | 0x04, 0x08, 0x10, 0x14 | see §3 |
| 3 | Avs2SetBitstreamReg (3649) | 0x44, 0x48, 0x4C, then 0x40 | see §4 |
| 4 | Avs2SetTopSecReg (4024) + FrameSecReg (3722), only with scale-down or rotation | top 0xE8 | [27:0] display chroma size, [31:30] format |
| | | top 0xCC | secondary strides |
| | | top 0xEC [2:0] | secondary format |
| | | 0x50 | (hRatio \| vRatio << 2) << 8 |
| | | 0x54, 0x58 | secondary Y and C addresses >> 8 |
| 5 | Avs2SetDramReg (3764) | 0x60 | neighbour-info buffer >> 8 (2 MiB, 0x200000) |
| | | 0x64 | entry-point (table) buffer >> 8 (512 bytes, §5) |
| | | 0x78 | co-located MV buffer of the reference in DPB slot `dpbIndex[0]` >> 8, or 0 |
| | | 0x7C | MV buffer of the current frame >> 8 |
| 6 | Avs2Set10BitReg (3818), only for bit depth 10 | 0x84 | offset of the 2-bit plane & 0x0fffffff |
| | | 0x8C | (2-bit stride & 0xfff) \| 0x2000 |
| | with scale/rotate | 0x8C | 0x2000 only |
| 7 | Avs2SetFunctionReg (3876) | 0x30 | see §6 |
| | | 0x34 | 7 (INIT_SWDEC) |
| | | 0x38 | 0x00080100 |
| | | 0x3C | 0 |
| | | 0x34 | 8 (DEC_SLICE: the trigger) |
| IRQ | ClearInterrupt (4373) | 0x38 | read, then the value written back (write-1-to-clear of bits 0..2) |

The vendor waits for the interrupt with `veops->waitInterrupt`. In cedrus the trigger write is the
`.trigger` op, and the IRQ path reads 0x38 bits 0..2 as the H.265 decoder does: bit 0 finished,
bit 1 error, bit 2 VLD data request.

MV buffer size per frame: ceil(w/64) × ceil(h/64) × 128 bytes. The vendor keeps 8 of them; the driver
keeps one per capture buffer.

**Top registers in cedrus.** `cedrus_dst_format_set()` already programs the top registers
(0xEC/0xC4/0xC8) before `.setup`. P010 uses `cedrus_dst_p010_output_set()`, which writes
0xE8/0xCC/0xEC and 0x50..0x58, exactly as for H.265 and VP9.

## 3. Header registers

**REG04, sequence**

| bits | meaning | source |
|---|---|---|
| [2:0] | lcu_size − 3 | the compiler emits (x+5)&7 |
| [5:3] | bit depth − 8 | vendor `internalBitDepth` (seq+36) = 6 + 2·sample_precision, see §8 |
| 6 | 0 | `slice_data` / reserved |
| 7 | field_coded_sequence | |
| 16 | wsm_enable | |
| 17 | dhp_enable | |
| 18 | mhp_skip_enable | |
| 19 | pmvr_enable | |
| 20 | secondary_transform_enable | |
| 21 | nsqt_enable | |
| 22 | nsip_enable | |
| 23 | amp_enable | |
| 24 | **!** sample_adaptive_offset_enable | the bit is a disable |
| 25 | adaptive_loop_filter_enable | named "..._disable" in the vendor struct but written as an enable |
| 26 | cross_slice_loopfilter_enable | |
| 27 | bcbr_enable && picture type ≠ I | |
| 28 | progressive_sequence | |
| 29 | background picture enable (!background_picture_disable) | |
| [31:30] | 1 | AVS2 decoder |

**REG08**: horizontal_size [13:0], vertical_size [29:16].

**REG10, picture 0**

| bits | meaning |
|---|---|
| 0, 1, 2 | picture_alf_enable Y, Cb, Cr (only when the sequence enables ALF) |
| 3 | fixed_picture_qp |
| 4 | loop_filter_disable |
| 5 | background_reference_flag (non-I pictures only) |
| [14:8] | picture_qp |
| 15 | refered_by_others (from the RCS of the picture) |
| [21:16] | chroma_quant_param_delta_cb, 6-bit two's complement |
| [29:24] | chroma_quant_param_delta_cr, 6-bit two's complement |

**REG14, picture 1**

| bits | meaning |
|---|---|
| [2:0] | HW picture type: I=0, P=1, B=2, F=3, S=4. Vendor: picture_coding_type 1 + background_pred_flag gives `typeb` 5, programmed as S=4 |
| [5:3] | num_of_reference_picture, as coded in the RCS |
| [10:6] | alpha_c_offset, 5-bit two's complement, only when the loop filter is on |
| [15:11] | beta_offset, 5-bit two's complement, only when the loop filter is on |

## 4. Bitstream registers

The vendor parses the sequence and picture headers in software, then points the engine at the first
slice start code (`00 00 01 xx`, with xx < 0x90; `Avs2SearchSliceStartCode`, line 7749). One trigger
decodes every slice of the picture.

| reg | value |
|---|---|
| 0x44 | bit offset of the first slice start code from the base: bytes·8, in bits [29:3] |
| 0x48 | remaining length in bits from that offset |
| 0x4C | end of the bitstream buffer >> 8. The vendor uses the end of its ring buffer; the driver uses the end of the OUTPUT plane |
| 0x40 | base >> 8 in [23:0] \| 0x10000000 valid \| 0x20000000 last \| 0x40000000 first |

**Pseudo start codes.** The vendor removes pseudo start codes (the 2 inserted bits after `00 00`, seen
as `00 00 02`) only in its *software* copy of the headers. It hands the raw stream to the engine and
sets CTRL bit 24 ("EPTB bypass").

**[board]** Does the engine remove pseudo start codes inside slice data by itself? The vendor's choice
suggests yes, as Rockchip's AVS2 hardware does.

## 5. Entry-point (table) buffer, 512 bytes

The buffer is written by `Avs2UpdateAlfPraramToEntryPointBuf` (8210), `Avs2UpdateWqmToEntryPointBuf`
(9425) and `Avs2UpdateRefFrameToEntryPointBuf` (9589). After the last upload the vendor flushes 0x200
bytes from the CPU cache; the driver uses a coherent allocation instead.

| offset | size | content |
|---|---|---|
| 0x000 | 176 | ALF (`REG_AVS2_ALF`; the vendor copies 172 bytes, but the engine reads the region map at +168, see 5.1) |
| 0x0B0 | 80 | weighting quant matrices (`REG_AVS2_WQM`) |
| 0x100 | 184 | reference list (`REG_AVS2_REF`) |

### 5.1 ALF (offset 0x000)

| offset | type | content |
|---|---|---|
| +0 | s8 [16][8] | luma filter f, coefficients c0..c7 as coded |
| +128 | s8 [2][8] | Cb and Cr, c0..c7 |
| +144 | u8 [16] | luma centre tap: 64 − 2·Σ(c0..c7) + c8 |
| +160 | u8 [2] | chroma centre taps, same formula |
| +162 | 6 bytes | reserved (zero) |
| +168 | u8 [8] | region → filter map: byte k = idx[2k] \| idx[2k+1] << 4. **Measured on the board** (2026-11-03) |

**The region map is at +168, not at +164 where the vendor library puts it.** The vendor builds a 172-byte table on the
stack with the map at bytes 164..171 and copies 0xac bytes of it to the pointer at DecInf+7688
(`Avs2UpdateAlfPraramToEntryPointBuf`, dis 0xce60). A plain 4-byte shift of the whole table cannot explain it: the
coefficients and centre taps work at the vendor offsets. With that layout every picture with two or
more luma filters decoded wrongly on the H616 (luma only, max error 9; chroma and single-filter pictures were
bit-exact). A probe (all 16 luma slots = filter 0, slot s = the identity filter, identity map; one 1080p I picture
per s) showed which LCUs the engine filters with which slot: slots 8..15 and 0, in the spec's region order
(`regionTable`, syntax.md §8), which is exactly what the engine sees if it reads the 16 nibbles from +168
(the old map's bytes 4..7 hold regions 8..15, then 4 zero bytes). With the map at +168 all 17 8-bit reference streams
are bit-exact. Why the vendor layout differs (another IP revision, or a vendor bug that only shows with multi-filter
ALF) is not known.

The region map is built as: idx[0] = 0; idx[k] = idx[k−1] + (pattern[k] ≠ 0) when there are at least
2 filters, otherwise 0. `pattern` comes from alf_region_distance.

The centre value overflows 8 bits for large c8; the vendor stores it as a byte all the same.
**[board]** Not specifically exercised: the reference streams pass, but whether any of their centre taps exceed 8 bits was not checked.

### 5.2 WQM (offset 0x0B0)

16 bytes of the 4x4 matrix, then 64 bytes of the 8x8 matrix, in raster order. The engine always applies
the matrix: "disabled" means a flat matrix of all 64s.

The vendor picks the source by pic_weight_quant_data_index:
- 0: the sequence matrix;
- 1: a matrix derived from the parameters;
- 2: the picture matrix.

`Avs2InitFrameQuantParam` is at line 8532. Its default tables match davs2/MPP, including the disputed
8x8 entry [3][7] = 28 (see syntax.md §7).

### 5.3 Reference list (offset 0x100)

Layout: `u32 pic[8][4]`, then `u32 ref_poc[7][2]`.

For each reference i < n, where n = 1 for an S picture and num_of_reference_picture otherwise:

| word | value |
|---|---|
| pic[i][0] | luma address >> 5 |
| pic[i][1] | (poc & 0x1ff) \| bottom << 16. bottom = 1 if the sequence is field coded and the current picture is not the top field |
| pic[i][2] | chroma address >> 5 |

Exception: the last reference of a P or F picture with background_reference_flag (the background
picture) gets the order count of the *current* picture (cur.poc − 1 if top field) instead of its own.

Each reference also carries its own reference-POC list, 7 × 9 bits packed little-endian into 64 bits:
- reference 0: low word in pic[0][3], high word in pic[1][3];
- reference i ≥ 1: ref_poc[i−1][0..1].

Entry 7 is the current picture:
- pic[7][0] = luma >> 5;
- pic[7][1] = poc & 0x1ff | bottom << 16;
- pic[7][2] = chroma >> 5 (the vendor writes Y here for AFBC, `bEnableAfbcFlag` at decoder+264; the driver does this for
  the current picture and for the references whenever the reconstruction is AFBC, i.e. P010 capture since patch 30);
- its own reference-POC list goes in ref_poc[6].

How a picture's reference-POC list is built:
- **B**: [ref1.poc, ref0.poc]. The RCS order is future, past, so the stored list is past, future (Amlogic does the same).
- **P, F, S**: the references in RCS order.
- Entries from n up to 3 are zero-filled.
- **I**: entries 0..3 are the picture's own POC.

The vendor writes B ref 0 as an unmasked s16; the driver masks it to 9 bits. **[board]** Check the
9-bit wrap with POC > 511.

The co-located picture is the reference in DPB slot `dpbIndex[0]` (reference 0). Its MV buffer goes in
0x78.

## 6. Function register (0x30)

| bits | meaning |
|---|---|
| 0, 1, 2 | finish, error and VLD-data-request IRQ enables |
| 9 | secondary output enable (scale/rotate; P010 in cedrus) |
| 24 | EPTB bypass. Always set by the vendor |
| 31 | set by the vendor only when 129 ≤ width ≤ 192 and height ≥ 65. It is DDR_CONSISTENCY in the cedrus H.265 names; the purpose is unknown. **[board]** |

Then 0x34 = 7, 0x38 = 0x80100, 0x3C = 0. The meaning of 0x80100 (bits 8 and 19 of the status
register) is unknown. **[board]**

## 7. 10-bit (0x84 / 0x8C)

The vendor never uses P010. It writes:
- 0x84 = offset of the 2-bit plane;
- 0x8C = stride \| bit 13 (`high10_bit_for_P010` / `snd_with_high10b` in the vendor bitfield dump).

`Avs2Set10BitReg` has no AFBC branch; with scale-down or rotation (`VConfig.bScaleDownEn/bRotationEn`) it writes 0x8C =
0x2000 only and skips 0x84.

The cedrus H.265 and VP9 P010 path sets bit 12 (P010) and never bit 13. The driver does this:
- **P010 capture**: bit 12, as for H.265, with the hidden AFBC reconstruction (since patch 30; before that, the hidden
  NV12 + 2-bit one) and the secondary output. 0x84 = 0, as the AFBC surface has no 2-bit plane.
- **8-bit-plus-2-bit capture** (the NV12 family at depth 10): bit 13, as the vendor does.

**[board]** Do bit 12 and bit 13 behave for AVS2 as they do for H.265?

## 8. Header-side facts used by the uAPI and the test decoder

- **Picture types.** picture_coding_type gives 1 P, 2 B, 3 F; background_pred_flag on a P picture gives S.
- **POC.** poc = DOI if low_delay, otherwise DOI + picture_output_delay − picture_reorder_delay.
  DOI is the 8-bit coi unwrapped across its 256 wrap. The hardware uses poc & 0x1ff.
- **Bit depth.** The vendor stores sample_precision at seq+60 and encoding_precision at seq+64. It
  then computes `internalBitDepth` (seq+36) = 6 + 2·sample_precision and `outputBitDepth` (seq+40) =
  6 + 2·encoding_precision (avs2_parse.c:1129-1146, dis 0x9b18-0x9b98). encoding_precision is read only
  for profile 0x22; otherwise it is 1.
  - REG04 [5:3] and the 10-bit test in Avs2Set10BitReg both read seq+36, so the hardware gets the
    depth from **sample_precision**.
  - davs2 and MPP name these the other way round: sample_precision is the output depth and
    encoding_precision the internal coding depth.
  - The driver follows the vendor. The two values differ only for an 8-bit source coded at 10 bits.
    **[board]** Test such a stream if one can be found or made.
