# W25: H616 G2D as a V4L2 mem2mem colour converter and scaler

State file of the task (datasheet item W25, docs/datasheet-checklist.md 2.5.3). Memory: project-g2d.md.

## State (2026-11-06)
- Kernel work: armbian-build branch `fix/sunxi-h616-g2d` (worktree `wt-g2d`, off `test-cumulative` eb446f8cb), pushed to
  `fork`, NOT merged (coordinator merges). Commit: see "Commits". Four patches in
  `patch/kernel/archive/sunxi-7.3/patches.media/h616-g2d/` (series.conf, end) and `CONFIG_VIDEO_SUN50I_G2D=m`:
  1. `clk: sunxi-ng: h616: Add the G2D bus reset` (RST_BUS_G2D = 64, G2D_BGR_REG 0x63c bit 16; mainline has the clocks
     CLK_G2D/CLK_BUS_G2D/CLK_MBUS_G2D but no reset).
  2. `dt-bindings: media: Add Allwinner H616 G2D` (allwinner,sun50i-h616-g2d.yaml).
  3. `media: sunxi: Add Allwinner H616 G2D colour conversion and scaling driver` (drivers/media/platform/sunxi/sun50i-g2d/).
  4. `arm64: dts: allwinner: h616: Add the G2D node` (g2d@1480000, SPI 90, clocks bus/mod/mbus, iommus = <&iommu 6>).
- Host checks: full kernel build (kernel-check/work-g2d), W=1 on the driver and the CCU file, dtc, dt_binding_check +
  CHECK_DTBS: see "Host checks".
- Board: NOT TESTED yet. Runner job `harness/runner-queue/26-g2d.md`, package `runner/{g2d-job.sh,HANDOFF.md}`, test tool
  `tool/` (g2dconv.c for the board and the host, g2dcmp.py). Results will land in `logs/runner-g2d/`.
- Patch sources of truth: `src/sun50i-g2d/*`, `src/allwinner,sun50i-h616-g2d.yaml`, generated into the worktree by
  `src/mkpatches.py` (string edits of the post-series files in kernel-check/work-cumul). Re-run it after editing src/.

## What the driver does
V4L2 m2m, single-planar API, one contiguous buffer per frame, MMAP + DMABUF, VB2 dma-contig through the IOMMU (master 6,
prerequisite fix 4f711b354 already merged). Path used: video overlay V0 -> coarse decimator (HDS/VDS, engaged above 8x
horizontal / 4x vertical downscale) -> VSU scaler (4-tap, 32 phases, also upsamples chroma to 4:4:4; engaged for every
YUV source and for every size change) -> blender pipe 0 in COPY mode, ROP pass-through, colour space = source's -> CSC2
(only when RGB <-> YUV) -> write-back (does the chroma subsampling of YUV outputs).
- Formats (both queues, 18): XR24 AR24 BX24 BA24 XB24 AB24 RX24 RA24 (32-bit), BGR3 RGB3, RGBP; NV12 NV21 YU12 YV12,
  NV16 NV61 422P. Sizes 8..2048, step hsub/vsub; plane-0 pitch 16-byte aligned (a larger user pitch up to 2x is kept).
- CSC matrices are computed from the OUTPUT-queue colorimetry (ycbcr_enc 601/709/2020/240M, limited or full range), Q10
  fixed point; constants carry a +0.5 rounding bias. The capture queue inherits the colorimetry.
