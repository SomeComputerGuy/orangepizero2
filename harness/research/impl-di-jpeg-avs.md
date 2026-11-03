# H616 video blocks with no driver: DI300, VE JPEG decode, AVS/AVS+ decode

Goal: the three datasheet rows in docs/datasheet-checklist.md that have no driver on the Zero2:
- §2.5.2 De-interlacer (DI): checklist item W13.
- §2.4.1 JPEG decode ("JPEG HFIF up to 45 MPPS"): W21.
- §2.4.1 AVS/AVS+ JiZhun 1080p60: W20.

Branch `feat/sunxi-h616-di-jpeg-avs` (worktree `wt-video-new`, based on `stonking-orangepizero2` at `cf62ac65a`), pushed to
`fork`. Each feature has its own patch block in `series.conf`, after the `h616-vdec` block:
`patches.media/h616-di/`, `patches.media/h616-jpeg/`, `patches.media/h616-avs/`.

Build trees:
- `kernel-check/scratch-video/linux`: git tree with one commit per patch. The base commit is the `cf62ac65a` series (749 patches).
- `kernel-check/work-video/linux-7.3.1`: the incremental ccache build tree. It is a copy of the built `work-board` tree,
  resynced to the base sources.
- `kernel-check/work-video-patch`: the `STAGE=patch` check tree.

**Nothing in this file has run on the board yet.**

---

## 1. De-interlacer (DI300)

### 1.1 Sources

| source | what it gave |
|---|---|
| Jernej Škrabec, github.com/jernejsk/linux-1 branch `h616-deinterlace-v1` (tip `0e02a5c7f`, the DI commits are `cb3d14a9b..b4cc0dbd1`), clone in `kernel-check/dl-di/jernej-linux` | The driver: V4L2 m2m, binding, DT node, FMD statistics and per-job weave control. Unposted; the later commits carry no Signed-off-by. His commit messages say he tested it on hardware with FFmpeg `deinterlace_v4l2m2m` and v4l2-compliance. |
| Vendor BSP 5.4 `drivers/char/sunxi-di/drv_div3x` (orangepi-xunlong/linux-orangepi `orange-pi-5.4-sun50iw9`), copied to `kernel-check/dl-di/vendor-5.4` | The full register map (`di300_reg.h`), the per-mode settings (`di300.c` `di_dev_apply_fixed_para`, `di_client.c` `di_client_reset`), the TNR tuning and the adaptive gain (`di300_alg.c`). |
| libcedarc `openmax/vdec/src/omx_deinterlace.cpp` (`harness/research/ve-encoder/dl/libcedarc-CalvinXu17-a133`), the only vendor user | Which frame goes in which input slot (`diSetPara`), the formats (NV12 in, YV12 out), and the TNR feedback scheme (the diagram in `__DiProcess3`). |
| Vendor DT `kernel-check/dl-vdec/bsp/sun50iw9p1.dtsi` l. 1767 | `deinterlace@1420000`, reg size 0x40000, SPI 89, IOMMU master 1. This matches Jernej's node. |
| Mainline `sun8i-di` | Not the same IP (H3/A64). Used only as m2m precedent: both outputs carry the source timestamp, and history is kept in the driver. |

### 1.2 What was wrong or missing in the imported driver

1. **Input slot order.** In 60 Hz mode the vendor fills `in_fb0` (→ IN_F0, `dma_di`) with the frame before last, `in_fb1` (IN_F1)
   with the previous frame, and `in_fb2` (IN_F2) with the newest. The DIT outputs fields 2/3, which come from IN_F1, and the TNR filters IN_F2.
   Jernej's driver put the newest frame in IN_F0 and the oldest in IN_F2: the same middle frame, but the motion neighbours
   reversed. Fixed to the vendor order. **[board] D3** decides it.
2. **Planar chroma.** For YUV420 and YUV422P the driver used the luma stride for the chroma field pitch and the bottom-field
   offset. The vendor uses `cstride` (half). Fixed. YV12 (`YVU420`), the format the datasheet lists, was missing; added.
