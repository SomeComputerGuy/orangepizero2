# Display tearing on the H616 DE33 (docs/status.md item 9): root cause, fix, board check

Agent task 2026-11-05. State for a fresh agent: section "RESULTS" at the end. Raw material:
harness/research/display-tearing/ (vendor DE33 lowlevel sources under dl/, runner package under runner/),
kernel-check/display-tearing/ (patch scratch tree a/ b/, build-check.log).

## 1. Earlier observations (what "display tearing" on the work list rests on)

- harness/research/impl-de33-afbc.md, rounds 2 and 3 (2026-11-03, image kernels #11/#12, fake 4K60 EDID, no sink):
  afbc-kms-play `--pattern XR24` at 3840x2160@60 on the primary plane: 60.04 flips/s, commits a mean **1.50 ms after the
  previous vblank, every one of 1499 inside the active video** (the 4K60 blanking is 0.667 ms). NV12 on the VI plane:
  1.84 ms. AFBC10 HEVC playback: mean 6.1 ms, 223 of 599 commits after the blanking; in real playback with the decoder
  ahead 92-97 % of commits fell inside the blanking only because the client commits right after the flip event.
  Section 6 there: "DE33 has no DBUFF on our regmap path, so plane registers take effect the moment the commit worker
  writes them ... tearing is likely on roughly 3-8 % of frames, near-certain for a compositor that commits at arbitrary
  times". Decision 2026-11-03 (option C): change nothing until tearing is confirmed; options A (defer the writes to the
  vblank IRQ) and B (RCQ port, LE 0223-0230) need the user's OK.
- harness/research/vdec-perf/de33-afbc-plan.md:193: the same risk noted before the AFBC work.
- The desktop/mpv sessions (impl-desktop-ffmpeg*.md) forced HDMI-A-1 on at 1024x768 for fbcon/mpv runs; with no sink
  nobody could see a torn frame, so the item stayed open as "Display tearing" without a measurement.
- A523 (sun55iw3) in the same tree: the v35x RCQ backend (sun55i_de.c) and sun4i_tcon.c carry a finished tearing
  investigation on hardware: arming the RCQ load from atomic_flush "applies the new datapath mid-frame -> tearing and
  momentary background-colour flashes"; the arm was moved into the TCON vblank IRQ, beam-gated on the TCON line counter
  (TCON+0xfc), with the vendor's arm target (disp_mgr_protect_reg_for_rcq) as reference.

## 2. Root cause (driver, c19 tree kernel-check/work-cumul/linux-7.3.1/drivers/gpu/drm/sun4i)

Register update path for a page flip on H616:
1. `drm_atomic_helper_commit_planes` -> `sun8i_vi_layer_atomic_update` / `sun8i_ui_layer_atomic_update` -> `regmap_write`
   on `layer->regs` = the **planes regmap** (sun50i_planes.c, planes@100000, plain MMIO, channel window
   `channel * 0x20000`: CSC +0x800, overlay +0x1000, scaler +0x4000, AFBC decompressor +0x5000).
2. `sun4i_crtc_atomic_flush` -> `sun8i_mixer_commit` -> blender writes (`regmap_write` on `engine->regs`, the mixer's
   **"display" regmap**, mixer@280000, plain MMIO), then
   ```c
   if (mixer->cfg->de_type != SUN8I_MIXER_DE33)
           regmap_write(engine->regs, SUN8I_MIXER_GLOBAL_DBUFF, SUN8I_MIXER_GLOBAL_DBUFF_ENABLE);
   ```
   DE2/DE3 double-buffer every register in hardware and swap the whole set at the next vblank when this bit is set at the
   end of the commit. **DE33 has no GLB_DBUFF** (its top block, DT reg `<0x8100 0x40>`, holds RT_EN at +0x0, status +0x4,
   size +0x8, clock +0xc and the RCQ registers from +0x10: RCQ_CTL = vendor `RTMX_RCQ_CTL_OFFSET(disp) = 0x8110 +
   disp*0x40`, the very register the A523 backend kicks). Our DE33 path uses neither, so every write in steps 1-2 is live
   the moment the commit worker issues it, at an arbitrary scan line.
3. `sun4i_crtc_atomic_flush` arms the page-flip event; `sun4i_tcon_handler` sends it at the next vblank
   (`drm_crtc_handle_vblank` + `sun4i_tcon_finish_page_flip`) and calls `engine->ops->vblank_quirk(engine, cur_line)`
   with the TCON line counter (TCON+0xfc) - the DE33 engine ops (`sun50i_engine_ops`) had no vblank_quirk.

