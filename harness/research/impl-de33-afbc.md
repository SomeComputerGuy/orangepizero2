# DE33 AFBC scanout, Stage A (H616 / Orange Pi Zero2, sunxi-7.3, 7.3.1)

Status 2026-11-03: host phase done. The board phase was **partly run, then paused** for a
reflash (about 01:37–01:45 UTC). See "Board results, round 1". AFBC playback has not run yet.

Branch: `feat/sunxi-h616-de33-afbc` (worktree `/home/aruni/orangepizero2/wt-de33`,
based on stonking-orangepizero2 cf62ac65a). One commit, 1f852632b, by Arun Iyengar
with the trailer `Assisted-by: Claude:claude-opus-5-5`. Pushed to `fork`
(SomeComputerGuy/build) and not merged.

## Series block

`patch/kernel/archive/sunxi-7.3/patches.drm/de33-afbc/` is in series.conf right
after `patches.drm/0048-T95-broken-CD.patch`. The patches come from LibreELEC.tv
projects/Allwinner/patches/linux (Jernej Skrabec), and Jernej stays the author.
Changed patches carry an `[aiyengar: ...]` note.

| Patch | Status |
|---|---|
| 0214 scaler bulk coefficient writes | verbatim |
| 0215 coefficient offset refactor | verbatim |
| 0216 per-channel YUV scanline | verbatim |
| 0217 RGB scanline sizes | verbatim |
| 0218 per-channel scaler types | hand-merged (older DE33 cfg layout in our tree) |
| 0219 VI scaler edge detection | verbatim |
| 0220 VSU8 | verbatim |
| 0221 remove read-modify-write | verbatim |
| 0222 DE3 CSC enable to mixer | include-context merge (megous takeover include) |
| 0231 enable DE33 plane scalers | context merge |
| 0243 align VI addresses (subsampled) | context merge |
| 0244 drm/gem AFBC size validation (sparse) | verbatim |
| 0246 allocate AFBC fb metadata | context merge |
| 0247 AFBC decompressor regs | **ported** from LE register shadows to regmap: `sun50i_afbc_write()` does `regmap_write(layer->regs, layer->afbc_base + reg)`. The FBD base is `ch*0x20000+0x5000` on DE33 (planes regmap) and `ch_base+0x300` on DE3 |
| 0248 AFBC on VI planes | **ported** to regmap (the stock commit path) |
| 0249 enable AFBC on H6 | verbatim |
| 0250 enable AFBC on H616 (`afbc_mask = BIT(0)`) | verbatim |
| 0240 shared DE33 DMA address space | partial: the mixer uses `drm_dev_set_dma_dev(drm, planes_dev)`. **DMA mask is 32-bit, not LE's 40**, because H616 DRAM is below 4 GiB and the IOMMU is 32-bit |
| dt-bindings: DE33 planes may have `iommus` | new (own) |
| arm64 dts h616: `iommus = <&iommu 0>` on planes@100000 | new (own; LE 0702 minus writeback) |

Not carried:
- LE 0223–0230 (register shadows/RCQ). We stay on regmap as the brief asks.
- 0245.
- The other LE writeback/RCQ patches.

Two existing Armbian patches had to change, because they define mixer cfgs that
use the removed `scaler_mask`. Both keep their previous behaviour:
- `patches.armbian/drm-sun4i-support-the-h3-and-h5-tv-encoders.patch` (H3 mixer1):
  `scaler_type = {VI_10, UI}`, `scanline_yuv = {2048}`, `scanline_rgb = {2048, 2048}`.
- `patches.armbian/7000-drm-sun55i-a523-hdmi.patch` (A523 mixer0):
  `scaler_type = {VI_10, UI, UI, UI}`, `scanline_yuv = {4096}`, `scanline_rgb = 2048 x4`.
  2048 is the fixed RGB scanline that applied before 0217.
- 0247 adds `sun50i_afbc.o` on a separate Makefile line, so that 7000's Makefile hunk context still applies.

