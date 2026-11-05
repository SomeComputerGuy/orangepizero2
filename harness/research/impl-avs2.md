# AVS2 hardware decode on the H616 (cedrus): implementation notes

**Status (2026-11-03): board-tested on the Orange Pi Zero2 (§7).** 8-bit AVS2 is bit-exact on all 17 reference streams
(after an ALF table fix found on the board). 10-bit is **self-consistent, not reference-verified** (§7.3). 4K Main10 P010
decodes at 58.5 fps VE-bound.

- **Goal:** the spec row "AVS2 JiZhun 10-bit 4K@60" (docs/spec-checklist.md).
- **Branch (current):** `feat/sunxi-h616-avs2-dec-v2` (commit `62c28d143` = `3a7feba0e` + board fixes, pushed to `fork`), in the worktree `wt-avs2-v2`.
  It is based on `feat/sunxi-h616-vdec-spec` at `5a078800a` (patch 30, AFBC reconstruction for P010). See §0.
- **Old branch:** `feat/sunxi-h616-avs2-dec` (`05081511c`, worktree `wt-avs2`, based on `d92a201f3`). Kept unchanged; superseded.
- **Kernel patches:** the series block `h616-vdec`, after patch 30 (`media-cedrus-reconstruct-10-bit-pictures-into-AFBC-for-P010-output.patch`).
  The scratch git tree is `kernel-check/scratch-avs2/linux`, branch `avs2-v4` (on `aa2de7fe3` = patch 30), with one commit
  per patch. Branch `avs2-v3` is the old version on patch 29.
- **Test decoder:** `harness/avs2dec/`.

Research notes in `harness/research/avs2/`:

| file | content |
|---|---|
| `regmap.md` | Clean-room register map and write sequence, recovered from the vendor `libawavs2.so`. The `[board]` marks are collected in §4 here. |
| `syntax.md` | AVS2 header syntax, cross-checked between MPP, davs2, Amlogic and the Moore Threads patch. The spec text itself is not freely available. |
| `prior-art.md` | Other AVS2 implementations. No open Allwinner code, no mainline V4L2 AVS2 uAPI. |
| `test-streams.md` | Test streams: 12 PKU 8-bit Main streams with official YUV md5s, one 3840x2160 Main10 broadcast capture without an md5. |

## 0. Rebase onto the AFBC series (2026-11-02)

Patch 30 changes the meaning of the shared P010 helpers: with P010 capture the hidden reconstruction/reference surface is
now 10-bit AFBC (`YUV420_10_AFBC_16X16_SPLIT`, one plane, 4 KiB aligned after the P010 picture) instead of linear NV12 plus
the 2-bit plane. `cedrus_recon_is_afbc()` makes `cedrus_engine_enable()` set the VE_MODE AFBC bits, `cedrus_dst_frame_fmt()`
returns the AFBC format with `bytesperline = 0`, and `cedrus_dst_10bit_extra_size()` sizes the AFBC surface.
(H.265 Main10 4K P010: 23.9 → 60.3 fps, impl-vdec-main10-perf.md.)

**Decision: AVS2 uses the same AFBC hidden reference for P010.** No AVS2-only linear path.
Evidence that the vendor drives AVS2 with AFBC on this decoder:
- libVE `SetAfbcParam`: on decoder IP 0x33010 (our board) AVS2 (codec 0x118) is AFBC capable, like VP9/H.264/H.265,
  and gets AFBC above 3839x2159 under the default `ENABLE_AFBC_JUST_BIG_SIZE` (vdec-main10-web.md).
- libVE `enableDecoder` sets the AFBC VE_MODE bits (0x10, bit 29, bit 12; clears 26/27) for AVS2 when AFBC is on (regmap §1).
- libawavs2 has an AFBC path of its own (`AVS2_DECODER.bEnableAfbcFlag`, decoder+264, set in `Avs2MallocFbmBuffer` from
  `eCtlAfbcMode` 2, or 1 with w ≥ 3840 / h ≥ 2160; it calls `veOps->setEnableAfbcFlag`):
  - the current picture's address word 2 (pic[7][2]) gets the luma (single plane) address instead of chroma
    (`Avs2UpdateRefFrameToEntryPointBuf`, dis 0xe158);
  - it writes the AFBC header block into the frame for the display (`Avs2UpdateFrameWqMatrix` area, dis 0xbce4); not needed by the VE.
- `Avs2Set10BitReg` has no AFBC branch: it writes 0x84 / 0x8C from the frame-buffer fields as usual (0x8C = 0x2000 only when
  scale-down or rotation is on).

What changed in the AVS2 driver patch (everything else came over unchanged; the uAPI and enable patches are identical apart
from the commit hash):
- With an AFBC reconstruction (`cedrus_recon_is_afbc()`), address word 2 of the current picture **and of every reference**
  is the AFBC plane address. The vendor does this for the current picture; for references it writes its frame buffer's
  chroma pointer, whose value for an AFBC buffer was not traced, so references copy the current-picture rule. (Patch 30's
  H.265 writes 0 for chroma instead; AVS2 follows its own vendor code.)
- Through the shared helpers, without AVS2 code: VE_MODE AFBC bits, AFBC primary output format, 0x84 = 0
  (bytesperline 0), 0x8C = 2-bit stride | P010 bit 12 (same as patch-30 H.265), extra capture size = AFBC surface.
- Comments and the commit message updated.
- Native AFBC capture for AVS2 is still not exposed (the AFBC capture formats are limited to HEVC/VP9 sources); see §6.