Consequences, by register:
- overlay/decompressor base address (`SUN8I_MIXER_CHAN_VI_LAYER_TOP_LADDR`, FBD_LADDR): the fetch switches buffers at the
  current line -> a classic tear line. At 1024x768@60 a commit 4 ms after vblank is at line ~160.
- `LAYER_ATTR` enable/format, blender `PIPE_CTL`/`ROUTE`, scaler size/steps: a partial frame with the new state,
  i.e. the background-colour flash and garbage the A523 team saw on hardware.
- VSU coefficients are the one exception: they have their own `COEFF_RDY` latch.

Who commits where: afbc-kms-play commits right after the flip event, so most of its commits fall inside the blanking by
luck (the measured 1.5 ms mean at 4K60 is already outside); fbcon, Xorg/modesetting, mpv `--vo=drm`/gpu, GStreamer
kmssink commit when a frame is ready, i.e. anywhere in the frame. With no sink attached to the board the torn frame is
not observable; the register write time is.

## 3. Vendor BSP comparison (harness/research/display-tearing/dl/vendor-disp2-5.4-sun50iw9/, fetched 2026-11-05 from
orangepi-xunlong/linux-orangepi orange-pi-5.4-sun50iw9, drivers/video/fbdev/sunxi/disp2/disp/)

- H616 User Manual V1.0 (docs/vendor), DE feature list p. 296: "Supports Register Configuration Queue for register update
  function" and "Supports write back only for high efficient dual display and miracast". No DE register descriptions.
- de_lowlevel_v33x_de330_de_feat.h: `#define RTMX_USE_RCQ (1)`: the vendor H616 driver updates the datapath through the
  RCQ DMA (register blocks in DMA memory, `de_rcq_head` list, `de_top_set_rcq_update()` writes RCQ_CTL = 1). The load is
  issued from the vsync path with a software gate: `disp_mgr_protect_reg_for_rcq()` sets `rcq_update` after the frame's
  configuration is written and waits for the RCQ finish IRQ before the next one (de_disp_manager.c:918).
- The AHB fallback (`RTMX_USE_RCQ` off) is exactly a software shadow written at vblank: `sync_event_proc()` (the TCON vsync
  interrupt, de_disp_display.c:804) -> `disp_sync_all()` -> `mgr->sync()` -> `disp_al_manager_sync()` ->
  `de_rtmx_update_reg_ahb()` (de_rtmx.c:318), which memcpy()s every dirty shadow block into the hardware registers,
  guarded by `bsp_disp_shadow_protect()` so a half-written configuration is never copied.
