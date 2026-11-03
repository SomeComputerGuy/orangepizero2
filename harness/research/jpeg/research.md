# H616 VE JPEG decode for cedrus: research notes (W21)

Date: 2026-11-03. Research only. No kernel code here. No downloaded program was built or run.
Abbreviations: `MPEG+x` = VE+0x100+x (MPEG decoder register file). `TOP+x` = VE+x. `JPEG+x` = VE+0xE00+x.
Clean-room: this file records register offsets, bit fields, table layouts and write order only. It
contains no vendor code.

Local material used:

| Short name | Path | Origin / id | Licence |
|---|---|---|---|
| jemk | `harness/research/ve-encoder/dl/jemk-cedrus/jpeg-test/{main.c,jpeg.c}` | github.com/jemk/cedrus, last jpeg-test commit d20f17cb07, restart support 9629b48 (2013) | GPL-2.0-or-later (file headers) |
| wiki | `harness/research/ve-encoder/dl/sunxi-A10_VE.txt` (text dump of linux-sunxi "A10 VE"/VE register guide; the `.wiki` files are 404 stubs) | linux-sunxi.org | CC-BY-SA (wiki) |
| az | `harness/research/ve-encoder/dl/allwinner-zh-media-codec/sunxi-cedarx/SOURCE/plugin/vdecoder/mjpeg/{mjpeg_hal.c,mjpeg_dec_lib.[ch]}` | github.com/allwinner-zh/media-codec a912bbe300 (2015) | LGPL-2.1-or-later (repo LICENSE + headers) |
| lm | `kernel-check/dl-jpeg/linkmauve-cedrus-jpeg-v1/series.mbox` (downloaded for this note) | patchew mbox of `<20240731164422.206503-1-linkmauve@linkmauve.fr>` | GPL-2.0 (kernel patch) |
| vmj | `.../libcedarc-CalvinXu17-a133/library/aarch64-linux-gnu/libawmjpeg.so` (sha256 8d4e96eb42f8bb4a…) | github.com/CalvinXu17/libcedarc e68d4a7270 | proprietary blob, no DWARF (`readelf -S`: no .debug_*) |
| vmjp | same dir `libawmjpegplus.so` (258c265d4f8fa44a…) | same | proprietary, no DWARF |
| vve | same dir `libvideoengine.so`, `libVE.so`; libVE disassembly `kernel-check/dl-vdec/re/libVE.a133.dis` | same | proprietary |
| vk | `harness/research/ve-encoder/dl/vendor-cedar_ve-5.4-sun50iw9/cedar_ve.c` | vendor kernel 5.4 sun50iw9 | GPL |
| k73 | `kernel-check/work-video-patch/linux-7.3.1` (read only) | patched 7.3.1 tree | GPL-2.0 |

My disassembly (objdump only): `/tmp/jpeg-scripts/{mjpeg,plus,videoengine,ve_t527,ve_60}.dis`; table readers
`/tmp/jpeg-scripts/{rdtab,rdpol,rdbytes}.py` (run with `python3 -I`).

---

## 0. Summary

