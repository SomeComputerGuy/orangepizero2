# DE33 AFBC10 scanout + 10-bit HDMI on Orange Pi Zero2: porting plan

Status: PLAN ONLY (2026-11-02). Nothing was ported, built or run on the board.
Base: `kernel-check/work-vdec/linux-7.3.1` (Armbian sunxi-7.3, full series), `wt-vdec/patch/kernel/archive/sunxi-7.3`.
Goal: show cedrus `AS01` (V4L2_PIX_FMT_YUV420_10_AFBC_16X16_SPLIT, 83.6 fps VE-bound today) as a DRM framebuffer
`DRM_FORMAT_YUV420_10BIT` + `DRM_FORMAT_MOD_ARM_AFBC(16x16|SPARSE|SPLIT)` at 4K60. Then add a 10-bit HDMI output.

Sources: LibreELEC.tv master `projects/Allwinner/patches/linux/` 0200–0285 plus 0700 and 0702 (82 files) are in
`le-de33/`. Each git blob SHA matches `vdec-web/dl/le-patches/list.json`, and the sha256 values are in `le-de33/SHA256SUMS`.
Method: (a) a script checked which of each patch's added lines already occur in our tree. (b) A dry-run applied the
patches in order to a scratch copy of the affected files in `/tmp`. The copy was deleted afterwards and our tree was not touched.
The "conflict" counts below are failed hunks from (b). They are approximate, because a failed hunk can cascade into later patches.

## 0. Key findings that shape the plan

1. **Our DE33 is the older `sun4i-drm-refactor` base.** Armbian `patches.drm/0032–0048` corresponds to LE 0200–0213.
   It is regmap-based: no register shadows, no RCQ (`sun8i_rdma.c` is absent).
   The LE AFBC patches 0247/0248 are written against LE's `sun8i_rdma_write()` shadow API (0223–0230).
2. **H616 VI planes expose no YUV at all today.** `sun50i_planes.c` has `.scaler_mask = 0` ("TODO: ... scaling"), so
   `sun8i_vi_layer_init_one()` picks `sun8i_vi_layer_de3_no_yuv_formats`. YUV 4:2:0 always goes through the VI scaler
   for chroma upsampling, even at 1:1. So the scaler enablement chain (LE 0214–0220 → 0231) is a hard prerequisite for AFBC.
   That chain is still regmap-based and mostly applies cleanly.
3. **Zero-copy import needs the DE IOMMU.** Our H616 dtsi gives the VE `iommus = <&iommu 3>, <&iommu 2>`, so cedrus buffers are
   IOVA-contiguous but physically scattered. The DE33 nodes have no `iommus`, and the DRM DMA device is the mixer
   (`sun8i_mixer.c:732`). `drm_gem_dma` import of a scattered dmabuf fails unless the importing device sits behind an IOMMU.
   LE solves this with 0240 (DMA device = `planes_dev`, 40-bit mask) and with `iommus = <&iommu 0>` on `planes@100000` in **0702**.
   (This is reasoning from the code. It was not tested on the board.)
4. **4K60 8-bit RGB HDMI already passes in our tree.** `sun8i_dw_hdmi_mode_valid_h6` allows pixel clocks up to 594 MHz, and dw-hdmi does SCDC/scrambling.
   So AFBC10 4K60 scanout can be proven **before** any HDMI work: the DE converts to RGB and the output is 8-bit.
   The 10-bit link is a separate second stage.
5. **"0283–0285" alone is not the 10-bit path.** They sit on 0256–0282: the bus-format negotiation, the CRTC output-format state,
   the formatter (`sun50i_fmt.c`), TCON halving for 4:2:0, PHY-by-TMDS and deep-colour preference.
   0259/0264/0268/0283/0284 also use the rdma API.

## 1. Per-patch status (LE 0200–0250, 0283–0285; numbers absent from LE: 0204 0206 0208 0234 0237)