- Neither vendor path writes a DE33 datapath register from process context during active video. Our DE33 path did.
- The vendor also has a write-back unit (de_wb.c, RTWB at DE+0x10000 with its own RCQ at 0x8200; LE patches 0235 "Add
  DE3 writeback support" and 0238 "clk-sunxi-ng de2: Allow H616 writeback routing register" exist in LibreELEC) - a DRM
  writeback connector would allow a scanout readback test; not in our tree (work list, section 6).

## 4. Fix (armbian-build branch `fix/sunxi-h616-de33-vblank-latch`, worktree wt-display-tearing, commit b04527be4, fork only)

Patch `patches.armbian/drm-sun4i-de33-latch-the-mixer-and-plane-registers-at-vblank.patch` (+ series.conf), 572 added lines:
- New `sun50i_shadow.{c,h}`: a bus-less regmap (`reg_read`/`reg_write` callbacks) in front of an MMIO block. Writes land in
  a staging copy (4 KiB pages allocated on first use; the DE33 uses ~30 of them), `sun50i_shadow_commit(range)` snapshots
  the staged words into a latch copy, `sun50i_shadow_flush(range)` writes the latched words to the hardware
  (`writel_relaxed`, spinlock, hard-IRQ safe). Reads return the staging copy (the one remaining RMW,
  `sun50i_mixer_set_output_yuv`, stays correct).
- `sun50i_planes.c`: the planes regmap becomes such a shadow; `sun50i_planes_commit(dev, mixer)` /
  `sun50i_planes_flush(dev, mixer)` act on the channel windows of that display only (the planes device is shared by
  mixer0/HDMI and mixer1/TVE).
- `sun8i_mixer.c`: for `DE33 && !uses_rcq` the "display" regmap becomes a shadow too. `sun8i_mixer_commit()` ends with
  `sun50i_mixer_latch_commit()`: snapshot both shadows for this display, set `latch_pending`, and `drm_crtc_vblank_get()`
  so the TCON interrupt stays on until the flush (legacy cursor updates have no event and would otherwise never flush).
  If the get fails the CRTC is off (planes of a modeset are programmed before the CRTC enable; after a disable): nothing
  scans out, write at once. New `sun50i_engine_ops.vblank_quirk = sun50i_mixer_vblank_quirk` flushes from the TCON vblank
  IRQ and drops the reference. `mode_set` records `line_active = crtc_vtotal - crtc_vsync_start` (TCON TV counter zeroed
  at vsync start, as measured on sun55iw3). A flush the IRQ services late (beam already in active video) is still written
  and counted: never worse than today, where every write is "late".
- Diagnostics, read-only module params `/sys/module/sun8i_mixer/parameters/de33_latch_{commits,coalesced,flushes,
  flushes_sync,flushes_late,words_max,ns_max,line_min,line_max,line_active}`. Frame-coherent means `flushes_late == 0`
  and `line_max < line_active`.
- Unchanged: DE2/DE3 (GLB_DBUFF), A523 RCQ, the TVE encoder, the "top" block, every regmap address and value the driver
  programs (the shadow replays the same words). Nothing is disabled.
- Semantics vs DRM: the flip event is still sent from the same vblank IRQ (a few us before the flush, same frame); the
  snapshot gives the frame boundary GLB_DBUFF gives in hardware, so a blocking commit that starts before the previous
  one's vblank is not mixed into it.
- Host check: `ARMBIAN=wt-display-tearing WORK=kernel-check/work-tearing STAGE=dtbs kernel-check/build-kernel.sh`: 841
  patches applied, 0 failed, dtbs exit 0 (the 17 known a64/h5 dtc warnings), 58 H616 overlays; `make W=1
  drivers/gpu/drm/sun4i/`: exit 0, no warnings (kernel-check/display-tearing/build-check.log).
- Not done, by the 2026-11-03 decision: option B (RCQ port, LE 0223-0230 / the A523 sun55i_de backend generalised).
  RCQ_CTL for the H616 is at top+0x10, same as A523, so that port stays possible later; it is a larger change and not
  needed for frame-coherent updates.

## 5. Mechanical check without a monitor (runner job 19, package harness/research/display-tearing/runner/)

- afbc-kms-play gained `-D/--commit-delay US` (pattern mode: sleep after each flip event before the next commit), so the
  commit, and on the stock kernel the register write, can be placed deep in the active video on purpose. Rebuilt
  (harness/afbc-kms-play/out/afbc-kms-play, sha256 fb2dc4a3...), 0 warnings.
- The job forces HDMI-A-1 on (`echo on > status`, no sink; DRM's built-in 1024x768 mode; if it is missing the chunk is
  NOT TESTED) and runs 600 XR24 page flips three times per kernel: d0 (commit right after the flip), d4 (4 ms later,
  line ~190 of 806), d12 (12 ms later), on the stock image kernel (baseline: the client's commit phase = write time) and
  on the fixed cumulative kernel, reading de33_latch_* before and after each run.
- Pass criteria (HANDOFF.md): 60 flips/s, no sequence gaps on all runs; on the fix kernel `flushes_late_delta == 0`,
  `line_max < line_active (35)`, one flush per flip, `ns_max < 500 us`, while the client's own commits for d4/d12 are all
  outside the blanking (so the write time is proven decoupled from the commit time); no WARN/flip_done timeout.
  If the TCON line counter does not run 0..vtotal from vsync start on H616 (unverified assumption, taken from the A523
  measurement), the line checks fail mechanically and `line_min/line_max` say what the counter does: then adjust
  `sun50i_mixer_latch_mode_set()` rather than the test.

## 6. Open items / work list

- Visible confirmation needs a sink: a real display or an HDMI capture device, or a DRM writeback connector for the DE33
  write-back unit (vendor de_wb.c; LE 0235/0238) which would allow a scanout CRC/readback test with alternating full-screen
  patterns. Work-list item, not started.
- Datasheet W-item overlap: DE33 10-bit/HDR formatter (W-items) are unaffected.
- If job 19 shows late flushes > 0 under load (IRQ latency > 0.7 ms), the next step is a beam-gated hrtimer retry like
  sun55i_de_schedule_arm(), holding the flip event until the write lands.

## RESULTS (state for a fresh agent)

- Root cause: section 2 (DE33 registers live on write; no GLB_DBUFF, RCQ unused; writes from the commit worker).
- Fix: b04527be4 on fix/sunxi-h616-de33-vblank-latch (fork), host-build-checked, NOT merged, NOT board-tested.
- Board check queued: harness/runner-queue/19-display-tearing.md (needs the fix in the next cumulative kernel, c20+).
- Next: coordinator merges b04527be4 into test-cumulative, builds/serves; runner runs job 19; a fresh agent judges
  done/19-display-tearing.summary.md with HANDOFF.md checks 0-7 and, if green, moves status item 9 "Display tearing" to
  "fixed, mechanically verified; visible confirmation pending a sink / writeback connector".