1. **On the H616 the vendor decodes JPEG with the MPEG engine (VE+0x100), not the block at VE+0xE00.**
   - libVE `policy_list` (vve `libVE.so` 0x4930, 21 entries of 24 bytes) has one entry per IC. The H616 entry,
     index 19 `{0x3301000012011, 0, 0, 624}`, has the third field (the JPEG-plus flag) at **0**.
   - libVE `enableDecoder` (`libVE.a133.dis` l.2450, 0x8bfc). For codec 0x101 (MJPEG) the jump table at 0x3822
     sends it to 0x8cd8. If bit `ve_list_num` of mask 0x58600 is set, it ORs `VE_MODE |= 0x20` and keeps
     the low nibble. Otherwise it writes `VE_MODE[3:0] = 0` (MPEG). The mask 0x58600 covers list indices 9, 10,
     15, 16 and 18: 0x1681, 0x1689 and the 0x30111xxxx parts. Index 19 (H616) is clear, so **H616 gets VE_MODE
     mode 0 and no bit 5**.
   - libvideoengine `CreateSpecificDecoder` (vve 0x18e0..0x1a58) compares the plugin name with "mjpegplus". It
     uses `libawmjpegplus` only for ICs (0x1681|0x1689 with ~8), 0x1708, 0x3011100020010/0x3011100021010 (with
     ~0x1000) and 0x3011100021110. The T527 copy also has 0x2111000021210, and the sun60iw2 (A733) copy has
     0x1001000021322 (`orangepi-build/x/{t527,sun60iw2}_…/libvideoengine.so`). **No copy lists 0x3301000012011.**
     The H616 therefore uses `libawmjpeg.so`.
   - `libawmjpeg` gets its base from `GetGroupRegsBase(1)` (vmj 0x1720), and libVE's group table (`libVE.so`
     0x4810) maps group 1 to "Mpeg/2/4" at 0x100. `libawmjpegplus` uses group 6, which is "JPEG" at 0xE00.
   - The vendor kernel's 0xE00 IRQ hook (vk l.373–392, `modual_sel & 0x20`) is compiled in for every
     `CONFIG_ARCH_SUN50I` part. That does not show the H616 has the block.
   - Board read (blikvm-docs `h616-ve-h264-encoder.md` l.443): 0xE00 reads zero "while none of them is
     selected". Nobody has read it with bit 5 set.
   - => **The datasheet-checklist note "VE+0xE00, VE_MODE bit 5" does not match what the vendor does on
     H616.** Build the decoder on the MPEG-engine JPEG path, the same path the A10…H6 parts use. Probing 0xE00 on
     the board is an open question (§7). It is not on the critical path.
