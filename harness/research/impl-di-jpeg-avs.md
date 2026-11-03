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

**Board run 2026-11-03** on image `4321861ff` (contains `d5f4c3d35`), image kernel as flashed (no trial kernel, no module
swap). Results are in §4. Fixes from that run are on the branch as `c69adf2bb` (committed, **not pushed**, **not yet
board-tested**: they need a new kernel). Scratch-tree commits: `0c7412fb6`, `a937ee1e0` (DI), `957ccb58b` (JPEG).
The test kernel for `d5f4c3d35` was `kernel-check/work-video/linux-7.3.1` (Image md5 `87011f73b3cd0c80a7c9b8b1536b47f0`).

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

---

## 3. AVS1 (JiZhun) / AVS+ (Guangdian) decode in the VE (cedrus)

### 3.1 Sources and design

- Research (clean-room, register offsets, bit fields and write order only, from the vendor `libawavs.so`, which has
  DWARF): `harness/research/avs1/` (`regmap.md`, `syntax.md`, `uapi-proposal.md`, `prior-art.md`, `test-streams.md`).
  There is no prior open AVS1 driver or stateless uAPI anywhere.
- **Engine:** the H.264 register bank (VE+0x200), VE_MODE 1 (`VE_MODE_DEC_H264`), CTRL bit 28 `isAvs`, the same
  arrangement as VP8. One trigger (0x17, then 0x19) decodes a whole picture, because the engine parses the slice
  headers and removes annex A pseudo start codes itself (CTRL bit 26). It has no SRAM tables. AVS+ weighting-quant
  matrices are derived in the engine from the coded parameters.
- **uAPI (downstream, like AVS2):**
  - pixel format `V4L2_PIX_FMT_AVS_FRAME` 'AVSF': one picture per OUTPUT buffer, raw;
  - controls `V4L2_CID_STATELESS_AVS_SEQUENCE` / `_PICTURE` / `_WEIGHT_QUANT` = STATELESS_BASE + 1000..1002, types
    0x02d0..0x02d2;
  - sizes 16 / 64 / 32 B, no holes (checked with pahole on aarch64);
  - the PICTURE control carries 3 resolved reference descriptors (forward, second forward, backward) with timestamp,
    picture_distance and structure/tff/intra flags;
  - the WQ deltas are s16 (the coded value can exceed s8). The driver truncates them to the 8-bit hardware field.