**What the board must confirm (A6, A8, A11 in §4):**
1. AVS2 P010 decodes correctly with the AFBC reference: pictures stable over a long GOP (no drift), since the P010 picture
   is produced from the same engine pass that writes the AFBC reference that later pictures predict from.
2. pic[i][2] = AFBC plane address for references is accepted (if P/B pictures are wrong but I pictures right, try 0 as
   H.265 does, then the luma + AFBC header offset).
3. 0x8C with stride | bit 12 under AFBC (the vendor would write bit 13 and, with its own secondary output, nothing else).
4. 4K throughput reaches 60 fps (A8).

**Fallback if AVS2 AFBC fails on the board:** make the reconstruction codec-aware: `cedrus_recon_is_afbc()`,
`cedrus_dst_frame_fmt()` and `cedrus_dst_10bit_extra_size()` return the old linear NV12 + 2-bit layout when
`ctx->src_fmt.pixelformat == V4L2_PIX_FMT_AVS2_FRAME`, and `cedrus_dst_p010_output_set()` keeps the old
`VE_PRIMARY_OUT_FMT_NV12` for that case (old code: branch `feat/sunxi-h616-avs2-dec`, scratch `avs2-v3`). Expect ~24 fps
at 4K then (the H.265 linear number).

## 1. Design

**Hardware model.**
- The decoder runs in the H.265 engine slot (VE+0x500) in AVS2 mode: REG04 bits 31:30 = 1. VE_MODE uses the plain H.265 mode, without VP9's RAMPD bits.
- Software parses the sequence and picture headers.
- The engine starts at the first slice start code and decodes every slice of the picture in one run, parsing the slice headers itself.
- The engine reads three tables from a 512-byte buffer in memory: ALF coefficients, weighting quant matrices, and the reference list with POCs.
- Co-located MVs are stored per frame (128 B per 64x64 block). The co-located picture is reference 0.

**uAPI (downstream).** Patch `media-uapi-add-AVS2-stateless-decoder-pixel-format-and-controls.patch`.

Pixel format:
- `V4L2_PIX_FMT_AVS2_FRAME` ('AVS2'). One OUTPUT buffer holds one coded picture: the picture header plus all slices, raw, with start codes. Sequence headers or extensions may come first.

Controls, at `V4L2_CID_CODEC_STATELESS_BASE` + 900..903, types 0x02c0..0x02c3:

| control | carries |
|---|---|
| `SEQUENCE` | Sequence header fields and flags. The RCS and WQ matrices are resolved by userspace. |
| `PICTURE` | Picture header fields and flags, POC, `data_offset` (first slice), and up to 7 `v4l2_avs2_ref_pic` entries. |
| `WEIGHT_QUANT` | The final 4x4 and 8x8 matrices for the picture; flat 64 when WQ is off. |
| `ALF` | Coefficients as coded, the 16-entry region→filter map, and the Y/Cb/Cr enables. |

Each `v4l2_avs2_ref_pic` holds:
- the capture timestamp and POC of the reference;
- that picture's own ref-POC list, in its own reference order;
- its picture type and the number of its references;
- a background flag.

The ref-POC list is needed because the engine wants every reference's own reference POCs for temporal MV prediction. HEVC solves the same problem with DPB entries.

The reference list is passed resolved, in RCS order:
- B pictures: future, then past.
- S pictures: the background picture in slot 0.
- P/F pictures with background_reference: the background picture in the last slot.

Validation follows the existing stateless patterns: flag masks, ranges, `zero_reserved`. Struct sizes are 20, 360, 80 and 348 bytes, with no padding holes (checked on the host). The docs cover ext-ctrls-codec-stateless, pixfmt-compressed, the queryctrl and g-ext-ctrls tables, the exceptions file, and the biblio entry.

**Why this shape.**
- The control split follows the existing stateless codecs: MPEG-2 has sequence, picture and quantisation; VC-1 and MPEG-4 have separate controls.
- The reference list and per-ref POC lists follow Rockchip MPP's AVS2 "syntax" and the libva PR #738 picture parameters. In those, userspace owns the DPB and the hardware gets resolved references.
- The driver applies the vendor's hardware-specific transforms, so userspace stays hardware-neutral:
  - the B-picture swap of the stored ref-POC list;
  - intra self-POCs;
  - zero fill;
  - the 9-bit masks;
  - the background POC substitution;
  - the ALF centre-tap reconstruction;
  - region nibble packing.

**Driver.** Patch `media-cedrus-add-AVS2-decoding.patch`, file `cedrus_avs2.c`, plus registration in cedrus.c/.h, cedrus_dec.c, cedrus_hw.c, cedrus_video.c and cedrus_regs.h, and the Makefile.
- `CEDRUS_CAPABILITY_AVS2_DEC` is BIT(9).
- **Buffers:**
  - Per context: a 2 MiB neighbour buffer (no kernel mapping) and the 512 B table buffer (coherent).
  - Per capture buffer: the col-MV buffer, freed in buf_cleanup.
- **Reused from the series:**
  - P010 (hidden AFBC reconstruction since patch 30, secondary output) and the 10-bit 2-bit plane: `cedrus_dst_frame_fmt/addr`, `cedrus_dst_p010_output_set`, `cedrus_dst_10bit_extra_size`, `cedrus_dst_2bit_stride`.
  - The H.265 IRQ status bits.
  - The H.265 size limit, 6144x4320 on the H616.
  - The VE reset on a codec switch (now also to or from AVS2).
- **try_ctrl:**
  - accepts 4:2:0 only;
  - rejects field coded sequences (v1);
  - checks the picture size;
  - sets `ctx->bit_depth` from sample_precision, as the vendor does (regmap §8);
  - allows 10-bit only with `H265_10_DEC`.