2. **There is prior open work.** Emmanuel Gil Peyrot (linkmauve) and Jernej Škrabec posted "[PATCH 0/4] media:
   cedrus: Add a JPEG decoder" on 2024-07-31 (Message-ID `<20240731164422.206503-1-linkmauve@linkmauve.fr>`,
   https://patchew.org/linux/20240731164422.206503-1-linkmauve@linkmauve.fr/).
   - It was tested on A10, A20 and A64.
   - It parses headers in the kernel with `v4l2_jpeg_parse_header()` and exposes `V4L2_PIX_FMT_JPEG` OUTPUT →
     NV12 CAPTURE.
   - It was never merged. On 2025-02-13 Sebastian Fricke asked for a rebase, CI style fixes and a reviewer. On
     2025-02-20 Jernej declined to review because he is a co-author and suggested Paul Kocialkowski
     (https://lkml.iu.edu/hypermail/linux/kernel/2502.2/07933.html).
   - k73 has no `cedrus_jpeg.c`, and an extended web search found no v2.
   - **Recommendation: rebase this series (GPL-2.0, authors credited, Signed-off-by kept) and add the H616
     variant and the fixes in §5. Do not start from scratch.**
3. **uAPI.** There is no stateless JPEG uAPI upstream. k73 `include/uapi/linux/v4l2-controls.h` has only the
   JPEG *compression* class (`V4L2_CID_JPEG_*`, l.1220–1242) and no `V4L2_CID_STATELESS_JPEG*`. All mainline
   JPEG decoders take a whole JFIF in `V4L2_PIX_FMT_JPEG` on OUTPUT and parse it in the kernel: mxc-jpeg, s5p-jpeg,
   mtk-jpeg, coda-jpeg, rcar_jpu. mxc-jpeg and coda use `v4l2_jpeg_parse_header` (k73
   `drivers/media/platform/nxp/imx-jpeg/mxc-jpeg.c` l.1980, `.../chips-media/coda/coda-jpeg.c`). Hantro and
   rockchip_vpu only *encode* JPEG (k73 `verisilicon/rockchip_vpu_hw.c` l.49–52, `HANTRO_MODE_JPEG_ENC`).
   **Your expectation is confirmed: stateful-style, header-parsing m2m decoder, requests not required.**

---

## 1. Prior open code

| Source | What it has | Notes |
|---|---|---|
| jemk `jpeg-test` (2013) | Complete user-space PoC on A10 via `/dev/cedar_dev`: parser, Q/Huffman upload, MPEG engine JPEG trigger, tiled 32x32 output to DEFE | Supports 4:4:4 / 4:2:2 / 4:2:2T / 4:2:0, 3 components, baseline only (`jpeg.c` rejects SOF1..15, DAC). Restart interval added in 9629b48 |
| wiki A10 VE | Register names for MPEG+0xB8 JPEG_SIZE, 0xBC JPEG_MCU, 0xC0 RES_INT, 0xCC/0xD0 ROT luma/chroma, 0xD4 ROTSCALE_CTRL, 0xD8/0xDC MCU_START/END, 0xE0/0xE4 SRAM offset/data; Huffman SRAM map; TRIG color fmt; VE_CTRL bit 5 "Enable JPEG decoder (sun8iw8p1 only)" | `sunxi-A10_VE.txt` l.4300–4420 (TRIG), l.5500–5900 (JPEG regs, Huffman map), l.2855–2867 (bit 5) |
| az `mjpeg_hal.c` (2015, LGPL-2.1+) | Vendor reference sequence for the MPEG-engine path, including the subsampling enum and the default DHT image | Same layout as jemk. Also does 4:1:1 and 4:0:0 |
| lm series (2024, GPL-2.0) | cedrus driver: `cedrus_jpeg.c` (352 lines) and secondary-output setup | See §5 for its gaps |
| libvdpau-sunxi | **No JPEG.** Files: h264.c, h265.c, mpeg12.c, mpeg4.c… (https://github.com/linux-sunxi/libvdpau-sunxi). VDPAU has no JPEG profile | Licence not checked (no LICENSE in the root listing) |
| Bootlin | Not found: no JPEG code in cedrus or libva-v4l2-request | — |
| linkmauve "Onix" | User-space JPEG library that tests the lm driver (lm cover letter, https://linkmauve.fr/dev/linux/cedrus-jpeg/v1/0000-cover-letter.patch) | Not downloaded |
| vmj / vmjp | Current vendor blobs for the MPEG path and the 0xE00 "plus" path | RE notes in §3 |

---

## 2. Kernel helper: `v4l2-jpeg.c` exists in 7.3.1

`k73/drivers/media/v4l2-core/v4l2-jpeg.c`, header `include/media/v4l2-jpeg.h`, Kconfig `V4L2_JPEG_HELPER`.

- **Accepts:**
  - SOF0 and SOF1. SOF1 may be 12-bit (l.294). The decoder must reject precision != 8.
  - DHT, parsed into `huffman_tables[(Tc<<1)|Th]`: index 0 = DC0, 1 = DC1, 2 = AC0, 3 = AC1 (l.474–529). Th > 1
    is -EINVAL, so only 2 table sets are allowed, which is the baseline limit.
  - DQT, giving `quantization_tables[0..3]`, with references in **stream (zigzag) order**.
  - DRI, giving `restart_interval`.
  - APP14, giving the Adobe transform.
  - SOS, giving `scan` and `ecs_offset`, and it stops at the ECS.
  - RSTn, SOI and EOI pass through, and unknown segments are skipped.
- **Rejects** SOF2/3 (progressive, lossless), SOF5–7, SOF9–15 and DAC with `-EINVAL` (l.640–648). Progressive
  and arithmetic-coded files are refused before they reach the hardware.
- It does not check that the scan covers all components. The driver must check `scan->num_components ==
  frame.num_components`, because a non-interleaved multi-scan baseline file is legal JPEG and the HW cannot
  decode it.

---

## 3. Register map and programming sequence (MPEG-engine JPEG path, the one the vendor uses on H616)

### 3.1 VE top

| Reg | Value for JPEG | Source |
|---|---|---|
| TOP+0x00 VE_MODE | `[3:0] = 0` (DEC_MPEG). Keep the DDR field (H616 `VE_MODE_DDR_MODE_BW_256`) as for the other codecs. **Bit 5 is not set on H616.** | libVE enableDecoder 0x8cd8/0x8cf4 + policy_list idx 19; lm patch 2 (`cedrus_engine_enable`: JPEG shares the MPEG mode) |
| TOP+0xC4 PRIMARY_CHROMA_BUF_LEN, 0xC8 PRIMARY_FB_LINE_STRIDE, 0xCC SECONDARY_FB_LINE_STRIDE (luma[15:0], chroma[31:16]), 0xE8 CHROMA_BUF_LEN (SDRT len [27:0], bit 28 luma-width-align-32, bit 29 chroma-width-align-8, [31:30] = 1 "EXT"), 0xEC OUT_FMT (primary [6:4], secondary-ext [2:0]: 0 tiled32 NV12, 1 tiled128, 2 YU12, 3 YV12, 4 NV12, 5 NV21) | For linear output, write the **secondary** set as well. Jernej, lm patch 1: "It's needed for JPEG codec, since engine outputs to it for some reason." | lm patch 1; k73 `cedrus_regs.h` l.79–107; vmj JpegHwDec 0x43b4–0x4520 |

Vendor `libawmjpeg` JpegHwDec on newer ICs (`nIcVersion > 0x1638`) uses four mode flags (JpegDec struct
offsets 2040/2044/2048/2052, names unknown):

- TOP+0xC4 is set from a context value, TOP+0xC8 and TOP+0xCC from luma/chroma strides, and TOP+0xE8 from
  `[29]=1, [28]=0, [31:30]=1, [27:0]=chroma len`.
- TOP+0xEC is set to primary=secondary=**5 (NV21)**, or to **3 (YV12)** in one mode. In the "secondary only"
  mode the vendor sets primary=0 (tiled) and secondary-ext=5.

So linear NV21/NV12/YV12 output works on this path. NV12 is just the 4 code (cedrus already uses it).

### 3.2 MPEG engine registers used for JPEG

| Off (MPEG+) | Name (wiki / lm) | Field use | Source |
|---|---|---|---|
| 0x14 | CTRL | IRQ enables: bit 3 finish, 4 error, 5 VLD-data-request (`IRQ_MASK` = 0x38); the vendor ORs 0x7c (bits 2–6). **Bit 18 `JPEG_FORCE_420`**: the vendor sets it for 4:2:2 and 4:4:4. lm also sets it for 4:2:2T. Bit 8 `ROTATE_SCALE_OUT_EN` with bit 7 `MC_NO_WRITEBACK`: the vendor writes **0x180 or 0x40180** on newer ICs | vmj 0x4388–0x43b0 (`csel 0x180 / 0x40180` on `fmt-2 <= 1`); az `set_internal_intr_enable_bits`; lm |
| 0x18 | TRIGGER | [26:24] = 3 JPEG; [29:27] chroma fmt (0 = 420, 1 = 411, 2 = 422, 3 = 444, 4 = 422T, 5 = 400); [3:0] = **0xE `HW_JPEG_VLD`** starts the decode. The vendor writes byte 3 first (`(fmt<<3)|3`) in init, then byte 0 = 0x0E at start | k73 `cedrus_regs.h` l.207–232 (already has `TRIGGER_JPEG`, `HW_JPEG_VLD`, `CHROMA_FMT_422T`); az; vmj 0x3fa0 (`strb [base+27]`) and 0x4280 (`strb 0xe,[base+24]`) |
| 0x1C | STATUS | bit 0 success, 1 error, 2 VLD data req (write 1 to clear; the vendor ORs 0xF). JPEG-specific: bit 19 `JPEG_MARKER`, 20 `JPEG_RESTART_ERROR`, 21 `JPEG_BIT_END` | k73 `cedrus_regs.h` l.246–275; vmj 0x4360 |
| 0x28 | VLD_ADDR | `phys[27:4] \| phys[31:28]>>28 into [3:0]`, plus bits 28/29/30 valid/last/first (= 0x7 << 28) | k73 `VE_DEC_MPEG_VLD_ADDR_BASE`; vmj 0x4320 |
| 0x2C | VLD_OFFSET | **bit** offset of the ECS from the buffer start (`ecs_offset*8`) | az/vmj (`(data-vbvBase)<<3`); lm |
| 0x30 | VLD_LEN | length in **bits**. The vendor uses `nFrameSize<<3`, lm uses `payload*8` | vmj; lm |
| 0x34 | VLD_END | last byte of the bitstream buffer: vendor `vbvBase+vbvSize-1`, jemk `buf+alloc-1`, lm `src+size` (no -1) | vmj InitJpegHw tail 0x40b8; jemk main.c |
| 0x80 | IQ_MIN_INPUT (k73 `VE_DEC_MPEG_IQMINPUT`) | 64 writes per table: `[13:8]` index i (0..63, **stream/zigzag order**, as in DQT), `[7:0]` q (8-bit only), **bit 14 = 1 for the luma table** (`IQMINPUT_FLAG_INTRA`), 0 for chroma. Order: luma 64 then chroma 64 | az InitJpegHw; vmj 0x3fd8–0x4040 (ORs `0x4000` on the first loop); jemk uses (64+i)/i, the same thing |
| 0xB8 | JPEG_SIZE | `[31:16]` MCU rows − 1, `[15:0]` MCU cols − 1, with MCU = 8·Hmax × 8·Vmax. Wiki: 16-bit fields. lm masks [26:16]/[10:0] | wiki l.5508; az; vmj 0x4058–0x4090 |
| 0xBC | JPEG_MCU | unknown, not written | wiki |
| 0xC0 | JPEG_RES_INT | DRI value (0 = none); the HW handles RSTn itself | wiki l.5575; jemk 9629b48; az; vmj `[base+192]` |
| 0xC4 | ERROR | — | k73 |
| 0xCC / 0xD0 | ROT_LUMA / ROT_CHROMA | **The decoded output goes to the rotate/scale buffers**, not REC_LUMA/CHROMA (0x48/0x4C) | wiki; jemk; az; vmj `[base+204]/[base+208]`; lm |
| 0xD4 | SDROT_CTRL | 0 = no rotate/scale. The vendor writes `((rot \| scale<<2) << 8)` (rotation and 1/2…1/8 downscale exist; ratio encoding not decoded) | az; vmj 0x4094 |
| 0xD8 / 0xDC | JPEG_MCU_START / END | unknown, unused (maybe partial/tiled decode) | wiki |
| 0xE0 / 0xE4 | SRAM_RW_OFFSET / DATA | Huffman upload: write offset 0, then 512 32-bit words to DATA (auto-increment) | wiki l.5833–5873; az FillJpegHuffmanTable; jemk |

### 3.3 Huffman SRAM image (2 KiB = 512 words, little-endian words)

The layout below is from wiki l.5859–5873 and was checked against the jemk, az and lm code.

- Bytes 0–255 hold 4 tree descriptors of 64 bytes each, in the order **Y-DC, Y-AC, C-DC, C-AC**.
  Each descriptor has three parts:
  - 16 × u16 `first_code[len]`: the canonical first code for each length 1..16. Start at code=0; for each
    length store code, then do `code += BITS[len]; code <<= 1`. Lengths after the last non-empty one are 0xFFFF.
  - 16 × u8 `offset[len]`: the running count of symbols before this length.
  - 16 bytes of zero.
- Bytes 256–1023 are zero.
- Bytes 1024–2047 hold 4 × 256-byte HUFFVAL arrays (Y-DC, Y-AC, C-DC, C-AC), each zero padded.
- **Only 2 table sets exist.** The Y tables come from scan component 0 and the C tables from scan component 1.
  **Cr must use the same DC/AC tables as Cb** (az picks `seqCompId[0]` and `[1]`).
- If the file has no DHT (MJPEG from webcams, the "AVI1" case), the vendor uploads the Annex K default tables.
  The az `DhtDefault[]` holds that precomputed image. In-kernel, use the `v4l2_jpeg_ref_table_*_ht` exports in
  k73 v4l2-jpeg.c l.106–169.

lm has a bug: in the HUFFVAL tail (`length & 3`) it builds `val` big-endian from the end. When the tail has 2–3
bytes this gives the reverse byte order of the u32 path. Check this against the layout above when rebasing.

### 3.4 Quantisation limits

- **Only 2 quant tables**: luma (component 0) and chroma (component 1). A JPEG whose Cr uses a third table
  different from Cb's is legal but cannot be decoded. Reject it, or accept with the error documented.
- 16-bit DQT (Pq=1) is not allowed in baseline 8-bit. The vendor parser keeps it, but the 8-bit field would
  truncate it, so reject it. (lm packs 16-bit values into [7:0], which is wrong. Reject instead.)

### 3.5 Decode sequence (write order: vendor libawmjpeg InitJpegHw + JpegHwDec, matches az/jemk/lm)

1. VE_MODE: mode 0 (MPEG), with the DDR bits as the variant needs.
2. MPEG+0xC0 ← restart_interval.
3. MPEG+0x18 byte 3 ← `(fmt<<3) | 3` (JPEG + chroma format).
4. MPEG+0x80 × 64 luma (bit 14 set), then × 64 chroma.
5. MPEG+0xCC/0xD0 ← output luma/chroma DMA addresses.
6. MPEG+0xB8 ← MCU rows/cols − 1.
7. MPEG+0xD4 ← 0 (no rotate/scale).
8. MPEG+0xE0 ← 0, then MPEG+0xE4 × 512 Huffman words.
9. MPEG+0x34 ← end address.
10. TOP output registers 0xC4/0xC8/0xCC/0xE8/0xEC for linear output (§3.1). MPEG+0x14 ← IRQ enables (0x38 or
    0x7c) | ROT_SCALE_OUT_EN/no-writeback (0x180) | FORCE_420 (bit 18) as needed.
11. MPEG+0x2C ← bit offset, MPEG+0x30 ← bit length, MPEG+0x28 ← address | 0x7<<28.
12. MPEG+0x18 byte 0 ← 0x0E (in cedrus: a full 32-bit write of `HW_JPEG_VLD | JPEG | fmt`, as lm does).
13. IRQ: STATUS bits 0..2. Clear by writing 1s (the vendor ORs 0xF). Disable via CTRL `&= ~0x38`. These are the
    same as the MPEG-2 `irq_*` ops already in cedrus.

### 3.6 Output formats and subsampling

- Supported subsampling: 4:2:0 (fmt 0), 4:1:1 (1), 4:2:2 (2), 4:4:4 (3), 4:2:2T/"vertical" (4), 4:0:0
  grayscale (5). Source: vmj SetJpegFormat 0x3ab0 compares sampling words 0x211111, 0x221111, 0x121111,
  0x411111, 0x111111 and 0x110000, and maps them to 2/0/4/1/3/5. The az enum gives the same mapping.
  lm only does the 3-component formats 420/422/444/422T.
- FORCE_420 (MPEG+0x14 bit 18) makes the engine write 4:2:0 for 4:2:2/4:4:4 input. That gives NV12 for all
  colour inputs.
  - lm cover letter: A10/A20 can only downscale 4:4:4→4:2:2, and newer SoCs can do more.
  - The vendor also ships `MjpegTransformPlanner422To420` (a software path) for the case where the HW outputs
    4:2:2.
  - Which chroma filter FORCE_420 uses (drop or average) is unknown.
- Output layout:
  - Tiled 32x32 NV12 (`V4L2_PIX_FMT_NV12_32L32`) goes through the primary/ROT path (jemk `output_ppm` shows the
    32×32 macro-tile addressing).
  - Linear NV12/NV21/YV12 come through the TOP secondary-output registers (§3.1).
  - **Yes, the linear/secondary output works on this path** (lm patch 1; the vendor uses NV21/YV12 on newer
    ICs). Stride: the vendor forces 16-byte alignment for MJPEG (`vdecoder.c` l.505–518: "mjpeg decoder just
    support 16-align").
- Grayscale: what the HW writes to the chroma plane in fmt 5 is unknown. Expose GREY or NV12 with a fixed
  chroma plane after testing on the board.

### 3.7 Limits

- Baseline only (SOF0, and SOF1 at 8 bit). No progressive (az/jemk/v4l2-jpeg all refuse SOF2) and no arithmetic
  coding.
- Only interleaved single-scan files.
- Max size:
  - The vendor `vdecoder.c` l.498 rejects any stream larger than 6144x3840 for all codecs.
  - JPEG_SIZE fields are 16-bit per the wiki, and lm assumes 11 bits and caps at 2048x2048.
  - VE_MODE bits 21/22 (`PIC_WIDTH_MORE_2048` / `IS_4096`) exist (k73 `cedrus_regs.h` l.50–51). Whether the
    JPEG path needs them is unknown.
  - **The 4096x4096 target has to be checked on the board.** If the HW limit is lower, the MCU_START/END
    registers (0xD8/0xDC) may allow decoding in strips (unknown).
- Throughput spec: 45 MPPS. That is ~21.7 fps at 1920x1080 and ~0.37 s for 4096x4096.

### 3.8 The 0xE00 "JPEG plus" engine (not used by the vendor on H616; for reference and the board probe)

- vmjp writes JPEG+0x14 CTRL `|= 0x38`, +0x18 trigger byte = 0x0E, +0x1C STATUS `|= 0xF`, +0x28/+0x2C/+0x30 VLD
  address/offset/length (vmjp JpegHwDecPlus 0x4eb8–0x4ff8).
- It also writes +0x20/+0x24 (a 40-bit address: `ubfx #32,#8` and the low word) on some ICs, and has a
  `Tile_Mode_Decode` path for large pictures.
- InitJpegHwPlus (0x4960) uses offsets 0x00–0x10, 0x40–0x6C, 0xB4–0xD4. So it is an MPEG-engine-style
  register file with extensions. It is not a plain clone, and mapping it fully would need more RE.
- vk IRQ: status at JPEG+0x1C bits [2:0], enables at JPEG+0x14 bits [5:3] (vk l.377–391).
- VE_MODE bit 5 selects it (wiki l.2867, vk).

### 3.9 Older SoCs

The same MPEG-engine path (mode 0, MPEG+0xB8..0xE4) is used from A10 (jemk, lm tests) to A64/H5/H6. The vendor
uses the plus engine only on 0x1681/0x1689 (V3/V3s class), 0x1708 and the 0x30111/0x21110-class ICs, plus the
T527/A733 entries above. The A13 has no JPEG per its manual (lm patch 3). The vendor code uses old SDRAM
addressing on ICs ≤ 0x1638 and skips the TOP secondary-output writes on them (vmj 0x43b4 `cmp 0x1638`).

---

## 4. uAPI decision

Expose a header-parsing m2m decoder, as mxc-jpeg does:

- OUTPUT queue: `V4L2_PIX_FMT_JPEG`, one complete JFIF per buffer.
- CAPTURE queue: `NV12` (linear, via secondary out) and `NV12_32L32`. Later NV21, YV12/YU12 (`YUV420`), and
  maybe GREY.
- Requests are not required: lm patch 4 sets `requires_requests = false`. That has to become per-codec, so the
  stateless codecs keep `requires_requests`.
- In `setup()`, `v4l2_jpeg_parse_header` reads SOF/DHT/DQT/DRI/SOS and `ecs_offset`.
- A real stateful-JPEG implementation should resolve the CAPTURE size at runtime. mxc-jpeg emits
  `V4L2_EVENT_SOURCE_CHANGE` (mxc-jpeg.c l.778, l.2747). lm instead relies on userspace setting the OUTPUT width
  and height, and its cover letter notes that "the driver can't know the JPEG's subsampling when formats are
  enumerated".
- **Minimum:** check that the parsed size fits the CAPTURE buffer and fail the job otherwise. **Better:**
  mxc-jpeg-style source-change handling.
- No new controls are needed. `V4L2_CID_JPEG_*` are encoder-oriented.

---

## 5. What to change when rebasing lm onto our tree

1. Add `CEDRUS_CAPABILITY_JPEG_DEC` to `sun50i_h616_cedrus_variant` (k73 cedrus.c l.1029). Mode 0 already fits
   `.ve_mode_ddr = BW_256`. lm patch 3 predates the H616 variant.
2. Patch 1 (secondary output) conflicts with our `cedrus_hw.c` l.160–201, which already writes the
   secondary/EXT registers for other uses (AFBC/10-bit). Merge it per format.
3. Add 4:1:1 and 4:0:0. Reject `num_components` other than 1 or 3, multi-scan files, Cr tables that differ from
   Cb's (quant or Huffman), and Pq=1. Use the default Huffman tables when the file has no DHT (MJPEG).
4. Remove the 2048 cap after board tests, and use 16-bit MCU fields if the HW accepts them.
5. Fix the Huffman tail byte order (§3.3). Set VLD_END to the buffer end − 1 rather than src+size (the vendor
   and jemk both do this).
6. Make `requires_requests` per codec.
7. CAPTURE size and format checks (§4).

---

## 6. Test plan inputs

### 6.1 Reference decoder

- No host PIL (`import PIL` fails), no cv2, no djpeg/cjpeg, no libjpeg headers.
- Available: ffmpeg (`/usr/bin/ffmpeg`, encoder pix_fmts yuvj420p/422p/444p, decoder `-idct` auto|int|simple),
  ImageMagick 7.1.2-31 (jpeg delegate), `libjpeg.so.8` (runtime only), numpy 2.4.6.
- Reference planes: `ffmpeg -idct int -i x.jpg -f rawvideo -pix_fmt <native yuvj*> ref.yuv`. ffmpeg's "int"
  is IJG `jrevdct` (the islow family), and with native pix_fmt there is no colour conversion or resampling.
  Compare YCbCr planes, not RGB.

### 6.2 Bit-exactness

- There is no evidence the VE matches libjpeg islow.
- The JPEG path runs through the shared MPEG IQ/IDCT units (wiki MPEG_STATUS IQIS/IDCT bits l.4445–4485), which
  are built for MPEG-2's IEEE-1180 IDCT.
- The wiki notes a ±1 rounding difference against libjpeg on the encoder side (l.10420).
- **Assume it is not bit-exact.**
- Acceptance (proposed):
  - Luma: max |Δ| ≤ 2 and PSNR ≥ 48 dB against the islow reference.
  - Chroma, native subsampling: the same thresholds.
  - Chroma with FORCE_420: compare against the reference chroma decimated 2:1, with the filter fixed after the
    first board run and the tolerances widened.
  - Bit-for-bit repeatability over 10 runs, then freeze golden md5s per vector.

### 6.3 Vectors

Generate them on the host with a small numpy baseline JPEG *writer* in `harness/research/jpeg/`, run with
`python3 -I`. ffmpeg cannot emit DRI/RST, 4:1:1, 4:2:2T, separate Cr tables or no-DHT files on demand, which is
why a writer is needed. ffmpeg/ImageMagick can generate the common cases.

| # | Case | Purpose |
|---|---|---|
| 1 | 4:2:0, 4:2:2, 4:4:4, 4:2:2T, 4:1:1, gray 4:0:0 at 1920x1080 | format matrix |
| 2 | DRI = 1, 7, MCU-row; also a stream with a corrupt RST (expect STATUS bit 20) | restart |
| 3 | sizes 1x1, 7x9, 17x33, 1921x1081, 2047/2048/2049 wide, 4095/4096 | odd sizes, MCU padding, limits |
| 4 | 4096x4096 4:2:0, and 6144x3840 | max size, throughput (target ≥ 45 MPPS: time 100 decodes) |
| 5 | no DHT (MJPEG/AVI1), DHT after DQT, multiple DHT segments, Cb≠Cr quant table, Pq=1, 12-bit SOF1, progressive SOF2, non-interleaved scans | must decode or be cleanly rejected |
| 6 | Real camera/USB-webcam MJPEG frames (the BliKVM capture use case) | real-world |
| 7 | Truncated ECS, garbage after EOI | error/timeout handling |

---

## 7. Open questions (need the board)

1. Does the H616 implement the 0xE00 engine? Probe: set VE_MODE bit 5, write and read back JPEG+0xC0 or +0x14,
   then clear. Read only, no decode. Low priority; the vendor never uses it on H616.
2. Max width/height on the MPEG-JPEG path. Are the JPEG_SIZE fields 11 or 16 bits? Does it need VE_MODE bits
   21/22 above 2048/4096?
3. What does FORCE_420 do to 4:2:2T and 4:1:1, and which chroma filter does it use? Without FORCE_420, does the
   H616 write true 4:2:2/4:4:4 (giving NV16/NV24)?
4. What goes into the chroma plane for grayscale (fmt 5)?
5. The vendor's MPEG CTRL 0x180 (ROT_SCALE_OUT_EN | MC_NO_WRITEBACK) on new ICs versus lm's IRQ-only value. Which
   one the H616 needs for linear output.
6. Unknown fields (JpegDec offsets 2040/2044/2048/2052/1956) that choose between primary-tiled, secondary-NV21
   and YV12 output. Board tests across 0xEC values will settle this.
7. MCU_START/END (0xD8/0xDC) and JPEG_MCU (0xBC): partial decode? Not needed for v1.