| LE | Subject (short) | In our tree? | Evidence / dry-run |
|---|---|---|---|
| 0200 | de2 clk: fix DE3.3 definitions | present | Armbian patches.drm/0032; 24/24 lines |
| 0201 | de2 clk: export regmap for DE33 | present | patches.drm/0035; 18/18 |
| 0202 | DE33 CSC | present | patches.drm/0033; 39/39 |
| 0203 | vi_layer: limit formats for DE33 | present (older rev) | patches.drm/0034; LE adds a `yuv_support` var (37/39) |
| 0205 | DE33 shared plane driver | present (older rev) | patches.drm/0037 `sun50i_planes.c`; probe/device-link differs (108/126) |
| 0207 | switch DE33 to split bindings | present (older rev) | patches.drm/0039; module-init/devlink differ (45/64) |
| 0209–0213 | H616 TCON TOP / R40 LCD / TCON TV / HDMI PHY / DE compatible | present | patches.drm/0041–0045; 100% |
| 0214 | scaler: bulk coeff writes | missing | applies clean |
| 0215 | scaler: coeff offset refactor | missing | clean |
| 0216 | per-channel YUV scanline | missing | clean |
| 0217 | RGB scanline sizes | missing | clean |
| 0218 | scaler types per channel | missing | 1/17 hunks fail (vi_layer `yuv_support`, because 0203 is the older rev) |
| 0219 | VI scaler edge detection | partial | ED register defines already in `sun8i_vi_scaler.h`; clean |
| 0220 | VSU8 scaler type | partial | some defines exist; clean |
| 0221 | mixer: remove RMW | missing | clean |
| 0222 | CSC enable moved to mixer | missing | 1/7 fail (csc/mixer; Armbian TVE `drm-sun4i-mixer-support-yuv-output-on-de33` touched it) |
| 0223–0230 | register shadows, VI/UI/scaler/CSC conversion, RCQ, drop regmaps | missing | 2–18% (context only). Big rework; collides with Armbian 7000 (A523 `uses_rcq`), TVE YUV, megous 0004 |
| 0231 | enable DE33 plane scalers | missing | 1/2 fail; hand-merge `scaler_type` table into our quirks |
| 0232 | layer alpha for VI w/o pixel alpha | partial | Armbian `drm-sun4i-add-pixel-blend-mode-property` covers most; 1 hunk, rdma context |
| 0233 | XRGB2101010 | partial | clean; optional |
| 0235/0236/0238 | DE3 writeback, H6 WB DT, H616 WB routing | missing | `sun50i_wb.c` absent; not needed |
| 0239 | IOMMU DRAM > 4 GiB | missing | not needed (Zero2 has ≤1 GiB) |
| 0240 | share DE33 DMA address space | missing | needed for zero-copy; port only the mixer/planes hunks (drop the WB hunks) |
| 0241 | DE33 AYUV | partial | clean; optional |
| 0242 | layer alpha for XRGB UI | partial | blend-mode patch covers most; 1 hunk, rdma context |
| 0243 | align VI addresses (subsampled) | missing | 1 hunk fails (rdma context); trivial hand-merge; recommended |
| 0244 | drm/gem: AFBC sparse size check | missing | `drm_gem_afbc_min_size()` exists upstream; patch clean |
| 0245 | drm/gem: Y210 AFBC bpp | missing | clean; optional (not AS01) |
| 0246 | sun4i: allocate AFBC fb metadata | missing | clean (`sun4i_framebuffer.c`) |
| 0247 | AFBC decompressor (`sun50i_afbc.c/h`) | missing | applies textually, but **must be rewritten rdma→regmap** (≈25 writes; `afbc_rdma` unit → regmap base `ch*0x20000+0x5000` in planes regmap) |
| 0248 | AFBC on VI planes | missing (9/46 context) | 2/18 fail + rdma→regmap; `format_mod_supported`, modifiers list, AFBC phase in scaler |
| 0249 | enable AFBC on H6 | missing | clean (1 line, H6 only; harmless) |
| 0250 | enable AFBC on H616 (`afbc_mask = BIT(0)`) | missing | clean after 0218/0231 |
| 0283 | 10-bit RGB out (H6/H616) | missing | 3/8 fail; rdma in `sun50i_fmt.c` |
| 0284 | YUV 4:4:4 out | missing | 3/11 fail; rdma + crtc state |
| 0285 | dw-hdmi prefer 10-bit 4:2:2 over 4:2:0 | missing (4/15 context) | clean on top of 0280/0281 |