Semantics checked by reading the code (not on hardware):
- TVE CSC paths: YUV420_10BIT gets YUV2RGB, or YUV2YUV when the output is YUV.
- DE3 never reaches the new CSC modes.
- Premultiplied blend mode is unaffected.
- fbdev-dma behind the IOMMU sets FBINFO_HIDE_SMEM_START, so the is_vmalloc WARN does not fire.
- All 285 later patches (megous, TVE, A523, ...) apply on top.

**Risk #1 (unverified):** DE33 has no DBUFF on our regmap path, so register writes
latch immediately. An AFBC plane update in mid-frame may tear. The vendor BSP's
non-RCQ "AHB" path does the same. The test client therefore logs each commit's
phase relative to vblank. If the board shows tearing, the fallback is to port
the RCQ rework (LE 0223–0230). Per the brief, that needs the caller's approval first.

## Host checks (all pass)

- STAGE=patch (WORK=kernel-check/work-de33/kb): **769 applied, 0 failed**.
- STAGE=all: build exit 0 with **0 C warnings**. dtbs exit 0. The 17 dtc warnings
  are the existing a64-pine64-7inch-lcd overlay and the nanopi-r1s-h5 warnings,
  none of them H616. 55 H616 overlays were built.
- DT_CHECK passes for: planes@100000 (which now has `iommus = <0x0e 0x00>`), tv-encoder@6524000 and tcon_tv1_out_tve.
- `make W=1 drivers/gpu/drm/sun4i/` is clean (0 warnings). It ran on the scratch replay tree
  (kernel-check/work-de33/src, log out/w1-sun4i.log), whose sources are
  identical to the kb build tree.
- Incremental ccache rebuild: STAGE=all rerun in 283 s, ccache 10651/10652 hits (99.99%); same results (exit 0, 0 C warnings, dtbs 0, DT_CHECK ok).
- Note: the first kb build was cold. It also downloaded the 7.3.1 tarball and cloned uwe5622 into
  kb/dl. Both are byte-identical to the existing cached copies (tarball sha256 fa595aad…,
  uwe5622 commit f88cd0d…), so this was a redundant fetch, not new software.

## Test client: harness/afbc-kms-play/

- `afbc-kms-play.c` is built statically against the cross-built FFmpeg
  (kernel-check/ffmpeg-afbc/install) by `build.sh`. It builds with 0 warnings, is about 19.5 MB, and needs only
  libm, libdrm, libudev and libc. A qemu-aarch64 usage smoke test passes.
- How it works:
  - A decoder thread feeds a bounded queue.
  - Atomic commits use NONBLOCK|PAGE_FLIP_EVENT.
  - Framebuffers are cached per dmabuf.
  - COLOR_ENCODING/RANGE come from the stream.
  - The primary plane is disabled, unless `-k` keeps it as an OSD (then the VI plane gets zpos 2).
- Options: `-f AS01` (AFBC10, the default), `AS12` (AFBC8) or linear P010/NV12, `--pattern NV12|XR24`, `--list` (IN_FORMATS).
- It writes a per-flip CSV and a summary: flips/s, interval mean and sd, seq gaps, underruns, a histogram, commit phase vs vblank, and decode latency.
- `mkedid.py` → `opiz2-fake4k60.bin` is a fake EDID with 3840x2160@60 (594 MHz, VIC 97) preferred, plus 1080p60 and HF-VSDB/SCDC. Both checksums are OK.
- `board-de33.sh <out> probe|full` is the board test script (§3.0 probe, then the full matrix incl. a devmem dump of the FBD registers at 0x01105000).
- `de33-fallback.sh/.service` restores the DTB and armbianEnv after 280 s without /run/vdec-ok. It complements vdec-fallback, which restores Image/modules.

## Board artifacts (ready, unshipped)

In kernel-check/vdec-serve:

| File | Size | sha256 (prefix) |
|---|---|---|
| Image.de33a | 37,321,216 B | e91ab614742c16f3 |
| modules-de33a.tgz | 33 MB, top dir 7.3.1/, INSTALL_MOD_STRIP=1 so .BTF is kept | 1a8e03bdc66c1f4d |
| sun50i-h616-orangepi-zero2.dtb.de33a | 53,328 B | 2323a9b0b9021759 |