- **Capture formats:** NV12/NV21/YUV420/YVU420/NV12_32L32, plus P010 at depth 10. AFBC stays limited to HEVC/VP9.
- The H616 variant enables the capability in the separate patch `media-cedrus-enable-AVS2-decoding-on-the-H616.patch`.

**Test decoder.** `harness/avs2dec/avs2dec.c` (MIT) with `avs2_wq_tables.h` (Apache-2.0).
- It parses the elementary stream, including bit-level pseudo-start-code removal for headers.
- It parses sequence and picture headers: intra and inter, RCS inline or indexed, WQ in all three modes, ALF.
- DPB handling:
  - DOI unwrap and POC;
  - reference lookup by DOI;
  - background (G/GB/S) handling;
  - marking and removal, including the |ΔPOC| ≥ 128 rule;
  - output bumping.
- It submits one V4L2 request per picture with all four controls, using MMAP buffers on `/dev/videoN` and `/dev/mediaN`.
- Output is I420 8-bit or 16-bit LE for 10-bit, cropped to the display size. It prints the overall md5, and per-frame md5s with `-f`.
- `-p` runs the parser and DPB only, without V4L2, for host testing.

**What was borrowed, and the licences.**
- No code was copied from any decoder. The parser was written from the syntax tables in `research/avs2/syntax.md`. That file is our own summary of MPP (Apache-2.0/MIT), davs2 (GPL-2.0+), Amlogic (GPL-2.0+) and the Moore Threads FFmpeg patch (LGPL-2.1+).
- **Structure borrowed (ideas, not code):**
  - parsing headers in software and passing raw slices (MPP, VA);
  - the DOI unwrap, POC formula, RCS reference lookup and marking (MPP/davs2);
  - the output rule (MPP-like).
- **Data copied:** the weighting quant tables come from Rockchip MPP `avs2d_ps.c` at commit `7916c3cc0`, under Apache-2.0. They are kept in their own file with the licence header and attribution. The same values appear in davs2 and in the vendor library.
- MD5 was written from RFC 1321.
- The kernel side follows the existing cedrus H.265/VP9 code (GPL-2.0+). The register knowledge is described clean-room in regmap.md; no vendor code was copied.

## 2. What is done and verified

| item | result |
|---|---|
| **v2 (on patch 30)** `STAGE=patch` (`ARMBIAN=wt-avs2-v2`, `WORK=kernel-check/work-avs2-patch`) | **745 applied, 0 failed** (`kernel-check/run-avs2-v2-patch.log`). All 24 files touched by patches 29-30 and the AVS2 patches are byte-identical to scratch `avs2-v4`; `drivers/staging/media/sunxi/cedrus` is identical as a directory. |
| **v2** incremental ccache build (`work-avs2`: the old AVS2 patches reversed, patch 30 and the v2 patches applied; sources compared with `avs2-v4`) | Image exit 0, 25 s, no warnings. Image md5 `8a954ea9420164e56dac5122a3f5a4fc`. |
| **v2** `W=1` on cedrus and v4l2-core (cedrus forced) | No warnings. |
| **v2** checkpatch --strict | Same as v1 below (the uAPI style notes and MAINTAINERS only). |
| *v1 rows below are for the old branch (patch 29 base).* | |
| Patches | 3 new: uAPI, driver, H616 enable. The series now has 744 patches. |
| `STAGE=patch` (`ARMBIAN=wt-avs2`, `WORK=kernel-check/work-avs2-patch`) | 744 applied, 0 failed (`kernel-check/run-avs2-patch.log`). The resulting cedrus, v4l2-core, uapi and media headers and the docs are byte-identical to the scratch tree and to the build tree. |
| Incremental ccache build (`kernel-check/work-avs2/linux-7.3.1`, a copy of the built work-vdec tree) | Image and modules exit 0. Final Image md5 `a7286bd4ece16ee9ba07d0c9fe6e9377`. |
| `W=1` on `drivers/staging/media/sunxi/cedrus/` and `drivers/media/v4l2-core/` (forced rebuild) | No warnings. |
| checkpatch --strict | Clean, except 4 `pr_cont` warnings and 1 `case ...; break;` line, which copy the style of the existing entries, plus the usual MAINTAINERS note. |
| avs2dec | Builds without warnings with `aarch64-linux-gnu-gcc` against the patched uapi headers (`kernel-check/avs2-uapi/include`, from `make headers_install`), and also natively on the host (`make host`). |
| avs2dec `-p` on all 12 PKU streams | Every picture parses. Picture counts match test-streams.md: 100/150/200. POC order matches the research dump: BasketballPass_ra gives I 0, F 8, B 4, 2, 1, ... Every picture is output once. |
| avs2dec `-p` on the CCTV4K Main10 capture | 292 pictures parse after the first sequence header (P and B, 3840x2160, LCU 32, no SAO/ALF). The video track was demuxed with my own `/tmp/avs2-scripts/mkv2es.py` to `/tmp/avs2-es/cctv4k-10bit.avs2`. It is an open GOP: the first B pictures reference pictures from before the capture start, and avs2dec reports those as missing. |

**Not done or not verified:**
- No board run: the register semantics, IRQ, output and md5 are all unchecked.
- No `make htmldocs` run on the new rst.
- No reference md5 exists for any 10-bit stream.
- WQ, background (G/GB/S), field coding and temporal_id are only parsed. No stream we have uses them.
- avs2dec does not handle a mid-stream change of resolution or bit depth.
- The kernel rejects field-coded sequences.

## 3. Uncertain points in the design (decide after board data)