HDMI dependencies (also missing). Dry-run fails, if any, are in parentheses: 0256 PHY by TMDS clock, 0257 sun8i bridge bus-fmt (1/2),
0258 CRTC output format/encoding (3/13), 0259 CSC output aware (9/14, the heaviest: Armbian's TVE patch already added
`mixer->output_yuv` + RGB2YUV in `sun8i_csc.c`), 0260/0261 Colorspace→AVI/CSC (1/3, 1/2), 0262 TCON halving for 4:2:0,
0264 formatter `sun50i_fmt.c` (3/10, rdma), 0265 YUV 4:2:0 on H6/H616 (6/13), 0266 PHY res by depth, 0267 max_bpc reset,
0268 formatter clamp (rdma), 0269 10-bit 4:2:0 (2/3), 0270 YUV444 video map code (1/4), 0271 AVMUTE, 0272 PHY clk select @594 (1/4),
0280 bus-fmt array size, 0281 prefer deep-colour RGB, 0282 YUV-vs-RGB helper (1/5).
Skip 0251/0252/0253/0263/0274, which are writeback/no-vblank only. 0252 (disable planes on CRTC disable) is a recommended fix but not needed for this goal.

## 2. Minimal ordered port set

Strategy: **stay on regmap and do not port the shadow/RCQ rework 0223–0230 now.** Rewrite each `sun8i_rdma_write(unit, off, v)` as
`regmap_write(layer->regs, unit_base + off, v)`. This is the shape of Jernej's older `de3-afbc` branch (3ecaa72a0036, regmap era).
New patches go into a new `patches.drm/de33-afbc/` block in series.conf after `patches.drm/0048` and **before** the Armbian
TVE/A523 blocks are touched. Leave A523 (`7000`, `sun55i_de.c`) and the TVE output working: the all-features rule applies.

**Stage A – AFBC10 scanout over today's 8-bit RGB HDMI (the 4K60 proof)**
1. LE 0214, 0215, 0216, 0217 (clean).
2. LE 0218, hand-merged: in `sun8i_vi_layer_init_one()` replace `scaler_mask & BIT(phy_index)` with `scaler_type[] != NONE`.
   Convert the remaining `scaler_mask` users in `sun8i_mixer.c` cfgs (DE2/DE3/H6) and in `sun8i_ui_layer.c`.
3. LE 0219, 0220 (ED + VSU8; clean). LE 0221 (clean). LE 0222, hand-merged against the TVE YUV-output hunk.
4. LE 0231, hand-merged: H616 quirks get `scaler_type {[0]=VI_ED,[1]=[2]=[6..8]=VI_8}` and per-channel scanlines (4096/2048).
   This turns on YUV (NV12/YUV420 linear) on DE33 VI planes for the first time. That needs its own board check (step 1 of §3).
5. LE 0243, hand-merged (regmap context).
6. LE 0244, 0246 (clean). 0245 optional.
7. LE 0247, rewritten for regmap: `sun50i_afbc_init(layer, regs)` stores the FBD base. DE33: `ch*DE33_CH_SIZE + 0x5000`
   inside the planes regmap. DE3: `sun8i_channel_base()+0x300`. Region sizes: 0x5c (DE33) / 0x58 (DE3). Add `afbc_mask` to `sun8i_layer_cfg`.