## Board results, round 1 (paused for reflash)

Raw data: harness/afbc-kms-play/results-2026-11-03/de33-out/.

**Image kernel (7.3.1-edge-sunxi64 #8, unmodified image DTB) with the fake EDID:**
- **The DE faults in the IOMMU as soon as HDMI scans out.** From fbcon takeover onward,
  master 0 faults every frame at 0x7bd00000/0x7bd01000. That address is the fbcon CMA buffer,
  a physical address being treated as an IOVA. Our sun50i-iommu writes BYPASS=0 for every
  master once cedrus attaches, and the DE is not mapped. Earlier boots never showed this
  only because HDMI was never active (no sink); serial.log has no master-0 faults before this boot.
  Expect the same with a real monitor on the image kernel. The Stage A dtsi change fixes it.
- Allocating a 4K XR24 dumb buffer fails with ENOMEM (CMA is 64 MB). The §3.0 probe could
  not run on the image kernel.
- The fbdev client re-probe prunes modes wider than fbcon's buffer (VIRTUAL_X), so sysfs `modes`
  shows only 720x480. A userspace GETCONNECTOR probe still lists 4K60 (594 MHz) as valid.

**Trial kernel (Image.de33a + DTB):**
- **Boot:** clean. No oops or WARN. 1100000.planes and the VE share IOMMU group 0. There are no
  master-0 faults; one master -1 fault (0xfff00000) appears at fbcon takeover.
- **EDID:** the firmware is requested at 1.17 s, before the rootfs is mounted (ENOENT). It loads after
  `echo on > /sys/class/drm/card0-HDMI-A-1/status`. To have it at boot, ship it in the
  initramfs or `CONFIG_EXTRA_FIRMWARE`.
- **IN_FORMATS, VI plane 35:** YU10 AFBC 16x16 with SPARSE, YTR|SPARSE, SPLIT|SPARSE and
  YTR|SPLIT|SPARSE, plus linear NV12/YU08/YU10. **YU08 AFBC is offered only as SPARSE and YTR|SPARSE, without SPLIT.**
  The FFmpeg 8-bit descriptor uses SPLIT|SPARSE, so the AS12 path is expected to be refused.
  Not yet checked whether the H616 FBD can do 8-bit split.
- **§3.0 probe, VE throughput** (ftrace cedrus_device_run→irq, HEVC Main10 2160p60 decoded as AS01):

  | Condition | VE-bound fps | Avg per job |
  |---|---|---|
  | No scanout | 83.6 | 11.96 ms |
  | 4K60 XRGB8888 flipping on the primary plane | **56.8** | 17.61 ms |

  So 4K XRGB scanout costs about 32% of VE throughput through DRAM contention. It is
  pessimistic for AFBC10 (4 B/px vs about 1.9 B/px), but 4K60 Main10 has little headroom.
- **Flip timing so far is not valid kernel data.** XR24 ran at 12.3 flips/s and NV12 at 8.1 flips/s with no
  underruns. Pattern mode repainted the whole 4K buffer on the CPU every frame through the
  uncached dumb mapping, which made it client-bound. That is fixed on the host (now only the 16-column bar stripes
  are redrawn; the client builds with 0 warnings) but not yet re-measured.
- **Not run:** AFBC HEVC/VP9 playback, the commit phase vs vblank for AFBC (the tearing check), the FBD
  register dump, OSD, AS12, TVE.

## Board phase: remaining (after reflash)

Planned once the caller hands the board over:
1. Image.de33a and modules-de33a.tgz (in kernel-check/vdec-serve), installed via install-kernel.sh and the vdec-fallback unit.
2. The EDID goes in /lib/firmware/edid, with `drm.edid_firmware=HDMI-A-1:edid/opiz2-fake4k60.bin video=HDMI-A-1:3840x2160@60D`.
3. Run the probe on the image kernel, then the full run on the trial kernel.
4. Restore the image kernel and reboot.

Doable without a display: IN_FORMATS, the IOMMU/fbcon boot, the flip rate and seq gaps at
4K60 timing, the FBD register dump, and the decode-to-flip budget.

**Need a real 4K display (pending):**
- visible picture correctness
- tearing
- colour/range
- the HDMI 2.0 594 MHz TMDS/SCDC link
- the TVE composite picture

None of these spec rows ("H.265 MP10 4K@60" and "VP9 P2 4K@60" on display) can be marked
met yet.

## Board results, round 2 (image 16cdd50a9, 7.3.1-edge-sunxi64 #11, Stage A merged), 2026-11-03

Raw data: harness/afbc-kms-play/results-2026-11-03-image16cdd50a9/de33-out/. No kernel was installed, only
the fake-EDID extraargs, which have since been restored. Afterwards the board was rebooted: serial shows `DRAM: 1024 MiB`, the image
kernel is running, and the boot shows 0 IOMMU faults.

**Display-engine IOMMU:** planes and the VE are in IOMMU group 0. There are no master-0 faults. One master -1 fault
(0xfff00000) appears at fbcon takeover.

**IN_FORMATS:** the libdrm iterator bug is fixed in the client (it now parses the blob by hand). VI plane 35 offers
SPARSE and SPLIT|SPARSE for YU08, YU10, YUYV and Y210, and YTR only on RGB. This matches the driver table, so the
round-1 claim "YU08 has no SPLIT" was a client bug.

**XR24 4K pattern on the primary plane (draw-once client):**
- 60.04 flips/s; 1498 of 1499 intervals in the 16.2–17.2 ms bucket.
- Commits land a mean 1.50 ms after vblank (vblank is 0.667 ms). Every commit lands during active scanout.

**NV12 linear 4K on VI plane 35:** 59.34 flips/s, 598 of 600 in-bucket, commit phase mean 1.84 ms.

**VE throughput (HEVC Main10 4K60, AS01 to null):**

| Condition | VE-bound fps |
|---|---|
| No scanout | 83.9 |
| 4K XR24 scanout | 63.0 |
| During AFBC playback through the client | 49.9 (20.0 ms per job) |

**AFBC10 HEVC Main10 2160p60** (YU10, modifier 0x...61 = SPLIT|SPARSE, accepted by atomic commit):
- 48.7 flips/s with 131 sequence gaps.
- 182 flips found the queue empty, so the decoder is the limit, not KMS. With 9 buffers in the queue, receive_frame
  latency is ≈0.
- 468 of 600 intervals were in-bucket.
- Commit phase: mean 6.1 ms after vblank, and 223 of 599 commits landed after the blanking. The remainder landed
  inside it because the commits were late; they are not phase-aligned.

**Open problems at the time (all resolved in round 3, below):**
1. The debugfs state captured 5 s into the AFBC run shows plane 35 with fb 86 as **P010, modifier 0x0, pitch 7680**,
   allocated by afbc-kms-play. Yet the client logged YU10/AFBC and 42,118,176-byte dmabufs. That size is larger than
   AFBC10 4K (17.2 MB) and P010 (24.9 MB). Either the descriptor path fell back to linear P010 (check fb_for_desc
   and the FFmpeg fork's descriptor), or the state was read during a different commit.
   **Until this is resolved, the AFBC scanout path is NOT proven.**
2. The FBD register dump at 0x01105000–0x0110505c read all zeros during playback. This fits (1), i.e. no AFBC
   on the plane, but my base address may also be wrong.
3. Tearing: the DE33 path without DBUFF commits during active scanout (1.5–6 ms after vblank). Whether the DE33
   latches at vblank cannot be decided without a sink. **A real display is needed.**

**Not run, cut by the time box:** VP9 P2 (interrupted at start), OSD, AS12 8-bit, TVE.


## Board results, round 3 (image 4321861ff, 7.3.1-edge-sunxi64 #12, Stage A 1f852632b merged), 2026-11-03

Raw data: harness/afbc-kms-play/results-2026-11-03-image4321861ff/. No kernel was installed. armbianEnv.txt was
restored at the end; the final boot shows `DRAM: 1024 MiB`, the image kernel, and 0 IOMMU faults, flip_done errors or WARNs.

### 1. Why rounds 1–2 showed "AFBC" as linear P010 in 42 MB buffers

**Root cause: userspace, not the kernel.** `kernel-check/ffmpeg-afbc/install` held a `libavutil.a` from 22:33.
The `V4L2REQUEST_PIXFMT` override was added to `hwcontext_v4l2request.c` at 22:41. The build tree was
rebuilt then, but `make install` was never re-run, so the client linked a libavutil without the override.
- The client's `setenv("V4L2REQUEST_PIXFMT", "AS01")` did nothing.
- FFmpeg took cedrus's first 10-bit CAPTURE format, P010, and exported it as linear P010.
- The "format YU10 modifier 0x...61" line the client printed was only its plane-selection request.

42,118,176 bytes is exactly the 4K AFBC10 size (17,234,976) plus the P010 size (24,883,200). Cedrus's 10-bit
P010 mode keeps an AFBC reference image next to the linear output. That size is inferred from the arithmetic;
I did not check it in the code of the image's cedrus.

**Fix:** re-ran `make install` (incremental, no recompiles). The client now logs each buffer's real descriptor
format, modifier, plane count and pitch, and warns when AS01/AS12 was requested but the buffer is not AFBC.

**Proof that the AFBC path is taken:**
- Buffers are 17,234,976 bytes (AFBC10) or 13,057,056 bytes (AFBC8), with one plane, pitch 0 and modifier 0x0800000000000061.
- debugfs shows plane 35 with fb YU10 and modifier 0x800000000000061.
- The FBD registers read during playback: FBD_CTL (0x01105000) = 0xFF000015 (enabled), 0x5008 = 0x086F0EFF
  (3839x2159), 0x5004 = 0x00003210. In round 2 these were all zero, which confirms that run never used AFBC.

### 2–4. Playback on the 4K60 fake-EDID mode, 600 frames (300 for OSD and 8-bit)

| Case | Format on plane 35 | Flips/s | Seq gaps | Starved flips | Commits outside vblank | Commit phase mean / max | VE-bound fps |
|---|---|---|---|---|---|---|---|
| HEVC Main10 2160p60 | YU10 AFBC split/sparse | **59.96** | 1 | 0 | 31 / 599 | 0.34 / 7.5 ms | 83.3 |
| VP9 Profile 2 2160p60 | YU10 AFBC | 56.58 | 14 | 42 | 48 / 599 | 1.67 / 110 ms | 84.4 |
| HEVC Main10 + primary kept on (OSD, VI at zpos 2) | YU10 AFBC | 59.80 | 1 | 0 | 19 / 299 | 0.43 / 19.6 ms | – |
| HEVC Main 8-bit (AS12) | YU08 AFBC | **59.99** | 0 | 0 | 8 / 299 | 0.27 / 3.9 ms | – |
| Linear NV12 pattern | NV12 | 59.26 | 1 | 0 | all | 2.1 ms | – |
| XR24 pattern on primary | XR24 | 59.26 | 1 | 0 | all | 1.8 ms | – |

- **VE throughput, HEVC Main10 to null:** 83.6 fps without scanout and 63.1 fps with 4K XR24 on the primary plane.
  With AFBC10 on the VI plane, the AFBC run's VE-bound rate is 83.3 fps, so AFBC scanout costs the decoder
  almost nothing, unlike XRGB.
- **VP9 starved flips:** the decoder is behind on 42 flips even though the VE could do 84 fps. Decode timing is
  bursty: the VP9 frame thread delivers frames late, and superframes contain hidden frames (648 VE jobs for 600
  frames). This is a pipeline matter, not KMS. The fix is a deeper queue or more `extra_hw_frames`; I didn't try it.
- **No new kernel messages** appeared during any run.
- The pattern runs commit late because the client draws the stripes on the CPU before each commit.

### 5. TV-out (TVE)

**Enabling `overlays=orangepi-zero2-expansion` boot-loops the board.**
- fbcon modesets Composite-1 (crtc-1, TCON TV1). The CRTC never produces a vblank:
  `[CRTC:72:crtc-1] vblank wait timed out` WARN, then a chain of 10 s `flip_done timed out` errors.
- Panfrost also fails to probe with -110.
- After about 55 s the board resets. I didn't capture why; the hardware watchdog is the likely cause, given
  that PID 1 or the console is stuck behind the DRM timeouts.
- The overlay also enables IR, so IR is currently unusable too.
- **Recovery:** I interrupted U-Boot over /dev/ttyOPIZ2 with the new
  `harness/afbc-kms-play/tools/uboot-noovl.py` and booted with the armbianEnv settings but no overlays, then
  removed the overlay line.

**Contained test:** the overlay plus `video=Composite-1:d` boots fine with tv-encoder bound. I unbound fbcon,
forced the connector on, and ran the client with a timeout:
- **Clocks are correct after the modeset:** pll-video1 and tve0 at 216 MHz, tcon-tv1 and tcon-top-tv1 at 13.5 MHz.
  TCON_TV_SETUP (0x06510000) = 0x10, so tv1_clk_src = TVE.
- **TCON TV1 is enabled but does not run:** GCTL 0x80000003, TCON1_CTL 0x80100160, the line counter (0xFC) stays
  at 0, and IRQ 99 (6516000.lcd-controller) counts 0.
- **Switching TCON_TV_SETUP to the CCU source at runtime did not start it either.**
- TVE0 reads 0x80300001 and TVE_TOP DAC_CFG0 reads 0x830B4201.
- **Conclusion:** the stall is in TCON TV1/TVE bring-up, which comes from the `sun8i_tve` / TCON TOP patches
  (`impl-audio-tve.md`, compile-tested only and never booted). It is upstream of the mixer, so DE33 Stage A is
  not implicated: the vblank interrupt comes from the TCON, and the TCON gets no pixel clock.
- The mixer1/DE33 YUV-output path could not be exercised. Picture quality needs a TV in any case.
- **Recommended next steps:**
  - Hand this to the TVE owner. Likely candidates are the TCON TV1 reset or gate, the TVE-to-TCON clock enable
    in TVE_TOP, or TCON1 needing the TVE started first.
  - Until it is fixed, make fbcon not take Composite by default (or have the connector report disconnected),
    so the overlay can't brick the board.

### 6. Tearing risk

- At 4K60 the vertical blanking is only 90 lines, 0.667 ms. On the regmap path the DE33 has no DBUFF, so plane
  registers take effect the moment the commit worker writes them.
- In real playback the client commits right after the flip event. With the decoder ahead, 95% (HEVC),
  92% (VP9) and 97% (8-bit) of commits landed inside the blanking.
- The rest landed later: up to 7.5 ms (HEVC), 19.6 ms (OSD) and 110 ms (VP9, after starvation). A late write
  changes the address mid-scanout, so it would tear at that scan line, about line 1000 for 7.5 ms. The exception
  is if the FBD or overlay latch their base at frame start, which I can't tell without a sink.
- **Assessment: tearing is likely on roughly 3–8% of frames**, more under CPU or DRAM load. It is
  near-certain for a compositor that commits at arbitrary times (most do, e.g. mpv's `--vo=drm` presents
  when the frame is ready).
- The robust fix is the RCQ path (LE 0223–0230), which updates registers in hardware at vblank. Per the rules
  I have not started it: **it needs the user's OK.**
- A cheaper, partial mitigation would be to defer the DE33 register writes in atomic_flush to the next vblank IRQ
  (software shadowing). That still races with long IRQ latency.
- A real 4K display is needed to confirm visible tearing.

### Fix commits

- Kernel branch `feat/sunxi-h616-de33-afbc`: **no kernel changes were needed.** The AFBC problem was the stale
  FFmpeg install.
- Harness (repo main, this commit): the client's descriptor logging and non-AFBC warning; `tools/uboot-noovl.py`;
  the round 2 and 3 results; this report. The draw-once pattern and the manual IN_FORMATS parse were already
  in main's 8132696.
