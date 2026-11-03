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