3. **Limits.** Were 2x2..2048x1200. The datasheet says 32x32..2048x1280. The height is now a multiple of 4 (whole chroma lines per
   field) and bytesperline is 16-aligned.
4. **Motion flag buffers.** A fixed 512 B pitch. The driver swapped only the DMA handles, so after an odd number of runs
   `dma_free_coherent` got a mismatched (cpu, dma) pair. Now sized like the vendor: pitch = ALIGN(2·w bits, 256)/8, h lines. An index toggles between the two buffers.
5. **Second output.** Got no metadata. It now gets the source metadata plus half a frame interval.
6. **Modes.** Only motion-adaptive field rate existed. Weave, bob, frame rate and TNR were missing.
7. Kept as Jernej wrote them: FMD raw statistics (10 × u32, read-only volatile control), the FMD enable, the per-job weave
   control (bound to a request), and the 300 MHz exclusive module clock (the datasheet needs 150 MHz for 1080p60).

### 1.3 Design (our two patches on top of Jernej's twelve)

- `media-sunxi-sun50i-di300-fix-input-order-planar-form.patch`: items 1-5 above.
- `media-sunxi-sun50i-di300-add-weave-bob-frame-rate-an.patch`: modes, TNR, VOF, capture format conversion.

`V4L2_CID_DEINTERLACING_MODE` (standard control, driver menu). It is grabbed while streaming because it decides the buffer handling.

| value | name | inputs (DMA_CTL) | output | DIT_SETTING | history | out/in |
|---|---|---|---|---|---|---|
| 0 | Motion Adaptive, Field Rate (vendor 60 Hz) | F0 = n-2, F1 = n-1, F2 = n (DI\|P\|C) | DIT0 + DIT1 | 0,4,16,20, diag | 2 | 2 |
| 1 | Motion Adaptive, Frame Rate (vendor 30 Hz) | F1 = n-1, F2 = n (P\|C) | DIT1 | 0,4,16, 24 (1-frame) | 1 | 1 |
| 2 | Bob | F1 = n (P) | DIT1 | 0,16, 24 | 0 | 1 |
| 3 | Weave | F1 = n (P) | DIT1 | 24 only | 0 | 1 |
| 4 | Noise Reduction Only (only if FUNC_VSN tnr_exist) | F1 = n-1, F2 = n (P\|C), MD + TNR, no DIT | TNR channel | n/a | 1 | 1 |

- Motion detection (FUNC_EN MD, DMA FR|FW) is on when a real previous frame exists. The first run of a stream is spatial (bob-like)
  in every motion mode, as in Jernej's warm-up rule.
- **Lag.** The motion modes deinterlace F1, i.e. one frame behind the input. Each input still yields its outputs at once,
  so synchronous clients don't stall. The first frame is output twice and the last frame never; the timestamps are those of the
  source buffer (as in sun8i-di). Weave, bob and TNR-only have no lag.
- **TNR** (`V4L2_CID_SUNXI_DI300_TNR_MODE`: off, fixed, adaptive; `TNR_STRENGTH` 0-255, default 0x3a; `TNR_LEVEL` high/middle/low,
  which sets the adaptive bounds 52-62 / 28-48 / 16-38).
  - Writes the vendor's fixed tuning at resume (0x240-0x2ac).
  - In the motion modes the filtered newest frame T(n) goes to one of 3 driver buffers (planar I420/422P). T(n-1) and T(n-2)
    replace the raw frames as F1/F0, which is the vendor's recursive scheme (omx_deinterlace.cpp diagram), so the DIT output is
    the filtered frame.
  - In TNR-only mode the reference is the previous *raw* frame (non-recursive). This is a choice, because the capture buffer
    can't be kept as a reference.
  - Adaptive gain = the vendor `di_alg_tnr_strengths_adjustment`: gain = (weight + 31·gain)/32, clamped, with weight from
    SUM_GAIN_Y/CNT and SUM_STILL_OUT. The 128-bit intermediate (`mul_u64_u64_div_u64`) fixes the vendor's u64 overflow.
    There is no scene-change input (that comes from the vendor's FMD software algorithm).
  - The datasheet allows TNR output only as YV12 or planar 422, and the vendor requires planar DIT output with TNR. So TNR is
    active only with a planar capture format.
- **Capture format.** Any supported format with the source's chroma subsampling (separate IN/DIT/TNR format fields, as in
  vendor NV12 → YV12). Semi-planar in and out must match, because one UVSEQ bit covers both.