1. **Bit depth source.** The vendor programs REG04 from sample_precision, which it calls `internalBitDepth`. davs2 and MPP call encoding_precision the internal depth. The two agree on every stream we have. If they ever differ, the driver follows the vendor.
2. **10-bit config.**
   - P010 capture sets 0x8C bit 12, as the H.265/VP9 P010 path does (with the AFBC reconstruction since v2, §0).
   - NV12-plus-2-bit capture sets bit 13, which is what the vendor always sets.
   - The vendor never uses P010 and, with the secondary output, writes only 0x2000 (bit 13).
3. **Background reference.**
   - The refPoc list stored with a P/F picture uses the background picture's real POC.
   - The table entry of that slot uses the current POC, as the vendor does.
   - Whether the vendor's stored list uses the real or the substituted POC was not traced.
4. **POC masks.** The driver masks B ref 0's POC to 9 bits; the vendor writes it unmasked as s16.
5. **ALF centre tap.** It is stored as u8 even when it overflows, as the vendor does.

## 4. Board questions and test plan (for when the board is handed over)

Prerequisites:
- Kernel: the `wt-avs2-v2` series (after the integration merge, `stonking-orangepizero2`). Either the incremental build of
  `work-avs2` (v2 Image above) or a normal `STAGE=all`.
- `harness/avs2dec/avs2dec` (aarch64).
- Streams copied to the board: the PKU set from `kernel-check/dl-avs2/streams-gitee-hwren/repo/ES/*/test.avs2` with `md5.txt`, and `/tmp/avs2-es/cctv4k-10bit.avs2`.
- Nothing third-party runs on the board.

| # | test | pass criterion | what it answers |
|---|---|---|---|
| A1 | `v4l2-compliance -d /dev/videoN` (already on the image), `v4l2-ctl --list-formats-out` | 'AVS2' is listed; the 4 controls show in `--list-ctrls`; no new failures | uAPI and control registration |
| A2 | `avs2dec -v -c 1 BasketballPass_416x240_50_ai/test.avs2 -o /tmp/f.yuv`; look at the frame (convert on the host) | IRQ arrives, no watchdog timeout, the picture looks right | engine select (REG04 [31:30], VE_MODE without RAMPD), 0x38 = 0x80100, bitstream regs 0x40-0x4C, EPTB bypass, pseudo start codes in slice data |
| A3 | full `_ai` streams (3) | md5 equals md5.txt (8-bit I420 in output order; the format is assumed until it matches) | intra, ALF table layout, centre tap, region nibbles, SAO disable bit |
| A4 | `_ld` streams (3, F pictures) | md5 match | reference table words and >>5 addresses, col-MV in/out, REG14 num refs |
| A5 | `_ra` streams (3), BQMall, PartyScene, ParkScene 1080p | md5 match | B pictures, the B swap of the ref-POC list, POC > 255 (ParkScene has 200 pictures; the 9-bit wrap needs > 511, so loop a stream twice or concatenate), the width-hack bit 31 (none of these widths is in 129-192: craft or skip) |
| A6 | CCTV4K Main10, P010 capture: `avs2dec -f`, then view frames on the host (first, middle and last pictures of the GOP) | the §7.3 self-consistency set: repeat runs identical, P010 == NV12-path upper bits on every frame, no drift across GOPs, PNG check | 10-bit: REG04 depth, 0x8C bit 12, P010 secondary output, AFBC hidden reference and its address words (§0 items 1-3) |
| A7 | the same stream with NV12 capture at depth 10 (needs a small avs2dec option, or v4l2-ctl), comparing the 8-bit planes and the 2-bit plane against A6 | identical up to rounding | bit 13 versus bit 12 |
| A8 | 4K throughput: time 300 pictures of CCTV4K with P010 (AFBC hidden reference), VE-bound with `ve-busy-cmd.sh` | ≥ 50 fps for the stream's rate, 60 for the spec row | spec row "4K@60". H.265 Main10 P010 with the AFBC reference reaches 60.3 fps (impl-vdec-main10-perf.md) |
| A9 | cross-codec: an H.265 or VP9 job interleaved with AVS2 in two processes | both correct | VE reset on switch |
| A11 | only if A6 fails: P pictures wrong but I pictures right → set reference pic[i][2] to 0 (as H.265), then retest; everything wrong → the §0 fallback (linear reconstruction for AVS2) | A6 passes | AFBC reference addressing for AVS2 |
| A10 | error paths: truncated picture, wrong data_offset, missing ref (open GOP start of CCTV4K) | error buffer, no hang, watchdog not hit | robustness |

The register-level questions behind these tests are listed in regmap.md:
- VE_MODE RAMPD;
- the meaning of 0x80100;
- 0x8C bit 13;
- bitstream end/length semantics;
- pseudo start codes in slice data (A2/A3);
- 9-bit POC wrap (A5);
- background/S pictures and field coding (no stream; see §5);
- bit 31 for widths 129-192;
- sample versus encoding precision.

If A2 fails, try these variations in order, one per run:
1. VE_MODE with RAMPD|bit30 (the VP9 path).
2. Clear EPTB bypass.
3. 0x44 counted from the slice start code versus after it.
4. 0x48 = total bits versus remaining bits.

## 5a. Update 2026-11-02: reference tools (approved)

Both tools are cloned and pinned (research/avs2/test-streams.md). The first user run of `make-refs.sh` stopped at the
davs2 10-bit configure.

**Both tools turn out to be 8-bit only:**
- davs2's configure rejects 10-bit; its `HIGH_BIT_DEPTH` path is untested upstream and is not forced on.
- xavs2 has no 16-bit pixel type at all.

The script was reworked:
- 8-bit only;
- independent, non-fatal and idempotent stages;
- a per-step summary.