8. LE 0248, rewritten for regmap. Hand-merge the vi_layer hunks: atomic_check AFBC branch (≤4096×4096), atomic_update AFBC
   path, `format_mod_supported`, the per-channel modifier list, and `bool afbc` in `sun8i_vi_scaler_setup()` (also the UI DE33 caller).
9. LE 0250 (+0249 for H6).
10. Zero-copy: the `sun8i_mixer.c` hunk of LE 0240 (`drm_dev_set_dma_dev(drm, mixer->planes_dev)` for DE33) and the 40-bit mask in
    `sun50i_planes_probe()`. From LE 0702, take **only** `iommus = <&iommu 0>;` on `planes@100000` (no writeback node).
    Check that the H616 IOMMU master-0 TLB prefetch is on (`sun50i-iommu.c` variant masks).

Expected Stage A hand-merges: 0218, 0222, 0231, 0243, and the 0247/0248 API rewrite. About 450–550 changed lines; the rest is clean.

**Stage B – 10-bit HDMI (after Stage A shows 60 fps)**
Order: 0256, 0257, 0258, 0259, 0260, 0261, 0262, 0264, 0265, 0266, 0267, 0268, 0269, 0270, 0271, 0272, 0280, 0281, 0282, 0283, 0284, 0285.
Hand-merges:
- 0259: reconcile LE's CRTC-state `engine->format/encoding` with Armbian's `mixer->output_yuv` / `sun50i_mixer_set_output_yuv()`.
  The TVE (composite) path must keep forcing YUV.
- 0258/0284: `sun4i_crtc.h` state subclass vs Armbian `drm-sun4i-a523-crtc-vblank-order` and megous gamma.
- 0264/0268/0283/0284: rewrite the rdma writes in `sun50i_fmt.c` as `regmap_write`/`writel`. The DE33 formatter sits at +0x5000 of the
  per-display region, i.e. the mixer "display" reg window at 0x280000, not the planes window. Check the window size.
- 0265/0269: dw-hdmi `sun8i_dw_hdmi.c` hunks vs Armbian A80 mode_valid / A523 quirks.
- Drop all `sun50i_wb.c` hunks (0263, the 0282 part).

**Alternative (decide after Stage A):** port the full 0223–0230 shadow/RCQ rework. This is the route if DE33 FBD/scaler writes turn out
not to latch atomically under DBUFF. Cost: about 1,000 lines with heavy collisions in `sun8i_mixer.c/h` and `sunxi_engine.h`
(A523 `uses_rcq`, TVE, megous p-boot takeover). In exchange, LE patches would apply nearly verbatim later.

## 3. Board verification (no Kodi)

Prerequisite (user-supplied): a 4K60 HDMI 2.0 sink. Today the board has none (`docs/status.md`: "no display yet").
The sink needs HDMI 2.0 with SCDC; for Stage B it must also be 4:2:0-10 / 4:2:2-capable (EDID Y420CMDB, HF-VSDB DC_30bit_420).
Without a sink, `video=HDMI-A-1:3840x2160@60D` plus `drm.edid_firmware=` (needs CONFIG_DRM_LOAD_EDID_FIRMWARE, not checked) still runs
TCON vblanks. That allows timing and bandwidth tests only, not image checks.