- **FMD/VOF.** In field-rate mode with FMD on, FMD_GLB = VOF_EN | VOF_BUF_SEL toggling each run (vendor). The FMD_WEAVE elements
  gain bit 2 (video_exist: keep video blending in video-on-film areas) and bit 3 (chroma weave). 0-3 keep Jernej's meaning.
  Cadence detection stays in userspace. The vendor's ~1500-line `di300_alg.c` state machine is not ported.

Not done (and why):
- Multi-context VOF state save/restore. The vendor copies the 4 × 0x140 VOF SRAM at +0x10000 via BIST mode per client. One
  stream at a time is fine; two interleaved FMD streams would mix VOF history.
- The demo-window bits (DIT_SETTING 8-10, vendor sets them to 1 with a zero window). Left 0, as Jernej has it; **[board] D9**.
- Crop windows other than the full frame.

### 1.4 Build status (host)

| check | result |
|---|---|
| `git am` of Jernej's 12 patches on the cf62 base | clean, authorship kept (`From: Jernej Skrabec`, his messages verbatim) |
| `STAGE=patch` (`ARMBIAN=wt-video-new`, `WORK=kernel-check/work-video-patch`) | **763 applied, 0 failed** (`kernel-check/run-video-di-patch.log`). The sunxi media dir and the h616 dtsi are identical to the scratch tree. |
| `W=1` on `drivers/media/platform/sunxi/sun50i-di300/` and `drivers/iommu/` | no warnings from the touched files (the only one is the existing `sun55i-iommu.c:577`, an untouched file) |
| `make dt_binding_check DT_SCHEMA_FILES=media/allwinner,sun50i-h616-deinterlace.yaml` | example validates. `dt-check-style` is skipped because the host lacks `ruamel.yaml` |
| `make CHECK_DTBS=y allwinner/sun50i-h616-orangepi-zero2.dtb` | no deinterlace warnings |
| DT_CHECK: decompiled Zero2 DTB | `deinterlace@1420000`, clocks 0x20/0x1f (CLK_BUS_DEINTERLACE/CLK_DEINTERLACE), reset 2, SPI 89, `iommus = <&iommu 1>` |
| Config | `CONFIG_VIDEO_SUN50I_DI300=m` added to `config/kernel/linux-sunxi64-edge.config` |
| Full incremental `Image modules dtb` in `work-video` (ccache) | exit 0, 5 min, no new warnings; Image md5 `4740fbc9138ff2801a0e9b670c398b31`, `sun50i-di300.ko` built |
| Branch | `feat/sunxi-h616-di-jpeg-avs` commit `0fec35361`, pushed to `fork` |

### 1.5 Test tools (host-built, nothing third-party on the board)

- `harness/di300test/di300test` (MIT, static aarch64): MMAP m2m client. It does all formats, `-m field|frame|bob|weave|tnr`,
  TNR/FMD/weave controls, `-c weave` (each output must equal its input, byte for byte), `-c keep` (finds which input
  frame/field survives unchanged in each output, i.e. measures lag, slot order and field order), `-r N` throughput,
  `-v` timestamps and FMD statistics.
- `harness/di300test/gen.py` (numpy): `moving` writes a ground-truth progressive sequence at field rate plus the interlaced
  frames woven from it (TFF/BFF). `telecine` writes 24p film plus a 3:2 pulldown.
- `harness/di300test/psnr.py`: luma PSNR against the ground truth with an offset search.
- Host sanity references on `gen.py moving 720 576 30` (I420): FFmpeg `yadif=1` 40.22 dB, `bwdif=1` 37.28 dB (best offset 0).
  DI300 field-rate output should land in the same range. It isn't expected to be bit-exact with either.