- Filter coefficients are generated (Catmull-Rom cubic, stretched by the downscale ratio); RGB sources get a linear
  vertical luma filter like the vendor does, YUV sources the cubic one. 4:2:0 chroma phase -0.25 (Q20 0xffff0000-ish
  value as the vendor's 0xfffc0000).
- Every job: mixer AHB reset pulse, program, enable the finish interrupt, start; 500 ms watchdog -> reset + buffers
  returned with ERROR + "job timed out" in dmesg. Runtime PM: bus + mod (300 MHz) + mbus clocks, CCU reset, TOP gates.
- Not done (W25 remainder): rotation/flip (ROT engine at 0x28000, V4L2_CID_ROTATE/HFLIP/VFLIP), UI overlays/blending,
  P010/P210/Y8/ARGB2101010/4444/1555, packed YUYV (different VSU path), crop/compose selection.

## Register notes (vendor BSP g2d_bsp_v2.c/g2d_regs_v2.h as reference, dl/vendor-5.4; manual has no register chapter)
- TOP 0x0000: SCLK_GATE/HCLK_GATE/AHB_RESET bit0 mixer, bit1 rot; SCLK_DIV; IP_VERSION 0x10. Vendor opens with 0x3 in
  all three and pulses AHB_RESET before each blit.
- MIXER 0x0100: CTL bit31 start (bits 4-7 scan order); INT bit0 finish flag (write 1 to clear), bit4 enable.
- V0 0x0800: ATTCTL = alpha<<24 | premul<<17 | fmt<<8 | alpha_mode<<1 | en; MBSIZE/SIZE (h-1)<<16|(w-1); COOR; PITCH0-2;
  LADD0-2; HADD = high bytes of the three planes; HDS/VDS_CTL0/1 coarse decimator ((mid<<16)|in, chroma variant).
- VSU 0x8000: CTRL bit0 en, bit8 held while writing coefficients, bit16 YUV; OUT_SIZE; Y/C_SIZE, H/VSTEP Q20, phases;
  Y_HCOEF 0x200, Y_VCOEF 0x300, C_HCOEF 0x400 (32 words of 4 x s8 taps summing to 64; tap -1 in the low byte).
- BLD 0x0400: EN_CTL bit8+n pipe enable; CH_ISIZE/OFFSET; CTL Porter-Duff factors (COPY 0x00010001, SRCOVER
  0x03010301); BLD_SIZE; OUT_COLOR bit0 premul, bit1 YUV colour space; ROP_CTL 0xf0 pass; CSC_CTL bit n enables CSC n;
  CSC n coefficients at 0x110 + 0x30 n, 12 words (3 rows: c0 c1 c2 const, Q10, two's complement 32-bit).
- WB 0x3000: ATT = format; SIZE; PITCH0-2; LADD/HADD per plane.
- Format codes: ARGB8888 0 .. BGRX8888 7 (name = little-endian word, so ARGB8888 = V4L2 ABGR32), RGB888 8, BGR888 9,
  RGB565 0xa; YUV422 SP UV 0x24 / VU 0x25 / planar 0x26; YUV420 SP UV 0x28 / VU 0x29 / planar 0x2a (= DE2 VI codes + 0x20,
  so 0x28 = NV12); Y8 0x30; P010 0x34; P210 0x36.
- Open question settled by the test, not by the sources: for planar YUV420 the vendor's g2d_set_info points hardware
  plane 1 at the third user plane; mainline DE2 (same code family) writes the DRM plane order (plane 1 = U). The driver
  assumes hardware plane 1 = U, 2 = V (YV12 swapped in the table). g2dcmp.py reports `uvswap 1` if the opposite holds.
- IOMMU: the manual (3.12, TLB6 prefetch note) suggests disabling the prefetch for G2D; the merged master-6 fix enables
  it for master 6 like the others. Keep as is unless job 26 shows iommu faults/garbage on this master (then the fix is a
  one-bit change of `sun50i_h616_variant.tlb_prefetch`, not a bypass).

## Host checks (2026-11-06, kernel-check/work-g2d, log kernel-check/run-g2d-build.log)
- Full build of test-cumulative eb446f8cb + the 4 patches: `patches applied: 849, failed: 0`, `build exit: 0; C warnings: 0`,
  sun50i-g2d.ko built (CONFIG_VIDEO_SUN50I_G2D=m), `DT_CHECK ok: g2d@1480000` and `allwinner,sun50i-h616-g2d` in the
  decompiled Zero2 DTB (clocks 0x22/0x21/0x37 = CLK_BUS_G2D/CLK_G2D/CLK_MBUS_G2D, reset 0x40 = 64, iommus <&iommu 6>).
- `make W=1 drivers/media/platform/sunxi/sun50i-g2d/ drivers/clk/sunxi-ng/ccu-sun50i-h616.o`: no output, exit 0.
- dtc: `dtbs exit: 0; dtc warnings: 17`, all pre-existing in unrelated files (sun50i-a64-pine64-7inch-lcd.dtso reg_format /
  pci / i2c / spi prerequisites, sun50i-h5-nanopi-r1s-h5.dtb) because this was a full tree build; none in sun50i-h616*.
- `make dt_binding_check DT_SCHEMA_FILES=media/allwinner,sun50i-h616-g2d.yaml`: exit 0, no finding for the schema (only the
  optional dt-check-style helper fails to import ruamel on this host, and the pre-existing hm5065.yaml parse error);
  `make CHECK_DTBS=y DT_SCHEMA_FILES=media/allwinner,sun50i-h616-g2d.yaml allwinner/sun50i-h616-orangepi-zero2.dtb`: exit 0,
  no g2d finding (dt-validate 2026.9).

## What job 26 decides (mechanical results -> next change)
- probe FAIL (no device): dmesg in files/g2d/probe-dmesg.txt: clock/reset names, IRQ, IOMMU attach.
- compliance failures: FAILLINE lines name the ioctl; fix in the driver.
- rgb-copy / rgb-* not exact: pitch/plane layout or format code mapping of the RGB entry (table in sun50i-g2d.c).
- rgb2yuv max_dev > tol with Y right and U/V wrong: CSC row order or the WB chroma order; `uvswap 1` on yu12/yv12 only:
  flip `swap_uv` of YU12/YV12 (hardware plane 1 = V).
- yuv2rgb wrong everywhere: VSU/CSC2 direction or BLD_OUT_COLOR_YUV; wrong at the borders only: cubic edge handling
  (border 2 already excluded, raise to 4 only if the interior is right).
- scale-* wrong but same-size right: VSU step/phase (Q20) or coefficient word order (tap -1 in the low byte).
- scale-down8 wrong, scale-down6 right: coarse decimator CTL1 encoding.
- TIMEOUT: the mixer never raised INT bit0: start bit / interrupt enable bit / clock gating; check `g2d_timeouts`.
- iommu_faults > 0: an address/pitch bug (fault address tells which plane) or the TLB6 prefetch note above.
- gst element 0: the v4l2 plugin did not pick the device (needs V4L2_CAP_VIDEO_M2M + a convert-capable format set).

## Commits
- armbian-build fix/sunxi-h616-g2d: 04964f921 `sunxi-7.3: H616 G2D as a V4L2 m2m colour converter and scaler (W25)` (off test-cumulative eb446f8cb, pushed to fork, unmerged).
- project repo: this file, runner/, tool/, src/, harness/runner-queue/26-g2d.md, .gitignore lines.