It now makes:
- the PKU md5-convention check;
- the davs2-8 Main10 probe;
- 8-bit xavs2 streams (1080p RA/LDP/temporal_id/LF-params, 4K RA, and WQ if the `-DENABLE_WQUANT=1` build works), with
  the encoder reconstruction as the reference and davs2-8 as a cross-check.

xavs2 cannot make background (G/GB/S) streams.

User command:

```
cd /home/aruni/orangepizero2 && harness/avs2dec/make-refs.sh 2>&1 | tee kernel-check/avs2-build-run2.log
```

The expected run time is roughly 10-30 min on the 20-core host. This is not measured: everything is C-only because the
host has no nasm.

## 5b. The 10-bit reference gap (cctv4k-10bit, spec row "10-bit 4K@60")

No open, trustworthy 10-bit AVS2 software decoder is known:
- davs2 has 10-bit disabled.
- uavs3d (https://github.com/uavs3/uavs3d, BSD-3-Clause) is an **AVS3** decoder, not AVS2, so it is not usable.
- FFmpeg has no native AVS2 decoder. Its libdavs2 wrapper is davs2 itself.
- The AVS2 RD reference software (RD19.x) is not public.
- Rockchip MPP, Amlogic and libva PR #738 are hardware paths, not software decoders.

A search on 2026-11-02 found nothing else (sources: https://github.com/uavs3/uavs3d,
https://github.com/intel/libva/pull/738, https://github.com/pkuvcl/davs2).

Options, for the user to decide:
1. **davs2 with `HIGH_BIT_DEPTH` forced** (patch out the configure check). Upstream disabled it as untested, so its
   md5s would not be trusted on their own.
2. **Another hardware decoder as the reference.** A Rockchip RK3588 board (Orange Pi 5) runs MPP AVS2 Main10: the other
   harness has an opi5. Two independent decoders agreeing would be strong evidence. This needs MPP on that board, which
   is another external-code approval.
3. **No bit-exact reference.** Fall back to self-consistency checks on the H616:
   - repeat runs give identical md5s;
   - P010 output matches NV12 plus the 2-bit plane;
   - frame-by-frame visual inspection;
   - no error status;
   - 8-bit streams prove the pipeline bit-exact, and 10-bit differs only in REG04 depth and 0x84/0x8C.

Until one of these is chosen, the 10-bit row can be claimed only as "decodes, visually correct", not bit-exact.

**The sample- versus encoding-precision question (regmap §8) stays open.** It needs an 8-bit-source stream coded at
10 bits (sample_precision 1, encoding_precision 2). xavs2 could only write that header (`encoder.c:1200`) with a real
10-bit build, which it does not have.

## 5. Approval request: reference decoder (external code, not built)

**Why it is needed.**
- There is no reference md5 for any 10-bit AVS2 stream, or for streams that use WQ, background pictures or field coding.
- The PKU md5s are documented only as "md5 of the reconstructed YUV", so the YUV format and order should be confirmed once.
- A spec-row claim of "10-bit works" needs a bit-exact comparison.

**What I would build, on the build host only, after your approval:**
- `https://github.com/pkuvcl/davs2` at commit `b41cf117452e2d73d827f02d3e30aa20f1c721ac` (2022-09-03, latest), GPL-2.0-or-later.
- Built twice with its own `build/linux/configure`: once 8-bit, and once with `--bit-depth=10` for Main10. No install, run as a normal user, no sudo, no Docker.

**Uses:**
1. Decode the 12 PKU streams and confirm the output matches md5.txt. This fixes the YUV format and order that avs2dec must produce.
2. Decode `/tmp/avs2-es/cctv4k-10bit.avs2` to produce per-frame md5s for A6. The leading open-GOP pictures will be dropped by both decoders, so their output start must be aligned.

**Known davs2 gaps** (syntax.md):
- It never parses picture-level WQ: it zeroes the flag before testing it.
- Its background-reference path is commented out.

So it is not a reference for WQ or background streams.

**Optional, a separate approval:** build `pkuvcl/xavs2` (GPL-2.0) to encode short Main10 and WQ/background test streams (A5/A6 coverage). I would give a pinned commit once approved; I have not looked it up yet.

## 7. Board results (2026-11-03)

Kernel: the `stonking-orangepizero2` cf62ac65a series (integration = image a2371fdc1 + patch 30 + AVS2 v2), built
incrementally in `kernel-check/work-board/linux-7.3.1` (copy of work-avs2 + the 20 integration-only source files,
config from the integration branch; olddefconfig identical), `7.3.1 #11`; then `#12` with the two fixes below
(Image md5 `9217ef8f347df23813d818b652733475`). Installed with `vdec-perf/install-kernel.sh` (Image + matching modules,
fallback armed to `vmlinuz-7.3.1-edge-sunxi64`). Streams were streamed over HTTP (`curl ... | avs2dec ... -`), never
copied to the board. Board scripts: `harness/avs2dec/board-avs2-8bit.sh`, `board-avs2-10bit.sh`, `board-avs2-misc.sh`,
`board-regress-vdec.sh`; host-side results in `kernel-check/avs2-board/`.

### 7.1 Bugs found and fixed (commit `62c28d143`)
1. **ALF region map offset.** First run: every picture with ≥ 2 luma ALF filters wrong (luma only, max error 9);
   ALF-off, chroma-only and 1-filter pictures bit-exact (correlated per picture over 3 intra streams). Userspace probes
   (avs2dec `AVS2_ALF_MODE`, kept for reference) showed the slot coefficients are all read correctly and that no
   permutation of the 16 regions fixes it; a per-slot identity-filter probe on a 1080p I picture mapped which LCUs the
   engine filters with which slot: the engine reads the 16 nibbles at **table byte 168**, not 164 where the vendor
   builds them (regmap §5.1). Fixed: 6 reserved bytes after the chroma centre taps, table 176 bytes.
2. **Default AVS2 sequence control invalid** (size 0 fails its own validation; v4l2-compliance TRY_EXT_CTRLS). Default
   now 176x144. (The HEVC SPS and VC-1 sequence defaults fail the same way; that is pre-existing, not touched.)

### 7.2 Results per test
| # | result |
|---|---|
| A1 | `AVS2` listed in `--list-formats-out`; the 4 controls are listed. v4l2-compliance 43/49: the 6 failures are series-wide (MG2S not in ENUM_FMT for G/TRY/S_FMT, duplicate `AS01`, DECODER_CMD, TRY_EXT_CTRLS from the HEVC SPS / VC-1 defaults); see the baseline line in §7.4. |
| A2 | IRQ, engine select (REG04 [31:30] = 1), VE_MODE plain H.265 without RAMPD, 0x38 = 0x80100, bitstream regs, EPTB bypass: all work (first picture decoded, plausible). |
| A3-A5 | **All 17 8-bit streams bit-exact, every frame** (per-frame md5 against davs2-8 / official PKU md5s): 12 PKU (ai/ld/ra at 416x240, BQMall/PartyScene 832x480, ParkScene 1080p 200 frames incl. POC > 255) and main-1080p-{ra,ldp,tid,lf}, main-2160p-ra; 1860 pictures. Covers I/P/F/B, the B ref-POC swap, col-MV, multi-filter ALF, SAO, temporal layers. Not covered by any stream: WQ (the wq-* streams are identical to the non-WQ ones), background/S pictures, field coding, POC wrap > 511, widths 129-192 (bit 31). |
| A6 | cctv4k-10bit (3840x2160 Main10, 292 pictures, 6 GOPs of I + 6x(P + 7B), no SAO/ALF), P010 with the **AFBC hidden reference**: decodes, see §7.3. REG04 depth from sample_precision, 0x84 = 0 and 0x8C = stride \| bit 12 under AFBC, and pic[i][2] = AFBC address for current and references are all accepted. |
| A7 | NV12 capture at 10 bits (linear NV12 + 2-bit reconstruction, 0x8C bit 13): decodes, upper 8 bits equal to the P010 path on all 292 frames (§7.3). |
| A8 | VE-bound (ftrace `cedrus_device_run`→`cedrus_irq`, VE 600 MHz, avs2dec `AVS2_NOOUT=1`): **4K Main10 P010 (AFBC ref) 58.5 fps** (17.1 ms/picture; avs2dec pipeline 40 fps, single request in flight + stream parsing); same stream NV12+2-bit linear ref 47.2 fps; 8-bit 4K main-2160p-ra NV12 linear 33.0 fps, NV12_32L32 tiled **79.0 fps**; 1080p ParkScene NV12 198 fps. The stream itself is 50p; the "4K@60" spec row is met by the 8-bit tiled path and missed by 2.5 % for 10-bit P010 (native AFBC capture for AVS2, §6, would add headroom as for H.265: 60 → 84 fps). |
| A9 | PartyScene AVS2 decoded 3x back to back while FFmpeg decoded 300 frames of 4K HEVC Main10 P010 in another process: AVS2 md5 = reference all 3 times, HEVC 300 framemd5 = reference. (A first attempt with VP9 4K as a third parallel decoder, while another agent's GPU tests ran, ran the board out of memory; the 15 s watchdog reset it. Not a VE fault: no cedrus timeout. After that warm reset the SPL reported "This DRAM setup is currently not supported" and then 512 MiB; a normal reboot restored 1 GiB. Reported to the coordinator.) |
| A10 | Truncated stream: clean stop. 40 corrupted bytes in slice data: per-picture "decode error" (error IRQ → buffer error), no hang, no watchdog; next stream decodes bit-exact. |
| A11 | Not needed (A6 passed). |

### 7.3 10-bit verification: self-consistency (decided with the user, option 3)
There is no open 10-bit AVS2 reference decoder (§5b), so the 10-bit spec row is claimed as
**"self-consistent on the H616, not reference-verified"**, backed by bit-exact 8-bit (§7.2 A3-A5) and these checks on
cctv4k-10bit (and on any other 10-bit AVS2 stream added later):
1. **Repeatability:** two P010 runs give identical per-frame md5s on all 292 frames; a third (interrupted) run matches on
   the first 226. No two frames share an md5 (no stuck output).
2. **Two independent reference paths agree:** P010 output (AFBC hidden reference) vs NV12 capture at 10 bits (linear
   NV12 + low-2-bit reference): upper 8 bits identical on **all 292 frames** (avs2dec `AVS2_OUT8=1` vs `AVS2_CAP=NV12`).
   The low 2 bits of a reference feed the upper bits of later P/B pictures through MC rounding, so a lossy or misaddressed
   AFBC reference would have shown up here. Only the low 2 bits of the output itself are covered by repeatability alone
   (the NV12 path's 2-bit plane is not read back).
3. **No drift across GOPs:** check 2 holds for all 6 GOPs, including the last B pictures of each 48-picture chain.
4. **Visual:** frames 0 (I), 1, 2, 100 (B in GOP 3) converted to PNG on the host (`kernel-check/avs2-board/out10/*.png`,
   full frame at 1280x720 and a 960x540 crop at 1:1): clean, no blocking, smearing or colour shift.

### 7.4 Regression of the other codecs on the same kernel
Same kernel #12, `harness/avs2dec/board-regress-vdec.sh` (FFmpeg v4l2request, whole-stream md5 vs host software decode):
H.265 Main10 → P010 `e57bc497…` PASS, VP9 P2 → P010 `1e40c2b3…` PASS, H.265 8-bit → NV12 `3bbb2852…` PASS,
VP9 P0 → NV12 `9368ae9b…` PASS, H.264 High 4K → NV12 `2f51f88f…` PASS. Rates VE-bound: H.265 Main10 P010 59.8 fps,
AFBC10 83.9, VP9 P2 P010 56.9 (as impl-vdec-main10-perf.md §2.3). So patch 30 + AVS2 together break no other codec.
v4l2-compliance: 43/49 on the test kernel and on the image kernel #8 alike (same 6 pre-existing failures; on #8 the
AVS2 default also fails TRY_EXT_CTRLS, fixed in #12).

Board restored afterwards: image kernel `7.3.1-edge-sunxi64 #8`, `/boot/vdec-trial` removed, 1 GiB, network up.

## 6. Follow-ups

- Field-coded (interlaced) sequences: the per-field reference handling and bottom-field flags are already in the table writer, but `try_ctrl` rejects them until they are tested.
- Native AFBC capture for AVS2 (`YUV420_10_AFBC_16X16_SPLIT` with an AVS2 source; the driver code already handles an AFBC
  reconstruction, only the format table entries are missing). Worth adding after A6 passes, for DE33 AFBC scanout and the
  extra headroom (H.265: 84 vs 60 fps).
- Upstreaming: the uAPI would need a second user (Rockchip rkvdec2 or Amlogic) before it is acceptable upstream. Keep it downstream until then.

## 8. 10-bit reference check, request queue, AFBC capture (2026-11-05)

### 8.1 10-bit against a second decoder: davs2 with HIGH_BIT_DEPTH forced
- Build (host only; davs2 is already approved, §5a): a copy of `build-src-davs2/davs2` at `b41cf117…` in
  `kernel-check/avs2-build/davs2-10`. Changes:
  - configure: the `--bit-depth=10` refusal is replaced by a message ("forced, untested upstream");
  - two type fixes the 16-bit `pel_t` needs: `ALIGN_POINTER` casts to `__typeof__(p)` (osdep.h), and the three
    `pic->planes[i] = (uint8_t *)frame->planes[i]` in decoder.cc.
  Built with `--disable-asm` (no nasm). No other change to the decoding code.
- Run: `davs2 -i cctv4k-10bit.avs2 -o fifo -t 8` (also `-t 1`, identical), per-frame md5 with `yuvtool.py md5 3840 2160 2`
  (16-bit LE, 10-bit values, I420, output order; the same convention as avs2dec). Results in `kernel-check/avs2-build/run10/`.
- **Result [M]: frames 0–290 (291 of 292) have the same md5 in davs2-10 and in the board's P010 output** (both earlier board
  runs, `out10/cctv4k-10bit.p010-a/b.txt`). That is all 6 GOPs and every I, P and B picture type in the stream, through the AFBC
  hidden reference. davs2-10's "Invalid cu_qp_delta" messages are its own range check (±40 at 10 bits). They clip only values
  beyond the range, and every one of them belongs to the last picture.
- **Frame 291 (POC 323, the last picture of the capture, a P picture referencing 315) differs.** Evidence that the picture
  itself is damaged:
  - It is a single slice. davs2 reports entropy-decoding errors (invalid intra luma mode 33, chroma mode errors,
    cu_qp_delta out of range) in it, and only in it.
  - Row-by-row comparison of the board dump (`kernel-check/avs2-build/run10/board-f291.yuv`, local only; avs2dec `AVS2_DUMP=291`) with davs2:
    LCU rows 0–16 are identical. The first difference is at LCU row 17 (y 544+, small errors 2–11), then nearly every LCU in
    rows 18+ differs.
  - Two independent decoders that agree bit-exactly on 291 pictures, including 54 other P pictures, diverge in the middle of
    one slice, which then fails syntax checks. That points to corrupt data (e.g. a transport packet lost in the broadcast
    capture), not to a decoder difference. [I] The hardware raised no error interrupt for it.
- So the 10-bit claim moves from "self-consistent" (§7.3) to **"bit-exact against an independent software decoder on all
  undamaged pictures (291/291)"**, with two caveats:
  - davs2's 10-bit path is not validated upstream. Agreement between two independent implementations is strong evidence,
    not conformance.
  - The stream exercises only PMVR and LCU 32: no SAO, ALF, WQ or background pictures at 10 bits. Those tools are bit-exact
    at 8 bits (§7.2) only.

### 8.2 avs2dec: two requests in flight
- The old avs2dec queued one picture, waited for it, then parsed the next. Timeline (`vdec-perf/ve-timeline.sh`): the VE was
  starved 1.2–1.6 ms per picture, pipeline 53 fps against 59 VE-bound.
- New: `AVS2_DEPTH` (default 2, 1 = old behaviour, max 3; 4 OUTPUT buffers/requests). Picture N+1 is queued before N is
  waited for; readback (md5/file) of a picture still in flight is deferred in output order. A capture buffer is reused only
  when its request is done and its readback is complete. Parse-only (`-p -v`) output is byte-identical to the old binary
  on all 9 local streams.
- Board [M]: 4K Main10 P010 VE-bound 59.0 / pipeline 57.7 fps (depth 2), 59.5 / 58.2 (depth 3); ready gaps 0.11–0.13 ms,
  no starvation.
- md5 with depth 2: cctv4k 10-bit `be9985dea38abffc850d73024165c990` (= the earlier runs), main-2160p-ra `3a3d5d7e…` and
  main-1080p-ra `13dbb783…` (= davs2-8 references).
- Also new: `AVS2_CAP=AFBC` (10-bit AFBC capture, throughput only, needs `AVS2_NOOUT=1`, like ST12).

### 8.3 4K Main10 speed: what limits it, and the changes
- The limit is the VE itself (impl-vdec-main10-perf.md §9): 16.8–17.0 ms per picture with P010, setup 0.2 ms, handover
  0.1 ms. The pipeline equals the VE rate once the client keeps two requests queued.
- [M] VE 624 MHz (vendor policy, devmem PLL_VE on the image kernel): AVS2 P010 VE-bound 61.7 fps, pipeline 60.0 fps (+ MBUS
  port 4 HIGHEST: 62.2 / 60.9). Bit-exact (10-bit `be9985de…`, 8-bit `3a3d5d7e…`), plus the 15 min soak of §9.3 there.
- Kernel (branch `feat/sunxi-h616-vdec-60fps`, rebased on `test/cumulative` 67cef8768, for cumulative kernel c2):
  - `ba5caad1e` `media-cedrus-offer-10-bit-AFBC-capture-for-AVS2.patch`: YUV420_10_AFBC_16X16_SPLIT as an opt-in capture
    format for 10-bit AVS2 (after the plain formats; P010 stays the default). It is a format-table entry only: the AVS2 code
    already programs the single-plane AFBC addresses (current and references), the AFBC VE_MODE bits and, without P010, the
    vendor's HIGH10 10-bit config. **The AVS2 uAPI is unchanged** (it stays avs2-v5, now shared with the OPi5 project).
  - `e6229e03c` `media-cedrus-run-the-H616-VE-at-624-MHz.patch`.
  Build-checked on base b9df5096b (813/0, `W=1` clean). **Not board-tested yet**: under the cumulative-kernel rule, round 3
  (`vdec-perf/board-queue-r3.sh`: AVS2 AFBC vs P010 rates at 624/600 MHz, md5 regression of the 10-bit paths, v4l2-compliance)
  runs on c2.

### 8.4 Spec row "AVS2 JiZhun 10-bit 4K@60"
- P010 through avs2dec: 57.7–58.7 fps at 600 MHz; **60.0 fps at 624 MHz** (VE-only 61.7). Bit-exact against davs2-10 on
  291/291 undamaged pictures.
- AFBC10 capture (round 3, kernel c2, §8.6): **87.8 fps pipeline at 624 MHz** (VE-only 89.4), 85.4 at 600 MHz. **Met with
  margin.** P010 at the c2 default: 61.3 (VE-only 62.5). [M]

### 8.5 Open
- Native AFBC output cannot be md5-checked (no AFBC decompressor). The evidence stays the AFBC reference loop inside the
  bit-exact P010 runs. Display of AFBC needs DE33 AFBC scanout (impl-vdec-main10-perf.md §6) and an HDMI 2.0 4K60 sink,
  which we do not have.
- 10-bit SAO/ALF/WQ/background: no stream. A real 10-bit encoder (xavs2 has none) or the AVS WG conformance suite is needed.
- FFmpeg AVS2 hwaccel (status item 6), using the avs2dec request-queue scheme.

### 8.6 Round 3 on kernel c2 (2026-11-05) [M]
c2 = test-cumulative b8258b7f2 with both patches of §8.3. The VE runs at 624 MHz by default. avs2dec-q, cctv4k 10-bit
4K, 292 pictures, all decoded with rc 0:

| capture | 624 (default) | 624 + port 4 QoS HIGHEST | 600 |
|---|---|---|---|
| P010, depth 2 | 62.5 / 61.3 | 62.3 / 61.0 | 59.1 / 58.0 |
| AFBC, depth 2 | 89.4 / 87.8 | 93.0 / 91.3 | 87.0 / 85.4 |
| AFBC, depth 3 | 89.3 / 87.4 | 92.8 / 90.6 | 86.9 / 85.1 |

(fps VE-only / pipeline span. Depth 3 adds nothing: the VE is already >98 % busy at depth 2.)
- Per picture, AFBC needs 11.2 ms of VE time against 16.0 ms for P010: the hidden P010 write costs about 30 % of the VE time.
- md5 on c2: 10-bit P010 `be9985de…` and 8-bit `3a3d5d7e…` PASS, so the AFBC capture entry changed nothing for P010.
  The AFBC capture writes the same reconstruction surface the bit-exact P010 path reads its references from. It cannot be
  md5-checked directly (§8.5). [I]
- v4l2-compliance 43/49, unchanged (§7.4). 0 cedrus timeouts.

### 8.7 uAPI v6 (documentation only)
Agreed with the OPi5 rkvdec (VDPU381) backend, which is bit-exact on v5 without changes. Branches:
- `fix/sunxi-avs2-uapi-v6` 332956b3f (merged into test-cumulative): ref_poc optional for hardware that tracks reference
  POCs; ALF coefficients as coded, with drivers deriving the centre tap (9.12.2); WQ in raster order, with drivers converting
  (untested); 10-bit not tied to P010; field coding rejected.
- `fix/sunxi-avs2-uapi-v6b` f993245ab: the matrix_8x8 kernel-doc wording.

Layout, CIDs and control types are unchanged from v5 d0aa5a388. Checks: patch 829/0, full build 0 warnings, kernel-doc
clean. The v4l-utils part is the AVS2_FRAME hunk already in patches/v4l-utils/0001. The RFC is held in
docs/upstream-queue.md row 10.