0. **Pre-port bandwidth probe (works on today's kernel):** put a 4K60 XRGB8888 dumb FB on the primary plane (`modetest -s ...@XR24`).
   That is 33.2 MB × 60 = **2.0 GB/s**, more than AFBC10 needs. Run the existing `ffmpeg ... -hwaccel v4l2request -f null` AS01
   decode at the same time with `ve-busy.sh` and VE/MBUS counters. Pass: VE still above 60 fps and no visible underflow artefacts.
1. **After Stage A, static checks:** `modetest -p` / `drm_info` shows `IN_FORMATS` for the VI plane on mixer0 (physical ch0) with
   YUV420_10BIT × AFBC(16x16|SPARSE|SPLIT). Display a linear NV12 test pattern (`modetest -P <vi>@<crtc>:3840x2160@NV12`) to check
   the newly enabled DE33 YUV path.
2. **Single AFBC frame:** a small client decodes one frame. It either imports the dmabuf directly (needs step 10) or copies it into a
   dumb buffer, which removes the IOMMU dependency. Then `drmModeAddFB2WithModifiers` and a 10 s display.
   `/sys/kernel/debug/dri/0/state` should show the AFBC modifier. Check the colours and that there is no block garbage.
3. **Playback client `afbc-kms-play`** (about 400 lines of C, built statically against the same cross-built FFmpeg as `build-ffmpeg.sh`):
   demux → `-hwaccel v4l2request` / `drm_prime` → `AVDRMFrameDescriptor` → `drmPrimeFDToHandle` → cached FB per dmabuf →
   atomic commit (VI plane only; primary/fbcon plane disabled or tiny, see §3.5) with `NONBLOCK|PAGE_FLIP_EVENT`.
   Log every flip event `(sequence, tv_sec, tv_usec)`. Verdict for a 600-frame 2160p60 Main10 clip:
   - flips per second = 60.00 ± 0.05;
   - sequence gaps > 1 = dropped/repeated frames; target 0, at most 1 per 1,000;
   - Δt histogram of flip timestamps around 16.67 ms;
   - decoder queue depth never empty (log `avcodec_receive_frame` latency); `extra_hw_frames` ≥ 4.
   Also capture `ve-busy.sh` load and VE `dram_read/write_cntr` per frame for the bandwidth account.
   mpv is a fallback only. `--vo=drm` is not zero-copy. The zero-copy route is `--vo=gpu --gpu-context=drm --hwdec=drm`
   (drmprime overlay), and it needs mpv built against the v4l2request FFmpeg plus GBM/Panfrost. Whether mpv maps the newer
   v4l2request hwdevice and passes AFBC modifiers is **unverified**.
4. **Stage B:** set the connector `max bpc`=10 (0267 also restores the default) and run with `drm.debug=0x04`. The bridge
   bus-format selection must log `UYYVYY10_0_5X30` (4:2:0-10) or `YUV10/UYVY12`-based 4:2:2. Confirm on the TV info OSD.
   Set `Colorspace=BT2020_YCC` and `HDR_OUTPUT_METADATA` for PQ clips. Repeat the 600-frame test.
5. **Bandwidth budget (DDR3-1440 ×32: 5.76 GB/s peak; assume about 3.5–4 GB/s usable):**
   - VE AFBC10 decode: counters give 9.86 MB read + 5.06 MB write per frame (units of 8 B), i.e. **0.90 GB/s at 60 fps**.
     At 83.6 fps this is 1.25 GB/s, so the decoder is limited by VE compute/latency, not by DRAM. Whether these counters cover
     every VE master is unverified.
   - DE AFBC10 scanout, worst case 15 bpp body + 16 B/block header: 15.55 + 0.52 MB ≈ 16.1 MB per frame → **≤0.97 GB/s**.
     Real content is lower. For comparison, linear P010 would be 1.49 GB/s.
   - The real risk is a full-screen UI/fbcon plane: 4K XRGB8888 adds **2.0 GB/s**, about 3.9 GB/s in total. Disable it during
     playback, or keep an OSD at 1080p once UI scalers are on (0231 enables VSU8 on ch6–8).
   - The DE is a hard real-time master and VE is bursty. With the DE behind the IOMMU, page-table walks add fetch latency.
     A DE33 FIFO-underflow status bit was not found in mainline, so the only underflow evidence is visual artefacts and flip jitter.
6. **dw-hdmi on H616:** the controller cap is 594 MHz TMDS character rate (comment in our `mode_valid_h6`; LE 0269/0285).
   4K60 (594 MHz pixel clock):

   | Output | TMDS | Fits? | Needs |
   |---|---|---|---|
   | RGB/4:4:4 8-bit | 594 MHz | yes (today) | scrambling, 0272 recommended |
   | RGB/4:4:4 10-bit | 742.5 MHz | **no** | – |
   | YUV 4:2:0 8-bit | 297 MHz | yes | 0256 0262 0264 0265 |
   | YUV 4:2:0 10-bit | 371.25 MHz | yes | + 0266 0268 0269; sink DC_30bit_420 |
   | YUV 4:2:2 10-in-12-bit | 594 MHz | yes | + 0270 0281 0284 0285; dw-hdmi CSC 4:4:4→4:2:2 |

   4:2:2 keeps full vertical chroma, and LE prefers it (0285). 4:2:0-10 has the most TMDS headroom (371 MHz) and is the
   fallback for marginal cables/PHY. The TCON clock halves for 4:2:0 (0262); the DE clock stays at 600 MHz against a 594 MHz pixel rate.

## 4. Effort and risks

| Phase | Work | Estimate |
|---|---|---|
| 0 | bandwidth probe with existing kernel (needs sink) | 0.5 day |
| A | ~14 patches, 6 hand-merges incl. 0247/0248 regmap rewrite, IOMMU/DT, one kernel build with ccache | 2–3 days + 1–2 days board debug |
| client | `afbc-kms-play` + flip-timestamp logging | 1 day |
| B | 22 patches, ~8 hand-merges (0258/0259/0264/0265/0269/0283/0284 heavy) | 3–5 days + 1–2 days with a 10-bit sink |
| alt | full 0223–0230 RCQ rework instead of regmap | +4–6 days |

Risks, highest first:
1. **Register latching without RCQ.** LE moved DE33 to RCQ "to latch display state atomically" (0229). If the FBD (+0x5000)
   or VSU registers are not covered by DBUFF double-buffering on DE33, regmap writes could tear or produce garbage on flips at 60 Hz.
   Mitigation: fall back to the RCQ rework.
2. **DE IOMMU.** Turning on master 0 changes every display allocation, including fbcon and TVE: fault handling, TLB prefetch,
   reset of sibling masters (we carry a patch for that). Without it there is no zero-copy.
3. **VI scaler throughput at 4K60 4:2:0 1:1.** The BSP "ability" check (600 MHz × 80% / (2160 × 60 × 3840) = 96 < 100) wants
   vertical coarse scaling for linear YUV. 0248 bypasses that check for AFBC, so it is untested whether the ED-VSU10 keeps up.
4. **Bandwidth/latency** with an OSD plane enabled (see §3.5). DDR3-1440 has headroom only if the UI plane stays small.
5. **Stage B merge debt** against Armbian's TVE YUV-output patch (0258/0259). Keep composite out working: re-test TVE.
6. 0248 caps AFBC at 4096×4096: fine for UHD and DCI 4K, not for the 6K H.265 decode we enabled.

## 5. Not verified

- No patch was applied to the real tree, built or booted. Conflict counts come from a GNU `patch` dry-run on copied files and include cascades.
- DE33 DBUFF coverage of FBD/scaler registers. Whether dmabuf import fails without the DE IOMMU (reasoned from `drm_gem_dma` + DT, not run).
- The VE counter scope, i.e. whether the per-frame VE DRAM bytes include all masters. The MBUS counter units.
- Whether a DE33 underflow status register exists. Whether CONFIG_DRM_LOAD_EDID_FIRMWARE is set.
- mpv/GStreamer support for v4l2request + AFBC modifiers. Where LE commit 77c51768df (extra vblank wait on DE3) lives.
  Our tree uses the stock `drm_atomic_helper_commit_tail_rpm`, so it is probably not affected.
- LE's full display series against our base beyond 0285. LE numbers 0204/0206/0208/0234/0237 (absent from LE's list).
- Any real 4K60 sink behaviour (EDID, 4:2:2/4:2:0-10 support, scrambling at 594 MHz).