### 1.6 Board test plan (DI)

Prerequisites:
- The kernel from this branch (`work-video` Image + modules + dtb, or the normal build), `di300test`, `gen.py` output
  (made on the host, copied over), and v4l2-compliance (already on the image).
- Formats are converted on the host with ffmpeg (`-pix_fmt nv12/nv21/yuv420p/nv16/yuv422p`; YV12 = yuv420p with the U/V planes swapped).

| # | test | pass | answers |
|---|---|---|---|
| D1 | `dmesg`, `/sys/kernel/iommu_groups`, `v4l2-ctl -d /dev/videoN --all --list-ctrls-menus`, `v4l2-compliance -d /dev/videoN` | probe OK, IOMMU group for 1420000.deinterlace, FUNC_VSN shows FMD/TNR controls, no compliance failures | binding, clocks, IOMMU master 1, has_tnr/has_fmd (`FUNC_VSN` value: read at probe, add `devmem`/debug print if needed) |
| D2 | weave, all 7 formats, 720x576 + 32x32 + 2048x1280: `di300test -m weave -c weave` | **every output byte-identical to its input** | exact field reconstruction (the datasheet's weave method), plane layouts, pitches, the limits |
| D3 | `-m field -c keep` on `gen.py moving` | the kept field of out 2k/2k+1 is the top/bottom field of in k-1 (lag 1), ~100% exact lines | slot order (F1 is output) and field order. If the kept fields come from k-1 but motion artefacts are bad, retry with the old slot order (swap F0/F2) and compare PSNR (D4) |
| D4 | `-m field`, `-m frame`, `-m bob` on `moving` 720x576 and 1920x1080 TFF and BFF, then `psnr.py` against the truth | field ≥ ~37 dB (yadif/bwdif range), frame/bob plausibly lower | motion-adaptive quality, BFF handling |
| D5 | throughput: `-m field -r 20` 1920x1080 NV12 (and 2048x1280) | ≥ 60 outputs/s (datasheet: 1080p60 at 150 MHz; we run 300 MHz) | performance row |
| D6 | TNR: `moving` + added noise (gen with noise, or ffmpeg `noise=alls=12:allf=t`), `-m field -F yv12 -t fixed`, `-t adaptive -l 0..2`, `-m tnr -F yv12` (progressive input) | PSNR against the clean truth improves with TNR on; adaptive stays within its bounds | TNR block, out_tnr channel, recursive references, the adaptive loop |
| D7 | NV12 → YV12 and NV16 → 422P conversion (`-f nv12 -F yv12 -m weave -c keep`) | 100% lines | separate IN/DIT format fields |
| D8 | FMD: `gen.py telecine`, `-m field -z -v` | FID/FRD counters show the 5-field 3:2 cadence; then with `-w` phases from a userspace detector, the woven outputs equal the film frames (luma exact; with bit 3 chroma too) | film-mode detection, field weave phases, VOF registers |
| D9 | if D2-D4 show edge or flat-area oddities: set DIT_SETTING bits 8-10 (demo window enables) as the vendor does | n/a | demo-window semantics |
| D10 | error paths: streamoff mid-stream, 2 contexts interleaved (one weave, one field), mode change while streaming (must be EBUSY) | no hang, buffers return | m2m bookkeeping |

Open register questions:
- Slot order (D3).
- FUNC_VSN on the H616 (TNR/FMD present?).
- DIT1 as the 1-frame output.
- TNR pitch/format with NV12 input.
- The demo-window bits.
- The MD flag buffer pitch. Ours is `ALIGN(2w,256)/8`, the vendor TODO formula is `((w+127)>>2)&~31`. They agree at 720, 1920 and 2048 (192/480/512).

---

## 2. JPEG decode in the VE (cedrus)

### 2.1 Sources and engine choice

- Research: `harness/research/jpeg/research.md` (register map §3, uAPI §4, rebase list §5, test inputs §6).
- **Engine:** on the H616 the vendor (`libawmjpeg` JpegHwDec) decodes baseline JPEG in the **MPEG engine (VE+0x100,
  VE_MODE mode 0)**, with JPEG registers at MPEG+0xB8..0xE4. The VE+0xE00 "JPEG plus" block that the checklist names
  (VE_MODE bit 5) is used by the vendor only on other ICs (V3s class, T527/A733). The same MPEG-engine path is the one
  used from A10 to H6 (jemk, lm), so it is the low-risk path. The 0xE00 block stays a probe item (J12).
- **Prior code:** Emmanuel Gil Peyrot and Jernej Skrabec, "[PATCH 0/4] media: cedrus: Add a JPEG decoder"
  (2024-07-31, lore `20240731164422.206503-1-linkmauve@linkmauve.fr`, never merged). Mbox:
  `kernel-check/dl-jpeg/linkmauve-cedrus-jpeg-v1/series.mbox`. It is the only open driver code. It uses the in-kernel
  `v4l2_jpeg_parse_header()`, as mxc-jpeg does.
- **uAPI:** no new uAPI. OUTPUT `V4L2_PIX_FMT_JPEG` (one JFIF per buffer, headers parsed by the driver), CAPTURE the
  existing cedrus formats (NV12, NV21, YUV420, YVU420 linear; NV12_32L32 tiled). No request needed for JPEG; all other
  codecs keep `requires_requests`.

### 2.2 Patch block `patches.media/h616-jpeg/` (5 patches)

| # | patch | author | notes |
|---|---|---|---|
| 1 | media: cedrus: Setup secondary output formats | Jernej Skrabec | rebased: our `cedrus_dst_format_set()` already has the linear cases and the secondary stride register, and H.265/VP9 use the secondary output for P010, so the secondary setup is a separate `cedrus_dst_secondary_format_set()` that only JPEG calls (all 4 linear formats). Rebase note in the commit message |
| 2 | media: cedrus: Add JPEG decoder | Emmanuel Gil Peyrot | context-only rebase (capability BIT(10), switch cases next to the newer codecs) |
| 3 | media: cedrus: Enable JPEG decoding in various variants | Jernej Skrabec | applied as is (A10..H6, not A13; predates the H616 variant) |
| 4 | media: cedrus: Don't require requests for all codecs | Jernej Skrabec | applied as is, made per-codec by patch 5 |
| 5 | media: cedrus: jpeg: enable on H616, fix tables, limits and queue setup | ours | below |

Patch 5:
- **H616:** `CEDRUS_CAPABILITY_JPEG_DEC` in the H616 variant. New variant flag `jpeg_rotate_out` (H616 only) sets MPEG
  CTRL bits 8 (rotate/scale out enable) and 7 (MC no-writeback), as the vendor writes 0x180/0x40180 on this IC. Other
  variants keep lm's tested behaviour.
- **Kernel mapping (a real bug):** cedrus allocates OUTPUT buffers with `DMA_ATTR_NO_KERNEL_MAPPING`, so
  `vb2_plane_vaddr()` returned NULL and lm's `v4l2_jpeg_parse_header()` call would have dereferenced NULL on MMAP
  buffers. `cedrus_s_fmt_vid_out_p()` now sets `dma_attrs = 0` and `requires_requests = false` for JPEG, and restores
  `NO_KERNEL_MAPPING` + `requires_requests` for every other codec (s_fmt is refused while the queue is busy, so this is
  safe).
- **Formats:** grey (1 component, chroma format 5, MCU 8x8, chroma plane filled with 0x80 by the CPU before the
  trigger) and 4:1:1 (fmt 1, MCU 32x8) beside 4:2:0/4:2:2/4:2:2T(4:4:0)/4:4:4. Everything except 4:2:0 sets
  `JPEG_FORCE_420` (CTRL bit 18), because every capture format is 4:2:0.
- **Huffman:** the SRAM image is written as one little-endian byte stream (descriptors at 0, HUFFVAL at 0x400, 2 KiB);
  missing DHT tables fall back to the T.81 annex K tables (`v4l2_jpeg_ref_table_*_ht`: webcam MJPEG has no DHT).
  The research note's "lm tail byte order" bug is **not** a bug: lm's tail loop also produces little-endian order.
  The rewrite only makes it obvious. A Python model of both upload loops gives byte-identical 2 KiB images on `s420`, `opt420` and `mjpeg422`, whose HUFFVAL lengths include 11, 53 and 58, so the tail cases are covered.
- **Bounds (a real bug):** `v4l2_jpeg_parse_header()` does not range-check the scan's Td/Ta selectors (0..15), and lm
  indexed the 4-entry table array with them. They are now limited to 0/1. The quantisation selectors are limited to 0..3.
- **Rejects** (the engine holds one luma and one chroma table set): Cr DQT or DHT tables that differ in content from
  Cb's, a 16-bit DQT, non-interleaved scans (Ns ≠ Nf), a scan component order different from the frame's, precision ≠ 8,
  and component counts other than 1 or 3. Progressive, arithmetic and lossless coding are already refused by the parser.
- **Sizes:** lm's 2048x2048 cap is replaced by checks that the picture fits the CAPTURE format and that the
  MCU-padded width fits the line stride (needed for 4:1:1). The limit is then the cedrus maximum, 4096x2304. The
  MCU-count fields are written as 16-bit fields (wiki). Below 16384 px this is identical to lm's 11-bit masks.
- `VLD_END` = last byte of the source buffer (vendor and jemk use `end − 1`; lm used `src + payload`).

### 2.3 Build status (host)

| check | result |
|---|---|
| Rebase onto scratch (after the DI commits) | patches 1, 2 conflicted on context only; 3, 4 applied with fuzz, and patch 3's placement was checked per variant (A10..H6 yes, A13/A523/H616 no) |
| `W=1` on `drivers/staging/media/sunxi/cedrus/` | no warnings |
| checkpatch on the series | 0 errors, 0 warnings (1 alignment CHECK on a long selector line) |
| `STAGE=patch` | **768 applied, 0 failed** (`kernel-check/run-video-jpeg-patch.log`); cedrus dir identical to the scratch tree |
| Full incremental `Image modules dtbs` (`work-video`) | exit 0, 2 min, 0 warnings in the log; Image md5 `e3201bf26760801f96b36b5ff329bfed` (DI + JPEG) |

### 2.4 Test tools and vectors

- `harness/jpegtest/jpegtest` (MIT, static aarch64): opens the cedrus node, reads the size from SOF, sets
  OUTPUT JPEG and CAPTURE `-f nv12|nv21|yu12|yv12|tiled`, keeps 2 jobs in flight, `-n N` repeats, prints ms/decode
  and **MPPS** (picture pixels / wall time, ioctl round trip included), and writes the last output cropped and packed
  (`-o`). Exit 1 if any capture buffer has the ERROR flag.
- `harness/jpegtest/gen.sh OUTDIR` (host: ffmpeg + ImageMagick/libjpeg) builds the vectors and **reference decodes with
  `ffmpeg -idct int`** (IJG islow integer IDCT, native planar format, no colour conversion). They are already
  generated in `kernel-check/jpeg-vectors/` (22 cases, `cases.txt`, `SHA256SUMS`):
  - subsampling: 4:2:0, 4:2:2, 4:4:4, 4:4:0, 4:1:1, grey (1080p);
  - DRI 1/7/120;
  - sizes 16x16, 17x33 (also 4:1:1), 1921x1081, 2049x64, 4096x2304;
  - optimised Huffman tables; no DHT;
  - must be rejected: Cr table ≠ Cb, progressive, 4096x4096 (> 2304 lines);
  - must complete with an error or garbage but no hang: truncated ECS;
  - FFmpeg MJPEG 4:2:2.
- `harness/jpegtest/jpegtool.py` (`info`, `strip-dht`, `cr-table`, `truncate`) makes the edited vectors. Host check:
  `nodht` decodes identically to `s420` with ffmpeg, so libjpeg's default tables are annex K and the reference holds.
- `harness/jpegtest/run.sh VECTORDIR [FMT]` (board): decodes every case and the throughput runs.
  `harness/jpegtest/check.sh VECTORDIR [FMT]` (host): runs `compare.py` per case. `compare.py` gives PSNR, max |Δ| and
  "EXACT" per plane. Non-4:2:0 reference chroma is brought to 4:2:0 both by averaging and by dropping samples, since
  the FORCE_420 filter is unknown. Grey chroma must be 128. Self-test on the host (reference repacked as NV12): EXACT;
  4:2:2 via drop: EXACT.

### 2.5 Board test plan (JPEG)

Copy `jpegtest`, `run.sh` and `kernel-check/jpeg-vectors/` (130 MB; the `src-*.png` files are not needed) to the
board, run `run.sh /root/jpeg-vectors nv12`, copy `out-nv12/` back, and run `check.sh` on the host.

| # | test | pass | answers |
|---|---|---|---|
| J1 | `v4l2-ctl --list-formats-out` on cedrus shows JPEG; `v4l2-compliance` on cedrus | JPEG listed; no new failures vs the h616-vdec baseline | capability, per-codec requests |
| J2 | `s420` NV12 | completes; Y PSNR ≥ 48 dB vs islow and max \|Δ\| ≤ 2 (EXACT would mean islow-equivalent IDCT) | **bit-exactness question**; engine selection, tables, ROT output |
| J3 | `s420` with nv21, yu12, yv12, tiled | the same Y and chroma (tiled: compare after de-tiling) | secondary-output formats (TOP 0xE8/0xEC/0xCC), planar chroma length |
| J4 | `s422`, `s444`, `s440`, `s411`, `mjpeg422` | Y as J2. Chroma close to either the avg or the drop reference, which tells us the FORCE_420 filter | FORCE_420 for 4:2:2/4:4:4/4:4:0, **4:1:1 with FORCE_420** (vendor doesn't set it for 4:1:1: if the output is wrong, try without and see what layout comes out) |
| J5 | `grey` | Y as J2, chroma 128 | fmt 5 and whether the engine touches chroma (drop the memset if it writes 128 itself) |
| J6 | `dri1`, `dri7`, `dri120` | as J2 | restart handling by the HW |
| J7 | `z16x16`, `z17x33`, `z17x33-411`, `z1921x1081`, `z2049x64`, `z4096x2304` | as J2, no IOMMU faults in dmesg | MCU padding, VE_MODE >2048 bits on the JPEG path, 16-bit MCU fields, max size |
| J8 | `nodht`, `opt420` | as J2 | annex K defaults, non-default tables |
| J9 | `crtable`, `prog`, `z4096x4096` | rejected (rc 1, "unsupported JPEG" or parse error in dmesg), next job fine | rejects |
| J10 | `trunc` | finishes (error flag or a partial picture); no watchdog storm, no hang; next decode fine | error IRQ/VLD request handling |
| J11 | throughput: `run.sh` perf lines (s420, s444, 4096x2304, 100 runs each) | **≥ 45 MPPS** (datasheet), i.e. ≤ 46 ms per 1080p picture | performance row. If short, check the VE clock (600 MHz in the variant) and whether the 2 KiB Huffman upload over MMIO dominates (time it with 16x16) |
| J12 | optional probe of the VE+0xE00 block (VE_MODE bit 5): read its registers with `devmem` | n/a | whether the "JPEG plus" block exists on the H616 |
| J13 | mixed use: JPEG and H.264 contexts alternating (two `jpegtest`/`v4l2-request` processes) | both correct | VE mode switching, the per-codec queue settings |

Acceptance (research §6.2): we assume the engine is **not** bit-exact with libjpeg islow (it uses the MPEG-2 IEEE-1180
IDCT). Then: luma max |Δ| ≤ 2 and PSNR ≥ 48 dB; chroma the same for 4:2:0; 10 repeat runs bit-identical; golden md5s
frozen after the first good run.

Open register questions: the FORCE_420 filter, 4:1:1 output, grey chroma, whether CTRL bits 7/8 are needed (try
without on H616), MCU field width above 2048 px, VE_MODE width bits for JPEG, the throughput cost of the MMIO Huffman
upload.