- **cedrus:**
  - `cedrus_avs.c`, `CEDRUS_CAPABILITY_AVS_DEC` = BIT(11);
  - a 48 KiB MB-info buffer (16 KiB aligned) per context, and a col-MV buffer per capture buffer (I/P write their own,
    B reads its backward reference's);
  - VE reset on codec switches involving AVS;
  - request validation of the required controls;
  - limit 16..1920 x 16..1088;
  - NV12 / NV12_32L32 and the other cedrus capture formats through the existing top-register path.

### 3.2 Patch block `patches.media/h616-avs/` (3 patches, ours)

1. media: uapi: add AVS stateless decoder pixel format and controls (uAPI, ctrl core, docs: biblio, ext-ctrls,
   pixfmt, queryctrl, g-ext-ctrls, exceptions).
2. media: cedrus: add AVS decoding.
3. media: cedrus: enable AVS decoding on the H616.

### 3.3 Build status (host)

| check | result |
|---|---|
| `W=1` on `drivers/staging/media/sunxi/cedrus/` and `drivers/media/v4l2-core/` | no warnings |
| checkpatch | patch 3 clean. Patch 2: MAINTAINERS note only. Patch 1: 3 `pr_cont` warnings and 1 table-style ERROR in the `v4l2-ioctl.c` descr table, the same as the AVS2 patch |
| `STAGE=patch` | **771 applied, 0 failed** (`kernel-check/run-video-avs-patch.log`). cedrus, v4l2-core, uapi headers and media docs are identical to the scratch tree |
| Full incremental `Image modules dtbs` (`work-video`) | rc 0, 0 warnings. **Image md5 `87011f73b3cd0c80a7c9b8b1536b47f0`** (this kernel has DI + JPEG + AVS) |

### 3.4 Test decoder and references

- `harness/avs1dec/` (MIT, own code):
  - `make` builds static aarch64 `avs1dec`; `make host` builds `avs1dec-host`;
  - parses ES/TS/PS input, sequence and picture headers (AVS+ fields included), keeps a 3-slot reference history,
    sends one request per picture, and writes output in display order;
  - `-c` writes FFmpeg framecrc lines (adler32), `-5` framemd5, `-o` I420; `-T` captures tiled; `-H` sets
    data_offset to just after the picture start code (vendor style) instead of the first slice start code;
  - `--dry-run -v` prints the control values for every picture.
- Dry run on the host, all 4 streams:

  | stream | pictures | order |
  |---|---|---|
  | `bunny` | 60 (I 2 / P 16 / B 42) | order identical to FFmpeg |
  | test card | 5, field-coded, AEC, 2 enhanced field B, 15 pseudo start codes | order identical to FFmpeg |
  | `cavs.mpg` | 170 with `-l 170` | order identical to FFmpeg |
  | `AVSFileFormat.es` | 105 | — |

  - `cavs.mpg`: the file is truncated, so it needs `-l 170`. It is an old revision with no slice start codes.
  - `AVSFileFormat.es`: its 12 `00 00 02` candidates are all outside slice data.
- References:
  - **FFmpeg master `N-128344-gaab6cec3e8` (`aab6cec3e8415154b3f0570f8d131db07a9901de`)**, built and installed by the
    user at `/usr/local/bin/ffmpeg`. Its output is in `kernel-check/avs1-refs-master/` (framecrc + framemd5, `SOURCE`,
    `SHA256SUMS`). The test card and `cavs.mpg` equal FATE.
  - **`bunny` differs from FATE in 51 of 60 frames.** The first difference is display 2, an all-skip B at half
    distance. It is **not** slice weighting: no P/B slice in bunny sets slice_weighting_flag, and 8.1's "weighted
    prediction" warning comes from the I pictures. FFmpeg 8.1 = FATE references are in `kernel-check/avs1-refs/`.
    The H616 output (A4) decides which is right.
  - `AVSFileFormat.es`: neither FFmpeg decodes it, so it has no reference.

### 3.5 Board test plan (AVS)

Setup:
- Host: serve `kernel-check/dl-avs1` as `http://10.56.0.1:8643/avs1/` (the AVS2 server) and copy
  `harness/avs1dec/avs1dec` to `/root/avs1/`.
- Board: `U=http://10.56.0.1:8643/avs1; O=/root/avs1/out; mkdir -p $O`. Find cedrus with `v4l2-ctl --list-devices`,
  then `V=/dev/videoN M=/dev/mediaN D="-d $V -m $M"`.
- To compare, run `diff <(grep -v '^#' ours) <(grep -v '^#' ref)`.

| # | test | pass | answers |
|---|---|---|---|
| A1 | `v4l2-compliance -d $V -s`; `--list-formats-out` shows AVSF; `-l` shows 3 AVS controls | no new compliance failures | uAPI, B1 |
| A2 | `curl -sS $U/fate-bunny/bunny.mp4 \| avs1dec $D -l 1 -c $O/b1.crc -v -` | rc 0, first frame 0xe9f1474e, dmesg clean. If it fails, retry with `-H` | B1, B2, B3 (B2, 0x19 without 0x17, needs a debug kernel and only matters if both fail) |
| A3 | full bunny with and without `-H` | record which data_offset convention decodes. That becomes the uAPI rule (doc follows) | B3 |
| A4 | bunny 60 frames vs `avs1-refs-master/bunny.mp4.framecrc` **and** `avs1-refs/bunny.framecrc` (FATE) | frames 0, 1, 3, 4, 30-34 match both; note which reference matches the rest. A first mismatch at a P points to col-MV / second ref, at a B only to distances | B5, B6, B7, and the FFmpeg master/FATE disagreement |
| A5 | test card (TS) vs `avs1-refs-master/avsplus-1080i-testcard.ts.framecrc` (= FATE), also with `-H` | 5 frames equal | B4 pseudo start codes, B8 one trigger per field-coded picture, B9 AEC, B11 MB-info, B13 enhanced field B |
| A6 | A4 and A5 again with `-T` (NV12_32L32) | total md5 equals the NV12 run | B12 |
| A7 | `cavs.mpg -l 170` vs master framecrc | expected to fail (pre-final revision); record rc / first bad frame | B14, informative |
| A8 | `AVSFileFormat.es -5 ... -o $O/aff.yuv` | completes; visual check | no reference exists |
| A9 | bunny → an H.264 test → one 8-bit AVS2 stream (avs2dec) → bunny again; also two avs1dec instances in parallel | all equal their references | VE reset on codec switch, context isolation |
| A10 | truncated bunny (`head -c 20000`); OUTPUT format 2560x1440 (clamped ≤ 1920x1088) | no hang, rate-limited warning, next run correct | error paths |
| A11 | throughput: test card ×20 and bunny looped | 1080 lines: report fps (spec 1080p60, so ≥ 60 fields/s for 1080i) | performance row (B10 WQ remains untested, no stream) |

Open questions:
- B1-B14, which only the board can answer.
- The data_offset convention (A3).
- A per-field trigger, if A5 frame 0 fails. That would need a second-slice offset in the uAPI.
- WQ delta width: s16 vs s8.
- The validation ranges: alpha/beta −8..8, chroma deltas −32..31, sample_precision 1.
- Interlaced MB height: the vendor's (h+15)/16 vs FFmpeg's ((h+31)>>5)<<1. They agree at 1080.
- Which bunny reference is correct.

---

## 4. Board results (image 4321861ff, 2026-11-03)

Board: /dev/video0 cedrus (/dev/media0), /dev/video1 sun50i-di300 (/dev/media1). Host outputs: `kernel-check/board-di/`,
`kernel-check/jpeg-vectors/out-nv12/`, `kernel-check/board-avs1/`. The board was soft-rebooted twice (`systemctl reboot`)
after DI hangs left a process in D state; no power cycle.

### 4.1 DI300

| test | result | details |
|---|---|---|
| D1 | PASS | probe OK, IOMMU group 0, FMD/TNR controls listed, v4l2-compliance 49/49 |
| D2 | PASS (note) | weave byte-exact for all 7 formats at 720x576, 32x32 and 2048x1280. Note: at exactly 2048x1280 with 4:2:2 input (NV16/NV61/422P) the engine reads past the end of the source buffer (IOMMU read fault at buffer start + size, any mode; output still exact). Heights ≤ 1276 and 2016x1280 are clean. Fix: one page of slack on MMAP source buffers (`0c7412fb6`) |
| D3 | PASS (note) | 100 % exact kept lines, TFF and BFF correct. The lag is 1.5 frames, not 1: job j outputs the second field of frame j−2 and the first field of j−1. The output timestamps still carry the newest source's time; not fixed (userspace can shift by 1.5 frames) |
| D4 | FAIL vs target | field mode 33.2–33.5 dB (720x576 TFF/BFF, 1080), frame 33.25, bob 30.1. Host references: intra-field linear 30.1, yadif 40.2, bwdif 37.3 dB. Static scene exact (except the leftmost ~8 columns of odd rows), so motion detection works; the moving-content quality looks like the hardware's interpolator. No driver fix |
| D5 | PASS | 1080p field mode 187.7 out/s, 2048x1280 148.7 out/s, frame mode 86.9 out/s (target ≥ 60); module clock 300 MHz |
| D6 | FAIL, fixed (untested) | `-m field -F yv12 -t fixed` hung: STATUS 0x100 (busy), FUNC_EN 0x5 (DIT+TNR, no MD), DMA_CTL 0x81110111. Root cause: on the first job (no history) MD was off while TNR was on; the engine never completes. With no driver watchdog, STREAMOFF then sleeps in `v4l2_m2m_cancel_job()` forever (D state, reboot needed). Fix `0c7412fb6`: MD in every TNR job (vendor behaviour) and a 1 s job watchdog (reset + `deinterlace_init` + ERROR buffers). No further TNR runs were made on the image kernel |
| D7 | FAIL, fixed (untested) | luma exact in all conversions; chroma wrong. NV12→I420/YV12: Cb and Cr exactly swapped. NV16→422P: Cb plane = source Cr, Cr plane broken (rows 0/1 repeated). I420→NV12: engine hang (same D-state symptom; FMT 0x10010000). Root cause: FMT_UVSEQ polarity inverted (vendor: 1 = VU for NV21/NV61; driver set it for NV12/NV16). Fix `a937ee1e0`: vendor polarity, and a semi-planar capture format must equal the source format (planar→semi-planar refused, since it hung). Also: di300test's `-c weave` cannot compare across formats (always "FAIL"); outputs were compared with `cmp`/numpy instead |
| D8 | PASS | `-z -v` on 3:2 telecine 720x480: FID/FOD/FRD counters show the 5-job cadence. With fixed weave phases `-w p\|8` (chroma weave), p = 0/1/2 give 38/16/38 outputs that equal a film frame exactly (luma and chroma), 0 without weave; the union covers all 60 outputs and all 23 film frames, so a per-job detector reconstructs the film exactly. Every 5th stats read is all-zero except FID23/FRD13 (possibly the VOF buffer toggle); informative |
| D9 | not run | optional |
| D10 | PASS | new `harness/di300test/di300err` (MIT, static): mode control and S_FMT give EBUSY while streaming; STREAMOFF with jobs queued returns and every buffer comes back; the context restarts. Three contexts in parallel (NV12 weave, I420 field, YV12 weave): weave exact, field output equal to a solo run. Three runs killed mid-stream (SIGKILL): no D state, next run exact |

### 4.2 JPEG (cedrus)

`run.sh /root/jpeg nv12` then `check.sh` on the host (references: `ffmpeg -idct int`).

| test | result | details |
|---|---|---|
| J1 | PASS | JPEG listed; v4l2-compliance 43/49, the same 6 failures as the h616-vdec/AVS2 baseline (MG2S G/TRY/S_FMT, duplicate AS01, DECODER_CMD, TRY_EXT_CTRLS); none new |
| J2 | PASS | s420: Y 65.27 dB, U 66.52, V 66.39, max \|Δ\| 1 (not islow-exact; ≤ 1 LSB). Ten runs give the same md5 |
| J3 | PASS | nv21, yu12, yv12 identical to nv12 vs reference; tiled de-tiled equals linear |
| J4 | PARTIAL | s422, s444: Y as J2, chroma matches the **averaging** reference (66.5 / 52.5 dB, max 1), so FORCE_420 averages. s440 and mjpeg422: refused cleanly by `v4l2_jpeg_parse_header()` (no 4:4:0 subsampling value; chroma factors other than 1x1 rejected, which the engine also cannot do). s411: **hang** (IOMMU read fault, master 3, then "frame processing timed out"; the cedrus watchdog recovered and the next jobs were fine). Fix `957ccb58b` refuses 4:1:1 |
| J5 | FAIL, refused now | grey: the job finishes in 0.45 ms with no error and writes no luma (linear and tiled alike); chroma 128 from the CPU fill. Root cause unknown (the vendor programs CTRL the same way, 0x180 without FORCE_420). Fix `957ccb58b` refuses greyscale until a trial kernel can probe it |
| J6 | PASS | dri1/7/120 identical to s420 |
| J7 | PASS except 4:1:1 | 16x16, 17x33, 1921x1081, 2049x64, 4096x2304: max \|Δ\| 1, no IOMMU faults. z17x33-411: wrong chroma (refused by `957ccb58b`) |
| J8 | PASS | nodht and opt420 identical to s420 |
| J9 | PASS | crtable ("Cb and Cr DQT tables differ"), prog (parse error), 4096x4096 (does not fit 4096x2304) refused, rc 1; next job fine |
| J10 | PASS | trunc completes, no hang, no watchdog |
| J11 | PASS | 1080p 4:2:0 16.5 ms = 125.8 MPPS; 4:4:4 34.2 ms = 60.7 MPPS; 4096x2304 72 ms = 131 MPPS (target 45 MPPS; ioctl round trip included) |
| J12 | n/a | VE+0xE00..0xEFF read all zero during JPEG decodes (VE_MODE 0x00020000): the "JPEG plus" block is unused/absent on this path |
| J13 | PASS | three JPEG contexts in parallel (1080p linear, 1080p 4:4:4 tiled, 4096x2304): outputs identical to solo runs. Mixed with AVS1 and AVS2 (sequential and parallel): every md5 unchanged (AVS1/AVS2 used instead of H.264 as the other codec) |

### 4.3 AVS1 / AVS+ (cedrus)

`avs1dec -d /dev/video0 -m /dev/media0`. Tool fix during the run: FFmpeg's framecrc seeds adler32 with 0, not 1
(`harness/avs1dec/avs1dec.c`); the frame data were already correct. avs1dec now also prints the hardware time
(request queue to completion).

| test | result | details |
|---|---|---|
| A1 | PASS | AVSF listed; the 3 controls listed (v4l2-ctl prints "unsupported payload type" for types 0x2d0-0x2d2, cosmetic); compliance as J1 |
| A2 | PASS | bunny frame 0 = 0xe9f1474e (md5 192c5c3d…), rc 0, dmesg clean |
| A3 | PASS | full bunny with and without `-H`: identical (md5 dd0376a6…), so both data_offset conventions decode |
| A4 | PASS | all 60 frames equal **FFmpeg master** (`avs1-refs-master`); 51 of 60 differ from FATE / FFmpeg 8.1, exactly as master does. The board settles the open question: master is right, the FATE reference is stale |
| A5 | PASS | AVS+ 1080i test card: 5/5 frames equal the reference (= FATE), also with `-H` |
| A6 | PASS | `-T` (NV12_32L32): same total md5 for bunny and the test card |
| A7 | FAIL (expected) | cavs.mpg (pre-final revision, no slice start codes, chroma_format/sample_precision 0): 170 frames, rc 0, no error IRQ, but every frame is all zero: the engine writes nothing. Informative; a picture without slice start codes could be refused by the decoder tool |
| A8 | PASS | AVSFileFormat.es: 105 frames, rc 0; contact sheet (frames 0, 50, 104) is clean video (`kernel-check/board-avs1/aff-tiles.png`) |
| A9 | PASS | bunny → JPEG → AVS2 (main-1080p-ldp, 30 frames, equal to the earlier board run) → test card → bunny: all md5 unchanged; the same four in parallel: unchanged |
| A10 | PASS | truncated bunny (20000 B), truncated test card, bunny with 20000 random bytes spliced in: rc 0, no hang, one rate-limited "AVS decode error: status …, error case …, mb …" per bad picture; the next full run correct. OUTPUT 2560x1440 AVSF is clamped to 1920x1088 |
| A11 | PASS | hardware time: 1080i test card 10.3 ms per frame (≈ 97 frames, ≈ 195 fields/s; tiled 8.8 ms), 720p bunny 4.2 ms (238 fps). Target 1080p60. Wall time of avs1dec is CPU-bound (md5/adler over uncached capture buffers, 3.8 s user for 60 frames), not the VE |

### 4.4 Fix commits (branch `feat/sunxi-h616-di-jpeg-avs`, `c69adf2bb`, not pushed)

| patch | fixes | board-tested |
|---|---|---|
| h616-di/media-sunxi-sun50i-di300-fix-TNR-hang-add-a-job-watc.patch | D6 hang (MD with TNR), job watchdog for any stuck job (D6, D7), D2 over-read padding | no |
| h616-di/media-sunxi-sun50i-di300-fix-the-UV-order-bit-limit-.patch | D7 UVSEQ polarity; planar→semi-planar refused | no |
| h616-jpeg/media-cedrus-jpeg-drop-greyscale-and-4-1-1.patch | J5, J4/J7 4:1:1: refused instead of black/hang | superseded in §6 by `media-cedrus-jpeg-fix-4-1-1-refuse-greyscale.patch` |

`STAGE=patch`: 774 applied, 0 failed (`kernel-check/run-video-fix-patch.log`); the DI and cedrus dirs equal the scratch
tree; W=1 clean; checkpatch clean.

Needs a trial kernel next: D6 (TNR fixed/adaptive, `-m tnr`), D7 (all conversions, check I420→NV12 is refused), the
watchdog path, D2 at 2048x1280 4:2:2 without faults; for JPEG, probing greyscale (CTRL/TOP output bits) and 4:1:1
without FORCE_420 to bring both back.


## 5. JPEG greyscale and 4:1:1: root-cause work and probe plan (Phase 1, host only)

The coordinator asked for a real fix rather than the refusal in `957ccb58b`, which stays only until a fix lands.

### 5.1 Our setup against the vendor, register by register

Sources:
- **az**: `allwinner-zh/media-codec` `mjpeg_hal.c` (LGPL, A10/A20-era C source).
- **vmj**: the current aarch64 `libawmjpeg.so` from libcedarc, disassembled here (`/tmp/vmj/vmj.dis`; functions
  `SetJpegFormat` 0x3ab0, `InitJpegHw` 0x3fa0, `JpegHwDec` 0x4280, `JpegMallocFrmBuffer` 0x2230).
- The vendor kernel `cedar_ve.c` (orangepi 4.9/5.4 sun50iw9) has no format-specific JPEG code, only the IRQ plumbing
  for the 0xE00 "JPEG plus" block (VE_MODE bit 5).

| item | vendor (vmj, IC > 0x1666 = H616 class) | ours | same? |
|---|---|---|---|
| chroma format, TRIGGER bits 29:27 | `strb (fmt<<3)\|3` at TRIGGER+3: 0 420, 1 411, 2 422, 3 444, 4 422T, 5 400 (`SetJpegFormat`: sampling words 0x221111/0x411111/0x211111/0x111111/0x121111/0x110000) | same values, 32-bit write | yes |
| MCU size | max H / V sampling factor × 8 (grey 1x1 → 8x8; a grey file with 2x2 sampling → 16x16) | grey always 8x8 | yes for 1x1 grey; differs for grey files with H/V > 1 |
| JPEG_SIZE (0xB8) | (rows−1)<<16 \| (cols−1) | same | yes |
| quant tables | luma = comp0 Tq, chroma = comp1 Tq (grey: comp1 is zeroed → table 0) | grey: chroma = luma table | yes |
| Huffman SRAM | Y from the scan's first component, C from the second (grey: the loop falls back to comp0 → C = Y) | grey: C = Y | yes |
| ROT_LUMA / ROT_CHROMA (0xCC/0xD0) | output addresses | same | yes |
| SD_ROT_DBLK_CTL (0xD4) | rotation/scale, 0 when not used | 0 | yes |
| VLD_END (0x34) | buffer end − 1 | same | yes |
| CTRL (0x14) | `\|= 0x7c` (IRQ bits 2–6) plus 0x180 (ROTATE_SCALE_OUT_EN + MC_NO_WRITEBACK) on linear output; **FORCE_420 (0x40000) only for fmt 2 and 3 (4:2:2, 4:4:4)** | IRQ 0x38 \| 0x180, FORCE_420 for **everything except 4:2:0 and grey** | **no**: IRQ bits 2/6; FORCE_420 on 4:1:1 and 4:2:2T |
| TOP 0xEC / 0xE8 / 0xCC | YV12 (3) or NV21 (5) secondary/primary, 0xE8 = [29] \| 1<<30 \| chroma length; strides into 0xCC; also writes **0xC4 / 0xC8 (primary chroma length / strides)** | NV12/NV21/YU12/YV12 secondary set; 0xC4/0xC8 not written for JPEG | partly |
| frame buffer (FBM) | 4:2:0 and grey → MB32_420 (7); 4:1:1, 4:2:2, 4:4:4, 4:2:2T → MB32_422 (8) on old ICs; **on IC > 0x1638 always 7** (4:2:0) | 4:2:0 capture formats only | consistent with the new-IC rule |

### 5.2 Conclusions

- **4:1:1: root cause found in the code.** The vendor never sets FORCE_420 for 4:1:1 (or 4:2:2T); on new ICs it
  still allocates a 4:2:0 frame and relies on the output path. We set FORCE_420 for 4:1:1, and that is the case that
  hung at 1080p (IOMMU read fault, master 3) and gave wrong chroma at 17x33. Candidate fix (trial commit
  `db5b40477`): FORCE_420 only for 4:2:2 and 4:4:4, as the vendor. The board must still show which chroma layout
  comes out (4:2:0 as hoped, or 4:2:2 rows), and where the old fault address lies relative to the buffers.
- **Greyscale: no static difference** in the JPEG registers for a 1x1 grey file except the IRQ-enable bits 2/6 and
  the primary TOP registers. The early finish (0.45 ms, no luma) needs the register dump after the job (STATUS bits
  19–21 JPEG_MARKER / RESTART_ERROR / BIT_END, the VLD bit offset, the MCU position) to tell "engine refused the
  format", "engine decoded but wrote elsewhere" and "engine stopped at once" apart. The capture is pre-filled with
  0x5a so "wrote zeros" and "wrote nothing" are distinct.

### 5.3 Trial kernel `jpegtrial`

- Worktree `wt-jpeg-trial` (detached at `4321861ff`) plus, in `series.conf`: the two DI fix patches
  (`0c7412fb6`, `a937ee1e0`); `trial-media-cedrus-jpeg-force420-vendor.patch` (= `db5b40477`, candidate fix);
  `trial-media-cedrus-jpeg-probe.patch` (= `4e687343b`, TRIAL ONLY). The refusal `957ccb58b` is not in it.
  Scratch branch `trial-jpeg`.
- Build: `STAGE=all ARMBIAN=wt-jpeg-trial WORK=kernel-check/work-jpegtrial build-kernel.sh` (ccache;
  `kernel-check/run-jpegtrial-all.log`): 806 patches applied, 0 failed; build exit 0, 0 C warnings; release `7.3.1`,
  cedrus built in, DI300 a module. Artifacts: `kernel-check/vdec-serve/Image.jpegtrial` (sha256 9d7a3bdb34b74f51…),
  `modules-jpegtrial.tgz` (installed by `install-kernel.sh` as `/lib/modules/7.3.1`; the image's own modules are
  untouched). The cedrus sources differ from the integration tree only in `cedrus_jpeg.c`.
- Probe parameters (`/sys/module/<cedrus>/parameters/`): `jpeg_dump` (register dump after setup and after the job,
  plus the source/capture IOVA ranges) and `jpeg_probe` bits:

| bit | variant |
|---|---|
| 0x1 | CTRL IRQ enables 0x7c (vendor) |
| 0x2 | no ROTATE_SCALE_OUT_EN / MC_NO_WRITEBACK (primary/MC output only) |
| 0x4 / 0x8 | FORCE_420 forced on / off |
| 0x10 | grey: JPEG_SIZE in 16x16 units |
| 0x20 | skip the secondary output setup |
| 0x40 | ROTATE_SCALE_OUT_EN but keep MC writeback |
| 0x80 | vendor byte writes to TRIGGER |
| 0x100 | also program primary chroma length / strides (TOP 0xC4/0xC8) |
| 0x200 | grey programmed as chroma format 0 |
| 0x400 | 4:1:1: JPEG_SIZE in 16x8 units |

### 5.4 Probe plan (one slot) and expected observables

Slot script `harness/jpegtest/jpeg-slot.sh install → confirm → stage → probe → tests → restore` (fallback armed by
`install-kernel.sh`; restore points `/boot/Image` back). `probe.sh` runs every case below with the capture pre-filled
with 0x5a; `analyze-probe.py` prints, per run: rc, time, STATUS / VLD offset / MCU after the job, % of luma and
chroma bytes written, luma PSNR, chroma PSNR under the 4:2:0-avg, 4:2:0-drop, 4:2:2-rows and raw-4:1:1 layouts,
and any IOMMU fault placed against the buffer ranges.

| run | vectors | expected if the hypothesis holds |
|---|---|---|
| control `c64` under every variant | 64x48 4:2:0 | luma/chroma ≈ 65 dB for all except 0x2/0x20 (output path changes) and 0x4/0x8 (no effect on 4:2:0) |
| grey 0 (baseline) | g64, grey | reproduces: Y written 0 %, ~0.4 ms; the dump shows which STATUS bit ends the job |
| grey 0x1 | | if the job ends on an interrupt we did not enable (bit 2 or 6): decode completes, Y written 100 % |
| grey 0x2, 0x40 | nv12 and tiled | if grey only writes through the MC/primary path: Y written into the tiled (primary) layout |
| grey 0x4 | | if the output unit needs FORCE_420 for 400: Y written |
| grey 0x10 | | if the engine counts grey MCUs in 16x16: Y written (bottom/right parts may miss) and the MCU register ends at cols×rows/4 |
| grey 0x100, 0x80, 0x20 | | primary TOP registers / trigger write width / secondary setup matter |
| grey 0x200 | | as fmt 0 the engine runs for normal decode time and writes garbage chroma: shows fmt 5 itself is the stop |
| g64s22 0 / 0x10 | grey with 2x2 sampling | tells the vendor's MCU rule (max factor × 8) for grey |
| 4:1:1 0 (candidate) | f64, z17x33-411, s411 (nv12, tiled) | no hang, Y exact; chroma matches 4:2:0-avg or -drop (fix done), or 4:2:2-rows (engine writes 4:2:2: needs a 4:2:2 handling decision) |
| 4:1:1 0x400, 0x404 | | checks the 32x8 MCU count (0x400 should break luma) |
| 4:1:1 0x4 at 1080p (last) | s411 | the old hang again, now with the IOVA ranges: places the fault (expected: past the capture buffer end, by chroma rows written as 4:2:2) |

After the probe: `PROBE=<best bits> jpeg-slot.sh tests` reruns J1–J13 plus D2 (2048x1280 4:2:2 faults), D6 (TNR
fixed/adaptive/off/tnr-only on the noisy clip) and D7 (all conversions, planar→semi-planar refused), then
`restore`. The final commit replaces `957ccb58b` with the confirmed fix and drops the probe patch.

## 6. Phase 2 board results (trial kernels `jpegtrial` and `jpegfix`, 2026-11-03)

### 6.1 Probe on `jpegtrial` (probe patch, `jpeg_probe` variants)

Outputs: `kernel-check/jpeg-probe/out/<variant>/`, summary `kernel-check/jpeg-probe/probe-summary.txt`.

- **Control** `c64` (4:2:0): Y 64.7 dB, chroma 64 dB under every variant except 0x20 (no secondary setup: no output).
- **Greyscale: not fixable with the known registers.** For g64, g64s22 and grey 1080p, every variant (IRQ 0x7c,
  no rotate-out, rotate-out with writeback, FORCE_420 on/off, MCU 16x16, primary TOP registers, byte trigger) ends
  the job in 0.6–0.9 ms with STATUS 0xc001 (success), VLD offset unchanged (0x0a40, the first scan byte), JPEG_MCU
  0x1, and no luma written. Programmed as fmt 0 (0x200) the same file runs the full decode (VLD offset to the end,
  MCU 0x60000) and writes luma (garbage): chroma format 5 itself makes the engine stop after the first MCU.
  Untested: MCU_START/END (MPEG+0xd8/0xdc) and the 0xE00 JPEG-plus block, which the vendor library does not
  program for grey either. **Kept refused** (`num_components != 3`), so userspace falls back to software.
- **4:1:1 without FORCE_420 (vendor rule): decodes correctly.** f64 and z17x33-411: luma exact; no hang. The chroma
  is written as is: one interleaved CbCr line of width/2 bytes per picture line, at the luma stride, so twice the
  size of an NV12 chroma plane (host check on `out/0/f64.nv12.raw`: chroma rows match the 4:1:1 reference to
  0.016 mean abs error). At 1080p this ran past the capture buffer (IOMMU read fault on master 3 at dst_end + 8 KiB),
  with FORCE_420 on and off alike. That was the original "hang". 0x400 (16-wide MCU) breaks luma: 32x8 MCUs are right.

### 6.2 Fix: `h616-jpeg/media-cedrus-jpeg-fix-4-1-1-refuse-greyscale.patch` (replaces the refusal patch)

- FORCE_420 only for 4:2:2 and 4:4:4, as libawmjpeg.
- 4:1:1: chroma goes to a per-context noncoherent bounce buffer (`bytesperline × (ALIGN(h,16)+16)`), luma straight to
  the capture buffer; a new `post_process` decoder op (called from `cedrus_irq` on success) resamples to 4:2:0 for
  NV12/NV21/YUV420/YVU420 (column-pair sample, average of the two lines). Tiled NV12_32L32 is refused for 4:1:1.
  The formula was checked on the probe raw data first (max 0.5 off the averaged reference).
- Greyscale refused with the evidence above.

### 6.3 `jpegfix` run (no probe patch; J1–J13, D2, D6, D7)

Build: `kernel-check/run-jpegfix-all.log`, 805 applied, 0 failed, 0 C warnings. Results:
`kernel-check/board-di/trial/jpegfix-tests.txt`, `kernel-check/jpeg-vectors/check-trial.txt`.

| test | result |
|---|---|
| J4 s411 1080p | **PASS now**: Y 65.27 dB, U/V avg 66.55 / 66.57 dB (max 1), no fault, no timeout |
| J7 z17x33-411 | **PASS now**: Y 64.83 dB, U 69.98 dB, V exact |
| J1–J3, J6–J13 others | unchanged from §4: s420/s422/s444, DRI 1/7/120, odd sizes, 4096x2304, opt/nodht ≈ 65–66 dB max 1; 4096x4096, crtable, prog rejected; trunc completes |
| J5 grey | refused (intended, §6.1) |
| s440, mjpeg422 | refused by `v4l2_jpeg_parse_header()`, as in §4 (not a regression) |
| perf | s420 1080p 16.5 ms (125.7 MPix/s), s444 34.3 ms, 4096x2304 71.5 ms |
| D2 2048x1280 4:2:2 | weave exact; **first run still had 6 IOMMU read faults**. Buffer addresses (debug module) put them exactly at the end of the **capture** buffers, not the source ones as §4 assumed. Padding moved to both queues (`fix-TNR-hang` patch amended); rerun: 0 faults for nv16/nv61/422p weave and bob |
| D6 TNR | fixed/adaptive/off 30 in → 60 out, 155 out/s; `-m tnr` 30 → 30; no hang |
| D7 | all conversions run; I420→NV12 refused; di300err streaming/STREAMOFF checks all ok |

The amended DI padding was tested by loading the rebuilt module on the `jpegfix` kernel (full test set rerun with it,
0 faults). Board left on the image kernel `7.3.1-edge-sunxi64`.

### 6.4 Commits

Scratch tree `kernel-check/scratch-video/linux` master: `f6dd01e8a` (DI TNR/watchdog/padding), `45d1c914d` (DI UV
order), `bd8cc0d19` (JPEG 4:1:1 fix, grey refused); old refusal kept as branch `refuse-grey-411-old`, probe on
branch `trial-jpeg`. `wt-video-new` series: `STAGE=patch` 774 applied, 0 failed (`kernel-check/run-videonew-patch.log`);
the cedrus and DI sources equal the scratch tree.


## 7. Greyscale: does the hardware decode it? (Phase 3, host-only research + probe plan)

### 7.1 What the vendor sends to the VE on the H616

- **Two vendor JPEG decoders.** libcedarc has `libawmjpeg` (the MPEG engine, VE+0x100, which is what we use) and
  `libawmjpegplus` (a separate "DEC/JPEG" register group at **VE+0xE00**: the libVE `getGroupRegAddr` table gives
  group 6 "DEC/JPEG" = 0xe00; `MjpegDecoderInit` calls `getGroupRegAddr(ve, 6)`). libawmjpegplus ships with DWARF;
  its `SetJpegFormatPlus` handles greyscale **of any sampling** and stores a separate `jpegGrayFormat`
  (h2v2 → 0, h4v1 → 1, h2v1 → 2, h1v1 → 3, h1v2 → 4) next to chroma format 5.
- **Which one the H616 gets.** `libvideoengine` `CreateSpecificDecoder` picks "mjpegplus" only for these VE
  versions (T527 build, same list in the aodzip/A133/sun60iw2 builds): 0x1681, 0x1689, 0x1708, 0x0003011100021010,
  0x0003011100021110, 0x0003011100020010, 0x0002111000021210. The H616 VE is **0x0003301000012011** (TOP+0xE0/0xE4,
  §6 board read), not in the list, so the H616 uses **libawmjpeg on the MPEG engine**, like us.
- **libawmjpeg grey path (vmj).** `JpegGetSof` accepts 1–3 components. `SetJpegFormat` maps the sampling word
  0x110000 (one 1x1 component) to format 5 and returns "supported"; any other 1-component sampling (e.g. 0x220000)
  → format 6 = error. `JpegDecoderMain` has no component-count check and no software fallback: 1x1 grey goes
  to the hardware with exactly the register sequence we use — `InitJpegHw`: MPEG+0xC0 = DRI, TRIGGER+3 =
  `5<<3|3`, IQ tables (luma = comp0 Tq, "chroma" = comp1 Tq = 0), ROT_LUMA/ROT_CHROMA, JPEG_SIZE in 8x8 MCUs,
  0xD4 = 0, Huffman SRAM (C tables = Y tables), VLD_END; `JpegHwDec`: TOP 0xC4/0xC8/0xE8/0xEC, CTRL 0x7c (|0x180
  on the linear-output paths; FORCE_420 not for format 5), VLD offset/len, VLD_ADDR | 0x70000000, TRIGGER byte 0
  = 0x0e. It never writes MCU_START/END (0xD8/0xDC) or anything in 0xE00. The A10/A20 C source (`mjpeg_hal.c`)
  is the same (JPEG400, same table loops).
- So the vendor *claims* MPEG-engine greyscale on the H616, with our settings. Nothing in the vendor code
  explains the board result (job ends after one MCU, 0 bits consumed). Either it is broken on this IP revision
  and nobody noticed (MJPEG video is never grey; the vendor image path on newer chips is mjpegplus), or a register
  outside the JPEG code differs.

### 7.2 Other generations and consumers

- Mainline cedrus JPEG (Linkmauve/Jernej, v1 2024) refuses `num_components != 3`; no grey support was ever written
  or tested there. jemk's `cedrus/jpeg-test` (A10 reverse engineering) handles only 4:4:4/4:2:2/4:2:2T/4:2:0
  (TRIGGER+3 = 0x1b/0x13/0x23/0x03), no grey. libvdpau-sunxi has no JPEG.
- Userspace that could reach the cedrus JPEG decoder:
  - **FFmpeg**: no `mjpeg_v4l2m2m` decoder upstream (v4l2m2m: H.263/H.264/HEVC/MPEG-1/2/4/VC-1/VP8/VP9 only) and
    the v4l2-request series (ours: patches 0001–0013) has no JPEG hwaccel. FFmpeg (mpv, ffplay, Kodi) **always
    decodes JPEG in software**, so greyscale already works there; the refusal never matters.
  - **GStreamer**: `gstv4l2` registers a `v4l2jpegdec` for any M2M device with image/jpeg on OUTPUT and raw on
    CAPTURE (cedrus qualifies), at rank PRIMARY+1, above `jpegdec` (PRIMARY). A refused job comes back with
    V4L2_BUF_FLAG_ERROR → GST_BUFFER_FLAG_CORRUPTED → `gst_video_decoder_drop_frame`: the grey picture is
    **dropped, not decoded in software**. Whether v4l2jpegdec works with cedrus at all (it expects the stateful
    protocol: SOURCE_CHANGE, DEC_CMD_STOP/LAST drain) is untested.

### 7.3 Ways out if the hardware cannot do it

- **(a) Present grey as a 3-component stream: not feasible cleanly.** An interleaved scan puts Y, Cb, Cr blocks
  inside every MCU, so inserting DC-only chroma blocks needs every Y block boundary, i.e. a full Huffman decode of
  all coefficients in the kernel, then re-emitting the bits with byte stuffing. That is the entropy half of a
  software decoder, on untrusted input, in the kernel; at 1080p it would cost about as much CPU as libjpeg-turbo
  saves by offloading IDCT. Not upstreamable, no real gain.
- **(b) Clean refusal + software fallback.** The kernel part is done (`-EINVAL` from setup, error buffer, log
  line). FFmpeg needs nothing. GStreamer drops the frame; making it fall back needs userspace help, e.g. a
  GStreamer patch that keeps `sampling=GRAYSCALE` (set by `jpegparse`) out of v4l2jpegdec's sink caps so decodebin
  picks `jpegdec`, or lowering v4l2jpegdec's rank on this board. To be verified on the board (7.4 step 4).

### 7.4 Probe build `greytrial` and board plan

- Scratch branch `trial-grey` (`kernel-check/scratch-video/linux`): master + TRIAL patch
  `trial-media-cedrus-jpeg-grey-probe.patch` (in `wt-jpeg-trial` series after the 4:1:1 fix; DI patches there are
  the final ones). Module parameters: `jpeg_grey` (let 1-component JPEGs through as format 5, Cb/Cr mirroring Y as
  the vendor), `jpeg_trig_xor`, `jpeg_ctrl_xor` (XOR into TRIGGER / CTRL), `jpeg_mcu_se` (MCU_START = 0, MCU_END =
  rows-1|cols-1, rows|cols, n-1, n), `jpeg_reg`/`jpeg_reg_val` (one extra MPEG register write before the
  trigger), `jpeg_dump` (MPEG, TOP and **VE+0xE00** dumps before the trigger and after the job).
- Board side `harness/jpegtest/probe-grey.sh` (staged by `jpeg-slot.sh stage`), ~170 runs on `g64` (64x48 grey
  1x1), plus `g64s22`, 1080p `grey`, tiled, and 4:2:0 `c64` controls first and last:
  1. chroma format codes 0–7 and TRIGGER bits 30/31;
  2. MCU_START/END variants (the "stops after exactly one MCU" hypothesis);
  3. every CTRL bit except the IRQ enables;
  4. TRIGGER bits 8–23;
  5. every MPEG register the JPEG path leaves alone (0x00–0xfc minus VLD/IQ/SRAM/output/size/trigger), written
     with 1 and with the JPEG_SIZE value;
  6. last: TRIGGER bits 24–26 (decoder mode).
  The `c64` dump also shows whether the 0xE00 block exists on the H616 (non-zero/changing registers in a 4:2:0
  decode).
- Success signature: VLD offset advancing to the end of the scan, JPEG_MCU = rows<<16, luma written ≈ reference
  (`analyze-probe.py` prints VLDOFF before→after, MCU, Y written %, PSNR, "E00 nonzero").
- Slot (one boot, ~15 min): `TAG=greytrial jpeg-slot.sh install` → `confirm` → `stage` → `greyprobe` →
  `restore`. If a variant decodes grey: fix patch replacing the refusal, then a `jpegfix`-style confirm boot with
  J1–J13. If none does: also (step 4) on the image kernel check `gst-inspect-1.0 v4l2jpegdec` and a
  `gst-launch-1.0 filesrc ! jpegparse ! decodebin ! fakesink` / `playbin` run on a grey and a colour JPEG, to
  decide whether the GStreamer fallback patch is needed.

### 7.5 Fallback if no probe variant decodes greyscale: keep GStreamer off v4l2jpegdec for grey

Facts these options rely on (gst 1.28.7 sources):
- The `v4l2jpegdec` sink template is `image/jpeg, parsed=true`, so `jpegparse` (rank PRIMARY) always sits in front
  of it.
- `jpegparse` adds `sampling` to its caps: "GRAYSCALE", "RGB", or "YCbCr-4:4:4/4:2:2/4:2:0/4:4:0/4:1:0/4:1:1".
- Autoplugging matches those caps against each factory's sink template and ranks. `jpegdec` is PRIMARY;
  `v4l2jpegdec` is PRIMARY+1.

| | A: rank override (no code) | B: caps patch (code) |
|---|---|---|
| what | `GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL`, set in `/etc/environment` and in the systemd `DefaultEnvironment` drop-ins (system and user); draft hook `harness/research/jpeg/gst-jpeg-rank-hook.sh.draft` | for driver "cedrus", `gstv4l2.c` limits the image/jpeg sink template to `sampling={YCbCr-4:2:0, 4:2:2, 4:4:4, 4:1:1}`; draft `harness/research/jpeg/gst-v4l2-cedrus-jpeg-sampling.patch.draft` (≈40 lines, not compiled: the host has no GStreamer dev files) |
| result | every autoplugged JPEG goes to `jpegdec` (software, correct for all samplings). `v4l2jpegdec` still works in explicit pipelines | colour JPEGs the driver can decode still go to cedrus; greyscale, RGB, 4:4:0 and 4:1:0 go to `jpegdec`. Also fixes the RGB (Adobe) case, which cedrus would decode with wrong colours |
| cost | one config hook, same pattern as `RUSTICL_ENABLE`; no binary; survives apt upgrades; trivially reversible | a rebuilt `libgstvideo4linux2.so` for the image's exact gst-plugins-good version, installed with `dpkg-divert` (as the libclc fix), rebuilt on every plugins-good update. Not upstreamable as is: upstream would want the driver to report its samplings, which V4L2 cannot do |
| feature loss | autoplugged hardware JPEG decode in GStreamer (the V4L2 decoder itself and explicit use remain) | none |

**Pick: A now; switch to B only if the board shows `v4l2jpegdec` decodes colour JPEGs correctly via playbin.**
- `v4l2jpegdec` expects the stateful decoder protocol: SOURCE_CHANGE, capture format from the driver, and a
  DEC_CMD_STOP/LAST-buffer drain. Cedrus JPEG offers a plain m2m interface with none of that, and it is untested
  with GStreamer.
- If that combination fails, colour JPEGs break too, and A is needed anyway. B would then add nothing.
- If it works, B keeps hardware decode for colour in autoplugging, which the never-drop-a-feature rule favours. It
  costs a carried binary, so it is worth paying only once the hardware path is shown to work end to end.
- FFmpeg-based players need neither option: they never use the cedrus JPEG decoder.

Board check for this decision (§7.4 step 3), on the image kernel, with `g.jpg` grey and `c.jpg` colour:
1. Run `gst-inspect-1.0 v4l2jpegdec`.
2. Run `gst-launch-1.0 -v filesrc location=X ! jpegparse ! decodebin ! videoconvert ! filesink location=out.raw`,
   once as is and once with `GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL` set.
3. For each run, record which decoder was chosen (`-v` output) and compare the output to `ffmpeg -i X -f rawvideo`.
